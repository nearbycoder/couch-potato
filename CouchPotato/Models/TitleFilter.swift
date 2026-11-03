import Foundation

/// Filters and sort order for browse pages (services, moods, See All lists). The same
/// filter runs locally on key-less lists and is translated to TMDB discover parameters.
struct TitleFilter: Hashable {
    enum Sort: String, CaseIterable, Identifiable {
        case popular, newest, rating, title
        var id: String { rawValue }
        var label: String {
            switch self {
            case .popular: "Popular"
            case .newest: "Newest"
            case .rating: "Highest Rated"
            case .title: "A–Z"
            }
        }
    }

    enum Years: String, CaseIterable, Identifiable {
        case any, thisYear, last5, y2020s, y2010s, y2000s, y1990s, older
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: "Any Year"
            case .thisYear: "This Year"
            case .last5: "Last 5 Years"
            case .y2020s: "2020s"
            case .y2010s: "2010s"
            case .y2000s: "2000s"
            case .y1990s: "1990s"
            case .older: "Before 1990"
            }
        }

        /// Inclusive year bounds; nil means open-ended.
        var bounds: (from: Int?, to: Int?) {
            let now = Calendar.current.component(.year, from: .now)
            switch self {
            case .any: return (nil, nil)
            case .thisYear: return (now, now)
            case .last5: return (now - 4, now)
            case .y2020s: return (2020, 2029)
            case .y2010s: return (2010, 2019)
            case .y2000s: return (2000, 2009)
            case .y1990s: return (1990, 1999)
            case .older: return (nil, 1989)
            }
        }
    }

    enum Genre: String, CaseIterable, Identifiable {
        case action, animation, comedy, crime, documentary, drama, family, scifi, horror, mystery, romance, reality
        var id: String { rawValue }
        var label: String {
            switch self {
            case .action: "Action & Adventure"
            case .animation: "Animation"
            case .comedy: "Comedy"
            case .crime: "Crime"
            case .documentary: "Documentary"
            case .drama: "Drama"
            case .family: "Family & Kids"
            case .scifi: "Sci-Fi & Fantasy"
            case .horror: "Horror"
            case .mystery: "Mystery & Thriller"
            case .romance: "Romance"
            case .reality: "Reality"
            }
        }

        var tmdbMovie: [Int] {
            switch self {
            case .action: [28, 12]
            case .animation: [16]
            case .comedy: [35]
            case .crime: [80]
            case .documentary: [99]
            case .drama: [18]
            case .family: [10751]
            case .scifi: [878, 14]
            case .horror: [27]
            case .mystery: [9648, 53]
            case .romance: [10749]
            case .reality: []
            }
        }

        /// TMDB has no TV genre for horror or romance, so those return movies only.
        var tmdbTV: [Int] {
            switch self {
            case .action: [10759]
            case .animation: [16]
            case .comedy: [35]
            case .crime: [80]
            case .documentary: [99]
            case .drama: [18]
            case .family: [10751, 10762]
            case .scifi: [10765]
            case .horror, .romance: []
            case .mystery: [9648]
            case .reality: [10764]
            }
        }

        /// Genre names as TMDB, TVmaze and iTunes spell them, lowercased.
        var names: Set<String> {
            switch self {
            case .action: ["action", "adventure", "action & adventure"]
            case .animation: ["animation", "anime"]
            case .comedy: ["comedy"]
            case .crime: ["crime", "legal", "espionage"]
            case .documentary: ["documentary", "nature", "history"]
            case .drama: ["drama", "medical"]
            case .family: ["family", "children", "kids", "kids & family"]
            case .scifi: ["science fiction", "science-fiction", "fantasy", "supernatural", "sci-fi & fantasy"]
            case .horror: ["horror"]
            case .mystery: ["mystery", "thriller"]
            case .romance: ["romance"]
            case .reality: ["reality"]
            }
        }
    }

    static let ratingSteps: [Double] = [6, 7, 8]

    var sort: Sort = .popular
    var years: Years = .any
    var genre: Genre?
    var minRating: Double?

    var isDefault: Bool { self == TitleFilter() }

    /// Stable key for caches and view identity.
    var key: String {
        "\(sort.rawValue)|\(years.rawValue)|\(genre?.rawValue ?? "-")|\(minRating.map { String(Int($0)) } ?? "-")"
    }

    func matches(_ title: CatalogTitle) -> Bool {
        let (from, to) = years.bounds
        if from != nil || to != nil {
            guard let year = title.year else { return false }
            if let from, year < from { return false }
            if let to, year > to { return false }
        }
        if let genre, !title.genres.contains(where: { genre.names.contains($0.lowercased()) }) { return false }
        if let minRating, (title.score ?? 0) < minRating { return false }
        return true
    }

    /// Filters, then sorts. `.popular` keeps the incoming order, which is already by popularity.
    func apply(_ titles: [CatalogTitle]) -> [CatalogTitle] {
        let kept = titles.filter(matches)
        switch sort {
        case .popular:
            return kept
        case .newest:
            let today = Date.now
            return kept
                .filter { ($0.releaseDate ?? .distantPast) <= today }
                .sorted { ($0.releaseDate ?? Self.date(year: $0.year)) > ($1.releaseDate ?? Self.date(year: $1.year)) }
        case .rating:
            return kept.sorted { ($0.score ?? -1) > ($1.score ?? -1) }
        case .title:
            return kept.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private static func date(year: Int?) -> Date {
        guard let year else { return .distantPast }
        return Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
    }

    // MARK: TMDB

    /// Discover parameters for one media kind, or nil when the filter rules that kind out
    /// (e.g. Horror has no TMDB TV genre).
    func tmdbQuery(for kind: MediaKind, includeGenre: Bool = true) -> (sort: String, genres: [Int], extra: [String: String?])? {
        var extra: [String: String?] = [:]
        let dateKey = kind == .movie ? "primary_release_date" : "first_air_date"
        let sortKey: String
        switch sort {
        case .popular: sortKey = "popularity.desc"
        case .newest:
            sortKey = "\(dateKey).desc"
            extra["\(dateKey).lte"] = DateParsing.dayString(.now)
        case .rating:
            sortKey = "vote_average.desc"
            extra["vote_count.gte"] = "200"
        case .title: sortKey = kind == .movie ? "title.asc" : "name.asc"
        }
        let (from, to) = years.bounds
        if let from { extra["\(dateKey).gte"] = "\(from)-01-01" }
        if let to {
            // Keep the earlier bound when Newest already capped it at today (ISO dates compare as strings).
            let end = "\(to)-12-31"
            if let today = extra["\(dateKey).lte"] ?? nil, today < end {} else { extra["\(dateKey).lte"] = end }
        }
        if let minRating {
            extra["vote_average.gte"] = String(Int(minRating))
            if extra["vote_count.gte"] == nil { extra["vote_count.gte"] = "50" }
        }
        var genres: [Int] = []
        if includeGenre, let genre {
            genres = kind == .movie ? genre.tmdbMovie : genre.tmdbTV
            if genres.isEmpty { return nil }
        }
        return (sortKey, genres, extra)
    }

    /// Orders one page of mixed movies and series by this filter's sort.
    func merge(shows: [CatalogTitle], movies: [CatalogTitle]) -> [CatalogTitle] {
        sort == .popular ? interleave(shows, movies) : TitleFilter(sort: sort).apply(shows + movies)
    }
}
