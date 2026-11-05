import SwiftUI
import SwiftData

@main
struct CouchPotatoApp: App {
    @State private var prefs: Preferences
    @State private var catalog: Catalog
    @State private var app: AppModel
    @State private var sync: SyncMonitor
    @State private var intelligence: Intelligence
    let container: ModelContainer

    init() {
        let services = AppServices.shared
        _prefs = State(initialValue: services.prefs)
        _catalog = State(initialValue: services.catalog)
        _app = State(initialValue: services.app)
        _sync = State(initialValue: services.sync)
        _intelligence = State(initialValue: services.intelligence)
        container = services.container
        CouchShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prefs)
                .environment(catalog)
                .environment(app)
                .environment(sync)
                .environment(intelligence)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1280, height: 860)
        #endif
        .commands {
            CommandGroup(after: .newItem) {
                Button("Plan a Night…") { app.plan(nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                Button("Tonight") { app.selection = .tab(.tonight) }.keyboardShortcut("1")
                Button("Watchlist") { app.selection = .tab(.queue) }.keyboardShortcut("2")
                Button("Planner") { app.selection = .tab(.planner) }.keyboardShortcut("3")
                Button("Shuffle") { app.selection = .tab(.roulette) }.keyboardShortcut("4")
                Button("Browse") { app.selection = .tab(.search) }.keyboardShortcut("f")
                Divider()
                Button("Refresh") { catalog.reset() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(prefs)
                .environment(catalog)
                .environment(app)
                .environment(sync)
                .environment(intelligence)
                .frame(width: 600, height: 760)
                .modelContainer(container)
        }
        #endif
    }
}
