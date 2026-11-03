import Foundation

/// TVmaze: a free, key-less TV catalog with schedules and the streamer/network
/// each show lives on. Data is CC BY-SA, credited in Settings.
struct TVMazeClient {
    private static let base = "https://api.tvmaze.com"

    private func get<T: Decodable>(_ path: String, _ query: [String: String?] = [:]) async throws -> T {
        try await HTTP.get(HTTP.url(Self.base, path, query))
    }

    func search(_ text: String) async throws -> [CatalogTitle] {
        let results: [TVMSearchResult] = try await get("/search/shows", ["q": text])
        return results.map { $0.show.catalogTitle }
    }

    /// Episodes released on streaming services (`web`) or US broadcast on a given day.
    func schedule(_ date: Date, web: Bool) async throws -> [TVMScheduleItem] {
        let day = DateParsing.dayString(date)
        return web
            ? try await get("/schedule/web", ["date": day])
            : try await get("/schedule", ["date": day, "country": "US"])
    }

    func detail(_ id: String) async throws -> (TVMShow, TitleDetail) {
        let url = URL(string: "\(Self.base)/shows/\(id)?embed[]=cast&embed[]=seasons&embed[]=images&embed[]=nextepisode")!
        let show: TVMShow = try await HTTP.get(url)
        let base = show.catalogTitle
        var title = base
        let backdrop = show.embedded?.images?
            .filter { $0.type == "background" }
            .sorted { ($0.main ?? false) && !($1.main ?? false) }
            .first?.resolutions.original?.url
        title.backdropURL = backdrop.flatMap(URL.init(string:))
        let cast = (show.embedded?.cast ?? []).prefix(20).map {
            CastMember(id: String($0.person.id), name: $0.person.name, character: $0.character?.name ?? "",
                       photoURL: ($0.person.image?.medium).flatMap(URL.init(string:)))
        }
        let seasons = (show.embedded?.seasons ?? []).filter { $0.number > 0 }.map {
            SeasonInfo(number: $0.number, name: ($0.name?.isEmpty == false ? $0.name! : "Season \($0.number)"),
                       episodeCount: $0.episodeOrder, posterURL: ($0.image?.original).flatMap(URL.init(string:)),
                       airYear: DateParsing.year($0.premiereDate))
        }
        let next = show.embedded?.nextepisode.map { $0.episodeInfo(show: base) }
        var offers: [ProviderOffer] = []
        for provider in base.providers {
            var link = provider.searchURL(for: base.name)
            if let site = show.officialSite, let host = URL(string: site)?.host,
               provider.searchTemplate.flatMap({ URL(string: $0)?.host }).map({ hostMatches(host, $0) }) == true {
                link = URL(string: site)
            }
            offers.append(ProviderOffer(provider: provider, kind: .stream, link: link))
        }
        let detail = TitleDetail(title: title, cast: Array(cast), seasons: seasons,
                                 availability: Availability(offers: offers, link: URL(string: show.url ?? ""), region: "US"),
                                 nextEpisode: next)
        return (show, detail)
    }

    func episodes(showID: String) async throws -> [TVMEpisode] {
        try await get("/shows/\(showID)/episodes")
    }

    private func hostMatches(_ a: String, _ b: String) -> Bool {
        let strip = { (h: String) in h.split(separator: ".").suffix(2).joined(separator: ".") }
        return strip(a) == strip(b)
    }
}

// MARK: - DTOs

struct TVMImage: Decodable { var medium: String?; var original: String? }
struct TVMChannel: Decodable { var id: Int; var name: String; var officialSite: String? }
struct TVMRating: Decodable { var average: Double? }
struct TVMExternals: Decodable { var imdb: String?; var thetvdb: Int? }

struct TVMEpisode: Decodable {
    var id: Int
    var name: String?
    var season: Int
    var number: Int?
    var airdate: String?
    var airstamp: String?
    var runtime: Int?
    var summary: String?
    var image: TVMImage?

    func episodeInfo(show: CatalogTitle) -> EpisodeInfo {
        EpisodeInfo(id: "tvmaze-ep-\(id)", showRef: show.ref, showName: show.name, season: season, number: number ?? 0,
                    name: name ?? "Episode \(number ?? 0)",
                    airDate: DateParsing.date(airstamp) ?? DateParsing.date(airdate),
                    runtime: runtime ?? show.runtime, overview: summary?.strippingHTML ?? "",
                    stillURL: (image?.original ?? image?.medium).flatMap(URL.init(string:)),
                    showPosterURL: show.posterURL)
    }
}

struct TVMSeason: Decodable {
    var number: Int
    var name: String?
    var episodeOrder: Int?
    var premiereDate: String?
    var image: TVMImage?
}

struct TVMCastCredit: Decodable {
    var person: Person
    var character: Character?
    struct Person: Decodable { var id: Int; var name: String; var image: TVMImage? }
    struct Character: Decodable { var name: String }
}

struct TVMShowImage: Decodable {
    var type: String?
    var main: Bool?
    var resolutions: Resolutions
    struct Resolutions: Decodable { var original: Res? }
    struct Res: Decodable { var url: String }
}

struct TVMEmbedded: Decodable {
    var cast: [TVMCastCredit]?
    var seasons: [TVMSeason]?
    var images: [TVMShowImage]?
    var nextepisode: TVMEpisode?
}

struct TVMShow: Decodable {
    var id: Int
    var url: String?
    var name: String
    var type: String?
    var language: String?
    var genres: [String]?
    var status: String?
    var runtime: Int?
    var averageRuntime: Int?
    var premiered: String?
    var officialSite: String?
    var rating: TVMRating?
    var weight: Int?
    var network: TVMChannel?
    var webChannel: TVMChannel?
    var externals: TVMExternals?
    var image: TVMImage?
    var summary: String?
    var embedded: TVMEmbedded?

    enum CodingKeys: String, CodingKey {
        case id, url, name, type, language, genres, status, runtime, averageRuntime, premiered, officialSite,
             rating, weight, network, webChannel, externals, image, summary
        case embedded = "_embedded"
    }

    var catalogTitle: CatalogTitle {
        let channels = [webChannel?.name, network?.name].compactMap { $0 }
        var providers: [Provider] = []
        for channel in channels {
            if let p = Provider.matching(name: channel), !providers.contains(p) { providers.append(p) }
        }
        return CatalogTitle(
            ref: TitleRef(source: .tvmaze, kind: .tv, id: String(id)),
            name: name,
            overview: summary?.strippingHTML ?? "",
            posterURL: (image?.original ?? image?.medium).flatMap(URL.init(string:)),
            year: DateParsing.year(premiered),
            releaseDate: DateParsing.date(premiered),
            genres: genres ?? [],
            score: rating?.average,
            runtime: averageRuntime ?? runtime,
            providers: providers,
            network: webChannel?.name ?? network?.name,
            status: status,
            homepage: officialSite.flatMap(URL.init(string:)),
            imdbID: externals?.imdb,
            popularity: Double(weight ?? 0))
    }
}

struct TVMSearchResult: Decodable { var show: TVMShow }

struct TVMScheduleItem: Decodable {
    var id: Int
    var season: Int?
    var number: Int?
    var airstamp: String?
    var embedded: Embedded?
    var show: TVMShow?

    struct Embedded: Decodable { var show: TVMShow }

    enum CodingKeys: String, CodingKey {
        case id, season, number, airstamp, show
        case embedded = "_embedded"
    }

    /// `/schedule/web` embeds the show; `/schedule` inlines it.
    var resolvedShow: TVMShow? { embedded?.show ?? show }
}
