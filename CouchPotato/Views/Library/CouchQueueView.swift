import SwiftUI
import SwiftData

struct CouchQueueView: View {
    @Environment(\.modelContext) private var context
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Query(sort: \SavedTitle.addedAt, order: .reverse) private var saved: [SavedTitle]

    @State private var status: WatchStatus = .queued
    @State private var kind: MediaKind?
    @State private var sort: Sort = .recent
    @State private var serviceFilter: String?
    @State private var searchText = ""

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recently added", name = "A to Z", rating = "Most potatoes", year = "Newest"
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
                statusTabs.padding(.horizontal)
                filters.padding(.horizontal)

                if filtered.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Device.isPhone ? 105 : 150), spacing: 14, alignment: .top)], spacing: 20) {
                        ForEach(filtered) { item in
                            NavigationLink(value: Route.title(item.ref, preview: item.asCatalogTitle)) {
                                QueueCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .spudBackground()
        .navigationTitle("Couch Queue")
        .searchable(text: $searchText, prompt: "Filter your couch")
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
                    Button {
                        withAnimation(.spring(response: 0.3)) { status = s }
                    } label: {
                        HStack(spacing: 6) {
                            Text(s.emoji)
                            Text(s.shortLabel)
                            Text("\(count)")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.white.opacity(0.35), in: Capsule())
                        }
                        .font(Spud.display(15, weight: .bold))
                        .foregroundStyle(status == s ? .white : Spud.ink)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(status == s ? Spud.brown : Spud.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                KindPicker(kind: $kind).frame(width: 260)
                let providers = Provider.all.filter { p in saved.contains { $0.providerIDs.contains(p.id) } }
                ForEach(providers) { p in
                    Button {
                        serviceFilter = serviceFilter == p.id ? nil : p.id
                    } label: {
                        ProviderChip(provider: p, isMine: serviceFilter == p.id, compact: true)
                            .opacity(serviceFilter == nil || serviceFilter == p.id ? 1 : 0.45)
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
            SpudMessage(title: "Your couch is empty!", message: "Find something good on Tonight or Search and tap “Add to Couch Queue”. Spud will keep it warm.",
                        expression: .wow, actionTitle: "Find something") { app.selection = .tab(.tonight) }
        case .watching:
            SpudMessage(title: "Nothing in progress", message: "Start something from your queue — Spud will track every episode.", expression: .sleepy)
        case .watched:
            SpudMessage(title: "No trophies yet", message: "Mark things watched to climb from Raw Spud to Mashed Royalty.", expression: .happy)
        case .dropped:
            SpudMessage(title: "No regrets here", message: "Things you gave up on land here. Life's too short for bad TV.", expression: .wink)
        }
    }

    @ViewBuilder
    private func menu(for item: SavedTitle) -> some View {
        ForEach(WatchStatus.allCases) { s in
            Button { item.status = s } label: { Label(s.label, systemImage: s.symbol) }
        }
        Button { app.plan(item.asCatalogTitle) } label: { Label("Plan a Couch Night…", systemImage: "calendar.badge.plus") }
        Divider()
        Button("Remove", systemImage: "trash", role: .destructive) { context.delete(item) }
    }
}

struct QueueCard: View {
    var item: SavedTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: item.posterURL, maxPixel: 500, placeholderTitle: item.name)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let p = item.providers.first(where: { $0 != .appleStore }) { ProviderDot(provider: p).padding(6) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if item.isFollowing {
                        Image(systemName: "bell.fill").font(.system(size: 11)).foregroundStyle(.white)
                            .padding(6).background(Spud.teal, in: Circle()).padding(6)
                    }
                }
                .shadow(color: .black.opacity(0.15), radius: 4, y: 3)
            Text(item.name).font(Spud.display(13, weight: .bold)).foregroundStyle(Spud.ink).lineLimit(1)
            if item.potatoes > 0 {
                Text(String(repeating: "🥔", count: item.potatoes)).font(.system(size: 11))
            } else if let progress = item.progressLabel {
                Text(progress).font(.system(size: 11, design: .rounded)).foregroundStyle(Spud.teal).lineLimit(1)
            } else {
                Text([item.year.map(String.init), item.kind.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Spud.inkSoft)
            }
        }
    }
}
