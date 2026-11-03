import Foundation
import Observation

/// One front door to every data source. With a TMDB key it uses TMDB for discovery,
/// search and all-provider availability; without one it blends TVmaze (series) and
/// Apple's iTunes charts (movies). Titles from any source can always be opened.
@MainActor
@Observable
final class Catalog {
    let prefs: Preferences
    private let tvmaze = TVMazeClient()

    @ObservationIgnored private var memo: [String: [CatalogTitle]] = [:]
    @ObservationIgnored private var tvPool: [CatalogTitle]?
    @ObservationIgnored private var moviePool: [String: CatalogTitle] = [:]
    @ObservationIgnored private var serviceSeries: [String: [CatalogTitle]] = [:]

    /// Page size for key-less lists, which arrive whole and are paged locally.
    static let pageSize = 60
    /// Per-service series catalogs built from TVmaze's full index by scripts/build_catalog.py.
    static let seriesCatalogBase = "https://nearbycoder.github.io/couch-potato/catalog/v1"

    init(prefs: Preferences) { self.prefs = prefs }

    var tmdb: TMDBClient? {
        let key = prefs.effectiveTMDBKey
        return key.isEmpty ? nil : TMDBClient(key: key, region: prefs.region)
    }

    var hasTMDB: Bool { tmdb != nil }

    private var itunes: ITunesClient { ITunesClient(country: prefs.region.lowercased()) }

    /// Drops cached lists (e.g. after the region, key or services change).
    func reset() {
        memo = [:]
        tvPool = nil
        moviePool = [:]
        serviceSeries = [:]
    }

    private func remember(_ key: String, _ load: () async throws -> [CatalogTitle]) async throws -> [CatalogTitle] {
        let fullKey = "\(key)|\(prefs.region)|\(hasTMDB)"
        if let hit = memo[fullKey] { return hit }
        let value = try await load()
        memo[fullKey] = value
        return value
    }

    // MARK: Home rows

    func trending() async throws -> [CatalogTitle] {
        try await remember("trending") {
            if let tmdb { return try await tmdb.trending() }
            async let shows = openTVPool()
            async let movies = openMovies(genre: nil)
            return interleave(Array(try await movies.prefix(15)), Array(try await shows.prefix(15)))
        }
    }

    func freshOnStreaming() async throws -> [CatalogTitle] {
        try await remember("fresh-\(prefs.myServiceIDs.sorted())") {
            if let tmdb { return try await tmdb.freshOnStreaming(services: prefs.myServices) }
            var items: [TVMScheduleItem] = []
            for offset in [0, -1, -2] {
                let day = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
                items += (try? await tvmaze.schedule(day, web: true)) ?? []
            }
            return uniqueShows(items).filter { !$0.providers.isEmpty }
        }
    }

    func popular(_ kind: MediaKind) async throws -> [CatalogTitle] {
        try await remember("popular-\(kind)") {
            if let tmdb { return try await tmdb.popular(kind) }
            return kind == .movie ? try await openMovies(genre: nil) : try await openTVPool()
        }
    }

    /// One page of what's on a service. An empty page means the list is exhausted.
    func onService(_ provider: Provider, kind: MediaKind? = nil, filter: TitleFilter = TitleFilter(),
                   page: Int = 1) async throws -> [CatalogTitle] {
        if tmdb == nil {
            if kind == .movie { return [] }
            return Self.slice(filter.apply(try await series(on: provider)), page: page)
        }
        return try await remember("service-\(provider.id)-\(kind?.rawValue ?? "all")-\(filter.key)-p\(page)") {
            async let movies = kind == .tv ? [] : discover(.movie, providers: [provider], filter: filter, page: page)
            async let shows = kind == .movie ? [] : discover(.tv, providers: [provider], filter: filter, page: page)
            return filter.merge(shows: try await shows, movies: try await movies)
        }
    }

    /// One TMDB discover page shaped by a filter; empty when the filter rules the kind out.
    private func discover(_ kind: MediaKind, providers: [Provider], moodGenres: [Int] = [], filter: TitleFilter,
                          extra: [String: String?] = [:], page: Int) async throws -> [CatalogTitle] {
        guard let tmdb, let query = filter.tmdbQuery(for: kind, includeGenre: moodGenres.isEmpty) else { return [] }
        var params = extra
        query.extra.forEach { params[$0] = $1 }
        return try await tmdb.discover(kind, providers: providers, genres: moodGenres.isEmpty ? query.genres : moodGenres,
                                       sort: query.sort, extra: params, page: page)
    }

