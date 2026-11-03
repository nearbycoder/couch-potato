import SwiftUI
import SwiftData

struct TitleDetailView: View {
    var ref: TitleRef
    var preview: CatalogTitle?

    @Environment(Catalog.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Environment(AppModel.self) private var app
    @Environment(\.layout) private var layout
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var savedMatches: [SavedTitle]

    @State private var detail: TitleDetail?
    @State private var error: Error?

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
                VStack(alignment: .leading, spacing: 28) {
                    DetailHeader(title: title, tagline: detail?.tagline)
                    actions(title).padding(.horizontal, layout.margin)
                    if let saved { PersonalCard(saved: saved).padding(.horizontal, layout.margin) }
                    WhereToWatch(title: title, availability: detail?.availability, isLoading: detail == nil && error == nil)
                        .padding(.horizontal, layout.margin)
                    about(title).padding(.horizontal, layout.margin)
                    if let next = detail?.nextEpisode { NextEpisodeCard(episode: next).padding(.horizontal, layout.margin) }
                    if let detail, title.kind == .tv, !detail.seasons.isEmpty {
                        SeasonsSection(title: title, seasons: detail.seasons, saved: saved).padding(.horizontal, layout.margin)
                    }
                    if let cast = detail?.cast, !cast.isEmpty { CastRow(cast: cast) }
                    if let similar = detail?.similar, !similar.isEmpty {
                        PosterRow(title: "More Like This", titles: similar, seeAll: .list("More Like This", similar))
                    }
                    if let error, detail == nil {
                        EmptyState(symbol: "exclamationmark.triangle", title: "Some details couldn't load", message: error.localizedDescription)
                    }
                    AttributionFooter()
                }
                .padding(.bottom, 32)
            } else if let error {
                EmptyState(symbol: "exclamationmark.triangle", title: "Couldn't load this title", message: error.localizedDescription)
            } else {
                LoadingView()
            }
        }
        .appBackground()
        .navigationTitle(title?.name ?? "")
        .inlineTitle()
        .toolbar {
            if let title {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: ref.webURL ?? ref.deepLink, subject: Text(title.name),
                              message: Text("\(title.name) on Couch Potato"))
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
                withAnimation(.easeOut(duration: 0.25)) { detail = loaded }
                saved?.update(from: loaded.title)
            } catch is CancellationError {
            } catch {
                self.error = error
            }
        }
    }

    @ViewBuilder
    private func actions(_ title: CatalogTitle) -> some View {
        // One row when it fits; otherwise the primary action on its own row above the rest.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                primaryAction(title)
                secondaryActions(title)
            }
            VStack(alignment: .leading, spacing: 10) {
                primaryAction(title)
                HStack(spacing: 10) { secondaryActions(title) }
            }
            VStack(alignment: .leading, spacing: 10) {
                primaryAction(title)
                secondaryActions(title)
            }
        }
    }

    @ViewBuilder
    private func primaryAction(_ title: CatalogTitle) -> some View {
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
                Button("Remove from Watchlist", systemImage: "trash", role: .destructive) {
                    Library.remove(ref.key, in: context)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: saved.status.symbol).symbolVariant(.fill)
                    Text(saved.status.label)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
            }
            .menuStyle(.button)
            .buttonStyle(.primary)
            .fixedSize()
        } else {
            Button {
                setStatus(.queued, title)
            } label: {
                Label("Add to Watchlist", systemImage: "plus")
            }
            .buttonStyle(.primary)
            .fixedSize()
        }
    }

    @ViewBuilder
    private func secondaryActions(_ title: CatalogTitle) -> some View {
        Button {
            app.plan(title)
        } label: {
            Label("Plan a Night", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.secondary)
        .fixedSize()
        if let trailer = detail?.trailerURL {
            Button {
                openURL(trailer)
            } label: {
                Label(ref.source == .itunes ? "Preview" : "Trailer", systemImage: "play.fill")
            }
            .buttonStyle(.secondary)
            .fixedSize()
        }
    }

    private func setStatus(_ status: WatchStatus, _ title: CatalogTitle) {
        let item = Library.save(detail?.title ?? title, status: status, in: context)
        if status == .watched, item.kind == .tv { item.isFollowing = false }
    }

    @ViewBuilder
    private func about(_ title: CatalogTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "About")
            if !title.overview.isEmpty {
                Text(title.overview)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
            FlowLayout(spacing: 6) {
                ForEach(title.genres, id: \.self) { Pill(text: $0) }
                if let cert = title.certification, !cert.isEmpty { Pill(text: cert) }
                if let status = title.status, title.kind == .tv { Pill(text: status, systemImage: "dot.radiowaves.left.and.right") }
                if let network = title.network { Pill(text: network, systemImage: "tv") }
                if let creators = detail?.creators, !creators.isEmpty {
                    Pill(text: creators.prefix(2).joined(separator: ", "), systemImage: title.kind == .movie ? "megaphone" : "pencil")
                }
            }
            if let homepage = title.homepage {
                Link(destination: homepage) {
                    Label("Official site", systemImage: "arrow.up.right.square").font(.footnote.weight(.medium))
                }
                .tint(Theme.accent)
            }
        }
    }
}

