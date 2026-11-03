import SwiftUI
import SwiftData

enum WatchStatus: String, CaseIterable, Identifiable, Codable {
    case queued, watching, watched, dropped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .queued: "Want to Watch"
        case .watching: "Watching"
        case .watched: "Watched"
        case .dropped: "Dropped"
        }
    }

    var shortLabel: String {
        switch self {
        case .queued: "Want"
        case .watching: "Watching"
        case .watched: "Watched"
        case .dropped: "Dropped"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "bookmark"
        case .watching: "play.circle"
        case .watched: "checkmark.circle"
        case .dropped: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .queued: Theme.info
        case .watching: Theme.accent
        case .watched: Theme.success
        case .dropped: Theme.textTertiary
        }
    }
}

/// A title on your couch. Synced through CloudKit, so every property has a default
/// and nothing is unique-constrained (duplicates from concurrent devices are merged
/// by `LibraryStore.dedupe`).
@Model
final class SavedTitle {
    var key: String = ""
    var sourceRaw: String = CatalogSource.tmdb.rawValue
    var kindRaw: String = MediaKind.movie.rawValue
    var externalID: String = ""
    var name: String = ""
    var overview: String = ""
    var posterURLString: String?
    var backdropURLString: String?
    var year: Int?
    var genresCSV: String = ""
    var providerIDsCSV: String = ""
    var runtime: Int?
    var statusRaw: String = WatchStatus.queued.rawValue
    var potatoes: Int = 0
    var notes: String = ""
    var addedAt: Date = Date.now
    var updatedAt: Date = Date.now
    var finishedAt: Date?
    var lastSeason: Int = 0
    var lastEpisode: Int = 0
    var isFollowing: Bool = false
    var imdbID: String?

    init(from title: CatalogTitle, status: WatchStatus = .queued) {
        key = title.ref.key
        sourceRaw = title.ref.source.rawValue
        kindRaw = title.ref.kind.rawValue
        externalID = title.ref.id
        statusRaw = status.rawValue
        isFollowing = title.kind == .tv && status != .dropped
        update(from: title)
    }

    func update(from title: CatalogTitle) {
        name = title.name
        if !title.overview.isEmpty { overview = title.overview }
        posterURLString = title.posterURL?.absoluteString ?? posterURLString
        backdropURLString = title.backdropURL?.absoluteString ?? backdropURLString
        year = title.year ?? year
        if !title.genres.isEmpty { genresCSV = title.genres.joined(separator: ",") }
        if !title.providers.isEmpty { providerIDsCSV = title.providers.map(\.id).joined(separator: ",") }
        runtime = title.runtime ?? runtime
        imdbID = title.imdbID ?? imdbID
    }

    var ref: TitleRef {
        TitleRef(source: CatalogSource(rawValue: sourceRaw) ?? .tmdb,
                 kind: MediaKind(rawValue: kindRaw) ?? .movie,
                 id: externalID)
    }

    var kind: MediaKind { MediaKind(rawValue: kindRaw) ?? .movie }

    var status: WatchStatus {
        get { WatchStatus(rawValue: statusRaw) ?? .queued }
        set {
            statusRaw = newValue.rawValue
            updatedAt = .now
            if newValue == .watched { finishedAt = finishedAt ?? .now }
        }
    }

    var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
    var backdropURL: URL? { backdropURLString.flatMap(URL.init(string:)) }
    var genres: [String] { genresCSV.split(separator: ",").map(String.init) }

    var providerIDs: [String] {
        get { providerIDsCSV.split(separator: ",").map(String.init) }
        set { providerIDsCSV = newValue.joined(separator: ",") }
    }

    var providers: [Provider] { providerIDs.compactMap(Provider.with(id:)) }

    var progressLabel: String? {
        guard kind == .tv, lastSeason > 0 else { return nil }
        return String(format: "Watched through S%02dE%02d", lastSeason, lastEpisode)
    }

    /// A lightweight catalog value so saved titles can reuse catalog views.
    var asCatalogTitle: CatalogTitle {
        CatalogTitle(ref: ref, name: name, overview: overview, posterURL: posterURL, backdropURL: backdropURL,
                     year: year, genres: genres, runtime: runtime, providers: providers, imdbID: imdbID)
    }
}

/// A planned viewing session on the Spud Planner.
@Model
final class CouchNight {
    var id: UUID = UUID()
    var titleKey: String = ""
    var titleName: String = ""
    var posterURLString: String?
    var startsAt: Date = Date.now
    var durationMinutes: Int = 120
    var note: String = ""
    var remind: Bool = true
    var isDone: Bool = false
    var calendarEventID: String?
    var createdAt: Date = Date.now

    init(titleKey: String, titleName: String, posterURL: URL?, startsAt: Date, durationMinutes: Int, note: String = "", remind: Bool = true) {
        self.titleKey = titleKey
        self.titleName = titleName
        self.posterURLString = posterURL?.absoluteString
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.note = note
        self.remind = remind
    }

    var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var ref: TitleRef? { TitleRef(key: titleKey) }
}
