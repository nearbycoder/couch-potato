import SwiftUI

/// A streaming service or store. The well-known ones are listed in `Provider.all`;
/// anything else TMDB reports becomes an ad-hoc provider.
struct Provider: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var shortName: String
    var colorHex: String
    var tmdbIDs: [Int] = []
    /// Lowercased name fragments that identify this provider in other catalogs.
    var aliases: [String] = []
    /// Search URL template; `{q}` is replaced by the title.
    var searchTemplate: String?

    var color: Color { Color(hexString: colorHex) }

    /// Two-or-three letter mark for monogram tiles when no logo image is available.
    var monogram: String {
        if let mark = Self.marks[id] { return mark }
        let letters = shortName.filter(\.isLetter)
        return String(letters.prefix(2)).uppercased()
    }

    static func == (lhs: Provider, rhs: Provider) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    func searchURL(for title: String) -> URL? {
        guard let searchTemplate,
              let q = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: searchTemplate.replacingOccurrences(of: "{q}", with: q))
    }
}

extension Provider {
    static let netflix = Provider(id: "netflix", name: "Netflix", shortName: "Netflix", colorHex: "E50914",
                                  tmdbIDs: [8, 1796], aliases: ["netflix"],
                                  searchTemplate: "https://www.netflix.com/search?q={q}")
    static let hulu = Provider(id: "hulu", name: "Hulu", shortName: "Hulu", colorHex: "1CE783",
                               tmdbIDs: [15], aliases: ["hulu", "fx", "fxx", "abc", "freeform"],
                               searchTemplate: "https://www.hulu.com/search?q={q}")
    static let disney = Provider(id: "disney", name: "Disney+", shortName: "Disney+", colorHex: "113CCF",
                                 tmdbIDs: [337], aliases: ["disney", "national geographic", "nat geo"],
                                 searchTemplate: "https://www.disneyplus.com/search?q={q}")
    static let hbo = Provider(id: "hbo", name: "HBO Max", shortName: "HBO Max", colorHex: "6A2FD8",
                              tmdbIDs: [1899, 384, 118], aliases: ["hbo", "max", "cinemax", "tnt", "tbs", "adult swim", "cartoon network", "discovery", "hgtv", "food network", "tlc"],
                              searchTemplate: "https://play.hbomax.com/search?q={q}")
    static let apple = Provider(id: "apple", name: "Apple TV", shortName: "Apple TV", colorHex: "A2AAAD",
                                tmdbIDs: [350], aliases: ["apple tv+", "apple tv"],
                                searchTemplate: "https://tv.apple.com/search?term={q}")
    static let prime = Provider(id: "prime", name: "Prime Video", shortName: "Prime", colorHex: "00A8E1",
                                tmdbIDs: [9, 119, 10], aliases: ["prime video", "amazon", "freevee", "mgm+"],
                                searchTemplate: "https://www.amazon.com/s?k={q}&i=instant-video")
    static let peacock = Provider(id: "peacock", name: "Peacock", shortName: "Peacock", colorHex: "F2A900",
                                  tmdbIDs: [386, 387], aliases: ["peacock", "nbc", "bravo", "usa network", "syfy", "e!"],
                                  searchTemplate: "https://www.peacocktv.com/search?q={q}")
    static let paramount = Provider(id: "paramount", name: "Paramount+", shortName: "Paramount+", colorHex: "0064FF",
                                    tmdbIDs: [531, 2303, 2616, 582], aliases: ["paramount", "cbs", "showtime", "mtv", "comedy central", "nickelodeon", "bet"],
                                    searchTemplate: "https://www.paramountplus.com/search/?q={q}")
    static let starz = Provider(id: "starz", name: "Starz", shortName: "Starz", colorHex: "C9A227",
                                tmdbIDs: [43], aliases: ["starz"], searchTemplate: "https://www.starz.com/us/en/search?q={q}")
    static let amc = Provider(id: "amc", name: "AMC+", shortName: "AMC+", colorHex: "C8102E",
                              tmdbIDs: [526, 80], aliases: ["amc", "shudder", "sundance", "acorn", "ifc"],
                              searchTemplate: "https://www.amcplus.com/search?q={q}")
    static let crunchyroll = Provider(id: "crunchyroll", name: "Crunchyroll", shortName: "Crunchyroll", colorHex: "F47521",
                                      tmdbIDs: [283], aliases: ["crunchyroll"],
                                      searchTemplate: "https://www.crunchyroll.com/search?q={q}")
    static let tubi = Provider(id: "tubi", name: "Tubi", shortName: "Tubi", colorHex: "7408FF",
                               tmdbIDs: [73], aliases: ["tubi"], searchTemplate: "https://tubitv.com/search/{q}")
    static let youtube = Provider(id: "youtube", name: "YouTube", shortName: "YouTube", colorHex: "FF0033",
                                  tmdbIDs: [192, 188], aliases: ["youtube"],
                                  searchTemplate: "https://www.youtube.com/results?search_query={q}")
    static let appleStore = Provider(id: "apple-store", name: "Apple TV Store", shortName: "Apple Store", colorHex: "A2AAAD",
                                     tmdbIDs: [2], aliases: ["apple tv store", "itunes"],
                                     searchTemplate: "https://tv.apple.com/search?term={q}")

    /// The services people can mark as "mine", in display order.
    static let streamers: [Provider] = [.netflix, .hulu, .disney, .hbo, .apple, .prime, .peacock, .paramount,
                                        .starz, .amc, .crunchyroll, .tubi, .youtube]
    static let all: [Provider] = streamers + [.appleStore]

    static func with(id: String) -> Provider? { all.first { $0.id == id } }

    private static let marks: [String: String] = [
        "netflix": "N", "hulu": "H", "disney": "D+", "hbo": "HBO", "apple": "TV", "prime": "PV", "peacock": "P",
        "paramount": "P+", "starz": "S", "amc": "AMC", "crunchyroll": "CR", "tubi": "T", "youtube": "YT", "apple-store": "TV",
    ]

    static func with(tmdbID: Int) -> Provider? { all.first { $0.tmdbIDs.contains(tmdbID) } }

    /// Matches a free-form network/channel name, e.g. "Apple TV" or "FX", to a provider.
    static func matching(name: String) -> Provider? {
        let lower = name.lowercased()
        if let exact = all.first(where: { $0.name.lowercased() == lower || $0.aliases.contains(lower) }) {
            return exact
        }
        return streamers.first { p in p.aliases.contains { alias in alias.count > 3 && lower.contains(alias) } }
    }

    static func adHoc(tmdbID: Int, name: String) -> Provider {
        Provider(id: "tmdb-\(tmdbID)", name: name, shortName: name, colorHex: "3A3A46", tmdbIDs: [tmdbID], searchTemplate: nil)
    }
}
