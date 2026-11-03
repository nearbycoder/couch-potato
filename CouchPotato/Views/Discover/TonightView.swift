import SwiftUI
import SwiftData

/// "Tonight's Tater": the home feed.
struct TonightView: View {
    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Query(sort: \SavedTitle.updatedAt, order: .reverse) private var saved: [SavedTitle]
    @Query private var nights: [CouchNight]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                GreetingHeader(rank: CouchRank(titles: saved, nights: nights))
                    .padding(.horizontal)

                Loadable(id: "hero-\(prefs.region)-\(catalog.hasTMDB)", load: { try await catalog.trending() }) { titles in
                    HeroCarousel(titles: Array(titles.prefix(8)))
                }

                MoodStrip().padding(.horizontal)

                let upNext = saved.filter { $0.status == .watching || $0.status == .queued }.prefix(15).map(\.asCatalogTitle)
                if !upNext.isEmpty {
                    PosterRow(title: "Up next on your couch", subtitle: "Pick up where you left off", emoji: "🛋️",
                              titles: Array(upNext))
                }

                AsyncRow(id: "trending", title: "Trending this week", subtitle: "What every couch is talking about",
                         emoji: "🔥") { try await catalog.trending() }

                AsyncRow(id: "fresh", title: "Fresh on streaming", subtitle: catalog.hasTMDB ? "New arrivals on your services" : "Episodes that just dropped",
                         emoji: "🧈") { try await catalog.freshOnStreaming() }

                ForEach(featuredServices) { provider in
                    AsyncRow(id: "svc-\(provider.id)", title: "Hot on \(provider.name)", subtitle: prefs.isMine(provider) ? "On your services ✓" : nil,
                             emoji: provider.emoji, seeAll: .provider(provider)) {
                        try await catalog.onService(provider)
                    }
                }

                AsyncRow(id: "popular-movie", title: "Popular movies", emoji: "🎬") { try await catalog.popular(.movie) }
                AsyncRow(id: "popular-tv", title: "Popular series", emoji: "📺") { try await catalog.popular(.tv) }

                AttributionFooter()
            }
            .padding(.vertical)
        }
        .spudBackground()
        .navigationTitle("Tonight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    app.selection = .tab(.roulette)
                } label: {
                    Label("Spin Roulette", systemImage: "dice")
                }
            }
            #if os(iOS)
            if Device.isPhone {
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
    var emoji: String?
    var seeAll: Route?
    var load: () async throws -> [CatalogTitle]

    @Environment(Preferences.self) private var prefs
    @Environment(Catalog.self) private var catalog
    @State private var titles: [CatalogTitle] = []
    @State private var failed = false

    var body: some View {
        Group {
            if !titles.isEmpty {
                PosterRow(title: title, subtitle: subtitle, emoji: emoji, titles: titles,
                          seeAll: seeAll ?? .list(title, titles))
            } else if !failed {
                VStack(alignment: .leading) {
                    SectionHeader(title: title, subtitle: subtitle, emoji: emoji).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 14).fill(Spud.cardRaised).frame(width: 130, height: 195)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .redacted(reason: .placeholder)
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

struct GreetingHeader: View {
    var rank: CouchRank
    @Environment(Preferences.self) private var prefs

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(Spud.display(Device.isPhone ? 26 : 32))
                    .foregroundStyle(Spud.ink)
                Text(quip)
                    .font(.spudBody)
                    .foregroundStyle(Spud.inkSoft)
                Pill(text: "\(rank.level.emoji) \(rank.level.name) · \(rank.points) pts", color: Spud.butter, foreground: Color(hex: 0x3B2416))
            }
            Spacer(minLength: 0)
            SpudMascot(size: Device.isPhone ? 72 : 96, expression: Calendar.current.component(.hour, from: .now) >= 23 ? .sleepy : .happy)
        }
    }

    private var greeting: String {
        let name = prefs.nickname.isEmpty ? "couch potato" : prefs.nickname
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Morning, \(name) ☀️"
        case 12..<17: return "Afternoon, \(name) 🌤️"
        case 17..<22: return "Evening, \(name) 🌙"
        default: return "Up late, \(name)? 🦉"
        }
    }

    private var quip: String {
        let quips = [
            "The couch has been expecting you.",
            "Snacks? Check. Blanket? Check. Let's pick something.",
            "Spud has opinions. Here they are.",
            "Remote located. Decision pending.",
            "Your cushions have been fluffed.",
        ]
        return quips[Calendar.current.component(.day, from: .now) % quips.count]
    }
}

/// Paging backdrop carousel.
struct HeroCarousel: View {
    var titles: [CatalogTitle]
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(titles) { title in
                    NavigationLink(value: Route.detail(title)) {
                        HeroCard(title: title)
                    }
                    .buttonStyle(.plain)
                    .titleContextMenu(title)
                    .containerRelativeFrame(.horizontal, count: Device.isPhone ? 1 : 2, spacing: 14)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }
}

struct HeroCard: View {
    var title: CatalogTitle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if title.backdropURL != nil {
                    RemoteImage(url: title.backdropURL, maxPixel: 1400, placeholderTitle: title.name)
                } else {
                    // Poster-only sources: a blurred poster wash behind the sharp poster.
                    ZStack {
                        RemoteImage(url: title.posterURL, maxPixel: 300, placeholderTitle: title.name)
                            .blur(radius: 24)
                            .scaleEffect(1.3)
                        HStack {
                            Spacer()
                            RemoteImage(url: title.posterURL, maxPixel: 600, placeholderTitle: title.name)
                                .aspectRatio(2 / 3, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(radius: 10)
                                .padding(14)
                        }
                    }
                }
            }
            .frame(height: Device.isPhone ? 220 : 280)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Pill(text: title.kind.label, systemImage: title.kind.symbol, color: Spud.butter, foreground: Color(hex: 0x3B2416))
                    if let score = title.score {
                        Pill(text: String(format: "%.1f", score), systemImage: "star.fill", color: .white.opacity(0.2), foreground: .white)
                    }
                }
                Text(title.name)
                    .font(Spud.display(Device.isPhone ? 24 : 28))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(radius: 4)
                if !title.overview.isEmpty {
                    Text(title.overview)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .frame(maxWidth: 420, alignment: .leading)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Spud.brown.opacity(0.25), radius: 0, x: 0, y: 5)
    }
}

struct MoodStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mood Mash", subtitle: "How's the couch feeling?", emoji: "🎭")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: Route.mood(mood)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mood.emoji).font(.system(size: 30))
                                Text(mood.title).font(Spud.display(15, weight: .bold))
                                Text(mood.blurb).font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.75)
                            }
                            .foregroundStyle(Color(hex: 0x2A1A10))
                            .frame(width: 130, alignment: .leading)
                            .padding(12)
                            .background(mood.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .rotationEffect(.degrees(Mood.allCases.firstIndex(of: mood)!.isMultiple(of: 2) ? -1.5 : 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }
}

struct AttributionFooter: View {
    @Environment(Catalog.self) private var catalog

    var body: some View {
        VStack(spacing: 4) {
            Text("🥔 Couch Potato")
                .font(Spud.display(13, weight: .bold))
            Text(catalog.hasTMDB
                 ? "Data & artwork from TMDB · streaming availability by JustWatch. This product uses the TMDB API but is not endorsed or certified by TMDB."
                 : "Series data from TVmaze (CC BY-SA) · movie charts from Apple. Add a TMDB key in Settings for every service.")
                .font(.system(size: 11, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Spud.inkSoft)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 8)
    }
}
