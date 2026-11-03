import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Portable JSON for the watchlist and plans, shared with the Android app
/// (android/.../domain/Backup.kt): ISO-8601 timestamps, stable title keys, plain fields.
/// iCloud keeps Apple devices in sync; this file moves a library to or from Android.
enum Backup {
    static let format = "couchpotato.backup"
    static let version = 1

    struct File: Codable {
        var format = Backup.format
        var version = Backup.version
        var exportedAt: Date
        var titles: [Title]
        var nights: [Night]
    }

    struct Title: Codable {
        var key: String
        var source: String
        var kind: String
        var externalID: String
        var name: String
        var overview: String?
        var posterURL: String?
        var backdropURL: String?
        var year: Int?
        var genres: [String]?
        var providerIDs: [String]?
        var runtime: Int?
        var status: String?
        var rating: Int?
        var potatoes: Int?
        var notes: String?
        var addedAt: Date?
        var updatedAt: Date?
        var finishedAt: Date?
        var lastSeason: Int?
        var lastEpisode: Int?
        var isFollowing: Bool?
        var imdbID: String?

        init(_ t: SavedTitle) {
            key = t.key
            source = t.sourceRaw
            kind = t.kindRaw
            externalID = t.externalID
            name = t.name
            overview = t.overview
            posterURL = t.posterURLString
            backdropURL = t.backdropURLString
            year = t.year
            genres = t.genres
            providerIDs = t.providerIDs
            runtime = t.runtime
            status = t.statusRaw
            rating = t.potatoes
            notes = t.notes
            addedAt = t.addedAt
            updatedAt = t.updatedAt
            finishedAt = t.finishedAt
            lastSeason = t.lastSeason
            lastEpisode = t.lastEpisode
            isFollowing = t.isFollowing
            imdbID = t.imdbID
        }
    }

    struct Night: Codable {
        init(_ n: CouchNight) {
            id = n.id.uuidString
            titleKey = n.titleKey
            titleName = n.titleName
            posterURL = n.posterURLString
            startsAt = n.startsAt
            durationMinutes = n.durationMinutes
            note = n.note
            remind = n.remind
            isDone = n.isDone
            createdAt = n.createdAt
        }

        var id: String?
        var titleKey: String
        var titleName: String?
        var posterURL: String?
        var startsAt: Date
        var durationMinutes: Int?
        var note: String?
        var remind: Bool?
        var isDone: Bool?
        var createdAt: Date?
    }

    struct Summary {
        var added = 0
        var updated = 0
        var nights = 0
        var message: String {
            "Added \(added) title\(added == 1 ? "" : "s"), updated \(updated), and imported \(nights) plan\(nights == 1 ? "" : "s")."
        }
    }

    // MARK: Export

    static func export(titles: [SavedTitle], nights: [CouchNight]) throws -> Data {
        let file = File(exportedAt: .now, titles: titles.map(Title.init), nights: nights.map(Night.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    // MARK: Import

    /// Merges a backup into the library. A title already here is only overwritten when
    /// the file's copy is newer; plans are matched by id, then by title and start time.
    @discardableResult
    static func merge(_ data: Data, into context: ModelContext) throws -> Summary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                // Epoch seconds or milliseconds.
                return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
            }
            let string = try container.decode(String.self)
            if let date = parseISO(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date \(string)")
        }
        let file = try decoder.decode(File.self, from: data)
        var summary = Summary()

        let existing = (try? context.fetch(FetchDescriptor<SavedTitle>())) ?? []
        var byKey: [String: SavedTitle] = [:]
        for item in existing where (byKey[item.key]?.updatedAt ?? .distantPast) <= item.updatedAt { byKey[item.key] = item }
        for item in file.titles {
            guard let ref = TitleRef(key: item.key) else { continue }
            let incomingUpdated = item.updatedAt ?? item.addedAt ?? .now
            if let current = byKey[item.key] {
                guard incomingUpdated > current.updatedAt else { continue }
                apply(item, to: current)
                summary.updated += 1
            } else {
                let saved = SavedTitle(from: CatalogTitle(ref: ref, name: item.name))
                apply(item, to: saved)
                context.insert(saved)
                byKey[item.key] = saved
                summary.added += 1
            }
        }

        let nights = (try? context.fetch(FetchDescriptor<CouchNight>())) ?? []
        var ids = Set(nights.map(\.id))
        var slots = Set(nights.map { "\($0.titleKey)|\(Int($0.startsAt.timeIntervalSince1970 / 60))" })
        for item in file.nights {
            let id = item.id.flatMap(UUID.init(uuidString:))
            let slot = "\(item.titleKey)|\(Int(item.startsAt.timeIntervalSince1970 / 60))"
            if let id, ids.contains(id) { continue }
            if slots.contains(slot) { continue }
            let night = CouchNight(titleKey: item.titleKey, titleName: item.titleName ?? "Couch night",
                                   posterURL: item.posterURL.flatMap(URL.init(string:)), startsAt: item.startsAt,
                                   durationMinutes: item.durationMinutes ?? 120, note: item.note ?? "",
                                   remind: item.remind ?? true)
            if let id { night.id = id }
            night.isDone = item.isDone ?? false
            night.createdAt = item.createdAt ?? .now
            context.insert(night)
            if let id { ids.insert(id) }
            slots.insert(slot)
            summary.nights += 1
        }
        try context.save()
        return summary
    }

    private static func apply(_ item: Title, to saved: SavedTitle) {
        saved.key = item.key
        saved.sourceRaw = item.source
        saved.kindRaw = item.kind
        saved.externalID = item.externalID
        saved.name = item.name
        saved.overview = item.overview ?? saved.overview
        saved.posterURLString = item.posterURL ?? saved.posterURLString
        saved.backdropURLString = item.backdropURL ?? saved.backdropURLString
        saved.year = item.year ?? saved.year
        if let genres = item.genres { saved.genresCSV = genres.joined(separator: ",") }
        if let providers = item.providerIDs { saved.providerIDsCSV = providers.joined(separator: ",") }
        saved.runtime = item.runtime ?? saved.runtime
        if let status = item.status, WatchStatus(rawValue: status) != nil { saved.statusRaw = status }
        saved.potatoes = min(5, max(0, item.rating ?? item.potatoes ?? saved.potatoes))
        saved.notes = item.notes ?? saved.notes
        saved.addedAt = item.addedAt ?? saved.addedAt
        saved.updatedAt = item.updatedAt ?? saved.updatedAt
        saved.finishedAt = item.finishedAt ?? saved.finishedAt
        saved.lastSeason = item.lastSeason ?? saved.lastSeason
        saved.lastEpisode = item.lastEpisode ?? saved.lastEpisode
        saved.isFollowing = item.isFollowing ?? saved.isFollowing
        saved.imdbID = item.imdbID ?? saved.imdbID
    }

    /// Android writes fractional seconds ("…:33.123Z"); Apple's default formatter rejects them.
    static func parseISO(_ string: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: string) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
    }
}

/// Wraps backup data for `fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
