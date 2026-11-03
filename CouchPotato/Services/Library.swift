import Foundation
import SwiftData

/// Helpers for reading and writing the synced library.
@MainActor
enum Library {
    static func saved(_ key: String, in context: ModelContext) -> SavedTitle? {
        var descriptor = FetchDescriptor<SavedTitle>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    static func save(_ title: CatalogTitle, status: WatchStatus = .queued, in context: ModelContext) -> SavedTitle {
        if let existing = saved(title.ref.key, in: context) {
            existing.update(from: title)
            existing.status = status
            return existing
        }
        let saved = SavedTitle(from: title, status: status)
        context.insert(saved)
        return saved
    }

    static func remove(_ key: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<SavedTitle>(predicate: #Predicate { $0.key == key })
        for item in (try? context.fetch(descriptor)) ?? [] { context.delete(item) }
    }

    /// CloudKit can't enforce uniqueness, so two devices adding the same title
    /// offline produce twins. Keep the most recently updated one.
    static func dedupe(in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<SavedTitle>()) else { return }
        let groups = Dictionary(grouping: all, by: \.key)
        for (_, twins) in groups where twins.count > 1 {
            let sorted = twins.sorted { $0.updatedAt > $1.updatedAt }
            let keeper = sorted[0]
            for twin in sorted.dropFirst() {
                keeper.potatoes = max(keeper.potatoes, twin.potatoes)
                if keeper.notes.isEmpty { keeper.notes = twin.notes }
                if twin.lastSeason * 1000 + twin.lastEpisode > keeper.lastSeason * 1000 + keeper.lastEpisode {
                    keeper.lastSeason = twin.lastSeason
                    keeper.lastEpisode = twin.lastEpisode
                }
                keeper.addedAt = min(keeper.addedAt, twin.addedAt)
                context.delete(twin)
            }
        }
        try? context.save()
    }
}

/// Couch Rank: a silly progression system based on what you've watched.
struct CouchRank {
    struct Level {
        let name: String
        let emoji: String
        let threshold: Int
        let quip: String
    }

    static let levels: [Level] = [
        Level(name: "Raw Spud", emoji: "🥔", threshold: 0, quip: "Freshly dug. The couch awaits."),
        Level(name: "Tater Tot", emoji: "🧆", threshold: 3, quip: "Small, round, full of potential."),
        Level(name: "Hash Brown", emoji: "🟫", threshold: 10, quip: "Crispy around the edges."),
        Level(name: "Curly Fry", emoji: "🌀", threshold: 25, quip: "You've developed a twist."),
        Level(name: "Baked Legend", emoji: "🔥", threshold: 50, quip: "Loaded with toppings and lore."),
        Level(name: "Mashed Royalty", emoji: "👑", threshold: 100, quip: "The couch bows to you."),
    ]

    let points: Int
    let moviesWatched: Int
    let showsWatched: Int
    let hoursWatched: Int

    init(titles: [SavedTitle], nights: [CouchNight]) {
        let watched = titles.filter { $0.status == .watched }
        moviesWatched = watched.filter { $0.kind == .movie }.count
        showsWatched = watched.filter { $0.kind == .tv }.count
        let rated = titles.filter { $0.potatoes > 0 }.count
        let doneNights = nights.filter(\.isDone).count
        let episodes = titles.filter { $0.kind == .tv }.reduce(0) { $0 + max(0, $1.lastEpisode) + max(0, $1.lastSeason - 1) * 8 }
        points = moviesWatched * 2 + showsWatched * 4 + rated + doneNights + episodes / 4
        let movieMinutes = watched.filter { $0.kind == .movie }.reduce(0) { $0 + ($1.runtime ?? 110) }
        let episodeMinutes = titles.filter { $0.kind == .tv }.reduce(0) { total, t in
            let eps = t.status == .watched ? max(10, t.lastEpisode) : max(0, t.lastEpisode)
            return total + eps * (t.runtime ?? 45)
        }
        hoursWatched = (movieMinutes + episodeMinutes) / 60
    }

    var level: Level { Self.levels.last { points >= $0.threshold } ?? Self.levels[0] }
    var nextLevel: Level? { Self.levels.first { $0.threshold > points } }

    var progressToNext: Double {
        guard let next = nextLevel else { return 1 }
        let span = Double(next.threshold - level.threshold)
        return span <= 0 ? 1 : Double(points - level.threshold) / span
    }
}
