import SwiftUI
import SwiftData

@main
struct CouchPotatoApp: App {
    @State private var prefs: Preferences
    @State private var catalog: Catalog
    @State private var app = AppModel()
    let container: ModelContainer

    init() {
        let prefs = Preferences()
        _prefs = State(initialValue: prefs)
        _catalog = State(initialValue: Catalog(prefs: prefs))
        container = Self.makeContainer()
    }

    /// CloudKit-backed store when the app is signed with the iCloud entitlement,
    /// otherwise a plain local store (e.g. unsigned simulator builds).
    static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedTitle.self, CouchNight.self])
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if !inMemory, let cloud = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)) {
            return cloud
        }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try! ModelContainer(for: schema, configurations: local)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(prefs)
                .environment(catalog)
                .environment(app)
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
                .frame(width: 600, height: 760)
                .modelContainer(container)
        }
        #endif
    }
}