struct DetailHeader: View {
    var title: CatalogTitle
    var tagline: String?

    @Environment(\.layout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The image is an overlay so a wide backdrop can't stretch the ScrollView.
            // Without a real backdrop, a short wash tinted by the poster stands in for one.
            // Capped by the screen height so short windows (an unfolded iPhone Duo) still show the actions.
            Color.clear
                .containerRelativeFrame(.vertical) { height, _ in
                    title.backdropURL != nil
                        ? min(layout.isCompact ? 300 : 380, height * 0.45)
                        : min(layout.isCompact ? 190 : 230, height * 0.3)
                }
                .frame(maxWidth: .infinity)
                .overlay {
                    if title.backdropURL != nil {
                        RemoteImage(url: title.backdropURL, maxPixel: 1600, placeholderTitle: nil)
                    } else {
                        RemoteImage(url: title.posterURL, maxPixel: 300, placeholderTitle: nil)
                            .blur(radius: 50)
                            .scaleEffect(1.6)
                            .opacity(0.7)
                    }
                }
                .clipped()
                .overlay(alignment: .bottom) {
                LinearGradient(stops: [
                    .init(color: Theme.bg.opacity(0), location: 0.3),
                    .init(color: Theme.bg.opacity(0.85), location: 0.8),
                    .init(color: Theme.bg, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                }

            HStack(alignment: .bottom, spacing: 18) {
                RemoteImage(url: title.posterURL, maxPixel: 600, placeholderTitle: title.name)
                    .frame(width: layout.detailPosterWidth, height: layout.detailPosterWidth * 1.5)
                    .artwork(radius: 14)
                    .softShadow(radius: 18, y: 10)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title.name)
                        .font(layout.isCompact ? .title.bold() : .largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    Text(title.metaLine).font(.footnote).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        if let score = title.score { ScoreLabel(score: score) }
                        if let cert = title.certification, !cert.isEmpty {
                            Text(cert)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.textTertiary))
                        }
                    }
                    if let tagline {
                        Text(tagline).font(.subheadline.italic()).foregroundStyle(Theme.textSecondary).lineLimit(2).padding(.top, 2)
                    }
                }
                .padding(.bottom, 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.margin)
            .offset(y: -56)
            .padding(.bottom, -56)
        }
    }
}

