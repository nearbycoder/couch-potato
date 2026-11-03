import Foundation

/// Apple's public iTunes charts + lookup: key-less movie box art, charts by genre,
/// and Apple TV Store rent/buy prices.
struct ITunesClient {
    var country: String = "us"

    func topMovies(genre: Int? = nil, limit: Int = 50) async throws -> [CatalogTitle] {
        let genrePart = genre.map { "/genre=\($0)" } ?? ""
        let url = URL(string: "https://itunes.apple.com/\(country)/rss/topmovies/limit=\(limit)\(genrePart)/json")!
        let feed: ITunesFeed = try await HTTP.get(url)
        return (feed.feed.entry ?? []).enumerated().compactMap { index, entry in
            entry.catalogTitle(rank: index)
        }
    }

    func lookup(_ id: String) async throws -> (CatalogTitle, ITunesTrack) {
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&country=\(country)")!
        let result: ITunesLookup = try await HTTP.get(url)
        guard let track = result.results.first else { throw HTTPError.status(404) }
        return (track.catalogTitle, track)
    }

    /// Bumps an mzstatic thumbnail URL to a crisp poster size.
    static func upscale(_ urlString: String?, to size: String = "600x900bb") -> URL? {
        guard let urlString else { return nil }
        let upscaled = urlString.replacingOccurrences(of: #"/\d+x\d+bb\.(png|jpg)$"#, with: "/\(size).jpg",
                                                      options: .regularExpression)
        return URL(string: upscaled)
    }
}

struct ITunesLabel: Decodable { var label: String }

struct ITunesFeed: Decodable {
    var feed: Feed
    struct Feed: Decodable { var entry: [ITunesEntry]? }
}

struct ITunesEntry: Decodable {
    var name: ITunesLabel
    var summary: ITunesLabel?
    var images: [ITunesLabel]?
    var id: ID
    var category: Category?
    var releaseDate: ITunesLabel?
    var rentalPrice: ITunesLabel?

    struct ID: Decodable {
        var attributes: Attributes
        struct Attributes: Decodable {
            var id: String
            enum CodingKeys: String, CodingKey { case id = "im:id" }
        }
    }

    struct Category: Decodable {
        var attributes: Attributes
        struct Attributes: Decodable { var label: String }
    }

    enum CodingKeys: String, CodingKey {
        case name = "im:name", summary, images = "im:image", id, category
        case releaseDate = "im:releaseDate", rentalPrice = "im:rentalPrice"
    }

    func catalogTitle(rank: Int) -> CatalogTitle {
        let date = DateParsing.date(releaseDate?.label)
        return CatalogTitle(
            ref: TitleRef(source: .itunes, kind: .movie, id: id.attributes.id),
            name: name.label,
            overview: summary?.label ?? "",
            posterURL: ITunesClient.upscale(images?.last?.label),
            year: date.map { Calendar.current.component(.year, from: $0) },
            releaseDate: date,
            genres: category.map { [$0.attributes.label] } ?? [],
            providers: [.appleStore],
            popularity: Double(100 - rank))
    }
}

struct ITunesLookup: Decodable { var results: [ITunesTrack] }

struct ITunesTrack: Decodable {
    var trackId: Int
    var trackName: String
    var artistName: String?
    var artworkUrl100: String?
    var longDescription: String?
    var primaryGenreName: String?
    var releaseDate: String?
    var trackTimeMillis: Int?
    var contentAdvisoryRating: String?
    var trackViewUrl: String?
    var trackPrice: Double?
    var trackRentalPrice: Double?
    var trackHdPrice: Double?
    var trackHdRentalPrice: Double?
    var previewUrl: String?

    var catalogTitle: CatalogTitle {
        let date = DateParsing.date(releaseDate)
        return CatalogTitle(
            ref: TitleRef(source: .itunes, kind: .movie, id: String(trackId)),
            name: trackName,
            overview: longDescription ?? "",
            posterURL: ITunesClient.upscale(artworkUrl100),
            year: date.map { Calendar.current.component(.year, from: $0) },
            releaseDate: date,
            genres: primaryGenreName.map { [$0] } ?? [],
            runtime: trackTimeMillis.map { $0 / 60_000 },
            providers: [.appleStore],
            certification: contentAdvisoryRating,
            homepage: trackViewUrl.flatMap(URL.init(string:)))
    }

    func availability() -> Availability {
        let link = trackViewUrl.flatMap(URL.init(string:))
        func price(_ value: Double?) -> String? { value.flatMap { $0 > 0 ? String(format: "$%.2f", $0) : nil } }
        var offers: [ProviderOffer] = []
        if let rent = price(trackHdRentalPrice ?? trackRentalPrice) {
            offers.append(ProviderOffer(provider: .appleStore, kind: .rent, price: rent, link: link))
        }
        if let buy = price(trackHdPrice ?? trackPrice) {
            offers.append(ProviderOffer(provider: .appleStore, kind: .buy, price: buy, link: link))
        }
        return Availability(offers: offers, link: link)
    }
}
