import SwiftUI
import SwiftData

struct TitleDetailView: View {
    var ref: TitleRef
    var preview: CatalogTitle?

    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var savedMatches: [SavedTitle]

    @State private var detail: TitleDetail?
    @State private var error: Error?
    @State private var celebrate = 0

    init(ref: TitleRef, preview: CatalogTitle?) {
        self.ref = ref
        self.preview = preview
        let key = ref.key
        _savedMatches = Query(filter: #Predicate<SavedTitle> { $0.key == key })
    }

    private var title: CatalogTitle? { detail?.title ?? preview ?? savedMatches.first?.asCatalogTitle }
    private var saved: SavedTitle? { savedMatches.first }

    var body: some View {
        ScrollView {
            if let title {
                VStack(alignment: .leading, spacing: 24) {
                    DetailHeader(title: title, tagline: detail?.tagline)
                    actions(title).padding(.horizontal)
                    if let saved { MyCouchCard(saved: saved).padding(.horizontal) }
                    WhereToWatch(title: title, availability: detail?.availability, isLoading: detail == nil && error == nil)
                        .padding(.horizontal)
                    overview(title).padding(.horizontal)
                    if let next = detail?.nextEpisode { NextEpisodeCard(episode: next).padding(.horizontal) }
                    if let detail, title.kind == .tv, !detail.seasons.isEmpty {
                        SeasonsSection(title: title, seasons: detail.seasons, saved: saved).padding(.horizontal)
                    }
                    if let cast = detail?.cast, !cast.isEmpty { CastRow(cast: cast) }
                    if let similar = detail?.similar, !similar.isEmpty {
                        PosterRow(title: "If you liked this…", subtitle: "Spud's follow-up snacks", emoji: "🍟", titles: similar)
                    }
                    if let error, detail == nil {
                        SpudMessage(title: "Couldn't load everything", message: error.localizedDescription, expression: .wow)
                    }
                    AttributionFooter()
                }
                .padding(.bottom, 32)
            } else if let error {
                SpudMessage(title: "Spud dropped the remote", message: error.localizedDescription, expression: .wow)
            } else {
                SpudLoading()
            }
        }
        .spudBackground()
        .ignoresSafeArea(edges: Device.isPhone ? .top : [])
        .navigationTitle(title?.name ?? "")
        .inlineTitle()
        .overlay { ConfettiBurst(trigger: celebrate) }
        .toolbar {
            if let title {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: ref.webURL ?? ref.deepLink, subject: Text(title.name),
                              message: Text("Couch Potato says: watch \(title.name) 🥔"))
                }
            }
        }
        .userActivity(AppModel.titleActivity) { activity in
            activity.title = title?.name
            activity.userInfo = ["key": ref.key]
            activity.webpageURL = ref.webURL
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
        .task(id: ref) {
            do {
                let loaded = try await catalog.detail(ref)
                withAnimation { detail = loaded }
                // Keep saved metadata (art, runtime, providers) fresh.
                saved?.update(from: loaded.title)
            } catch is CancellationError {
            } catch {
                self.error = error
            }
        }
    }

