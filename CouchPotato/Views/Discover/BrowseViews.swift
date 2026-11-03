import SwiftUI

struct MoodView: View {
    var mood: Mood
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var kind: MediaKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Text(mood.emoji).font(.system(size: 54))
                    VStack(alignment: .leading) {
                        Text(mood.title).font(.spudTitle).foregroundStyle(Spud.ink)
                        Text(mood.blurb).font(.spudBody).foregroundStyle(Spud.inkSoft)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .spudCard(mood.color.opacity(0.25))
                .padding(.horizontal)

                KindPicker(kind: $kind).padding(.horizontal)

                Loadable(id: "mood-\(mood.id)-\(kind?.rawValue ?? "all")-\(prefs.region)-\(catalog.hasTMDB)-\(prefs.onlyMyServices)",
                         load: { try await catalog.mood(mood, kind: kind) }) { titles in
                    if titles.isEmpty {
                        SpudMessage(title: "Nothing in this mood… yet", message: "Spud came up empty. Try another vibe or add a TMDB key in Settings.", expression: .sleepy)
                    } else {
                        PosterGrid(titles: titles)
                    }
                }
            }
            .padding(.vertical)
        }
        .spudBackground()
        .navigationTitle(mood.title)
        .inlineTitle()
    }
}

struct ProviderView: View {
    var provider: Provider
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var kind: MediaKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(provider.emoji) \(provider.name)")
                            .font(.spudTitle)
                            .foregroundStyle(.white)
                        Text(prefs.isMine(provider) ? "One of your services ✓" : "Not one of your services (yet)")
                            .font(.spudCaption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Button(prefs.isMine(provider) ? "Remove" : "I have this") { prefs.toggle(provider) }
                        .buttonStyle(.chunky(.white, foreground: provider.color))
                }
                .spudCard(provider.color)
                .padding(.horizontal)

                if catalog.hasTMDB { KindPicker(kind: $kind).padding(.horizontal) }

                Loadable(id: "svc-\(provider.id)-\(kind?.rawValue ?? "all")-\(prefs.region)-\(catalog.hasTMDB)",
                         load: { try await catalog.onService(provider, kind: kind) }) { titles in
                    if titles.isEmpty {
                        SpudMessage(title: "Spud's search came up dry",
                                    message: catalog.hasTMDB ? "Nothing found for \(provider.name) in \(prefs.region)." : "Without a TMDB key Spud only sees shows airing this week. Add a free key in Settings to browse the full \(provider.name) catalog.",
                                    expression: .sleepy)
                    } else {
                        PosterGrid(titles: titles)
                    }
                }
            }
            .padding(.vertical)
        }
        .spudBackground()
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
        .spudBackground()
        .navigationTitle(title)
        .inlineTitle()
    }
}

struct KindPicker: View {
    @Binding var kind: MediaKind?

    var body: some View {
        Picker("Type", selection: $kind) {
            Text("Everything").tag(MediaKind?.none)
            Text("Movies").tag(MediaKind?.some(.movie))
            Text("Series").tag(MediaKind?.some(.tv))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
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
