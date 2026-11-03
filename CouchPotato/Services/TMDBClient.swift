import Foundation

/// The Movie Database: full movie + TV catalog, box art, and JustWatch-powered
/// "where to watch" data for every major service. Requires a (free) API key.
struct TMDBClient {
    let key: String
    let region: String

    private static let base = "https://api.themoviedb.org/3"
    static let imageBase = "https://image.tmdb.org/t/p/"

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String?] = [:]) async throws -> T {
        guard !key.isEmpty else { throw HTTPError.missingKey }
        var query = query
        var headers: [String: String] = [:]
        // v4 read tokens are JWTs; v3 keys go in the query string.
        if key.hasPrefix("eyJ") { headers["Authorization"] = "Bearer \(key)" } else { query["api_key"] = key }
        query["language"] = query["language"] ?? "en-US"
        return try await HTTP.get(HTTP.url(Self.base, path, query), headers: headers, decoder: decoder)
    }

    static func image(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: imageBase + size + path)
    }

    // MARK: Lists

    func validate() async throws { let _: TMDBConfiguration = try await get("/configuration") }

    func trending() async throws -> [CatalogTitle] {
        let page: TMDBPage<TMDBItem> = try await get("/trending/all/week")
        return page.results.compactMap { $0.catalogTitle() }
    }

    func popular(_ kind: MediaKind) async throws -> [CatalogTitle] {
        let page: TMDBPage<TMDBItem> = try await get("/\(kind.rawValue)/popular", ["region": region])
        return page.results.compactMap { $0.catalogTitle(kind: kind) }
    }

    func discover(_ kind: MediaKind, providers: [Provider] = [], genres: [Int] = [], sort: String = "popularity.desc",
                  extra: [String: String?] = [:], page: Int = 1) async throws -> [CatalogTitle] {
        var query: [String: String?] = [
            "sort_by": sort,
            "watch_region": region,
            "include_adult": "false",
            "page": String(page),
        ]
        if !providers.isEmpty {
            query["with_watch_providers"] = providers.flatMap(\.tmdbIDs).map(String.init).joined(separator: "|")
            query["with_watch_monetization_types"] = "flatrate|free|ads"
        }
        if !genres.isEmpty { query["with_genres"] = genres.map(String.init).joined(separator: "|") }
        extra.forEach { query[$0] = $1 }
        let result: TMDBPage<TMDBItem> = try await get("/discover/\(kind.rawValue)", query)
        return result.results.compactMap { $0.catalogTitle(kind: kind) }
    }

    func freshOnStreaming(services: [Provider]) async throws -> [CatalogTitle] {
        let today = DateParsing.dayString(.now)
        let monthAgo = DateParsing.dayString(Calendar.current.date(byAdding: .day, value: -60, to: .now)!)
        let providers = services.isEmpty ? Provider.streamers.prefix(8).map { $0 } : services
        async let movies = discover(.movie, providers: providers, sort: "popularity.desc",
                                    extra: ["primary_release_date.gte": monthAgo, "primary_release_date.lte": today])
        async let shows = discover(.tv, providers: providers, sort: "popularity.desc",
                                   extra: ["air_date.gte": monthAgo, "air_date.lte": today])
        return interleave(try await movies, try await shows)
    }

    func search(_ text: String) async throws -> [CatalogTitle] {
        let page: TMDBPage<TMDBItem> = try await get("/search/multi", ["query": text, "include_adult": "false"])
        return page.results.compactMap { $0.catalogTitle() }
    }

    func searchMovie(name: String, year: Int?) async throws -> CatalogTitle? {
        let page: TMDBPage<TMDBItem> = try await get("/search/movie", ["query": name, "year": year.map(String.init)])
        return page.results.first?.catalogTitle(kind: .movie)
    }

    func find(imdbID: String) async throws -> CatalogTitle? {
        let result: TMDBFindResult = try await get("/find/\(imdbID)", ["external_source": "imdb_id"])
        return result.tvResults.first?.catalogTitle(kind: .tv) ?? result.movieResults.first?.catalogTitle(kind: .movie)
    }

    // MARK: Details

    func detail(_ ref: TitleRef) async throws -> TitleDetail {
        let appended = ref.kind == .movie
            ? "credits,videos,watch/providers,recommendations,similar,external_ids,release_dates"
            : "aggregate_credits,credits,videos,watch/providers,recommendations,similar,external_ids,content_ratings"
        let d: TMDBDetail = try await get("/\(ref.kind.rawValue)/\(ref.id)", ["append_to_response": appended])
        return d.titleDetail(kind: ref.kind, region: region)
    }

    func availability(_ ref: TitleRef) async throws -> Availability {
        let result: TMDBWatchProviders = try await get("/\(ref.kind.rawValue)/\(ref.id)/watch/providers")
        return result.availability(region: region)
    }

    func episodes(showID: String, showName: String, season: Int, poster: URL?) async throws -> [EpisodeInfo] {
        let s: TMDBSeasonDetail = try await get("/tv/\(showID)/season/\(season)")
        let ref = TitleRef(source: .tmdb, kind: .tv, id: showID)
        return s.episodes.map { e in
            EpisodeInfo(id: "tmdb-ep-\(e.id)", showRef: ref, showName: showName, season: e.seasonNumber, number: e.episodeNumber,
                        name: e.name ?? "Episode \(e.episodeNumber)", airDate: DateParsing.date(e.airDate), runtime: e.runtime,
                        overview: e.overview ?? "", stillURL: Self.image(e.stillPath, size: "w500"), showPosterURL: poster)
        }
    }

    func upcomingEpisodes(showID: String) async throws -> [EpisodeInfo] {
        let d: TMDBDetail = try await get("/tv/\(showID)")
        guard let next = d.nextEpisodeToAir else { return [] }
        let poster = Self.image(d.posterPath, size: "w342")
        let all = try await episodes(showID: showID, showName: d.name ?? "", season: next.seasonNumber, poster: poster)
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return all.filter { ($0.airDate ?? .distantPast) >= startOfToday && $0.number >= next.episodeNumber }
    }
}

