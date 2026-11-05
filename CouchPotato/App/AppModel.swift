import SwiftUI
import Observation

enum AppTab: String, Hashable, CaseIterable {
    case tonight, search, queue, planner, roulette, settings
    case service

    var title: String {
        switch self {
        case .tonight: "Tonight"
        case .search: "Browse"
        case .queue: "Watchlist"
        case .planner: "Planner"
        case .roulette: "Shuffle"
        case .settings: "Settings"
        case .service: "Service"
        }
    }

    var symbol: String {
        switch self {
        case .tonight: "play.rectangle.on.rectangle"
        case .search: "magnifyingglass"
        case .queue: "bookmark"
        case .planner: "calendar"
        case .roulette: "shuffle"
        case .settings: "gearshape"
        case .service: "play.tv"
        }
    }
}

/// Navigation destinations shared by every tab's stack.
enum Route: Hashable {
    case title(TitleRef, preview: CatalogTitle?)
    case mood(Mood)
    case provider(Provider)
    case list(String, [CatalogTitle])
    case ask

    static func detail(_ title: CatalogTitle) -> Route { .title(title.ref, preview: title) }
}

/// Selected tab, per-tab navigation paths and cross-tab requests (deep links,
/// "plan a night for this title", Handoff).
@MainActor
@Observable
final class AppModel {
    var selection: TabSelection = .tab(.tonight)
    var paths: [TabSelection: NavigationPath] = [:]
    var planningTitle: CatalogTitle?
    var isPlanning = false
    var showOnboarding = false
    var showSettings = false
    /// A search requested from outside the Browse screen (Siri, Spotlight).
    var pendingSearch: String?

    static let titleActivity = "com.nearbycoder.couchpotato.title"

    func path(_ tab: TabSelection) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route) {
        if selection == .tab(.settings) { selection = .tab(.tonight) }
        paths[selection, default: NavigationPath()].append(route)
    }

    func open(_ ref: TitleRef) {
        // Stay on the current tab when it can push; settings has no stack on Mac.
        if selection == .tab(.settings) { selection = .tab(.tonight) }
        paths[selection, default: NavigationPath()].append(Route.title(ref, preview: nil))
    }

    func handle(url: URL) {
        guard url.scheme == "couchpotato" else { return }
        switch url.host {
        case "title":
            if let ref = TitleRef(key: url.lastPathComponent) { open(ref) }
        case "roulette", "shuffle": selection = .tab(.roulette)
        case "planner": selection = .tab(.planner)
        case "queue", "watchlist": selection = .tab(.queue)
        default: break
        }
    }

    func search(_ text: String) {
        selection = .tab(.search)
        paths[.tab(.search)] = NavigationPath()
        pendingSearch = text
    }

    func plan(_ title: CatalogTitle?) {
        planningTitle = title
        isPlanning = true
    }
}

enum TabSelection: Hashable {
    case tab(AppTab)
    case service(String)
}
