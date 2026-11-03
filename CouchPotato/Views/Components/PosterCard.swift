import SwiftUI
import SwiftData

/// Box art with caption and an optional watchlist status mark.
struct PosterCard: View {
    var title: CatalogTitle
    var width: CGFloat
    var showsCaption = true
    var status: WatchStatus?

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: title.posterURL, maxPixel: width * 3, placeholderTitle: title.name)
                .frame(width: width, height: width * 1.5)
                .artwork()
                .overlay(alignment: .topTrailing) {
                    if let status { StatusMark(status: status).padding(6) }
                }
                .softShadow(radius: hovering ? 16 : 8, y: hovering ? 10 : 4)
                .scaleEffect(hovering ? 1.03 : 1)

            if showsCaption {
                Text(title.name)
                    .font(.posterTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(title.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hovering = h } }
        .accessibilityElement(children: .combine)
    }
}

struct StatusMark: View {
    var status: WatchStatus

    var body: some View {
        Image(systemName: status.symbol)
            .symbolVariant(.fill)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel(status.label)
    }
}

/// A horizontally scrolling row of posters with a header and "See All".
struct PosterRow: View {
    var title: String
    var subtitle: String?
    var titles: [CatalogTitle]
    var seeAll: Route?

    @Environment(\.layout) private var layout
    @Query private var saved: [SavedTitle]

    var body: some View {
        let statusByKey = Dictionary(saved.map { ($0.key, $0.status) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: title, subtitle: subtitle)
                if let seeAll {
                    NavigationLink(value: seeAll) {
                        HStack(spacing: 2) {
                            Text("See All")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.seeAll)
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, layout.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(titles) { title in
                        PosterLink(route: .detail(title)) {
                            PosterCard(title: title, width: layout.posterWidth, status: statusByKey[title.ref.key])
                        }
                        .titleContextMenu(title)
                    }
                }
                .padding(.horizontal, layout.margin)
                .padding(.vertical, 8)
            }
            .focusEffectDisabled()
        }
    }
}

/// An adaptive grid of posters.
struct PosterGrid: View {
    var titles: [CatalogTitle]
    /// Called as the last few posters scroll into view, to fetch the next page.
    var onNearEnd: (() -> Void)?

    @Environment(\.layout) private var layout
    @Query private var saved: [SavedTitle]

    var body: some View {
        let statusByKey = Dictionary(saved.map { ($0.key, $0.status) }, uniquingKeysWith: { a, _ in a })
        let tail = Set(titles.suffix(12).map(\.id))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.gridMinWidth), spacing: layout.isCompact ? 12 : 14, alignment: .top)], spacing: 20) {
            ForEach(titles) { title in
                PosterLink(route: .detail(title)) {
                    GridPoster(title: title, status: statusByKey[title.ref.key])
                }
                .titleContextMenu(title)
                .onAppear { if tail.contains(title.id) { onNearEnd?() } }
            }
        }
        .padding(.horizontal, layout.margin)
        .focusEffectDisabled()
    }
}

/// A poster grid that keeps loading pages as you scroll, until a page comes back empty.
struct PagedGrid<Empty: View>: View {
    var id: String
    var load: (Int) async throws -> [CatalogTitle]
    @ViewBuilder var empty: () -> Empty

    @State private var titles: [CatalogTitle] = []
    @State private var nextPage = 1
    @State private var exhausted = false
    @State private var loading = false
    @State private var error: Error?
    @State private var attempt = 0

    var body: some View {
        Group {
            if !titles.isEmpty {
                VStack(spacing: 20) {
                    PosterGrid(titles: titles) { Task { await loadMore() } }
                    footer
                }
            } else if let error {
                EmptyState(symbol: "wifi.exclamationmark", title: "Couldn't load",
                           message: error.localizedDescription, actionTitle: "Try Again") { attempt += 1 }
            } else if exhausted {
                empty()
            } else {
                LoadingView()
            }
        }
        .task(id: "\(id)#\(attempt)") {
            titles = []
            nextPage = 1
            exhausted = false
            error = nil
            loading = false
            await loadMore()
        }
    }

    @ViewBuilder private var footer: some View {
        if loading {
            ProgressView().frame(height: 44)
        } else if error != nil, !exhausted {
            Button("Load More") { Task { await loadMore() } }.buttonStyle(.secondary)
        }
    }

    private func loadMore() async {
        guard !loading, !exhausted else { return }
        loading = true
        defer { loading = false }
        let page = nextPage
        do {
            let batch = try await load(page)
            guard page == nextPage else { return }
            let known = Set(titles.map(\.id))
            let fresh = batch.filter { !known.contains($0.id) }
            titles += fresh
            nextPage += 1
            error = nil
            // Stop on an empty page, or after a few pages that only repeat what we have.
            if batch.isEmpty || page >= 40 || (fresh.isEmpty && page > 1) { exhausted = true }
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }
}

/// A poster that fills its grid cell.
struct GridPoster: View {
    var title: CatalogTitle
    var status: WatchStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { RemoteImage(url: title.posterURL, maxPixel: 500, placeholderTitle: title.name) }
                .artwork()
                .overlay(alignment: .topTrailing) {
                    if let status { StatusMark(status: status).padding(6) }
                }
                .softShadow(radius: 8, y: 4)
            Text(title.name).font(.posterTitle).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text(title.subtitle).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

/// Quick actions on any poster.
struct TitleContextMenu: ViewModifier {
    var title: CatalogTitle
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.contextMenu {
            ForEach([WatchStatus.queued, .watching, .watched]) { status in
                Button {
                    Library.save(title, status: status, in: context)
                } label: {
                    Label(status.label, systemImage: status.symbol)
                }
            }
            Button {
                app.plan(title)
            } label: {
                Label("Plan a Night…", systemImage: "calendar.badge.plus")
            }
            ShareLink(item: title.ref.webURL ?? title.ref.deepLink, subject: Text(title.name),
                      message: Text("\(title.name) on Couch Potato"))
        }
    }
}

extension View {
    func titleContextMenu(_ title: CatalogTitle) -> some View { modifier(TitleContextMenu(title: title)) }
}

/// A mood tile: duotone gradient, symbol and title.
struct MoodTile: View {
    var mood: Mood

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: mood.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: mood.symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
            VStack(alignment: .leading, spacing: 2) {
                Text(mood.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                Text(mood.blurb).font(.caption).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
            }
            .padding(14)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A navigation push that never takes keyboard focus on macOS, so poster rows
/// don't show a focus outline when a window opens.
struct PosterLink<Label: View>: View {
    var route: Route
    @ViewBuilder var label: () -> Label
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            app.push(route)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }
}