    @ViewBuilder
    private func actions(_ title: CatalogTitle) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons(title) }
            VStack(alignment: .leading, spacing: 10) { actionButtons(title) }
        }
    }

    @ViewBuilder
    private func actionButtons(_ title: CatalogTitle) -> some View {
        if let saved {
            Menu {
                ForEach(WatchStatus.allCases) { status in
                    Button {
                        setStatus(status, title)
                    } label: {
                        Label(status.label, systemImage: status.symbol)
                    }
                }
                Divider()
                Button("Remove from Couch", systemImage: "trash", role: .destructive) {
                    Library.remove(ref.key, in: context)
                }
            } label: {
                Label("\(saved.status.emoji) \(saved.status.label)", systemImage: "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .menuStyle(.button)
            .buttonStyle(.chunky(Spud.brown))
            .fixedSize()
        } else {
            Button {
                setStatus(.queued, title)
            } label: {
                Label("Add to Couch Queue", systemImage: "plus")
            }
            .buttonStyle(.chunky(Spud.ketchup))
            .fixedSize()
        }
        Button {
            app.plan(title)
        } label: {
            Label("Plan a night", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.chunky(Spud.teal))
        .fixedSize()
        if let trailer = detail?.trailerURL {
            Button {
                openURL(trailer)
            } label: {
                Label(ref.source == .itunes ? "Preview" : "Trailer", systemImage: "play.fill")
            }
            .buttonStyle(.chunky(Spud.butter, foreground: Color(hex: 0x3B2416)))
            .fixedSize()
        }
    }

    private func setStatus(_ status: WatchStatus, _ title: CatalogTitle) {
        let item = Library.save(detail?.title ?? title, status: status, in: context)
        if status == .watched {
            celebrate += 1
            if item.kind == .tv { item.isFollowing = false }
        }
    }

    @ViewBuilder
    private func overview(_ title: CatalogTitle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "The scoop", emoji: "📜")
            if !title.overview.isEmpty {
                Text(title.overview)
                    .font(.spudBody)
                    .foregroundStyle(Spud.ink)
                    .textSelection(.enabled)
            }
            FlowLayout(spacing: 6) {
                ForEach(title.genres, id: \.self) { Pill(text: $0) }
                if let cert = title.certification, !cert.isEmpty { Pill(text: cert, systemImage: "person.2.fill") }
                if let status = title.status, title.kind == .tv { Pill(text: status, systemImage: "antenna.radiowaves.left.and.right") }
                if let network = title.network { Pill(text: network, systemImage: "tv") }
                if let creators = detail?.creators, !creators.isEmpty {
                    Pill(text: creators.prefix(2).joined(separator: ", "), systemImage: title.kind == .movie ? "megaphone.fill" : "pencil")
                }
            }
            if let homepage = title.homepage {
                Link(destination: homepage) {
                    Label("Official site", systemImage: "safari").font(.spudCaption)
                }
                .tint(Spud.teal)
            }
        }
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon.imageScale(.small) }
    }
}

struct DetailHeader: View {
    var title: CatalogTitle
    var tagline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: title.backdropURL ?? title.posterURL, maxPixel: 1600, placeholderTitle: nil)
                    .blur(radius: title.backdropURL == nil ? 30 : 0)
                    .frame(height: Device.isPhone ? 300 : 360)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, Spud.cream], startPoint: .center, endPoint: .bottom)
            }

            HStack(alignment: .bottom, spacing: 16) {
                RemoteImage(url: title.posterURL, maxPixel: 600, placeholderTitle: title.name)
                    .frame(width: Device.isPhone ? 118 : 160, height: Device.isPhone ? 177 : 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
                    .rotationEffect(.degrees(-2))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title.name)
                        .font(Spud.display(Device.isPhone ? 26 : 34))
                        .foregroundStyle(Spud.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    Text(title.subtitle).font(.spudCaption).foregroundStyle(Spud.inkSoft)
                    if let score = title.score {
                        ScoreBadge(score: score)
                    }
                    if let tagline {
                        Text("“\(tagline)”").font(.system(.subheadline, design: .serif)).italic().foregroundStyle(Spud.inkSoft)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .offset(y: -60)
            .padding(.bottom, -60)
        }
    }
}

struct ScoreBadge: View {
    var score: Double

    var body: some View {
        let potatoes = Int((score / 2).rounded())
        HStack(spacing: 4) {
            Text(String(repeating: "🥔", count: max(1, potatoes))).font(.system(size: 13))
            Text(String(format: "%.1f", score)).font(Spud.display(13, weight: .bold)).foregroundStyle(Spud.ink)
            Text(verdict).font(.spudCaption).foregroundStyle(Spud.inkSoft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Community score \(String(format: "%.1f", score)) out of 10")
    }

    private var verdict: String {
        switch score {
        case 8...: "certified crispy"
        case 7..<8: "well seasoned"
        case 6..<7: "decent spud"
        case 5..<6: "a bit soggy"
        default: "mashed"
        }
    }
}

/// Your personal stuff about a saved title: rating, notes, progress, follow.
struct MyCouchCard: View {
    @Bindable var saved: SavedTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your take", subtitle: PotatoRating.label(saved.potatoes), emoji: "📝")
                if saved.kind == .tv {
                    Toggle(isOn: $saved.isFollowing) {
                        Label("Follow", systemImage: saved.isFollowing ? "bell.fill" : "bell")
                            .font(.spudCaption)
                    }
                    .toggleStyle(.button)
                    .tint(Spud.teal)
                }
            }
            PotatoRating(value: Binding(get: { saved.potatoes }, set: { saved.potatoes = $0; saved.updatedAt = .now }))
            if let progress = saved.progressLabel {
                Pill(text: progress, systemImage: "checkmark.circle.fill", color: Spud.teal.opacity(0.2))
            }
            TextField("Notes for future you (who recommended it? snack pairing?)", text: $saved.notes, axis: .vertical)
                .font(.spudBody)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Spud.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Added \(saved.addedAt.formatted(.relative(presentation: .named)))")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Spud.inkSoft)
        }
        .spudCard()
    }
}

