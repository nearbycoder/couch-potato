import Foundation

enum MediaKind: String, Codable, CaseIterable, Hashable {
    case movie, tv

    var label: String { self == .movie ? "Movie" : "Series" }
    var pluralLabel: String { self == .movie ? "Movies" : "Series" }
    var symbol: String { self == .movie ? "film" : "tv" }
}

enum CatalogSource: String, Codable, Hashable {
    case tmdb, tvmaze, itunes

    var displayName: String {
        switch self {
        case .tmdb: "TMDB"
        case .tvmaze: "TVmaze"
        case .itunes: "Apple TV Store"
        }
    }
}

/// A stable pointer to a title in one of the catalogs, e.g. `tmdb-movie-603`.
struct TitleRef: Hashable, Codable, Identifiable {
    var source: CatalogSource
    var kind: MediaKind
    var id: String

    var key: String { "\(source.rawValue)-\(kind.rawValue)-\(id)" }

    init(source: CatalogSource, kind: MediaKind, id: String) {
        self.source = source
        self.kind = kind
        self.id = id
    }

    init?(key: String) {
        let parts = key.split(separator: "-", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              let source = CatalogSource(rawValue: parts[0]),
              let kind = MediaKind(rawValue: parts[1]) else { return nil }
        self.init(source: source, kind: kind, id: parts[2])
    }

    var deepLink: URL { URL(string: "couchpotato://title/\(key)")! }

    var webURL: URL? {
        switch source {
        case .tmdb: URL(string: "https://www.themoviedb.org/\(kind.rawValue)/\(id)")
        case .tvmaze: URL(string: "https://www.tvmaze.com/shows/\(id)")
        case .itunes: URL(string: "https://tv.apple.com/movie/id\(id)")
        }
    }
}

struct CatalogTitle: Identifiable, Hashable {
    var ref: TitleRef
    var name: String
    var overview: String = ""
    var posterURL: URL?
    var backdropURL: URL?
    var year: Int?
    var releaseDate: Date?
    var genres: [String] = []
    /// 0–10 community score.
    var score: Double?
    var runtime: Int?
    /// Providers known up front (e.g. the streamer a TVmaze show airs on).
    var providers: [Provider] = []
    var network: String?
    var status: String?
    var certification: String?
    var homepage: URL?
    var imdbID: String?
    var popularity: Double = 0

    var id: String { ref.key }
    var kind: MediaKind { ref.kind }

    static func == (lhs: CatalogTitle, rhs: CatalogTitle) -> Bool { lhs.ref == rhs.ref }
    func hash(into hasher: inout Hasher) { hasher.combine(ref) }

    var subtitle: String {
        var bits: [String] = []
        if let year { bits.append(String(year)) }
        bits.append(kind.label)
        if let runtime, runtime > 0 { bits.append(runtime.runtimeLabel) }
        return bits.joined(separator: " · ")
    }
}

struct CastMember: Identifiable, Hashable {
    var id: String
    var name: String
    var character: String
    var photoURL: URL?
}

struct EpisodeInfo: Identifiable, Hashable {
    var id: String
    var showRef: TitleRef
    var showName: String
    var season: Int
    var number: Int
    var name: String
    var airDate: Date?
    var runtime: Int?
    var overview: String = ""
    var stillURL: URL?
    var showPosterURL: URL?

    var code: String { String(format: "S%02dE%02d", season, number) }
}

struct SeasonInfo: Identifiable, Hashable {
    var number: Int
    var name: String
    var episodeCount: Int?
    var posterURL: URL?
    var airYear: Int?
    var id: Int { number }
}

enum OfferKind: String, CaseIterable, Hashable {
    case stream, free, ads, rent, buy

    var label: String {
        switch self {
        case .stream: "Stream"
        case .free: "Free"
        case .ads: "Free with ads"
        case .rent: "Rent"
        case .buy: "Buy"
        }
    }
}

struct ProviderOffer: Identifiable, Hashable {
    var provider: Provider
    var kind: OfferKind
    var logoURL: URL?
    var price: String?
    var link: URL?
    var id: String { "\(provider.id)-\(kind.rawValue)" }
}

struct Availability: Hashable {
    var offers: [ProviderOffer] = []
    /// Attribution/landing page for the availability data (TMDB → JustWatch).
    var link: URL?
    var region: String = "US"

    func offers(_ kind: OfferKind) -> [ProviderOffer] { offers.filter { $0.kind == kind } }
    var isEmpty: Bool { offers.isEmpty }
    var providers: [Provider] {
        var seen = Set<String>()
        return offers.map(\.provider).filter { seen.insert($0.id).inserted }
    }
}

struct TitleDetail {
    var title: CatalogTitle
    var tagline: String?
    var cast: [CastMember] = []
    var seasons: [SeasonInfo] = []
    var availability = Availability()
    var similar: [CatalogTitle] = []
    var trailerURL: URL?
    var nextEpisode: EpisodeInfo?
    var creators: [String] = []
}

extension Int {
    var runtimeLabel: String {
        let h = self / 60, m = self % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

extension String {
    /// Strips the light HTML TVmaze uses in summaries.
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
