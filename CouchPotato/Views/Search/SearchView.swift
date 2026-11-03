import SwiftUI

struct SearchView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var query = ""
    @State private var results: [CatalogTitle] = []
    @State private var isSearching = false
    @State private var kind: MediaKind?

    private let suggestions = ["Severance", "The Bear", "Dune", "Bluey", "Only Murders", "Paddington", "Shōgun", "The Office"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    idle
                } else if isSearching && results.isEmpty {
                    SpudLoading(label: "Rummaging through the couch cushions…")
                } else if results.isEmpty {
                    SpudMessage(title: "No spuds found", message: "Nothing matched “\(query)”. Check the spelling, or try a shorter title.", expression: .wow)
                } else {
                    KindPicker(kind: $kind).padding(.horizontal)
                    PosterGrid(titles: results.filter { kind == nil || $0.kind == kind })
                }
            }
            .padding(.vertical)
        }
        .spudBackground()
        .navigationTitle("Search")
        .searchable(text: $query, placement: .automatic, prompt: "Movies, shows, guilty pleasures…")
        .task(id: query) {
            let text = query
            guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350)) // debounce
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = (try? await catalog.search(text)) ?? []
            guard !Task.isCancelled else { return }
            results = prefs.onlyMyServices && catalog.hasTMDB == false
                ? found.filter { $0.providers.isEmpty || $0.providers.contains(where: prefs.isMine) }
                : found
            isSearching = false
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                SpudMascot(size: 70, expression: .wow, gaze: 0.6)
                VStack(alignment: .leading, spacing: 4) {
                    Text("What are we hunting for?").font(.spudHeadline).foregroundStyle(Spud.ink)
                    Text(catalog.hasTMDB ? "Every movie and series, across every service." : "Series via TVmaze, movies from Apple's charts. Add a TMDB key for everything.")
                        .font(.spudBody).foregroundStyle(Spud.inkSoft)
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Try one of these", emoji: "💡")
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { query = s } label: { Pill(text: s, systemImage: "magnifyingglass", color: Spud.card) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Browse by service", emoji: "📺")
                FlowLayout(spacing: 8) {
                    ForEach(Provider.streamers) { p in
                        NavigationLink(value: Route.provider(p)) {
                            ProviderChip(provider: p, isMine: prefs.isMine(p))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)

            MoodStrip().padding(.horizontal)
        }
    }
}
