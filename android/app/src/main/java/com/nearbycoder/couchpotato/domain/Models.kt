package com.nearbycoder.couchpotato.domain

import androidx.compose.runtime.Immutable
import java.time.LocalDate

enum class MediaKind(val raw: String, val label: String, val pluralLabel: String) {
    MOVIE("movie", "Movie", "Movies"),
    TV("tv", "Series", "Series");

    companion object {
        fun fromRaw(raw: String?): MediaKind? = entries.firstOrNull { it.raw == raw }
    }
}

enum class CatalogSource(val raw: String, val displayName: String) {
    TMDB("tmdb", "TMDB"),
    TVMAZE("tvmaze", "TVmaze"),
    ITUNES("itunes", "Apple TV Store");

    companion object {
        fun fromRaw(raw: String?): CatalogSource? = entries.firstOrNull { it.raw == raw }
    }
}

/** A stable pointer to a title in one of the catalogs, e.g. `tmdb-movie-603`. */
@Immutable
data class TitleRef(val source: CatalogSource, val kind: MediaKind, val id: String) {
    val key: String get() = "${source.raw}-${kind.raw}-$id"

    val deepLink: String get() = "couchpotato://title/$key"

    val webUrl: String
        get() = when (source) {
            CatalogSource.TMDB -> "https://www.themoviedb.org/${kind.raw}/$id"
            CatalogSource.TVMAZE -> "https://www.tvmaze.com/shows/$id"
            CatalogSource.ITUNES -> "https://tv.apple.com/movie/id$id"
        }

    companion object {
        fun parse(key: String?): TitleRef? {
            if (key.isNullOrBlank()) return null
            val parts = key.split("-", limit = 3)
            if (parts.size != 3) return null
            val source = CatalogSource.fromRaw(parts[0]) ?: return null
            val kind = MediaKind.fromRaw(parts[1]) ?: return null
            return TitleRef(source, kind, parts[2])
        }
    }
}

@Immutable
data class CatalogTitle(
    val ref: TitleRef,
    val name: String,
    val overview: String = "",
    val posterUrl: String? = null,
    val backdropUrl: String? = null,
    val year: Int? = null,
    val releaseDate: LocalDate? = null,
    val genres: List<String> = emptyList(),
    /** 0–10 community score. */
    val score: Double? = null,
    val runtime: Int? = null,
    /** Providers known up front (e.g. the streamer a TVmaze show airs on). */
    val providers: List<Provider> = emptyList(),
    val network: String? = null,
    val status: String? = null,
    val certification: String? = null,
    val homepage: String? = null,
    val imdbId: String? = null,
    val popularity: Double = 0.0,
) {
    val id: String get() = ref.key
    val kind: MediaKind get() = ref.kind

    /** `2024 · Drama · 1h 52m` */
    val subtitle: String
        get() = buildList {
            year?.let { add(it.toString()) }
            add(kind.label)
            runtime?.takeIf { it > 0 }?.let { add(it.runtimeLabel) }
        }.joinToString(" · ")

    /** `2024 · Drama · 1h 52m · ★ 7.8` */
    val metadataLine: String
        get() = buildList {
            year?.let { add(it.toString()) }
            genres.firstOrNull()?.let { add(it) }
            runtime?.takeIf { it > 0 }?.let { add(it.runtimeLabel) }
            score?.let { add("★ " + "%.1f".format(it)) }
        }.joinToString(" · ")
}

@Immutable
data class CastMember(val id: String, val name: String, val character: String, val photoUrl: String?)

@Immutable
data class EpisodeInfo(
    val id: String,
    val showRef: TitleRef,
    val showName: String,
    val season: Int,
    val number: Int,
    val name: String,
    val airDate: LocalDate? = null,
    val airTimeEpochMillis: Long? = null,
    val runtime: Int? = null,
    val overview: String = "",
    val stillUrl: String? = null,
    val showPosterUrl: String? = null,
) {
    val code: String get() = "S%02dE%02d".format(season, number)
}

@Immutable
data class SeasonInfo(
    val number: Int,
    val name: String,
    val episodeCount: Int?,
    val posterUrl: String?,
    val airYear: Int?,
)

enum class OfferKind(val raw: String, val label: String) {
    STREAM("stream", "Stream"),
    FREE("free", "Free"),
    ADS("ads", "Free with ads"),
    RENT("rent", "Rent"),
    BUY("buy", "Buy");
}

@Immutable
data class ProviderOffer(
    val provider: Provider,
    val kind: OfferKind,
    val logoUrl: String? = null,
    val price: String? = null,
    val link: String? = null,
) {
    val id: String get() = "${provider.id}-${kind.raw}"
}

@Immutable
data class Availability(
    val offers: List<ProviderOffer> = emptyList(),
    /** Attribution/landing page for the availability data (TMDB → JustWatch). */
    val link: String? = null,
    val region: String = "US",
) {
    fun offers(kind: OfferKind): List<ProviderOffer> = offers.filter { it.kind == kind }
    val isEmpty: Boolean get() = offers.isEmpty()
    val providers: List<Provider> get() = offers.map { it.provider }.distinctBy { it.id }
}

@Immutable
data class TitleDetail(
    val title: CatalogTitle,
    val tagline: String? = null,
    val cast: List<CastMember> = emptyList(),
    val seasons: List<SeasonInfo> = emptyList(),
    val availability: Availability = Availability(),
    val similar: List<CatalogTitle> = emptyList(),
    val trailerUrl: String? = null,
    val nextEpisode: EpisodeInfo? = null,
    val creators: List<String> = emptyList(),
)

val Int.runtimeLabel: String
    get() {
        val h = this / 60
        val m = this % 60
        if (h == 0) return "${m}m"
        return if (m == 0) "${h}h" else "${h}h ${m}m"
    }

/** Strips the light HTML TVmaze uses in summaries. */
fun String.strippingHtml(): String =
    replace(Regex("<[^>]+>"), "")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .trim()

fun <T> interleave(a: List<T>, b: List<T>): List<T> {
    val out = ArrayList<T>(a.size + b.size)
    for (i in 0 until maxOf(a.size, b.size)) {
        if (i < a.size) out += a[i]
        if (i < b.size) out += b[i]
    }
    return out
}