struct WhereToWatch: View {
    var title: CatalogTitle
    var availability: Availability?
    var isLoading: Bool

    @Environment(Preferences.self) private var prefs
    @Environment(Catalog.self) private var catalog
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Where to watch", subtitle: subtitle, emoji: "📡")
            if let availability, !availability.isEmpty {
                let sorted = availability.offers.sorted { prefs.isMine($0.provider) && !prefs.isMine($1.provider) }
                ForEach(OfferKind.allCases, id: \.self) { kind in
                    let offers = sorted.filter { $0.kind == kind }
                    if !offers.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.label.uppercased())
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(Spud.inkSoft)
                            FlowLayout(spacing: 8) {
                                ForEach(offers) { offer in
                                    Button {
                                        if let url = offer.link ?? offer.provider.searchURL(for: title.name) ?? availability.link {
                                            openURL(url)
                                        }
                                    } label: {
                                        ProviderChip(provider: offer.provider, logoURL: offer.logoURL, detail: offer.price,
                                                     isMine: prefs.isMine(offer.provider))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Open \(title.name) on \(offer.provider.name)")
                                }
                            }
                        }
                    }
                }
                if let link = availability.link, catalog.hasTMDB {
                    Link(destination: link) {
                        Text("Availability via JustWatch").font(.system(size: 11, design: .rounded))
                    }
                    .tint(Spud.inkSoft)
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 12) {
                    SpudMascot(size: 44, expression: .sleepy, bobbing: false)
                    Text(catalog.hasTMDB
                         ? "Spud couldn't find this streaming in \(prefs.region) right now. Check back soon!"
                         : "Add a free TMDB key in Settings and Spud will check every streaming service for you.")
                        .font(.spudBody)
                        .foregroundStyle(Spud.inkSoft)
                }
            }
        }
        .spudCard()
    }

    private var subtitle: String? {
        guard let availability, !availability.isEmpty else { return nil }
        let mine = availability.offers.filter { [.stream, .free, .ads].contains($0.kind) && prefs.isMine($0.provider) }
        if let first = mine.first { return "On your \(first.provider.name) — no extra cost! 🎉" }
        return "In \(prefs.region) · tap to open"
    }
}

struct NextEpisodeCard: View {
    var episode: EpisodeInfo

    var body: some View {
        HStack(spacing: 14) {
            Text("📅").font(.system(size: 34))
            VStack(alignment: .leading, spacing: 4) {
                Text("Next episode").font(.spudCaption).foregroundStyle(Spud.inkSoft)
                Text("\(episode.code) · \(episode.name)").font(Spud.display(16, weight: .bold)).foregroundStyle(Spud.ink)
                if let date = episode.airDate {
                    Text(date.formatted(date: .complete, time: .omitted) + " (\(date.formatted(.relative(presentation: .named))))")
                        .font(.spudCaption).foregroundStyle(Spud.teal)
                }
            }
            Spacer()
        }
        .spudCard(Spud.butter.opacity(0.3))
    }
}