func interleave<T>(_ a: [T], _ b: [T]) -> [T] {
    var out: [T] = []
    for i in 0..<max(a.count, b.count) {
        if i < a.count { out.append(a[i]) }
        if i < b.count { out.append(b[i]) }
    }
    return out
}

// MARK: - DTOs

struct TMDBConfiguration: Decodable {}

struct TMDBPage<T: Decodable>: Decodable {
    var results: [T]
}

struct TMDBFindResult: Decodable {
    var movieResults: [TMDBItem]
    var tvResults: [TMDBItem]
}

enum TMDBGenres {
    static let names: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 99: "Documentary",
        18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Science Fiction", 10770: "TV Movie", 53: "Thriller",
        10752: "War", 37: "Western", 10759: "Action & Adventure", 10762: "Kids", 10763: "News",
        10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics",
    ]
}

struct TMDBItem: Decodable {
    var id: Int
    var title: String?
    var name: String?
    var overview: String?
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: String?
    var firstAirDate: String?
    var voteAverage: Double?
    var popularity: Double?
    var genreIds: [Int]?
    var mediaType: String?

    func catalogTitle(kind explicitKind: MediaKind? = nil) -> CatalogTitle? {
        let kind: MediaKind
        if let explicitKind { kind = explicitKind }
        else if mediaType == "movie" { kind = .movie }
        else if mediaType == "tv" { kind = .tv }
        else { return nil } // people, collections…
        let date = kind == .movie ? releaseDate : firstAirDate
        return CatalogTitle(
            ref: TitleRef(source: .tmdb, kind: kind, id: String(id)),
            name: (kind == .movie ? title : name) ?? title ?? name ?? "Untitled",
            overview: overview ?? "",
            posterURL: TMDBClient.image(posterPath, size: "w500"),
            backdropURL: TMDBClient.image(backdropPath, size: "w1280"),
            year: DateParsing.year(date),
            releaseDate: DateParsing.date(date),
            genres: (genreIds ?? []).compactMap { TMDBGenres.names[$0] },
            score: voteAverage.flatMap { $0 > 0 ? $0 : nil },
            popularity: popularity ?? 0)
    }
}

