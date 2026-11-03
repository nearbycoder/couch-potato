import SwiftUI

struct MoodView: View {
    var mood: Mood
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(\.layout) private var layout
    @State private var kind: MediaKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                KindPicker(kind: $kind).padding(.horizontal, layout.margin)

                PagedGrid(id: "mood-\(mood.id)-\(kind?.rawValue ?? "all")-\(prefs.region)-\(catalog.hasTMDB)-\(prefs.onlyMyServices)",
                          load: { try await catalog.mood(mood, kind: kind, page: $0) }) {
                    EmptyState(symbol: "rectangle.on.rectangle.slash", title: "Nothing here yet",
                               message: "Try another mood, or add a TMDB API key in Settings for the full catalog.")
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle(mood.title)
        .navigationSubtitle(mood.blurb)
        .largeTitle()
    }
}

struct ProviderView: View {
    var provider: Provider
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(\.layout) private var layout
    @State private var kind: MediaKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if catalog.hasTMDB {
                    KindPicker(kind: $kind).padding(.horizontal, layout.margin)
                } else {
                    Text("Series only. Add a free TMDB key in Settings to see \(provider.name) movies too.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, layout.margin)
                }

                PagedGrid(id: "svc-\(provider.id)-\(kind?.rawValue ?? "all")-\(prefs.region)-\(catalog.hasTMDB)",
                          load: { try await catalog.onService(provider, kind: kind, page: $0) }) {
                    EmptyState(symbol: "play.tv", title: "Nothing to show",
                               message: catalog.hasTMDB
                               ? "No titles found for \(provider.name) in \(prefs.region)."
                               : "No series found for \(provider.name). Add a free TMDB API key in Settings to browse movies too.")
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle(provider.name)
        .navigationSubtitle(prefs.isMine(provider) ? "One of your services" : "")
        .largeTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    prefs.toggle(provider)
                } label: {
                    Label(prefs.isMine(provider) ? "Remove from My Services" : "Add to My Services",
                          systemImage: prefs.isMine(provider) ? "checkmark.circle.fill" : "plus.circle")
                }
                .help(prefs.isMine(provider) ? "Remove from My Services" : "Add to My Services")
            }
        }
    }
}

struct TitleListView: View {
    var title: String
    var titles: [CatalogTitle]

    var body: some View {
        ScrollView {
            PosterGrid(titles: titles).padding(.vertical)
        }
        .appBackground()
        .navigationTitle(title)
        .inlineTitle()
    }
}

struct KindPicker: View {
    @Binding var kind: MediaKind?

    var body: some View {
        Picker("Type", selection: $kind) {
            Text("All").tag(MediaKind?.none)
            Text("Movies").tag(MediaKind?.some(.movie))
            Text("Series").tag(MediaKind?.some(.tv))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
    }
}

/// Shared destinations for every navigation stack.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .title(let ref, let preview): TitleDetailView(ref: ref, preview: preview)
            case .mood(let mood): MoodView(mood: mood)
            case .provider(let provider): ProviderView(provider: provider)
            case .list(let title, let titles): TitleListView(title: title, titles: titles)
            }
        }
    }
}

extension View {
    func withRoutes() -> some View { modifier(RouteDestinations()) }
}
