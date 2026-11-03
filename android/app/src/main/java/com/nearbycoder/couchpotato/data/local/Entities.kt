package com.nearbycoder.couchpotato.data.local

import androidx.compose.runtime.Immutable
import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.TitleRef
import com.nearbycoder.couchpotato.domain.WatchStatus
import java.util.UUID

/** A title on your watchlist. */
@Immutable
@Entity(tableName = "saved_titles")
data class SavedTitle(
    @PrimaryKey val key: String,
    val source: String,
    val kind: String,
    @ColumnInfo(name = "external_id") val externalId: String,
    val name: String,
    val overview: String = "",
    @ColumnInfo(name = "poster_url") val posterUrl: String? = null,
    @ColumnInfo(name = "backdrop_url") val backdropUrl: String? = null,
    val year: Int? = null,
    @ColumnInfo(name = "genres_csv") val genresCsv: String = "",
    @ColumnInfo(name = "provider_ids_csv") val providerIdsCsv: String = "",
    val runtime: Int? = null,
    val status: String = WatchStatus.QUEUED.raw,
    /** 0–5 stars. */
    val rating: Int = 0,
    val notes: String = "",
    @ColumnInfo(name = "added_at") val addedAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "updated_at") val updatedAt: Long = System.currentTimeMillis(),
    @ColumnInfo(name = "finished_at") val finishedAt: Long? = null,
    @ColumnInfo(name = "last_season") val lastSeason: Int = 0,
    @ColumnInfo(name = "last_episode") val lastEpisode: Int = 0,
    @ColumnInfo(name = "is_following") val isFollowing: Boolean = false,
    @ColumnInfo(name = "imdb_id") val imdbId: String? = null,
) {
    val ref: TitleRef
        get() = TitleRef(
            CatalogSource.fromRaw(source) ?: CatalogSource.TMDB,
            MediaKind.fromRaw(kind) ?: MediaKind.MOVIE,
            externalId,
        )

    val mediaKind: MediaKind get() = MediaKind.fromRaw(kind) ?: MediaKind.MOVIE
    val watchStatus: WatchStatus get() = WatchStatus.fromRaw(status)
    val genres: List<String> get() = genresCsv.split(",").filter { it.isNotBlank() }
    val providerIds: List<String> get() = providerIdsCsv.split(",").filter { it.isNotBlank() }
    val providers: List<Provider> get() = providerIds.mapNotNull { Provider.withId(it) }

    val progressLabel: String?
        get() = if (mediaKind == MediaKind.TV && lastSeason > 0) {
            "Seen through S%02dE%02d".format(lastSeason, lastEpisode)
        } else null

    /** A lightweight catalog value so saved titles can reuse catalog views. */
    val asCatalogTitle: CatalogTitle
        get() = CatalogTitle(
            ref = ref, name = name, overview = overview, posterUrl = posterUrl, backdropUrl = backdropUrl,
            year = year, genres = genres, runtime = runtime, providers = providers, imdbId = imdbId,
        )

    fun updated(from: CatalogTitle): SavedTitle = copy(
        name = from.name,
        overview = from.overview.ifEmpty { overview },
        posterUrl = from.posterUrl ?: posterUrl,
        backdropUrl = from.backdropUrl ?: backdropUrl,
        year = from.year ?: year,
        genresCsv = if (from.genres.isNotEmpty()) from.genres.joinToString(",") else genresCsv,
        providerIdsCsv = if (from.providers.isNotEmpty()) from.providers.joinToString(",") { it.id } else providerIdsCsv,
        runtime = from.runtime ?: runtime,
        imdbId = from.imdbId ?: imdbId,
    )

    fun withStatus(newStatus: WatchStatus, now: Long = System.currentTimeMillis()): SavedTitle = copy(
        status = newStatus.raw,
        updatedAt = now,
        finishedAt = if (newStatus == WatchStatus.WATCHED) (finishedAt ?: now) else finishedAt,
    )

    companion object {
        fun from(title: CatalogTitle, status: WatchStatus = WatchStatus.QUEUED): SavedTitle {
            val now = System.currentTimeMillis()
            return SavedTitle(
                key = title.ref.key,
                source = title.ref.source.raw,
                kind = title.ref.kind.raw,
                externalId = title.ref.id,
                name = title.name,
                overview = title.overview,
                posterUrl = title.posterUrl,
                backdropUrl = title.backdropUrl,
                year = title.year,
                genresCsv = title.genres.joinToString(","),
                providerIdsCsv = title.providers.joinToString(",") { it.id },
                runtime = title.runtime,
                status = status.raw,
                addedAt = now,
                updatedAt = now,
                finishedAt = if (status == WatchStatus.WATCHED) now else null,
                isFollowing = title.kind == MediaKind.TV && status != WatchStatus.DROPPED,
                imdbId = title.imdbId,
            )
        }
    }
}

/** A planned viewing session in the Planner. */
@Immutable
@Entity(tableName = "couch_nights")
data class CouchNight(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    @ColumnInfo(name = "title_key") val titleKey: String,
    @ColumnInfo(name = "title_name") val titleName: String,
    @ColumnInfo(name = "poster_url") val posterUrl: String? = null,
    @ColumnInfo(name = "starts_at") val startsAt: Long,
    @ColumnInfo(name = "duration_minutes") val durationMinutes: Int = 120,
    val note: String = "",
    val remind: Boolean = true,
    @ColumnInfo(name = "is_done") val isDone: Boolean = false,
    @ColumnInfo(name = "calendar_event_id") val calendarEventId: String? = null,
    @ColumnInfo(name = "created_at") val createdAt: Long = System.currentTimeMillis(),
) {
    val endsAt: Long get() = startsAt + durationMinutes * 60_000L
    val ref: TitleRef? get() = TitleRef.parse(titleKey)
}
