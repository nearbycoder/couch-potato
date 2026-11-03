import SwiftUI

/// Moods, each mapped onto the genre systems of every catalog.
enum Mood: String, CaseIterable, Identifiable, Hashable {
    case cozy, laughs, thrills, feels, spooky, brainy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cozy: "Cozy"
        case .laughs: "Laughs"
        case .thrills: "Thrills"
        case .feels: "Feels"
        case .spooky: "Spooky"
        case .brainy: "Brainy"
        }
    }

    var symbol: String {
        switch self {
        case .cozy: "sofa"
        case .laughs: "face.smiling"
        case .thrills: "bolt"
        case .feels: "heart"
        case .spooky: "moon.stars"
        case .brainy: "brain"
        }
    }

    var blurb: String {
        switch self {
        case .cozy: "Comfort watches and family favorites"
        case .laughs: "Comedies and feel-good fun"
        case .thrills: "Thrillers, action and crime"
        case .feels: "Dramas and romances"
        case .spooky: "Horror, mystery and the supernatural"
        case .brainy: "Documentaries, science fiction and history"
        }
    }

    /// Duotone gradient (top-leading to bottom-trailing).
    var gradient: [Color] {
        switch self {
        case .cozy: [Color(hex: 0xD98E5A), Color(hex: 0x5A2E1A)]
        case .laughs: [Color(hex: 0xF0C94A), Color(hex: 0x5C4300)]
        case .thrills: [Color(hex: 0xE2473F), Color(hex: 0x3B0B0B)]
        case .feels: [Color(hex: 0x5B7FE8), Color(hex: 0x121C4A)]
        case .spooky: [Color(hex: 0x8A5CF5), Color(hex: 0x22104D)]
        case .brainy: [Color(hex: 0x3DBB9E), Color(hex: 0x0B3A33)]
        }
    }

    var tint: Color { gradient[0] }

    var tmdbMovieGenres: [Int] {
        switch self {
        case .cozy: [10751, 16, 10749]
        case .laughs: [35]
        case .thrills: [53, 28]
        case .feels: [18]
        case .spooky: [27]
        case .brainy: [99, 878]
        }
    }

    var tmdbTVGenres: [Int] {
        switch self {
        case .cozy: [10751, 16]
        case .laughs: [35]
        case .thrills: [10759, 80]
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
        case .thrills: ["Thriller", "Action", "Crime", "Action & Adventure", "Espionage", "War"]
        case .feels: ["Drama", "Romance"]
        case .spooky: ["Horror", "Supernatural", "Mystery"]
        case .brainy: ["Documentary", "Science-Fiction", "Sci-Fi & Fantasy", "Science Fiction", "History", "Medical", "Legal"]
        }
    }

    var itunesGenreIDs: [Int] {
        switch self {
        case .cozy: [4410, 4412]
        case .laughs: [4404]
        case .thrills: [4416, 4401]
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

/// Time-available filter for Shuffle.
enum TimeBudget: Int, CaseIterable, Identifiable {
    case snack = 35, hour = 70, evening = 150, allNight = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .snack: "30 min"
        case .hour: "1 hour"
        case .evening: "An evening"
        case .allNight: "All night"
        }
    }
}
