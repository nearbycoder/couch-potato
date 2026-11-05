import AppIntents
import SwiftUI

// The actions Siri (and Shortcuts) can call. Each returns its result as values Siri can
// chain into the next step, plus a spoken/visible dialog. They all go through
// CouchActions so they behave exactly like the app and the in-app assistant.

struct FindSomethingToWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Something to Watch"
    static let description = IntentDescription(
        "Describe what you're in the mood for, like “a cozy mystery series” or “something funny under an hour,” and get matching movies and series.",
        categoryName: "Discover")

    @Parameter(title: "Request", requestValueDialog: "What are you in the mood for?")
    var request: String

    static var parameterSummary: some ParameterSummary { Summary("Find \(\.$request)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TitleEntity]> & ProvidesDialog & ShowsSnippetView {
        let (summary, titles) = try await AppServices.shared.actions.find(request)
        let top = Array(titles.prefix(8))
        await preloadPosters(top)
        let names = ListFormatter.localizedString(byJoining: top.prefix(3).map(\.name))
        let dialog: IntentDialog = top.isEmpty
            ? "I couldn't find anything for that. Try describing it differently."
            : "Here's what I found: \(names)."
        return .result(value: top.map { TitleEntity($0) }, dialog: dialog,
                       view: TitlesSnippet(heading: summary, titles: top))
    }
}

struct SearchCouchPotatoIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Couch Potato"
    static let description = IntentDescription("Search for movies and series by name.", categoryName: "Discover")

    @Parameter(title: "Search Text")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Search for \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TitleEntity]> & ProvidesDialog {
        let titles = Array(try await AppServices.shared.actions.search(text).prefix(10))
        let dialog: IntentDialog = titles.isEmpty
            ? "Nothing matched “\(text)”."
            : "Top match: \(titles[0].name)\(titles[0].year.map { " (\($0))" } ?? "")."
        return .result(value: titles.map { TitleEntity($0) }, dialog: dialog)
    }
}

/// Opens the Browse screen with a search, for "search Couch Potato for …".
@AppIntent(schema: .system.search)
struct ShowSearchResultsIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.shared.app.search(criteria.term)
        return .result()
    }
}

struct OpenTitleIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Title"
    static let description = IntentDescription("Opens a movie or series in Couch Potato.", categoryName: "Library")

    @Parameter(title: "Title")
    var target: TitleEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        if let ref = TitleRef(key: target.id) { AppServices.shared.app.open(ref) }
        return .result()
    }
}

struct AddToWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Watchlist"
    static let description = IntentDescription("Adds a movie or series to your Couch Potato watchlist.", categoryName: "Library")

    @Parameter(title: "Title")
    var title: TitleEntity

    @Parameter(title: "Status", default: .queued)
    var status: WatchStatusEntity

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$title) as \(\.$status)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TitleEntity> & ProvidesDialog {
        let actions = AppServices.shared.actions
        let resolved = try await actions.title(title.id)
        let saved = actions.setStatus(status.status, for: resolved)
        await actions.reindexLibrary()
        let dialog: IntentDialog = status == .queued
            ? "Added \(resolved.name) to your watchlist."
            : "Marked \(resolved.name) as \(saved.status.label.lowercased())."
        return .result(value: TitleEntity(saved), dialog: dialog)
    }
}

struct MarkWatchedIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark as Watched"
    static let description = IntentDescription("Marks a movie or series as watched.", categoryName: "Library")

    @Parameter(title: "Title")
    var title: TitleEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TitleEntity> & ProvidesDialog {
        let actions = AppServices.shared.actions
        let saved = actions.setStatus(.watched, for: try await actions.title(title.id))
        await actions.reindexLibrary()
        return .result(value: TitleEntity(saved), dialog: "Marked \(saved.name) as watched.")
    }
}

struct WhereToWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Where to Watch"
    static let description = IntentDescription("Finds which services stream, rent or sell a movie or series in your region.",
                                               categoryName: "Discover")

    @Parameter(title: "Title")
    var title: TitleEntity

    static var parameterSummary: some ParameterSummary { Summary("Where to watch \(\.$title)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let actions = AppServices.shared.actions
        let resolved = try await actions.title(title.id)
        let availability = try await actions.availability(of: resolved)
        let sentence = actions.whereToWatchSentence(resolved, availability)
        return .result(value: availability.providers.map(\.name), dialog: "\(sentence)")
    }
}

