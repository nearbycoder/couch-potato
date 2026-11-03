package com.nearbycoder.couchpotato.domain

import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.data.remote.Http
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * Portable JSON for the watchlist and plans. This is the bridge between the
 * Android and Apple apps: ISO-8601 timestamps, stable title keys, plain fields.
 */
object Backup {
    const val FORMAT = "couchpotato.backup"
    const val VERSION = 1

    @Serializable
    data class File(
        val format: String = FORMAT,
        val version: Int = VERSION,
        val exportedAt: String,
        val titles: List<Title>,
        val nights: List<Night>,
    )

    @Serializable
    data class Title(
        val key: String,
        val source: String,
        val kind: String,
        val externalID: String,
        val name: String,
        val overview: String = "",
        val posterURL: String? = null,
        val backdropURL: String? = null,
        val year: Int? = null,
        val genres: List<String> = emptyList(),
        val providerIDs: List<String> = emptyList(),
        val runtime: Int? = null,
        val status: String,
        val rating: Int = 0,
        val notes: String = "",
        val addedAt: String,
        val updatedAt: String,
        val finishedAt: String? = null,
        val lastSeason: Int = 0,
        val lastEpisode: Int = 0,
        val isFollowing: Boolean = false,
        val imdbID: String? = null,
    )

    @Serializable
    data class Night(
        val id: String,
        val titleKey: String,
        val titleName: String,
        val posterURL: String? = null,
        val startsAt: String,
        val durationMinutes: Int,
        val note: String = "",
        val remind: Boolean = true,
        val isDone: Boolean = false,
        val createdAt: String,
    )

    private val json = Json { prettyPrint = true; encodeDefaults = true; explicitNulls = false }

    private fun iso(millis: Long): String = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(millis))

    fun export(titles: List<SavedTitle>, nights: List<CouchNight>): String {
        val file = File(
            exportedAt = iso(System.currentTimeMillis()),
            titles = titles.map { t ->
                Title(
                    key = t.key, source = t.source, kind = t.kind, externalID = t.externalId, name = t.name,
                    overview = t.overview, posterURL = t.posterUrl, backdropURL = t.backdropUrl, year = t.year,
                    genres = t.genres, providerIDs = t.providerIds, runtime = t.runtime, status = t.status,
                    rating = t.rating, notes = t.notes, addedAt = iso(t.addedAt), updatedAt = iso(t.updatedAt),
                    finishedAt = t.finishedAt?.let(::iso), lastSeason = t.lastSeason, lastEpisode = t.lastEpisode,
                    isFollowing = t.isFollowing, imdbID = t.imdbId,
                )
            },
            nights = nights.map { n ->
                Night(
                    id = n.id, titleKey = n.titleKey, titleName = n.titleName, posterURL = n.posterUrl,
                    startsAt = iso(n.startsAt), durationMinutes = n.durationMinutes, note = n.note, remind = n.remind,
                    isDone = n.isDone, createdAt = iso(n.createdAt),
                )
            },
        )
        return json.encodeToString(file)
    }

    data class Imported(val titles: List<SavedTitle>, val nights: List<CouchNight>)

    /** Lenient import: tolerates missing fields, epoch or ISO timestamps, and `potatoes` as a rating alias. */
    fun import(text: String): Imported {
        val root = Http.json.parseToJsonElement(text).jsonObject
        val titles = root["titles"]?.jsonArray?.mapNotNull { el -> parseTitle(el.jsonObject) } ?: emptyList()
        val nights = root["nights"]?.jsonArray?.mapNotNull { el -> parseNight(el.jsonObject) } ?: emptyList()
        return Imported(titles, nights)
    }

    private fun JsonObject.str(vararg names: String): String? =
        names.firstNotNullOfOrNull { (this[it] as? JsonPrimitive)?.contentOrNull }

    private fun JsonObject.int(vararg names: String): Int? =
        names.firstNotNullOfOrNull { (this[it] as? JsonPrimitive)?.let { p -> p.intOrNull ?: p.doubleOrNull?.toInt() } }

    private fun JsonObject.bool(vararg names: String): Boolean? =
        names.firstNotNullOfOrNull { (this[it] as? JsonPrimitive)?.booleanOrNull }

    private fun JsonObject.millis(vararg names: String): Long? =
        names.firstNotNullOfOrNull { name ->
            val p = this[name] as? JsonPrimitive ?: return@firstNotNullOfOrNull null
            p.longOrNull?.let { if (it < 100_000_000_000L) it * 1000 else it }
                ?: p.doubleOrNull?.let { if (it < 100_000_000_000.0) (it * 1000).toLong() else it.toLong() }
                ?: p.contentOrNull?.let { s -> runCatching { Instant.parse(s).toEpochMilli() }.getOrNull() }
        }

    private fun JsonObject.strings(name: String): List<String> =
        this[name]?.let { el ->
            runCatching { el.jsonArray.map { it.jsonPrimitive.content } }.getOrNull()
                ?: (el as? JsonPrimitive)?.contentOrNull?.split(",")?.filter { it.isNotBlank() }
        } ?: emptyList()

    private fun parseTitle(o: JsonObject): SavedTitle? {
        val key = o.str("key") ?: return null
        val ref = TitleRef.parse(key) ?: return null
        val now = System.currentTimeMillis()
        return SavedTitle(
            key = key,
            source = o.str("source", "sourceRaw") ?: ref.source.raw,
            kind = o.str("kind", "kindRaw") ?: ref.kind.raw,
            externalId = o.str("externalID", "externalId") ?: ref.id,
            name = o.str("name") ?: "Untitled",
            overview = o.str("overview") ?: "",
            posterUrl = o.str("posterURL", "posterUrl", "posterURLString"),
            backdropUrl = o.str("backdropURL", "backdropUrl", "backdropURLString"),
            year = o.int("year"),
            genresCsv = o.strings("genres").ifEmpty { o.strings("genresCSV") }.joinToString(","),
            providerIdsCsv = o.strings("providerIDs").ifEmpty { o.strings("providerIDsCSV") }.joinToString(","),
            runtime = o.int("runtime"),
            status = WatchStatus.fromRaw(o.str("status", "statusRaw")).raw,
            rating = (o.int("rating", "potatoes") ?: 0).coerceIn(0, 5),
            notes = o.str("notes") ?: "",
            addedAt = o.millis("addedAt") ?: now,
            updatedAt = o.millis("updatedAt") ?: now,
            finishedAt = o.millis("finishedAt"),
            lastSeason = o.int("lastSeason") ?: 0,
            lastEpisode = o.int("lastEpisode") ?: 0,
            isFollowing = o.bool("isFollowing") ?: false,
            imdbId = o.str("imdbID", "imdbId"),
        )
    }

    private fun parseNight(o: JsonObject): CouchNight? {
        val titleKey = o.str("titleKey") ?: return null
        val startsAt = o.millis("startsAt") ?: return null
        return CouchNight(
            id = o.str("id") ?: UUID.randomUUID().toString(),
            titleKey = titleKey,
            titleName = o.str("titleName") ?: "Couch night",
            posterUrl = o.str("posterURL", "posterUrl", "posterURLString"),
            startsAt = startsAt,
            durationMinutes = o.int("durationMinutes") ?: 120,
            note = o.str("note") ?: "",
            remind = o.bool("remind") ?: true,
            isDone = o.bool("isDone") ?: false,
            createdAt = o.millis("createdAt") ?: System.currentTimeMillis(),
        )
    }
}
