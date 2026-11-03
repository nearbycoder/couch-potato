import SwiftUI

struct MoodView: View {
    var mood: Mood
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(\.layout) private var layout
    @State private var kind: MediaKind?
    @State private var filter = TitleFilter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    KindPicker(kind: $kind)
                    FilterBar(filter: $filter, showsGenre: false)
                }
                .padding(.horizontal, layout.margin)

                PagedGrid(id: "mood-\(mood.id)-\(kind?.rawValue ?? "all")-\(filter.key)-\(prefs.region)-\(catalog.hasTMDB)-\(prefs.onlyMyServices)",
                          load: { try await catalog.mood(mood, kind: kind, filter: filter, page: $0) }) {
                    if filter.isDefault {
                        EmptyState(symbol: "rectangle.on.rectangle.slash", title: "Nothing here yet",
                                   message: "Try another mood, or add a TMDB API key in Settings for the full catalog.")
                    } else {
                        FilterEmptyState { filter = TitleFilter() }
                    }
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
    @State private var filter = TitleFilter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    if catalog.hasTMDB { KindPicker(kind: $kind) }
                    FilterBar(filter: $filter)
                    if !catalog.hasTMDB {
                        Text("Series only. Add a free TMDB key in Settings to see \(provider.name) movies too.")
                            .font(.footnote).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, layout.margin)

                PagedGrid(id: "svc-\(provider.id)-\(kind?.rawValue ?? "all")-\(filter.key)-\(prefs.region)-\(catalog.hasTMDB)",
                          load: { try await catalog.onService(provider, kind: kind, filter: filter, page: $0) }) {
                    if filter.isDefault {
                        EmptyState(symbol: "play.tv", title: "Nothing to show",
                                   message: catalog.hasTMDB
                                   ? "No titles found for \(provider.name) in \(prefs.region)."
                                   : "No series found for \(provider.name). Add a free TMDB API key in Settings to browse movies too.")
                    } else {
                        FilterEmptyState { filter = TitleFilter() }
                    }
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

    @Environment(\.layout) private var layout
    @State private var filter = TitleFilter()

    var body: some View {
        let shown = filter.apply(titles)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FilterBar(filter: $filter).padding(.horizontal, layout.margin)
                if shown.isEmpty {
                    FilterEmptyState { filter = TitleFilter() }
                } else {
                    PosterGrid(titles: shown)
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle(title)
        .inlineTitle()
    }
}

/// Sort, release-year, genre and rating menus for browse pages. Wraps on narrow screens.
struct FilterBar: View {
    @Binding var filter: TitleFilter
    var showsGenre = true

    var body: some View {
        FlowLayout(spacing: 8) {
            menu("Sort", value: filter.sort.label, systemImage: "arrow.up.arrow.down", active: filter.sort != .popular) {
                Picker("Sort", selection: $filter.sort) {
                    ForEach(TitleFilter.Sort.allCases) { Text($0.label).tag($0) }
                }
            }
            menu("Released", value: filter.years.label, systemImage: "calendar", active: filter.years != .any) {
                Picker("Released", selection: $filter.years) {
                    ForEach(TitleFilter.Years.allCases) { Text($0.label).tag($0) }
                }
            }
            if showsGenre {
                menu("Genre", value: filter.genre?.label ?? "Any Genre", systemImage: "theatermasks", active: filter.genre != nil) {
                    Picker("Genre", selection: $filter.genre) {
                        Text("Any Genre").tag(TitleFilter.Genre?.none)
                        ForEach(TitleFilter.Genre.allCases) { Text($0.label).tag(TitleFilter.Genre?.some($0)) }
                    }
                }
            }
            menu("Rating", value: filter.minRating.map { "\(Int($0))+ Rating" } ?? "Any Rating", systemImage: "star",
                 active: filter.minRating != nil) {
                Picker("Rating", selection: $filter.minRating) {
                    Text("Any Rating").tag(Double?.none)
                    ForEach(TitleFilter.ratingSteps, id: \.self) { Text("\(Int($0))+").tag(Double?.some($0)) }
                }
            }
            if !filter.isDefault {
                Button("Reset") { withAnimation(.snappy) { filter = TitleFilter() } }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .frame(height: 32)
            }
        }
        .animation(.snappy, value: filter)
    }

    private func menu<Content: View>(_ title: String, value: String, systemImage: String, active: Bool,
                                     @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.caption.weight(.semibold))
                Text(value).font(.subheadline.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).opacity(0.7)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(active ? Theme.onAccent : Theme.textPrimary)
            .background(active ? Theme.accent : Theme.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

struct FilterEmptyState: View {
    var reset: () -> Void

    var body: some View {
        EmptyState(symbol: "line.3.horizontal.decrease.circle", title: "No matches",
                   message: "No titles match these filters.", actionTitle: "Reset Filters", action: reset)
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
