import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var prefs
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<SavedTitle> { $0.statusRaw == "queued" }) private var queued: [SavedTitle]

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selection) {
            Tab(AppTab.tonight.title, systemImage: AppTab.tonight.symbol, value: TabSelection.tab(.tonight)) {
                stack(.tab(.tonight)) { TonightView() }
            }
            Tab(AppTab.queue.title, systemImage: AppTab.queue.symbol, value: TabSelection.tab(.queue)) {
                stack(.tab(.queue)) { WatchlistView() }
            }
            .badge(queued.count)
            Tab(AppTab.planner.title, systemImage: AppTab.planner.symbol, value: TabSelection.tab(.planner)) {
                stack(.tab(.planner)) { PlannerView() }
            }
            Tab(AppTab.roulette.title, systemImage: AppTab.roulette.symbol, value: TabSelection.tab(.roulette)) {
                stack(.tab(.roulette)) { ShuffleView() }
            }
            Tab(value: TabSelection.tab(.search), role: .search) {
                stack(.tab(.search)) { BrowseView() }
            }

            // Sidebar-only entries. Phones get Settings from the toolbar instead,
            // and services from Browse, so their tab bar stays at five items.
            if Self.hasSidebar {
                #if os(iOS)
                Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: TabSelection.tab(.settings)) {
                    stack(.tab(.settings)) { SettingsView() }
                }
                .defaultVisibility(.hidden, for: .tabBar)
                #endif

                TabSection("Services") {
                    ForEach(sidebarServices) { provider in
                        Tab(provider.name, systemImage: "play.tv", value: TabSelection.service(provider.id)) {
                            stack(.service(provider.id)) { ProviderView(provider: provider) }
                        }
                    }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
        }
        .modifier(AdaptiveTabStyle())
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tint(Theme.accent)
        .environment(\.layout, LayoutMetrics(isCompact: sizeClass == .compact))
        .sheet(isPresented: $app.isPlanning) {
            PlanNightSheet(initialTitle: app.planningTitle)
        }
        .sheet(isPresented: $app.showOnboarding) {
            OnboardingView()
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
        .onOpenURL { app.handle(url: $0) }
        .onContinueUserActivity(AppModel.titleActivity) { activity in
            if let key = activity.userInfo?["key"] as? String, let ref = TitleRef(key: key) { app.open(ref) }
        }
        .onAppear {
            Library.dedupe(in: context)
            if !prefs.hasOnboarded { app.showOnboarding = true }
            clearKeyboardFocus()
        }
        .onChange(of: app.selection) { clearKeyboardFocus() }
    }

    /// AppKit hands keyboard focus to the first poster when a window opens, which
    /// draws a focus outline around it. Posters don't need keyboard focus.
    private func clearKeyboardFocus() {
        #if os(macOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        #endif
    }

    static var hasSidebar: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        true
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

/// A sidebar on iPad and Mac; the standard tab bar on phone-class devices
/// (including the iPhone Duo, whose wide inner display would otherwise get an
/// unlabeled icon strip).
private struct AdaptiveTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if RootView.hasSidebar {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content.tabViewStyle(.tabBarOnly)
        }
    }
}
