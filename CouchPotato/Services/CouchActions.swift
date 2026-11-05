import CoreSpotlight
import Foundation
import SwiftData

/// Everything Couch Potato can *do*, in one place. Siri (App Intents) and the in-app
/// assistant (Foundation Models tools) both call these, so they behave identically.
@MainActor
final class CouchActions {
    private unowned let services: AppServices
    /// Titles recently handed to Siri or the assistant, so follow-ups ("add the second
    /// one") resolve instantly without another network round trip.
    private var recent: [String: CatalogTitle] = [:]

    init(services: AppServices) { self.services = services }

    private var context: ModelContext { services.context }
    private var catalog: Catalog { services.catalog }

    // MARK: Finding

    /// A natural-language request ("a cozy mystery series") → titles. Uses the on-device
    /// model when it's available, otherwise a plain search.
    func find(_ request: String) async throws -> (summary: String, titles: [CatalogTitle]) {
        if services.intelligence.isAvailable {
            let query = try await services.intelligence.interpret(request)
            let titles = try await catalog.ask(query)
            return (query.summary, remember(titles))
        }
        return (request, try await search(request))
    }

    /// Titles whose name matches, your library first.
    func search(_ text: String) async throws -> [CatalogTitle] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 2 else { return [] }
        let mine = library().filter { $0.name.localizedCaseInsensitiveContains(needle) }.map(\.asCatalogTitle)
        let found = (try? await catalog.search(needle)) ?? []
        var seen = Set<String>()
        return remember((mine + found).filter { seen.insert($0.id).inserted })
    }

    /// Resolves a key to a title: the library, then recent results, then the catalog.
    func title(_ key: String) async throws -> CatalogTitle {
        if let saved = Library.saved(key, in: context) { return saved.asCatalogTitle }
        if let hit = recent[key] { return hit }
        guard let ref = TitleRef(key: key) else { throw ActionError.unknownTitle }
        let detail = try await catalog.detail(ref)
        return remember([detail.title])[0]
    }

    /// Resolves a title the user named, preferring exact name matches in the library.
    func title(named name: String) async throws -> CatalogTitle {
        if TitleRef(key: name) != nil { return try await title(name) }
        let lower = name.lowercased()
        if let exact = library().first(where: { $0.name.lowercased() == lower }) { return exact.asCatalogTitle }
        if let exact = recent.values.first(where: { $0.name.lowercased() == lower }) { return exact }
        guard let first = try await search(name).first else { throw ActionError.notFound(name) }
        return first
    }

    // MARK: Library

    func library(_ statuses: Set<WatchStatus> = Set(WatchStatus.allCases)) -> [SavedTitle] {
        let all = (try? context.fetch(FetchDescriptor<SavedTitle>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))) ?? []
        return all.filter { statuses.contains($0.status) }
    }

    @discardableResult
    func setStatus(_ status: WatchStatus, for title: CatalogTitle) -> SavedTitle {
        let item = Library.save(title, status: status, in: context)
        if status == .watched, item.kind == .tv { item.isFollowing = false }
        try? context.save()
        return item
    }

    func remove(_ key: String) {
        Library.remove(key, in: context)
        try? context.save()
    }

    // MARK: Watching

    /// Where a title streams, rents or sells in the user's region.
    func availability(of title: CatalogTitle) async throws -> Availability {
        try await catalog.detail(title.ref).availability
    }

    /// One sentence for Siri, e.g. "Wednesday is streaming on Netflix."
    func whereToWatchSentence(_ title: CatalogTitle, _ availability: Availability) -> String {
        let mine = Set(services.prefs.myServiceIDs)
        func names(_ kind: OfferKind) -> [String] {
            var seen = Set<String>()
            return availability.offers(kind)
                .sorted { mine.contains($0.provider.id) && !mine.contains($1.provider.id) }
                .map(\.provider.name).filter { seen.insert($0).inserted }
        }
        let stream = names(.stream) + names(.free) + names(.ads)
        if !stream.isEmpty {
            return "\(title.name) is streaming on \(ListFormatter.localizedString(byJoining: Array(stream.prefix(3))))."
        }
        let rent = names(.rent) + names(.buy)
        if !rent.isEmpty {
            return "\(title.name) isn't on a streaming service right now, but you can rent or buy it on \(ListFormatter.localizedString(byJoining: Array(rent.prefix(2))))."
        }
        return "I couldn't find anywhere to watch \(title.name) in \(availability.region) right now."
    }

    // MARK: Planning

    @discardableResult
    func planNight(_ title: CatalogTitle, at date: Date, minutes: Int? = nil) async -> CouchNight {
        if Library.saved(title.ref.key, in: context) == nil { Library.save(title, status: .queued, in: context) }
        let night = CouchNight(titleKey: title.ref.key, titleName: title.name, posterURL: title.posterURL,
                               startsAt: date, durationMinutes: minutes ?? title.runtime ?? 120)
        context.insert(night)
        try? context.save()
        await Reminders.schedule(night, minutesBefore: services.prefs.remindMinutesBefore)
        if services.prefs.addNightsToCalendar { night.calendarEventID = await CalendarBridge.add(night) }
        return night
    }

    func upcomingNights() -> [CouchNight] {
        let start = Calendar.current.startOfDay(for: .now)
        let all = (try? context.fetch(FetchDescriptor<CouchNight>(sortBy: [SortDescriptor(\.startsAt)]))) ?? []
        return all.filter { $0.startsAt >= start && !$0.isDone }
    }

    // MARK: Deciding

    /// Picks something for tonight from the watchlist (or what's trending if it's empty).
    func shuffle(mood: Mood?, maxMinutes: Int?) async throws -> CatalogTitle {
        var pool = library([.queued, .watching]).map(\.asCatalogTitle)
        if pool.count < 2 { pool += (try? await catalog.trending()) ?? [] }
        let fits = pool.filter { title in
            (mood == nil || mood!.matches(title)) && (maxMinutes == nil || (title.runtime ?? 0) <= maxMinutes!)
        }
        guard let pick = (fits.isEmpty ? pool : fits).randomElement() else { throw ActionError.nothingToPick }
        return remember([pick])[0]
    }

    // MARK: Spotlight / Siri personal context

    /// Indexes the library so Siri and Spotlight know what's on your watchlist.
    func reindexLibrary() async {
        let entities = library().map(TitleEntity.init)
        do {
            try await CSSearchableIndex.default().deleteAppEntities(ofType: TitleEntity.self)
            if !entities.isEmpty { try await CSSearchableIndex.default().indexAppEntities(entities) }
        } catch {
            print("[Spotlight] indexing failed: \(error)")
        }
    }

    @discardableResult
    func remember(_ titles: [CatalogTitle]) -> [CatalogTitle] {
        for title in titles { recent[title.id] = title }
        if recent.count > 400 { recent = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) }) }
        return titles
    }
}

enum ActionError: LocalizedError {
    case unknownTitle
    case notFound(String)
    case nothingToPick

    var errorDescription: String? {
        switch self {
        case .unknownTitle: "I couldn't find that title."
        case .notFound(let name): "I couldn't find anything called “\(name)”."
        case .nothingToPick: "Your watchlist is empty. Add a few titles first."
        }
    }
}