    /// One page of titles for a mood. An empty page means the list is exhausted.
    func mood(_ mood: Mood, kind: MediaKind? = nil, filter: TitleFilter = TitleFilter(), page: Int = 1) async throws -> [CatalogTitle] {
        // A mood already picks its genres, so the filter's genre doesn't apply here.
        var filter = filter
        filter.genre = nil
        if tmdb == nil { return Self.slice(filter.apply(try await openMood(mood, kind: kind)), page: page) }
        return try await remember("mood-\(mood.rawValue)-\(kind?.rawValue ?? "all")-\(prefs.onlyMyServices)-\(filter.key)-p\(page)") {
            let services = prefs.onlyMyServices ? prefs.myServices : []
            let extra: [String: String?] = ["vote_count.gte": "150"]
            async let movies = kind == .tv ? [] : discover(.movie, providers: services, moodGenres: mood.tmdbMovieGenres,
                                                           filter: filter, extra: extra, page: page)
            async let shows = kind == .movie ? [] : discover(.tv, providers: services, moodGenres: mood.tmdbTVGenres,
                                                            filter: filter, extra: extra, page: page)
            return filter.merge(shows: try await shows, movies: try await movies)
        }
    }

    private func openMood(_ mood: Mood, kind: MediaKind?) async throws -> [CatalogTitle] {
        try await remember("mood-\(mood.rawValue)-\(kind?.rawValue ?? "all")-\(prefs.myServiceIDs.sorted())") {
            var movies: [CatalogTitle] = []
            if kind != .tv {
                for genre in mood.itunesGenreIDs { movies += (try? await openMovies(genre: genre)) ?? [] }
            }
            guard kind != .movie else { return dedupe(movies) }
            var shows = try await openTVPool()
            let services = prefs.myServices.isEmpty ? Array(Provider.streamers.prefix(6)) : prefs.myServices
            for provider in services { shows += (try? await series(on: provider)) ?? [] }
            shows = dedupe(shows).filter(mood.matches).sorted { $0.popularity > $1.popularity }
            return interleave(dedupe(movies), shows)
        }
    }

    private static func slice(_ titles: [CatalogTitle], page: Int) -> [CatalogTitle] {
        let start = (page - 1) * pageSize
        guard page >= 1, start < titles.count else { return [] }
        return Array(titles[start..<min(start + pageSize, titles.count)])
    }

