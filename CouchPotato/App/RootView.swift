import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavedTitle> { $0.statusRaw == "queued" }) private var queued: [SavedTitle]

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selection) {
            Tab(AppTab.tonight.title, systemImage: AppTab.tonight.symbol, value: TabSelection.tab(.tonight)) {
                stack(.tab(.tonight)) { TonightView() }
            }
            Tab(value: TabSelection.tab(.search), role: .search) {
                stack(.tab(.search)) { SearchView() }
            }
            Tab(AppTab.queue.title, systemImage: AppTab.queue.symbol, value: TabSelection.tab(.queue)) {
                stack(.tab(.queue)) { CouchQueueView() }
            }
            .badge(queued.count)
            Tab(AppTab.planner.title, systemImage: AppTab.planner.symbol, value: TabSelection.tab(.planner)) {
                stack(.tab(.planner)) { PlannerView() }
            }
            Tab(AppTab.roulette.title, systemImage: AppTab.roulette.symbol, value: TabSelection.tab(.roulette)) {
                stack(.tab(.roulette)) { RouletteView() }
            }
            #if os(iOS)
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: TabSelection.tab(.settings)) {
                stack(.tab(.settings)) { SettingsView() }
            }
            .defaultVisibility(.hidden, for: .tabBar)
            #endif

            TabSection("Streaming Services") {
                ForEach(sidebarServices) { provider in
                    Tab(provider.name, systemImage: "play.tv.fill", value: TabSelection.service(provider.id)) {
                        stack(.service(provider.id)) { ProviderView(provider: provider) }
                    }
                }
            }
            .defaultVisibility(.hidden, for: .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Spud.ketchup)
        .sheet(isPresented: $app.isPlanning) {
            PlanNightSheet(initialTitle: app.planningTitle)
        }
        .sheet(isPresented: $app.showOnboarding) {
            OnboardingView()
        }
        .onOpenURL { app.handle(url: $0) }
        .onContinueUserActivity(AppModel.titleActivity) { activity in
            if let key = activity.userInfo?["key"] as? String, let ref = TitleRef(key: key) { app.open(ref) }
        }
        .onAppear {
            Library.dedupe(in: context)
            if !prefs.hasOnboarded { app.showOnboarding = true }
        }
        #if os(iOS)
        .sheet(isPresented: $app.showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { app.showSettings = false } }
                    }
            }
        }
        #endif
    }

    private var sidebarServices: [Provider] {
        let mine = prefs.myServices
        return mine.isEmpty ? Array(Provider.streamers.prefix(8)) : mine
    }

    private func stack<Content: View>(_ tab: TabSelection, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: app.path(tab)) {
            content().withRoutes()
        }
    }
}
