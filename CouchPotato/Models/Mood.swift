import SwiftUI

/// "Mood Mash" vibes, each mapped onto the genre systems of every catalog.
enum Mood: String, CaseIterable, Identifiable, Hashable {
    case cozy, laughs, edge, feels, spooky, brainy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cozy: "Cozy"
        case .laughs: "Belly Laughs"
        case .edge: "Edge of Couch"
        case .feels: "Big Feels"
        case .spooky: "Spooky"
        case .brainy: "Brain Food"
        }
    }

    var emoji: String {
        switch self {
        case .cozy: "🧸"
        case .laughs: "😂"
        case .edge: "😱"
        case .feels: "😭"
        case .spooky: "👻"
        case .brainy: "🧠"
        }
    }

    var blurb: String {
        switch self {
        case .cozy: "Blanket burrito energy."
        case .laughs: "Snort-laughs guaranteed."
        case .edge: "Cushion-gripping thrills."
        case .feels: "Tissues within arm's reach."
        case .spooky: "Watch from behind a pillow."
        case .brainy: "Smarter by the credits."
        }
    }

    var color: Color {
        switch self {
        case .cozy: Spud.potato
        case .laughs: Spud.butter
        case .edge: Spud.ketchup
        case .feels: Color(hex: 0x5B8DEF)
        case .spooky: Spud.grape
        case .brainy: Spud.lettuce
        }
    }

    var tmdbMovieGenres: [Int] {
        switch self {
        case .cozy: [10751, 16, 10749]
        case .laughs: [35]
        case .edge: [53, 28]
        case .feels: [18]
        case .spooky: [27]
        case .brainy: [99, 878]
        }
    }

    var tmdbTVGenres: [Int] {
        switch self {
        case .cozy: [10751, 16]
        case .laughs: [35]
        case .edge: [10759, 80]
        case .feels: [18]
        case .spooky: [9648]
        case .brainy: [99, 10765]
        }
    }

    /// Genre names as they appear in TVmaze, iTunes and TMDB payloads.
    var genreNames: [String] {
        switch self {
        case .cozy: ["Family", "Children", "Animation", "Kids & Family", "Romance", "Holiday"]
        case .laughs: ["Comedy"]
        case .edge: ["Thriller", "Action", "Crime", "Action & Adventure", "Espionage", "War"]
        case .feels: ["Drama", "Romance"]
        case .spooky: ["Horror", "Supernatural", "Mystery"]
        case .brainy: ["Documentary", "Science-Fiction", "Sci-Fi & Fantasy", "Science Fiction", "History", "Medical", "Legal"]
        }
    }

    var itunesGenreIDs: [Int] {
        switch self {
        case .cozy: [4410, 4412]
        case .laughs: [4404]
        case .edge: [4416, 4401]
        case .feels: [4406]
        case .spooky: [4408]
        case .brainy: [4405, 4413]
        }
    }

    func matches(_ title: CatalogTitle) -> Bool {
        let names = Set(genreNames.map { $0.lowercased() })
        return title.genres.contains { names.contains($0.lowercased()) }
    }
}

/// "I've got…" time budgets for Spud Roulette.
enum TimeBudget: Int, CaseIterable, Identifiable {
    case snack = 35, hour = 70, evening = 150, allNight = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .snack: "A snack (30m)"
        case .hour: "An hour"
        case .evening: "An evening"
        case .allNight: "All night"
        }
    }

    var emoji: String {
        switch self {
        case .snack: "🍟"
        case .hour: "🥔"
        case .evening: "🛋️"
        case .allNight: "🌙"
        }
    }
}
