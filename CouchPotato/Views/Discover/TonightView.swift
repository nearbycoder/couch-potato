import SwiftUI
import SwiftData

/// The home feed.
struct TonightView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Environment(\.layout) private var layout
    @Query(sort: \SavedTitle.updatedAt, order: .reverse) private var saved: [SavedTitle]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                Loadable(id: "hero-\(prefs.region)-\(catalog.hasTMDB)", load: { try await catalog.trending() }) { titles in
                    HeroCarousel(titles: Array(titles.prefix(8)))
                }

                let upNext = saved.filter { $0.status == .watching || $0.status == .queued }.prefix(15).map(\.asCatalogTitle)
                if !upNext.isEmpty {
                    PosterRow(title: "Up Next", subtitle: "From your watchlist", titles: Array(upNext), seeAll: nil)
                }

                AsyncRow(id: "trending", title: "Trending This Week") { try await catalog.trending() }

                AsyncRow(id: "fresh", title: "New on Streaming",
                         subtitle: catalog.hasTMDB ? "Recent arrivals on your services" : "Episodes released in the last few days") {
                    try await catalog.freshOnStreaming()
                }

                MoodsRow()

                ForEach(featuredServices) { provider in
                    AsyncRow(id: "svc-\(provider.id)", title: "Popular on \(provider.name)",
                             subtitle: prefs.isMine(provider) ? "One of your services" : nil,
                             seeAll: .provider(provider)) {
                        try await catalog.onService(provider)
                    }
                }

                AsyncRow(id: "popular-movie", title: "Popular Movies") { try await catalog.popular(.movie) }
                AsyncRow(id: "popular-tv", title: "Popular Series") { try await catalog.popular(.tv) }

                AttributionFooter()
            }
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle("Tonight")
        .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.selection = .tab(.roulette)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
            }
            #if os(iOS)
            if layout.isCompact {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        app.showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            #endif
        }
        .refreshable { catalog.reset() }
    }

    private var featuredServices: [Provider] {
        let mine = prefs.myServices
        return mine.isEmpty ? [.netflix, .hulu, .disney, .hbo, .apple, .prime] : mine
    }
}

struct AsyncRow: View {
    var id: String
    var title: String
    var subtitle: String?
    var seeAll: Route?
    var load: () async throws -> [CatalogTitle]

    @Environment(Preferences.self) private var prefs
    @Environment(Catalog.self) private var catalog
    @Environment(\.layout) private var layout
    @State private var titles: [CatalogTitle] = []
    @State private var failed = false

    var body: some View {
        Group {
            if !titles.isEmpty {
                PosterRow(title: title, subtitle: subtitle, titles: titles, seeAll: seeAll ?? .list(title, titles))
            } else if !failed {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: title, subtitle: subtitle).padding(.horizontal, layout.margin)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<8, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Theme.posterRadius, style: .continuous)
                                    .fill(Theme.surfaceElevated)
                                    .frame(width: layout.posterWidth, height: layout.posterWidth * 1.5)
                            }
                        }
                        .padding(.horizontal, layout.margin)
                    }
                }
            }
        }
        .task(id: "\(id)-\(prefs.region)-\(catalog.hasTMDB)-\(prefs.myServiceIDs.count)") {
            do {
                titles = try await load()
                failed = titles.isEmpty
            } catch is CancellationError {
            } catch {
                failed = titles.isEmpty
            }
        }
    }
}

/// Paging hero carousel with a page indicator.
struct HeroCarousel: View {
    var titles: [CatalogTitle]