struct CastRow: View {
    var cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Starring", emoji: "🌟").padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(cast) { member in
                        VStack(spacing: 6) {
                            RemoteImage(url: member.photoURL, maxPixel: 240, placeholderTitle: nil)
                                .frame(width: 76, height: 76)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Spud.butter, lineWidth: 3))
                            Text(member.name).font(Spud.display(12, weight: .bold)).foregroundStyle(Spud.ink)
                                .lineLimit(2).multilineTextAlignment(.center)
                            Text(member.character).font(.system(size: 10, design: .rounded)).foregroundStyle(Spud.inkSoft)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(width: 90)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct SeasonsSection: View {
    var title: CatalogTitle
    var seasons: [SeasonInfo]
    var saved: SavedTitle?

    @Environment(Catalog.self) private var catalog
    @Environment(\.modelContext) private var context
    @State private var season = 1
    @State private var episodes: [EpisodeInfo] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Episodes", subtitle: "Tap ✓ to mark everything up to there watched", emoji: "🎞️")
                Picker("Season", selection: $season) {
                    ForEach(seasons) { s in Text(s.name).tag(s.number) }
                }
                .labelsHidden()
                .fixedSize()
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(episodes) { episode in
                EpisodeRow(episode: episode, isWatched: isWatched(episode)) { markThrough(episode) }
            }
        }
        .spudCard()
        .onAppear {
            if let saved, saved.lastSeason > 0, seasons.contains(where: { $0.number == saved.lastSeason }) {
                season = saved.lastSeason
            } else {
                season = seasons.first?.number ?? 1
            }
        }
        .task(id: season) {
            loading = true
            episodes = (try? await catalog.episodes(title.ref, showName: title.name, season: season, poster: title.posterURL)) ?? []
            loading = false
        }
    }

    private func isWatched(_ e: EpisodeInfo) -> Bool {
        guard let saved else { return false }
        return e.season < saved.lastSeason || (e.season == saved.lastSeason && e.number <= saved.lastEpisode)
    }

    private func markThrough(_ e: EpisodeInfo) {
        let item = saved ?? Library.save(title, status: .watching, in: context)
        if isWatched(e) && item.lastSeason == e.season && item.lastEpisode == e.number {
            // Un-tick the latest one.
            item.lastEpisode = max(0, e.number - 1)
            if item.lastEpisode == 0 { item.lastSeason = max(0, e.season - 1) }
        } else {
            item.lastSeason = e.season
            item.lastEpisode = e.number
        }
        if item.status == .queued { item.status = .watching }
        item.updatedAt = .now
    }
}

struct EpisodeRow: View {
    var episode: EpisodeInfo
    var isWatched: Bool
    var toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: episode.stillURL, maxPixel: 400, placeholderTitle: nil)
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isWatched ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.number). \(episode.name)").font(Spud.display(14, weight: .bold)).foregroundStyle(Spud.ink).lineLimit(2)
                HStack(spacing: 6) {
                    if let date = episode.airDate { Text(date.formatted(date: .abbreviated, time: .omitted)) }
                    if let runtime = episode.runtime { Text("· \(runtime.runtimeLabel)") }
                    if let date = episode.airDate, date > .now { Text("· upcoming").foregroundStyle(Spud.ketchup) }
                }
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Spud.inkSoft)
                if !episode.overview.isEmpty {
                    Text(episode.overview).font(.system(size: 12, design: .rounded)).foregroundStyle(Spud.inkSoft).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button(action: toggle) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isWatched ? Spud.lettuce : Spud.inkSoft.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWatched ? "Watched" : "Mark watched through this episode")
            .sensoryFeedback(.success, trigger: isWatched)
        }
    }
}

/// A simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A burst of potatoes and popcorn when you finish something.
struct ConfettiBurst: View {
    var trigger: Int
    @State private var pieces: [Piece] = []

    struct Piece: Identifiable {
        let id = UUID()
        let emoji: String
        let x: CGFloat
        let rotation: Double
        var fallen = false
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    Text(piece.emoji)
                        .font(.system(size: 28))
                        .rotationEffect(.degrees(piece.fallen ? piece.rotation : 0))
                        .position(x: piece.x * proxy.size.width, y: piece.fallen ? proxy.size.height + 40 : -40)
                        .opacity(piece.fallen ? 0.2 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) {
            pieces = (0..<36).map { _ in
                Piece(emoji: ["🥔", "🍿", "🍟", "⭐️", "🧈", "🎉"].randomElement()!, x: .random(in: 0.05...0.95),
                      rotation: .random(in: -540...540))
            }
            withAnimation(.easeIn(duration: 1.8)) {
                for i in pieces.indices { pieces[i].fallen = true }
            }
            Task {
                try? await Task.sleep(for: .seconds(2))
                pieces = []
            }
        }
        .sensoryFeedback(.success, trigger: trigger)
    }
}
