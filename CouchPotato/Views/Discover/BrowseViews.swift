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
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: mood.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: mood.symbol).font(.title2).foregroundStyle(.white.opacity(0.9)).padding(.bottom, 6)
                        Text(mood.title).font(.title.bold()).foregroundStyle(.white)
                        Text(mood.blurb).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(20)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, layout.margin)

                KindPicker(kind: $kind).padding(.horizontal, layout.margin)

                Loadable(id: "mood-\(mood.id)-\(kind?.rawValue ?? "all")-\(prefs.region)-\(catalog.hasTMDB)-\(prefs.onlyMyServices)",
                         load: { try await catalog.mood(mood, kind: kind) }) { titles in
                    if titles.isEmpty {
                        EmptyState(symbol: "rectangle.on.rectangle.slash", title: "Nothing here yet",
                                   message: "Try another mood, or add a TMDB API key in Settings for the full catalog.")
                    } else {
                        PosterGrid(titles: titles)
                    }
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle(mood.title)
        .inlineTitle()
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
                HStack(spacing: 14) {
                    ProviderTile(provider: provider, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.name).font(.title2.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(prefs.isMine(provider) ? "One of your services" : "Not in your services")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        prefs.toggle(provider)
                        catalog.reset()
                    } label: {
                        Label(prefs.isMine(provider) ? "Added" : "Add", systemImage: prefs.isMine(provider) ? "checkmark" : "plus")
                    }
                    .buttonStyle(.secondary)
                }
                .card()
                .padding(.horizontal, layout.margin)

                if catalog.hasTMDB { KindPicker(kind: $kind).padding(.horizontal, layout.margin) }

                Loadable(id: "svc-\(provider.id)-\(kind?.rawValue ?? "all")-\(prefs.region)-\(catalog.hasTMDB)",
                         load: { try await catalog.onService(provider, kind: kind) }) { titles in
                    if titles.isEmpty {
                        EmptyState(symbol: "play.tv", title: "Nothing to show",
                                   message: catalog.hasTMDB
                                   ? "No titles found for \(provider.name) in \(prefs.region)."
                                   : "Without a TMDB API key only series airing this week are visible. Add a free key in Settings to browse the full \(provider.name) catalog.")
                    } else {
                        PosterGrid(titles: titles)
                    }
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle(provider.name)
        .inlineTitle()
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