/// Rating, notes, progress and follow for a saved title.
struct PersonalCard: View {
    @Bindable var saved: SavedTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Your Rating", subtitle: StarRating.label(saved.potatoes))
                if saved.kind == .tv {
                    Toggle(isOn: $saved.isFollowing) {
                        Label("Follow", systemImage: saved.isFollowing ? "bell.fill" : "bell")
                            .font(.footnote.weight(.medium))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.secondary)
                    .tint(Theme.accent)
                }
            }
            StarRating(value: Binding(get: { saved.potatoes }, set: { saved.potatoes = $0; saved.updatedAt = .now }))
            if let progress = saved.progressLabel {
                Pill(text: progress, systemImage: "checkmark", dot: nil, tint: Theme.success.opacity(0.15), foreground: Theme.success)
            }
            TextField("Notes", text: $saved.notes, prompt: Text("Add a note"), axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("Added \(saved.addedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .card()
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
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Where to Watch", subtitle: subtitle)
            if let availability, !availability.isEmpty {
                let sorted = availability.offers.sorted { prefs.isMine($0.provider) && !prefs.isMine($1.provider) }
                ForEach(OfferKind.allCases, id: \.self) { kind in
                    let offers = sorted.filter { $0.kind == kind }
                    if !offers.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind.label.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.6)
                                .foregroundStyle(Theme.textTertiary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 4) {
                                    ForEach(offers) { offer in
                                        Button {
                                            if let url = offer.link ?? offer.provider.searchURL(for: title.name) ?? availability.link {
                                                openURL(url)
                                            }
                                        } label: {
                                            ProviderOfferView(offer: offer, isMine: prefs.isMine(offer.provider))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Open \(title.name) on \(offer.provider.name)")
                                    }
                                }
                            }
                        }
                    }
                }
                if let link = availability.link, catalog.hasTMDB {
                    Link(destination: link) {
                        Text("Availability by JustWatch").font(.caption)
                    }
                    .tint(Theme.textTertiary)
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(catalog.hasTMDB
                     ? "Not currently available to stream in \(prefs.region)."
                     : "Add a free TMDB API key in Settings to see every service that carries this title.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private var subtitle: String? {
        guard let availability, !availability.isEmpty else { return nil }
        let mine = availability.offers.filter { [.stream, .free, .ads].contains($0.kind) && prefs.isMine($0.provider) }
        if let first = mine.first { return "Included with your \(first.provider.name) subscription" }
        return "In \(prefs.region)"
    }
}

struct NextEpisodeCard: View {
    var episode: EpisodeInfo

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Next Episode").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                Text("\(episode.code) · \(episode.name)").font(.headline).foregroundStyle(Theme.textPrimary)
                if let date = episode.airDate {
                    Text(date.formatted(date: .complete, time: .omitted) + " · " + date.formatted(.relative(presentation: .named)))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .card()
    }
}

struct CastRow: View {
    var cast: [CastMember]
    @Environment(\.layout) private var layout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Cast").padding(.horizontal, layout.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(cast) { member in
                        VStack(spacing: 8) {
                            RemoteImage(url: member.photoURL, maxPixel: 240, placeholderTitle: nil)
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Theme.hairline))
                            Text(member.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                .lineLimit(2).multilineTextAlignment(.center)
                            Text(member.character).font(.caption2).foregroundStyle(Theme.textSecondary)
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(width: 88)
                    }
                }
                .padding(.horizontal, layout.margin)
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
                SectionHeader(title: "Episodes", subtitle: "Tap the circle to mark watched through that episode")
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
                if episode.id != episodes.last?.id { Divider().overlay(Theme.hairline) }
            }
        }
        .card()
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
                .artwork(radius: 8)
                .opacity(isWatched ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(episode.number). \(episode.name)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                HStack(spacing: 6) {
                    if let date = episode.airDate { Text(date.formatted(date: .abbreviated, time: .omitted)) }
                    if let runtime = episode.runtime { Text("· \(runtime.runtimeLabel)") }
                    if let date = episode.airDate, date > .now { Text("· Upcoming").foregroundStyle(Theme.accent) }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                if !episode.overview.isEmpty {
                    Text(episode.overview).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button(action: toggle) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isWatched ? Theme.success : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWatched ? "Watched" : "Mark watched through this episode")
            .sensoryFeedback(.success, trigger: isWatched)
        }
        .padding(.vertical, 4)
    }
}
