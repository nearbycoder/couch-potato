package com.nearbycoder.couchpotato.domain.ai

import androidx.compose.runtime.Immutable
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.Genre
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.TitleFilter
import com.nearbycoder.couchpotato.domain.TitleSort
import com.nearbycoder.couchpotato.domain.YearRange
import com.nearbycoder.couchpotato.domain.runtimeLabel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject

/**
 * A natural-language request ("a cozy mystery series") interpreted into the app's own
 * browse vocabulary. Produced by the on-device model as JSON and parsed by [AskQuery.parse].
 * Shared semantics with the Apple app.
 */
@Immutable
data class AskQuery(
    /** null means movies and series. */
    val kind: MediaKind? = null,
    val filter: TitleFilter = TitleFilter(),
    val mood: Mood? = null,
    /** Longest runtime wanted, in minutes; 0 means no limit. */
    val maxMinutes: Int = 0,
    val services: List<Provider> = emptyList(),
    val keywords: String = "",
    val summary: String = "",
) {
    /** Keeps titles whose runtime is unknown or fits [maxMinutes]. */
    fun fitsRuntime(title: CatalogTitle): Boolean = maxMinutes <= 0 || title.runtime == null || title.runtime <= maxMinutes

    fun fitsKind(title: CatalogTitle): Boolean = kind == null || title.kind == kind

    /**
     * Drops fields the model filled in without the request asking for them (small models
     * over-fill). Deterministic and identical to the Apple app's `validated(against:)`:
     * - services only when the request names the service (or an alias);
     * - maxMinutes only when the request has a digit or a time word;
     * - minRating only when the request has a quality word;
     * - keywords dropped when genre, mood, years or services are set (a descriptive request).
     * Terms match whole words; terms with a space or "+" match anywhere in the text.
     */
    fun constrained(request: String): AskQuery {
        val text = request.lowercase()
        val words = text.split(Regex("[^\\p{L}\\p{N}+]+")).filter { it.isNotEmpty() }.toSet()
        fun mentions(terms: List<String>) = terms.any { term ->
            if (' ' in term || '+' in term) text.contains(term) else term in words
        }
        val keptServices = services.filter { mentions(serviceTerms[it.id].orEmpty()) }
        val keepMinutes = text.any { it.isDigit() } || mentions(timeWords)
        val keepRating = mentions(qualityWords)
        val descriptive = filter.genre != null || mood != null || filter.years != YearRange.ANY || keptServices.isNotEmpty()
        return copy(
            services = keptServices,
            maxMinutes = if (keepMinutes) maxMinutes else 0,
            filter = if (keepRating) filter else filter.copy(minRating = null),
            keywords = if (descriptive) "" else keywords,
        )
    }

    /**
     * This query, then progressively looser versions to try when it finds nothing:
     * without maxMinutes, then also without minRating, years, and services.
     * Steps that change nothing are skipped.
     */
    fun relaxations(): List<AskQuery> {
        val steps = ArrayList<AskQuery>()
        var q = this
        steps += q
        q = q.copy(maxMinutes = 0); if (q != steps.last()) steps += q
        q = q.copy(filter = q.filter.copy(minRating = null)); if (q != steps.last()) steps += q
        q = q.copy(filter = q.filter.copy(years = YearRange.ANY)); if (q != steps.last()) steps += q
        q = q.copy(services = emptyList()); if (q != steps.last()) steps += q
        return steps
    }

    /** The interpreted filters as short read-only labels, in display order. */
    val chips: List<String>
        get() = buildList {
            kind?.let { add(it.pluralLabel) }
            filter.genre?.let { add(it.label) }
            mood?.let { add(it.title) }
            if (filter.years != YearRange.ANY) add(filter.years.label)
            filter.minRating?.let { add("★ ${it.toInt()}+") }
            if (maxMinutes > 0) add("Under ${maxMinutes.runtimeLabel}")
            services.forEach { add(it.name) }
            if (filter.sort != TitleSort.POPULAR) add(filter.sort.label)
            if (keywords.isNotBlank()) add("“${keywords.trim()}”")
        }

    companion object {
        /** Results are capped at this many titles. */
        const val MAX_RESULTS = 60

        /** Terms that name each service in a request (same lists as the Apple app). */
        private val serviceTerms: Map<String, List<String>> = mapOf(
            "netflix" to listOf("netflix"),
            "hulu" to listOf("hulu"),
            "disney" to listOf("disney", "disney+", "disney plus"),
            "hbo" to listOf("hbo", "max"),
            "apple" to listOf("apple"),
            "prime" to listOf("prime", "amazon"),
            "peacock" to listOf("peacock"),
            "paramount" to listOf("paramount", "paramount+"),
            "starz" to listOf("starz"),
            "amc" to listOf("amc", "amc+"),
            "crunchyroll" to listOf("crunchyroll"),
            "tubi" to listOf("tubi"),
            "youtube" to listOf("youtube"),
        )

        /** Words that make a runtime limit believable ("under an hour", "something short"). */
        private val timeWords = listOf("minute", "minutes", "min", "mins", "hour", "hours", "hr", "short", "quick")

        /** Words that make a rating floor believable ("highly rated", "award-winning"). */
        private val qualityWords = listOf("good", "great", "best", "top", "highly", "acclaimed", "rated", "rating", "award", "awards")

        private val json = Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

        /**
         * Parses the model's reply. Tolerates ``` fences, prose around the object, unknown
         * keys and unknown values (each falls back to its default). Returns null when no JSON
         * object can be found, so the caller can fall back to a plain text search.
         */
        fun parse(raw: String): AskQuery? {
            val obj = extractObject(raw) ?: return null
            return fromJson(obj)
        }

        /** Parses the model's reply and keeps only what [request] actually asked for. */
        fun parse(raw: String, request: String): AskQuery? = parse(raw)?.constrained(request)

        /** A plain text search of the user's own words, used when the model can't help. */
        fun fallback(request: String): AskQuery {
            val text = request.trim()
            return AskQuery(keywords = text, summary = "Titles matching “$text”")
        }

        internal fun extractObject(raw: String): JsonObject? {
            val text = stripFences(raw)
            val start = text.indexOf('{')
            val end = text.lastIndexOf('}')
            if (start < 0 || end <= start) return null
            return runCatching { json.parseToJsonElement(text.substring(start, end + 1)).jsonObject }.getOrNull()
        }

        internal fun stripFences(raw: String): String =
            raw.trim()
                .replace(Regex("^```[a-zA-Z]*\\s*"), "")
                .replace(Regex("\\s*```\\s*$"), "")
                .trim()

        fun fromJson(obj: JsonObject): AskQuery {
            val minRating = obj.number("minRating")?.let(::ratingFloor)
            val filter = TitleFilter(
                sort = enumByName(obj.string("sort"), TitleSort.entries) ?: TitleSort.POPULAR,
                years = enumByName(obj.string("years"), YearRange.entries) ?: YearRange.ANY,
                genre = genre(obj.string("genre")),
                minRating = minRating,
            )
            return AskQuery(
                kind = kind(obj.string("kind")),
                filter = filter,
                mood = mood(obj.string("mood")),
                maxMinutes = obj.number("maxMinutes")?.toInt()?.coerceIn(0, 24 * 60) ?: 0,
                services = services(obj["services"]),
                keywords = obj.string("keywords")?.trim().orEmpty(),
                summary = obj.string("summary")?.trim()?.trimEnd('.').orEmpty(),
            )
        }

        /** Lowercase letters and digits only, so `thisYear`, `THIS_YEAR` and `this year` all match. */
        private fun norm(value: String): String = value.lowercase().filter { it.isLetterOrDigit() }

        private fun <E : Enum<E>> enumByName(value: String?, entries: List<E>): E? {
            val key = value?.let(::norm)?.takeIf { it.isNotEmpty() } ?: return null
            return entries.firstOrNull { norm(it.name) == key }
        }

        private fun kind(value: String?): MediaKind? = when (value?.let(::norm)) {
            "movie", "movies", "film", "films" -> MediaKind.MOVIE
            "series", "tv", "show", "shows", "tvshow", "tvseries" -> MediaKind.TV
            else -> null
        }

        private fun genre(value: String?): Genre? {
            enumByName(value, Genre.entries)?.let { return it }
            val key = value?.let(::norm) ?: return null
            return when (key) {
                "sciencefiction", "fantasy", "scififantasy" -> Genre.SCIFI
                "thriller", "mysterythriller" -> Genre.MYSTERY
                "adventure", "actionadventure" -> Genre.ACTION
                "kids", "familykids" -> Genre.FAMILY
                "anime" -> Genre.ANIMATION
                else -> null
            }
        }

        private fun mood(value: String?): Mood? {
            enumByName(value, Mood.entries)?.let { return it }
            return Mood.withId(value?.let(::norm))
        }

        /** Snaps a score to the 6 / 7 / 8 floors the browse filters offer. */
        private fun ratingFloor(value: Double): Double? {
            val score = if (value > 10) value / 10 else value
            return when {
                score >= 8 -> 8.0
                score >= 7 -> 7.0
                score >= 6 -> 6.0
                else -> null
            }
        }

        private fun services(element: JsonElement?): List<Provider> {
            val names = when (element) {
                is JsonArray -> element.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                is JsonPrimitive -> element.contentOrNull?.split(',').orEmpty()
                else -> emptyList()
            }
            return names.mapNotNull { name ->
                val key = norm(name)
                if (key.isEmpty()) return@mapNotNull null
                Provider.streamers.firstOrNull { it.id == key || norm(it.name) == key }
                    ?: Provider.matching(name.trim())?.takeIf { it in Provider.streamers }
            }.distinct()
        }

        private fun JsonObject.string(key: String): String? = when (val e = this[key]) {
            null, is JsonNull -> null
            is JsonPrimitive -> e.contentOrNull
            else -> null
        }

        private fun JsonObject.number(key: String): Double? = when (val e = this[key]) {
            is JsonPrimitive -> e.doubleOrNull ?: e.contentOrNull?.trim()?.toDoubleOrNull()
            else -> null
        }
    }
}

/**
 * Round-robin merge of several ranked lists: the first of each, then the second of each,
 * and so on, skipping titles already taken.
 */
fun mergeInterleaved(lists: List<List<CatalogTitle>>): List<CatalogTitle> {
    val seen = HashSet<String>()
    val out = ArrayList<CatalogTitle>()
    val longest = lists.maxOfOrNull { it.size } ?: 0
    for (i in 0 until longest) {
        for (list in lists) {
            val title = list.getOrNull(i) ?: continue
            if (seen.add(title.id)) out += title
        }
    }
    return out
}