    @Environment(\.layout) private var layout
    @State private var current: String?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(titles) { title in
                        HeroCard(title: title)
                            .containerRelativeFrame(.horizontal) { length, _ in cardWidth(in: length) }
                            .id(title.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, layout.margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)

            HStack(spacing: 6) {
                ForEach(titles) { title in
                    Capsule()
                        .fill(title.id == (current ?? titles.first?.id) ? Theme.textPrimary : Theme.textTertiary.opacity(0.5))
                        .frame(width: title.id == (current ?? titles.first?.id) ? 18 : 6, height: 6)
                        .animation(.easeOut(duration: 0.25), value: current)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// One card per page on phones; on wider screens cards stay at least ~760 pt wide
    /// (so text and artwork never crowd) and a single card leaves the next one peeking in.
    private func cardWidth(in length: CGFloat) -> CGFloat {
        if layout.isCompact { return length }
        let pages = max(1, Int((length + 16) / 776))
        if pages == 1 { return length - 64 }
        return (length - 16 * CGFloat(pages - 1)) / CGFloat(pages)
    }
}

struct HeroCard: View {
    var title: CatalogTitle

    @Environment(\.layout) private var layout
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var saved: [SavedTitle]

    private var isSaved: Bool { saved.contains { $0.key == title.ref.key } }
    /// Wide layout without a backdrop: the poster sits in its own column beside the text.
    private var posterMode: Bool { !layout.isCompact && title.backdropURL == nil }
    private var posterHeight: CGFloat { layout.heroHeight - 64 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The artwork is an overlay so a wide backdrop can't stretch the layout.
            Color.clear
                .frame(height: layout.heroHeight)
                .frame(maxWidth: .infinity)
                .overlay { heroImage }
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { app.push(.detail(title)) }

            if !posterMode {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .black.opacity(0.55), location: 0.7),
                    .init(color: .black.opacity(0.92), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 10) {
                Pill(text: title.kind.label, tint: .white.opacity(0.16), foreground: .white)
                Text(title.name)
                    .font(layout.isCompact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(title.metaLine)
                    if let score = title.score {
                        Text("·")
                        Image(systemName: "star.fill").font(.caption2)
                        Text(String(format: "%.1f", score))
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

                if posterMode, !title.overview.isEmpty {
                    Text(title.overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(4)
                        .frame(maxWidth: 440, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button {
                        if !isSaved { Library.save(title, status: .queued, in: context) }
                    } label: {
                        Label(isSaved ? "In Watchlist" : "Add to Watchlist", systemImage: isSaved ? "checkmark" : "plus")
                    }
                    .buttonStyle(.primary)
                    .disabled(isSaved)
                    Button {
                        app.push(.detail(title))
                    } label: {
                        Text("Details")
                    }
                    .buttonStyle(.secondary)
                    .environment(\.colorScheme, .dark)
                }
                .lineLimit(1)
                .fixedSize()
                .padding(.top, 4)
            }
            .padding(layout.isCompact ? 18 : 28)
            // Keep the text clear of the poster column.
            .padding(.trailing, posterMode ? posterHeight * 2 / 3 + 40 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
        .softShadow(radius: 20, y: 10)
        .titleContextMenu(title)
    }

    @ViewBuilder
    private var heroImage: some View {
        if title.backdropURL != nil, !layout.isCompact {
            RemoteImage(url: title.backdropURL, maxPixel: 1600, placeholderTitle: title.name)
        } else if layout.isCompact {
            RemoteImage(url: title.posterURL ?? title.backdropURL, maxPixel: 900, placeholderTitle: title.name)
        } else {
            // Poster-only sources on wide layouts: a dark wash tinted by the artwork, the poster at the trailing edge.
            ZStack(alignment: .trailing) {
                RemoteImage(url: title.posterURL, maxPixel: 300, placeholderTitle: nil)
                    .blur(radius: 48)
                    .scaleEffect(1.5)
                LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.55), .black.opacity(0.35)],
                               startPoint: .leading, endPoint: .trailing)
                RemoteImage(url: title.posterURL, maxPixel: 700, placeholderTitle: title.name)
                    .frame(width: posterHeight * 2 / 3, height: posterHeight)
                    .artwork(radius: 10)
                    .softShadow(radius: 16, y: 8)
                    .padding(.trailing, 28)
            }
        }
    }
}

struct MoodsRow: View {
    @Environment(\.layout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Moods", subtitle: "Browse by how you feel").padding(.horizontal, layout.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: Route.mood(mood)) {
                            MoodTile(mood: mood).frame(width: layout.isCompact ? 190 : 220)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, layout.margin)
                .padding(.vertical, 4)
            }
            .focusEffectDisabled()
        }
    }
}

struct AttributionFooter: View {
    @Environment(Catalog.self) private var catalog
    @Environment(\.layout) private var layout

    var body: some View {
        Text(catalog.hasTMDB
             ? "Data and artwork from TMDB. Streaming availability by JustWatch. This product uses the TMDB API but is not endorsed or certified by TMDB."
             : "Series data from TVmaze (CC BY-SA). Movie charts from Apple. Add a TMDB API key in Settings for the full catalog and all-provider availability.")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, layout.margin)
            .padding(.top, 8)
    }
}
