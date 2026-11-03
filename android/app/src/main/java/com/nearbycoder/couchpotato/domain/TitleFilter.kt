package com.nearbycoder.couchpotato.domain

import androidx.compose.runtime.Immutable
import java.time.LocalDate

/** How a browse grid is ordered. */
enum class TitleSort(val label: String) {
    POPULAR("Popular"),
    NEWEST("Newest"),
    RATING("Highest Rated"),
    TITLE("A–Z"),
}

/** Release-date windows for browse grids. */
enum class YearRange(val label: String) {
    ANY("Any Year"),
    THIS_YEAR("This Year"),
    LAST5("Last 5 Years"),
    Y2020S("2020s"),
    Y2010S("2010s"),
    Y2000S("2000s"),
    Y1990S("1990s"),
    OLDER("Before 1990");

    /** Inclusive (from, to) years; null means unbounded on that side. */
    fun bounds(currentYear: Int = LocalDate.now().year): Pair<Int?, Int?> = when (this) {
        ANY -> null to null
        THIS_YEAR -> currentYear to currentYear
        LAST5 -> (currentYear - 4) to currentYear
        Y2020S -> 2020 to 2029
        Y2010S -> 2010 to 2019
        Y2000S -> 2000 to 2009
        Y1990S -> 1990 to 1999
        OLDER -> null to 1989
    }

    fun contains(year: Int?, currentYear: Int = LocalDate.now().year): Boolean {
        if (this == ANY) return true
        if (year == null) return false
        val (from, to) = bounds(currentYear)
        return (from == null || year >= from) && (to == null || year <= to)
    }
}

/** Browse genres, mapped onto TMDB movie/TV genre ids and TVmaze genre names. */
enum class Genre(val label: String, val tmdbMovie: List<Int>, val tmdbTv: List<Int>, names: List<String>) {
    ACTION("Action & Adventure", listOf(28, 12), listOf(10759), listOf("action", "adventure", "action & adventure")),
    ANIMATION("Animation", listOf(16), listOf(16), listOf("animation", "anime")),
    COMEDY("Comedy", listOf(35), listOf(35), listOf("comedy")),
    CRIME("Crime", listOf(80), listOf(80), listOf("crime", "legal", "espionage")),
    DOCUMENTARY("Documentary", listOf(99), listOf(99), listOf("documentary", "nature", "history")),
    DRAMA("Drama", listOf(18), listOf(18), listOf("drama", "medical")),
    FAMILY("Family & Kids", listOf(10751), listOf(10751, 10762), listOf("family", "children", "kids", "kids & family")),
    SCIFI("Sci-Fi & Fantasy", listOf(878, 14), listOf(10765),
        listOf("science fiction", "science-fiction", "fantasy", "supernatural", "sci-fi & fantasy")),
    HORROR("Horror", listOf(27), emptyList(), listOf("horror")),
    MYSTERY("Mystery & Thriller", listOf(9648, 53), listOf(9648), listOf("mystery", "thriller")),
    ROMANCE("Romance", listOf(10749), emptyList(), listOf("romance")),
    REALITY("Reality", emptyList(), listOf(10764), listOf("reality"));

    fun tmdbIds(kind: MediaKind): List<Int> = if (kind == MediaKind.MOVIE) tmdbMovie else tmdbTv

    /** Genre names as TMDB, TVmaze and iTunes spell them, lowercased (same list as the Apple app). */
    private val names: Set<String> = names.toSet()

    fun matches(titleGenre: String): Boolean = titleGenre.lowercase() in names
}

/** Sort + filters for a browse grid. Shared semantics with the Apple app. */
@Immutable
data class TitleFilter(
    val sort: TitleSort = TitleSort.POPULAR,
    val years: YearRange = YearRange.ANY,
    val genre: Genre? = null,
    /** 6.0, 7.0 or 8.0 (0–10 scale); null means any. */
    val minRating: Double? = null,
) {
    val isDefault: Boolean
        get() = sort == TitleSort.POPULAR && years == YearRange.ANY && genre == null && minRating == null

    /** Stable string for memo keys, e.g. `POPULAR|ANY|-|-`. */
    val key: String
        get() = "${sort.name}|${years.name}|${genre?.name ?: "-"}|${minRating?.toString() ?: "-"}"

    fun matches(t: CatalogTitle, today: LocalDate = LocalDate.now()): Boolean {
        if (!years.contains(t.year, today.year)) return false
        genre?.let { g -> if (t.genres.none(g::matches)) return false }
        minRating?.let { min -> if ((t.score ?: 0.0) < min) return false }
        return true
    }

    /** Keeps the titles that match, in this filter's order. */
    fun apply(list: List<CatalogTitle>, today: LocalDate = LocalDate.now()): List<CatalogTitle> =
        sorted(list.filter { matches(it, today) }, today)

    /**
     * Orders titles by [sort] without filtering. POPULAR keeps the incoming order;
     * NEWEST drops anything dated in the future.
     */
    fun sorted(list: List<CatalogTitle>, today: LocalDate = LocalDate.now()): List<CatalogTitle> = when (sort) {
        TitleSort.POPULAR -> list
        TitleSort.NEWEST -> list
            .filter { t -> t.releaseDate?.let { it <= today } ?: t.year?.let { it <= today.year } ?: true }
            .sortedWith(compareByDescending<CatalogTitle, LocalDate?>(nullsFirst()) { it.sortDate })
        TitleSort.RATING -> list.sortedWith(compareByDescending<CatalogTitle, Double?>(nullsFirst()) { it.score })
        TitleSort.TITLE -> list.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** TMDB `sort_by` for this filter. */
    fun tmdbSort(kind: MediaKind): String = when (sort) {
        TitleSort.POPULAR -> "popularity.desc"
        TitleSort.NEWEST -> if (kind == MediaKind.MOVIE) "primary_release_date.desc" else "first_air_date.desc"
        TitleSort.RATING -> "vote_average.desc"
        TitleSort.TITLE -> if (kind == MediaKind.MOVIE) "title.asc" else "name.asc"
    }

    /**
     * Extra TMDB discover params for this filter (dates, vote floors), merged over [base].
     * `vote_count.gte` keeps the highest floor asked for.
     */
    fun tmdbParams(kind: MediaKind, base: Map<String, String?> = emptyMap(), today: LocalDate = LocalDate.now()): Map<String, String?> {
        val out = LinkedHashMap(base)
        fun voteFloor(min: Int) {
            val current = out["vote_count.gte"]?.toIntOrNull() ?: 0
            if (min > current) out["vote_count.gte"] = min.toString()
        }
        val dateField = if (kind == MediaKind.MOVIE) "primary_release_date" else "first_air_date"
        var from: LocalDate? = null
        var to: LocalDate? = null
        val (fromYear, toYear) = years.bounds(today.year)
        fromYear?.let { from = LocalDate.of(it, 1, 1) }
        toYear?.let { to = LocalDate.of(it, 12, 31) }
        if (sort == TitleSort.NEWEST) to = to?.let { minOf(it, today) } ?: today
        from?.let { out["$dateField.gte"] = it.toString() }
        to?.let { out["$dateField.lte"] = it.toString() }
        if (sort == TitleSort.RATING) voteFloor(200)
        minRating?.let {
            out["vote_average.gte"] = it.toInt().toString()
            voteFloor(50)
        }
        return out
    }
}

private val CatalogTitle.sortDate: LocalDate?
    get() = releaseDate ?: year?.let { LocalDate.of(it, 1, 1) }
