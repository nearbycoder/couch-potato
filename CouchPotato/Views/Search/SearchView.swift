import SwiftUI

/// Search plus browse-by-service and browse-by-mood.
struct BrowseView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(Intelligence.self) private var intelligence
    @Environment(\.layout) private var layout
    @State private var query = ""
    @State private var results: [CatalogTitle] = []
    @State private var isSearching = false
    @State private var kind: MediaKind?

    private let suggestions = ["Severance", "The Bear", "Dune", "Shōgun", "Paddington", "Only Murders in the Building", "Andor", "The Office"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    idle
                } else if isSearching && results.isEmpty {
                    LoadingView()
                } else if results.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No results",
                               message: "Nothing matched “\(query)”. Check the spelling or try a shorter title.")
                } else {
                    KindPicker(kind: $kind).padding(.horizontal, layout.margin)
                    PosterGrid(titles: results.filter { kind == nil || $0.kind == kind })
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle("Browse")
        .searchable(text: $query, placement: .automatic, prompt: "Movies and series")
        .task(id: query) {
            let text = query
            guard text.trimmingCharacters(in: .whitespaces).count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = (try? await catalog.search(text)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private var idle: some View {
        idleContent.focusEffectDisabled()
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if intelligence.isAvailable {
                AskCard().padding(.horizontal, layout.margin)
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Suggestions")
                FlowLayout(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { query = s } label: { Pill(text: s, systemImage: "magnifyingglass") }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, layout.margin)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Services", subtitle: prefs.myServices.isEmpty ? nil : "Yours are marked")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.isCompact ? 164 : 200), spacing: 10)], spacing: 10) {
                    ForEach(Provider.streamers) { p in
                        NavigationLink(value: Route.provider(p)) {
                            ProviderChip(provider: p, isSelected: prefs.isMine(p), showsCheck: prefs.isMine(p))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, layout.margin)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Moods")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.isCompact ? 150 : 220), spacing: 12)], spacing: 12) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: Route.mood(mood)) { MoodTile(mood: mood) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, layout.margin)

            if !catalog.hasTMDB {
                Text("Series search is powered by TVmaze; movie search covers Apple's charts. Add a TMDB API key in Settings to search everything.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, layout.margin)
            }
        }
    }
}
