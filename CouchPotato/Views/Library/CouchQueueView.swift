import SwiftUI
import SwiftData

struct WatchlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Environment(\.layout) private var layout
    @Query(sort: \SavedTitle.addedAt, order: .reverse) private var saved: [SavedTitle]

    @State private var status: WatchStatus = .queued
    @State private var kind: MediaKind?
    @State private var sort: Sort = .recent
    @State private var serviceFilter: String?
    @State private var searchText = ""

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recently Added", name = "Title", rating = "Rating", year = "Year"
        var id: String { rawValue }
    }

    private var filtered: [SavedTitle] {
        var items = saved.filter { $0.status == status }
        if let kind { items = items.filter { $0.kind == kind } }
        if let serviceFilter { items = items.filter { $0.providerIDs.contains(serviceFilter) } }
        if !searchText.isEmpty { items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
        switch sort {
        case .recent: break
        case .name: items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .rating: items.sort { $0.potatoes > $1.potatoes }
        case .year: items.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        return items
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusTabs.padding(.horizontal, layout.margin)
                filters.padding(.horizontal, layout.margin)

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.gridMinWidth), spacing: layout.isCompact ? 12 : 14, alignment: .top)], spacing: 20) {
                        ForEach(filtered) { item in
                            NavigationLink(value: Route.title(item.ref, preview: item.asCatalogTitle)) {
                                WatchlistCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(.horizontal, layout.margin)
                    .focusEffectDisabled()
                }
            }
            .padding(.vertical)
        }
        .appBackground()
        .navigationTitle("Watchlist")
        .searchable(text: $searchText, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private var statusTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WatchStatus.allCases) { s in
                    let count = saved.filter { $0.status == s }.count
                    let selected = status == s
                    Button {
                        withAnimation(.snappy) { status = s }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.label)
                            Text("\(count)").foregroundStyle(selected ? Theme.bg.opacity(0.7) : Theme.textTertiary)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selected ? Theme.bg : Theme.textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(selected ? Theme.textPrimary : Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                KindPicker(kind: $kind).frame(width: 240)
                let providers = Provider.all.filter { p in saved.contains { $0.providerIDs.contains(p.id) } }
                ForEach(providers) { p in
                    Button {
                        serviceFilter = serviceFilter == p.id ? nil : p.id
                    } label: {
                        HStack(spacing: 6) {
                            ProviderTile(provider: p, size: 20)
                            Text(p.shortName).font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.fill, in: Capsule())
                        .overlay(Capsule().strokeBorder(serviceFilter == p.id ? Theme.accent : .clear))
                        .opacity(serviceFilter == nil || serviceFilter == p.id ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch status {
        case .queued:
            EmptyState(symbol: "bookmark", title: "Your watchlist is empty",
                       message: "Find something on Tonight or Browse and add it here.",
                       actionTitle: "Browse") { app.selection = .tab(.search) }
        case .watching:
            EmptyState(symbol: "play.circle", title: "Nothing in progress",
                       message: "Start something from your watchlist and track every episode here.")
        case .watched:
            EmptyState(symbol: "checkmark.circle", title: "Nothing watched yet",
                       message: "Mark titles as watched to build your history and level up.")
        case .dropped:
            EmptyState(symbol: "minus.circle", title: "Nothing dropped",
                       message: "Titles you gave up on will appear here.")
        }
    }

    @ViewBuilder
    private func menu(for item: SavedTitle) -> some View {
        ForEach(WatchStatus.allCases) { s in
            Button { item.status = s } label: { Label(s.label, systemImage: s.symbol) }
        }
        Button { app.plan(item.asCatalogTitle) } label: { Label("Plan a Night…", systemImage: "calendar.badge.plus") }
        Divider()
        Button("Remove", systemImage: "trash", role: .destructive) { context.delete(item) }
    }
}

struct WatchlistCard: View {
    var item: SavedTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { RemoteImage(url: item.posterURL, maxPixel: 500, placeholderTitle: item.name) }
                .artwork()
                .overlay(alignment: .topLeading) {
                    if let p = item.providers.first(where: { $0 != .appleStore }) {
                        ProviderTile(provider: p, size: 22).padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.isFollowing {
                        Image(systemName: "bell.fill").font(.caption2).foregroundStyle(Theme.textPrimary)
                            .padding(6).background(.ultraThinMaterial, in: Circle()).padding(6)
                    }
                }
                .softShadow(radius: 8, y: 4)
            Text(item.name).font(.posterTitle).foregroundStyle(Theme.textPrimary).lineLimit(1)
            if item.potatoes > 0 {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= item.potatoes ? "star.fill" : "star")
                            .font(.system(size: 9))
                            .foregroundStyle(i <= item.potatoes ? Theme.accent : Theme.textTertiary)
                    }
                }
            } else if let progress = item.progressLabel {
                Text(progress).font(.caption).foregroundStyle(Theme.success).lineLimit(1)
            } else {
                Text([item.year.map(String.init), item.kind.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }
}
