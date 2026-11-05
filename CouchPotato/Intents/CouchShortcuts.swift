import AppIntents

/// Phrases Siri recognizes without any setup. Every phrase must name the app.
struct CouchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShuffleTonightIntent(), phrases: [
            "What should I watch on \(.applicationName)",
            "Pick something to watch with \(.applicationName)",
            "Shuffle \(.applicationName)",
        ], shortTitle: "What to Watch", systemImageName: "shuffle")

        AppShortcut(intent: FindSomethingToWatchIntent(), phrases: [
            "Find something to watch in \(.applicationName)",
            "Ask \(.applicationName) for a recommendation",
        ], shortTitle: "Find Something", systemImageName: "sparkles")

        AppShortcut(intent: ShowWatchlistIntent(), phrases: [
            "Show my \(.applicationName) watchlist",
            "What's on my \(.applicationName) watchlist",
        ], shortTitle: "Watchlist", systemImageName: "bookmark")

        AppShortcut(intent: AddToWatchlistIntent(), phrases: [
            "Add \(\.$title) to my \(.applicationName) watchlist",
            "Add a title to \(.applicationName)",
        ], shortTitle: "Add to Watchlist", systemImageName: "plus")

        AppShortcut(intent: WhereToWatchIntent(), phrases: [
            "Where can I watch \(\.$title) on \(.applicationName)",
            "Where is it streaming in \(.applicationName)",
        ], shortTitle: "Where to Watch", systemImageName: "play.tv")

        AppShortcut(intent: PlanNightIntent(), phrases: [
            "Plan a movie night in \(.applicationName)",
            "Schedule \(\.$title) in \(.applicationName)",
        ], shortTitle: "Plan a Night", systemImageName: "calendar.badge.plus")

        AppShortcut(intent: UpcomingNightsIntent(), phrases: [
            "What's planned in \(.applicationName)",
        ], shortTitle: "Planned Nights", systemImageName: "calendar")
    }
}