struct TMDBNamed: Decodable { var id: Int?; var name: String }

struct TMDBCast: Decodable {
    var id: Int
    var name: String
    var character: String?
    var profilePath: String?
    var roles: [TMDBRole]?
    struct TMDBRole: Decodable { var character: String? }
}

struct TMDBCredits: Decodable { var cast: [TMDBCast] }

struct TMDBVideo: Decodable { var key: String; var site: String; var type: String; var official: Bool? }
struct TMDBVideos: Decodable { var results: [TMDBVideo] }

struct TMDBProviderEntry: Decodable {
    var providerId: Int
    var providerName: String
    var logoPath: String?
    var displayPriority: Int?
}

struct TMDBRegionProviders: Decodable {
    var link: String?
    var flatrate: [TMDBProviderEntry]?
    var free: [TMDBProviderEntry]?
    var ads: [TMDBProviderEntry]?
    var rent: [TMDBProviderEntry]?
    var buy: [TMDBProviderEntry]?
}

struct TMDBWatchProviders: Decodable {
    var results: [String: TMDBRegionProviders]

    func availability(region: String) -> Availability {
        guard let r = results[region] else { return Availability(region: region) }
        var offers: [ProviderOffer] = []
        var seen = Set<String>()
        func add(_ entries: [TMDBProviderEntry]?, _ kind: OfferKind) {
            for e in (entries ?? []).sorted(by: { ($0.displayPriority ?? 99) < ($1.displayPriority ?? 99) }) {
                let provider = Provider.with(tmdbID: e.providerId)
                    ?? Provider.matching(name: e.providerName)
                    ?? Provider.adHoc(tmdbID: e.providerId, name: e.providerName)
                // Collapse e.g. "Netflix" + "Netflix basic with Ads" into one chip per kind.
                guard seen.insert("\(provider.id)-\(kind.rawValue)").inserted else { continue }
                offers.append(ProviderOffer(provider: provider, kind: kind,
                                            logoURL: TMDBClient.image(e.logoPath, size: "w154")))
            }
        }
        add(r.flatrate, .stream)
        add(r.free, .free)
        add(r.ads, .ads)
        add(r.rent, .rent)
        add(r.buy, .buy)
        return Availability(offers: offers, link: r.link.flatMap(URL.init(string:)), region: region)
    }
}

struct TMDBEpisode: Decodable {
    var id: Int
    var name: String?
    var overview: String?
    var episodeNumber: Int
    var seasonNumber: Int
    var airDate: String?
    var runtime: Int?
    var stillPath: String?
}

struct TMDBSeason: Decodable {
    var seasonNumber: Int
    var name: String?
    var episodeCount: Int?
    var posterPath: String?
    var airDate: String?
}

struct TMDBSeasonDetail: Decodable { var episodes: [TMDBEpisode] }

struct TMDBExternalIDs: Decodable { var imdbId: String? }

struct TMDBReleaseDates: Decodable {
    var results: [Country]
    struct Country: Decodable { var iso31661: String; var releaseDates: [Entry] }
    struct Entry: Decodable { var certification: String? }
}

struct TMDBContentRatings: Decodable {
    var results: [Country]
    struct Country: Decodable { var iso31661: String; var rating: String? }
}