struct ShowWatchlistIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Watchlist"
    static let description = IntentDescription("Lists the titles on your watchlist.", categoryName: "Library")

    @Parameter(title: "Status", default: .queued)
    var status: WatchStatusEntity

    static var parameterSummary: some ParameterSummary { Summary("Get titles marked \(\.$status)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TitleEntity]> & ProvidesDialog & ShowsSnippetView {
        let items = AppServices.shared.actions.library([status.status])
        let titles = items.map(\.asCatalogTitle)
        await preloadPosters(Array(titles.prefix(8)))
        let dialog: IntentDialog
        if items.isEmpty {
            dialog = "Nothing is marked \(status.status.label.lowercased()) yet."
        } else {
            let names = ListFormatter.localizedString(byJoining: items.prefix(3).map(\.name))
            dialog = items.count > 3 ? "You have \(items.count) titles, including \(names)." : "You have \(names)."
        }
        return .result(value: items.map(TitleEntity.init), dialog: dialog,
                       view: TitlesSnippet(heading: status.status.label, titles: Array(titles.prefix(8))))
    }
}

struct PlanNightIntent: AppIntent {
    static let title: LocalizedStringResource = "Plan a Night"
    static let description = IntentDescription("Schedules a viewing night with a reminder.", categoryName: "Planner")

    @Parameter(title: "Title")
    var title: TitleEntity

    @Parameter(title: "When", requestValueDialog: "When do you want to watch it?")
    var date: Date

    static var parameterSummary: some ParameterSummary { Summary("Watch \(\.$title) on \(\.$date)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let actions = AppServices.shared.actions
        let resolved = try await actions.title(title.id)
        let night = await actions.planNight(resolved, at: date)
        let when = night.startsAt.formatted(.dateTime.weekday(.wide).hour().minute())
        return .result(dialog: "You're set to watch \(resolved.name) \(when). I'll remind you before it starts.")
    }
}

struct ShuffleTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick Something for Tonight"
    static let description = IntentDescription("Picks something from your watchlist for tonight.", categoryName: "Discover")

    @Parameter(title: "Mood")
    var mood: MoodEntity?

    @Parameter(title: "Time Available (minutes)", inclusiveRange: (20, 600))
    var minutes: Int?

    static var parameterSummary: some ParameterSummary { Summary("Pick something \(\.$mood) under \(\.$minutes) minutes") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<TitleEntity> & ProvidesDialog & ShowsSnippetView {
        let services = AppServices.shared
        let pick = try await services.actions.shuffle(mood: mood?.mood, maxMinutes: minutes)
        var pitch = ""
        if services.intelligence.isAvailable {
            for try await text in services.intelligence.pitch(for: pick, mood: mood?.mood, minutes: minutes) { pitch = text }
        }
        await preloadPosters([pick])
        let dialog: IntentDialog = pitch.isEmpty ? "How about \(pick.name)?" : "How about \(pick.name)? \(pitch)"
        return .result(value: TitleEntity(pick), dialog: dialog,
                       view: TitlesSnippet(heading: "Tonight's pick", titles: [pick], pitch: pitch))
    }
}

struct UpcomingNightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Planned Nights"
    static let description = IntentDescription("Lists your upcoming viewing nights.", categoryName: "Planner")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let nights = AppServices.shared.actions.upcomingNights()
        let lines = nights.map { "\($0.titleName), \($0.startsAt.formatted(.dateTime.weekday(.wide).hour().minute()))" }
        let dialog: IntentDialog = nights.isEmpty
            ? "You don't have any nights planned."
            : "Coming up: \(ListFormatter.localizedString(byJoining: Array(lines.prefix(3))))."
        return .result(value: lines, dialog: dialog)
    }
}

/// Snippet views render outside the app's normal view tree, so posters are fetched
/// into the image cache first and drawn from it synchronously.
@MainActor
private func preloadPosters(_ titles: [CatalogTitle]) async {
    await withTaskGroup(of: Void.self) { group in
        for url in titles.compactMap(\.posterURL) {
            group.addTask { _ = await ImagePipeline.shared.image(url, maxPixel: 300) }
        }
    }
}

struct TitlesSnippet: View {
    var heading: String
    var titles: [CatalogTitle]
    var pitch: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !heading.isEmpty {
                Text(heading).font(.headline)
            }
            if titles.count == 1, let title = titles.first {
                HStack(alignment: .top, spacing: 12) {
                    RemoteImage(url: title.posterURL, maxPixel: 300, placeholderTitle: title.name)
                        .frame(width: 70, height: 105)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.name).font(.title3.weight(.semibold))
                        Text(title.subtitle).font(.caption).foregroundStyle(.secondary)
                        if !pitch.isEmpty { Text(pitch).font(.subheadline).padding(.top, 2) }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(titles) { title in
                            VStack(alignment: .leading, spacing: 4) {
                                RemoteImage(url: title.posterURL, maxPixel: 300, placeholderTitle: title.name)
                                    .frame(width: 72, height: 108)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(title.name).font(.caption.weight(.medium)).lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