    func search(_ text: String) async throws -> [CatalogTitle] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        if let tmdb { return try await tmdb.search(query) }
        async let shows = tvmaze.search(query)
        if moviePool.isEmpty { _ = try? await openMovies(genre: nil) }
        let needle = query.lowercased()
        let movies = moviePool.values.filter { $0.name.lowercased().contains(needle) }
        return interleave(movies.sorted { $0.popularity > $1.popularity }, try await shows)
    }

    // MARK: Details

    func detail(_ ref: TitleRef) async throws -> TitleDetail {
        switch ref.source {
        case .tmdb:
            guard let tmdb else { throw HTTPError.missingKey }
            return try await tmdb.detail(ref)
        case .tvmaze:
            var (show, detail) = try await tvmaze.detail(ref.id)
            detail.similar = try await openTVPool()
                .filter { $0.ref != ref && !Set($0.genres).isDisjoint(with: show.genres ?? []) }
                .prefix(15).map { $0 }
            if let enriched = await tmdbAvailability(imdbID: show.externals?.imdb) { detail.availability = enriched }
            return detail
        case .itunes:
            let (title, track) = try await itunes.lookup(ref.id)
            var availability = track.availability()
            if let tmdb, let match = try? await tmdb.searchMovie(name: title.name, year: title.year),
               let tmdbAvailability = try? await tmdb.availability(match.ref) {
                // Keep Apple's exact prices, add everything else TMDB knows about.
                availability.offers += tmdbAvailability.offers.filter { $0.provider != .appleStore }
                availability.offers.sort { OfferKind.allCases.firstIndex(of: $0.kind)! < OfferKind.allCases.firstIndex(of: $1.kind)! }
            }
            let similar = try await openMovies(genre: nil).filter { $0.ref != ref && !Set($0.genres).isDisjoint(with: title.genres) }
            return TitleDetail(title: title, cast: [], availability: availability, similar: Array(similar.prefix(15)),
                               trailerURL: track.previewUrl.flatMap(URL.init(string:)),
                               creators: track.artistName.map { [$0] } ?? [])
        }
    }

    private func tmdbAvailability(imdbID: String?) async -> Availability? {
        guard let tmdb, let imdbID, let match = try? await tmdb.find(imdbID: imdbID) else { return nil }
        guard let availability = try? await tmdb.availability(match.ref), !availability.isEmpty else { return nil }
        return availability
    }

    func episodes(_ ref: TitleRef, showName: String, season: Int, poster: URL?) async throws -> [EpisodeInfo] {
        switch ref.source {
        case .tmdb:
            guard let tmdb else { throw HTTPError.missingKey }
            return try await tmdb.episodes(showID: ref.id, showName: showName, season: season, poster: poster)
        case .tvmaze:
            let show = CatalogTitle(ref: ref, name: showName, posterURL: poster)
            return try await tvmaze.episodes(showID: ref.id).filter { $0.season == season }.map { $0.episodeInfo(show: show) }
        case .itunes:
            return []
        }
    }

    /// Future episodes for a followed show, soonest first.
    func upcomingEpisodes(_ ref: TitleRef, showName: String, poster: URL?) async -> [EpisodeInfo] {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        switch ref.source {
        case .tmdb:
            return (try? await tmdb?.upcomingEpisodes(showID: ref.id)) ?? []
        case .tvmaze:
            let show = CatalogTitle(ref: ref, name: showName, posterURL: poster)
            let all = (try? await tvmaze.episodes(showID: ref.id)) ?? []
            return all.map { $0.episodeInfo(show: show) }.filter { ($0.airDate ?? .distantPast) >= startOfToday }
        case .itunes:
            return []
        }
    }

    // MARK: Key-less pools

    /// Shows airing now across streamers + US networks, most popular first.
    private func openTVPool() async throws -> [CatalogTitle] {
        if let tvPool { return tvPool }
        let days = (-6...1).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
        let items = await withTaskGroup(of: [TVMScheduleItem].self) { group in
            for day in days { group.addTask { [tvmaze] in (try? await tvmaze.schedule(day, web: true)) ?? [] } }
            for day in days.suffix(3) { group.addTask { [tvmaze] in (try? await tvmaze.schedule(day, web: false)) ?? [] } }
            var all: [TVMScheduleItem] = []
            for await batch in group { all += batch }
            return all
        }
        let pool = uniqueShows(items).filter { $0.posterURL != nil }
        if pool.isEmpty { throw HTTPError.status(503) }
        tvPool = pool
        return pool
    }

    /// Every series we know streams on a service: the published catalog plus anything
    /// that aired this week, most popular first. Falls back to this week alone offline.
    private func series(on provider: Provider) async throws -> [CatalogTitle] {
        if let hit = serviceSeries[provider.id] { return hit }
        async let published: [TVMShow]? = try? HTTP.get(URL(string: "\(Self.seriesCatalogBase)/\(provider.id).json")!)
        let airing = ((try? await openTVPool()) ?? []).filter { $0.providers.contains(provider) }
        let catalog = (await published ?? []).map(\.catalogTitle).filter { $0.providers.contains(provider) }
        let all = dedupe(airing + catalog).sorted { $0.popularity > $1.popularity }
        if all.isEmpty { throw HTTPError.status(503) }
        if !catalog.isEmpty { serviceSeries[provider.id] = all }
        return all
    }

    private func openMovies(genre: Int?) async throws -> [CatalogTitle] {
        try await remember("itunes-\(genre ?? 0)") {
            let movies = try await itunes.topMovies(genre: genre)
            for movie in movies { moviePool[movie.id] = movie }
            return movies
        }
    }

    private func uniqueShows(_ items: [TVMScheduleItem]) -> [CatalogTitle] {
        var seen = Set<Int>()
        return items.compactMap(\.resolvedShow)
            .filter { seen.insert($0.id).inserted && ($0.language ?? "English") == "English" }
            .map(\.catalogTitle)
            .sorted { $0.popularity > $1.popularity }
    }

    private func dedupe(_ titles: [CatalogTitle]) -> [CatalogTitle] {
        var seen = Set<String>()
        return titles.filter { seen.insert($0.id).inserted }
    }
}