struct TMDBDetail: Decodable {
    var id: Int
    var title: String?
    var name: String?
    var overview: String?
    var tagline: String?
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: String?
    var firstAirDate: String?
    var voteAverage: Double?
    var popularity: Double?
    var runtime: Int?
    var episodeRunTime: [Int]?
    var genres: [TMDBNamed]?
    var status: String?
    var homepage: String?
    var imdbId: String?
    var externalIds: TMDBExternalIDs?
    var credits: TMDBCredits?
    var aggregateCredits: TMDBCredits?
    var videos: TMDBVideos?
    var watchProviders: TMDBWatchProviders?
    var seasons: [TMDBSeason]?
    var nextEpisodeToAir: TMDBEpisode?
    var networks: [TMDBNamed]?
    var similar: TMDBPage<TMDBItem>?
    var recommendations: TMDBPage<TMDBItem>?
    var createdBy: [TMDBNamed]?
    var releaseDates: TMDBReleaseDates?
    var contentRatings: TMDBContentRatings?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, tagline, posterPath, backdropPath, releaseDate, firstAirDate, voteAverage,
             popularity, runtime, episodeRunTime, genres, status, homepage, imdbId, externalIds, credits,
             aggregateCredits, videos, seasons, nextEpisodeToAir, networks, similar, recommendations, createdBy,
             releaseDates, contentRatings
        case watchProviders = "watch/providers"
    }

    func titleDetail(kind: MediaKind, region: String) -> TitleDetail {
        let date = kind == .movie ? releaseDate : firstAirDate
        let ref = TitleRef(source: .tmdb, kind: kind, id: String(id))
        let availability = watchProviders?.availability(region: region) ?? Availability(region: region)
        let certification: String? = kind == .movie
            ? releaseDates?.results.first { $0.iso31661 == region }?.releaseDates.compactMap(\.certification).first { !$0.isEmpty }
            : contentRatings?.results.first { $0.iso31661 == region }?.rating
        let poster = TMDBClient.image(posterPath, size: "w500")
        let title = CatalogTitle(
            ref: ref,
            name: (kind == .movie ? title : name) ?? "Untitled",
            overview: overview ?? "",
            posterURL: poster,
            backdropURL: TMDBClient.image(backdropPath, size: "original"),
            year: DateParsing.year(date),
            releaseDate: DateParsing.date(date),
            genres: genres?.map(\.name) ?? [],
            score: voteAverage.flatMap { $0 > 0 ? $0 : nil },
            runtime: runtime ?? episodeRunTime?.first,
            providers: availability.offers(.stream).map(\.provider),
            network: networks?.first?.name,
            status: status,
            certification: certification,
            homepage: homepage.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            imdbID: imdbId ?? externalIds?.imdbId,
            popularity: popularity ?? 0)

        let castSource = (aggregateCredits?.cast.isEmpty == false ? aggregateCredits : credits)?.cast ?? []
        let cast = castSource.prefix(20).map {
            CastMember(id: String($0.id), name: $0.name,
                       character: $0.character ?? $0.roles?.first?.character ?? "",
                       photoURL: TMDBClient.image($0.profilePath, size: "w185"))
        }
        let trailer = videos?.results
            .filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
            .sorted { ($0.official ?? false) && !($1.official ?? false) }
            .first
            .flatMap { URL(string: "https://www.youtube.com/watch?v=\($0.key)") }
        let recs = (recommendations?.results ?? []) + (similar?.results ?? [])
        var seen = Set<Int>()
        let similarTitles = recs.filter { seen.insert($0.id).inserted }.prefix(18).compactMap { $0.catalogTitle(kind: kind) }
        let next = nextEpisodeToAir.map { e in
            EpisodeInfo(id: "tmdb-ep-\(e.id)", showRef: ref, showName: title.name, season: e.seasonNumber,
                        number: e.episodeNumber, name: e.name ?? "", airDate: DateParsing.date(e.airDate),
                        runtime: e.runtime, overview: e.overview ?? "", stillURL: TMDBClient.image(e.stillPath, size: "w500"),
                        showPosterURL: poster)
        }
        let seasons = (seasons ?? []).filter { $0.seasonNumber > 0 }.map {
            SeasonInfo(number: $0.seasonNumber, name: $0.name ?? "Season \($0.seasonNumber)", episodeCount: $0.episodeCount,
                       posterURL: TMDBClient.image($0.posterPath, size: "w342"), airYear: DateParsing.year($0.airDate))
        }
        return TitleDetail(title: title, tagline: tagline.flatMap { $0.isEmpty ? nil : $0 }, cast: Array(cast),
                           seasons: seasons, availability: availability, similar: Array(similarTitles),
                           trailerURL: trailer, nextEpisode: next, creators: createdBy?.map(\.name) ?? [])
    }
}
