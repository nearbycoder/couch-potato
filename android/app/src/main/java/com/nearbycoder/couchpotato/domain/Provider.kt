package com.nearbycoder.couchpotato.domain

import androidx.compose.runtime.Immutable
import java.net.URLEncoder

/**
 * A streaming service or store. The well-known ones are listed in [Provider.all];
 * anything else TMDB reports becomes an ad-hoc provider.
 */
@Immutable
class Provider(
    val id: String,
    val name: String,
    val shortName: String,
    /** Brand color as RRGGBB. Used only for small tiles, dots and monograms. */
    val colorHex: String,
    val tmdbIds: List<Int> = emptyList(),
    /** Lowercased name fragments that identify this provider in other catalogs. */
    val aliases: List<String> = emptyList(),
    /** Search URL template; `{q}` is replaced by the title. */
    val searchTemplate: String? = null,
) {
    override fun equals(other: Any?): Boolean = other is Provider && other.id == id
    override fun hashCode(): Int = id.hashCode()
    override fun toString(): String = "Provider($id)"

    /** Two-letter monogram for tiles without a logo image. */
    val monogram: String
        get() {
            val words = name.split(" ", "+").filter { it.isNotBlank() }
            return when {
                words.size >= 2 -> (words[0].take(1) + words[1].take(1)).uppercase()
                name.length >= 2 -> name.take(2).replaceFirstChar { it.uppercase() }
                else -> name.uppercase()
            }
        }

    fun searchUrl(title: String): String? {
        val template = searchTemplate ?: return null
        val q = URLEncoder.encode(title, "UTF-8").replace("+", "%20")
        return template.replace("{q}", q)
    }

    companion object {
        val netflix = Provider(
            id = "netflix", name = "Netflix", shortName = "Netflix", colorHex = "E50914",
            tmdbIds = listOf(8, 1796), aliases = listOf("netflix"),
            searchTemplate = "https://www.netflix.com/search?q={q}",
        )
        val hulu = Provider(
            id = "hulu", name = "Hulu", shortName = "Hulu", colorHex = "1CE783",
            tmdbIds = listOf(15), aliases = listOf("hulu", "fx", "fxx", "abc", "freeform"),
            searchTemplate = "https://www.hulu.com/search?q={q}",
        )
        val disney = Provider(
            id = "disney", name = "Disney+", shortName = "Disney+", colorHex = "113CCF",
            tmdbIds = listOf(337), aliases = listOf("disney", "national geographic", "nat geo"),
            searchTemplate = "https://www.disneyplus.com/search?q={q}",
        )
        val hbo = Provider(
            id = "hbo", name = "HBO Max", shortName = "HBO Max", colorHex = "6A2FD8",
            tmdbIds = listOf(1899, 384, 118),
            aliases = listOf("hbo", "max", "cinemax", "tnt", "tbs", "adult swim", "cartoon network", "discovery", "hgtv", "food network", "tlc"),
            searchTemplate = "https://play.hbomax.com/search?q={q}",
        )
        val apple = Provider(
            id = "apple", name = "Apple TV", shortName = "Apple TV", colorHex = "A2AAAD",
            tmdbIds = listOf(350), aliases = listOf("apple tv+", "apple tv"),
            searchTemplate = "https://tv.apple.com/search?term={q}",
        )
        val prime = Provider(
            id = "prime", name = "Prime Video", shortName = "Prime", colorHex = "00A8E1",
            tmdbIds = listOf(9, 119, 10), aliases = listOf("prime video", "amazon", "freevee", "mgm+"),
            searchTemplate = "https://www.amazon.com/s?k={q}&i=instant-video",
        )
        val peacock = Provider(
            id = "peacock", name = "Peacock", shortName = "Peacock", colorHex = "F2A900",
            tmdbIds = listOf(386, 387), aliases = listOf("peacock", "nbc", "bravo", "usa network", "syfy", "e!"),
            searchTemplate = "https://www.peacocktv.com/search?q={q}",
        )
        val paramount = Provider(
            id = "paramount", name = "Paramount+", shortName = "Paramount+", colorHex = "0064FF",
            tmdbIds = listOf(531, 2303, 2616, 582),
            aliases = listOf("paramount", "cbs", "showtime", "mtv", "comedy central", "nickelodeon", "bet"),
            searchTemplate = "https://www.paramountplus.com/search/?q={q}",
        )
        val starz = Provider(
            id = "starz", name = "Starz", shortName = "Starz", colorHex = "C9A227",
            tmdbIds = listOf(43), aliases = listOf("starz"),
            searchTemplate = "https://www.starz.com/us/en/search?q={q}",
        )
        val amc = Provider(
            id = "amc", name = "AMC+", shortName = "AMC+", colorHex = "C8102E",
            tmdbIds = listOf(526, 80), aliases = listOf("amc", "shudder", "sundance", "acorn", "ifc"),
            searchTemplate = "https://www.amcplus.com/search?q={q}",
        )
        val crunchyroll = Provider(
            id = "crunchyroll", name = "Crunchyroll", shortName = "Crunchyroll", colorHex = "F47521",
            tmdbIds = listOf(283), aliases = listOf("crunchyroll"),
            searchTemplate = "https://www.crunchyroll.com/search?q={q}",
        )
        val tubi = Provider(
            id = "tubi", name = "Tubi", shortName = "Tubi", colorHex = "7408FF",
            tmdbIds = listOf(73), aliases = listOf("tubi"),
            searchTemplate = "https://tubitv.com/search/{q}",
        )
        val youtube = Provider(
            id = "youtube", name = "YouTube", shortName = "YouTube", colorHex = "FF0033",
            tmdbIds = listOf(192, 188), aliases = listOf("youtube"),
            searchTemplate = "https://www.youtube.com/results?search_query={q}",
        )
        val appleStore = Provider(
            id = "apple-store", name = "Apple TV Store", shortName = "Apple Store", colorHex = "5E5CE6",
            tmdbIds = listOf(2), aliases = listOf("apple tv store", "itunes"),
            searchTemplate = "https://tv.apple.com/search?term={q}",
        )

        /** The services people can mark as "mine", in display order. */
        val streamers: List<Provider> = listOf(
            netflix, hulu, disney, hbo, apple, prime, peacock, paramount, starz, amc, crunchyroll, tubi, youtube,
        )
        val all: List<Provider> = streamers + appleStore

        /** Default services for the home feed when the user hasn't picked any. */
        val defaults: List<Provider> = listOf(netflix, hulu, disney, hbo, apple, prime)

        fun withId(id: String): Provider? = all.firstOrNull { it.id == id }

        fun withTmdbId(tmdbId: Int): Provider? = all.firstOrNull { tmdbId in it.tmdbIds }

        /** Matches a free-form network/channel name, e.g. "Apple TV" or "FX", to a provider. */
        fun matching(name: String): Provider? {
            val lower = name.lowercase().trim()
            all.firstOrNull { it.name.lowercase() == lower || lower in it.aliases }?.let { return it }
            return streamers.firstOrNull { p -> p.aliases.any { alias -> alias.length > 3 && lower.contains(alias) } }
        }

        fun adHoc(tmdbId: Int, name: String): Provider =
            Provider(id = "tmdb-$tmdbId", name = name, shortName = name, colorHex = "8A6A52", tmdbIds = listOf(tmdbId))
    }
}
