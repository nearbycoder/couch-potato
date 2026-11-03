package com.nearbycoder.couchpotato.domain

/** Moods, each mapped onto the genre systems of every catalog. */
enum class Mood(
    val id: String,
    val title: String,
    val blurb: String,
    /** Duotone gradient, top-left to bottom-right (RRGGBB). */
    val gradientFrom: Long,
    val gradientTo: Long,
    val tmdbMovieGenres: List<Int>,
    val tmdbTvGenres: List<Int>,
    /** Genre names as they appear in TVmaze, iTunes and TMDB payloads. */
    val genreNames: List<String>,
    val itunesGenreIds: List<Int>,
) {
    COZY(
        id = "cozy", title = "Cozy", blurb = "Warm, gentle and easy.",
        gradientFrom = 0xFFD98E5A, gradientTo = 0xFF5A2E1A,
        tmdbMovieGenres = listOf(10751, 16, 10749), tmdbTvGenres = listOf(10751, 16),
        genreNames = listOf("Family", "Children", "Animation", "Kids & Family", "Romance", "Holiday"),
        itunesGenreIds = listOf(4410, 4412),
    ),
    LAUGHS(
        id = "laughs", title = "Laughs", blurb = "Comedies that actually land.",
        gradientFrom = 0xFFF0C94A, gradientTo = 0xFF5C4300,
        tmdbMovieGenres = listOf(35), tmdbTvGenres = listOf(35),
        genreNames = listOf("Comedy"),
        itunesGenreIds = listOf(4404),
    ),
    THRILLS(
        id = "edge", title = "Thrills", blurb = "Action, crime and suspense.",
        gradientFrom = 0xFFE2473F, gradientTo = 0xFF3B0B0B,
        tmdbMovieGenres = listOf(53, 28), tmdbTvGenres = listOf(10759, 80),
        genreNames = listOf("Thriller", "Action", "Crime", "Action & Adventure", "Espionage", "War"),
        itunesGenreIds = listOf(4416, 4401),
    ),
    FEELS(
        id = "feels", title = "Feels", blurb = "Dramas worth the tissues.",
        gradientFrom = 0xFF5B7FE8, gradientTo = 0xFF121C4A,
        tmdbMovieGenres = listOf(18), tmdbTvGenres = listOf(18),
        genreNames = listOf("Drama", "Romance"),
        itunesGenreIds = listOf(4406),
    ),
    SPOOKY(
        id = "spooky", title = "Spooky", blurb = "Horror, mystery and the supernatural.",
        gradientFrom = 0xFF8A5CF5, gradientTo = 0xFF22104D,
        tmdbMovieGenres = listOf(27), tmdbTvGenres = listOf(9648),
        genreNames = listOf("Horror", "Supernatural", "Mystery"),
        itunesGenreIds = listOf(4408),
    ),
    BRAINY(
        id = "brainy", title = "Brainy", blurb = "Documentaries and smart sci-fi.",
        gradientFrom = 0xFF3DBB9E, gradientTo = 0xFF0B3A33,
        tmdbMovieGenres = listOf(99, 878), tmdbTvGenres = listOf(99, 10765),
        genreNames = listOf("Documentary", "Science-Fiction", "Sci-Fi & Fantasy", "Science Fiction", "History", "Medical", "Legal"),
        itunesGenreIds = listOf(4405, 4413),
    );

    fun matches(title: CatalogTitle): Boolean {
        val names = genreNames.map { it.lowercase() }.toSet()
        return title.genres.any { it.lowercase() in names }
    }

    companion object {
        fun withId(id: String?): Mood? = entries.firstOrNull { it.id == id }
    }
}

/** "I've got…" time budgets for Shuffle. Minutes; 0 means no limit. */
enum class TimeBudget(val minutes: Int, val label: String, val shortLabel: String) {
    SNACK(35, "30 minutes", "30m"),
    HOUR(70, "An hour", "1h"),
    EVENING(150, "An evening", "Evening"),
    ALL_NIGHT(0, "All night", "All night");

    fun fits(runtime: Int?): Boolean = minutes == 0 || runtime == null || runtime <= minutes
}
