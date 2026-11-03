package com.nearbycoder.couchpotato.data.remote

import com.nearbycoder.couchpotato.domain.Availability
import com.nearbycoder.couchpotato.domain.CastMember
import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.EpisodeInfo
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.OfferKind
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.ProviderOffer
import com.nearbycoder.couchpotato.domain.SeasonInfo
import com.nearbycoder.couchpotato.domain.TitleDetail
import com.nearbycoder.couchpotato.domain.TitleRef
import com.nearbycoder.couchpotato.domain.interleave
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate

/**
 * The Movie Database: full movie + TV catalog, box art, and JustWatch-powered
 * "where to watch" data for every major service. Requires a (free) API key.
 */
class TmdbClient(private val key: String, val region: String) {

    private suspend inline fun <reified T> get(path: String, query: Map<String, String?> = emptyMap()): T {
        if (key.isEmpty()) throw MissingKeyException()
        val q = query.toMutableMap()
        val headers = mutableMapOf<String, String>()
        // v4 read tokens are JWTs; v3 keys go in the query string.
        if (key.startsWith("eyJ")) headers["Authorization"] = "Bearer $key" else q["api_key"] = key
        q.putIfAbsent("language", "en-US")
        return Http.get(Http.url(BASE, path, q), headers)
    }

    // Lists

    suspend fun validate() {
        get<TmdbConfiguration>("/configuration")
    }

    suspend fun trending(): List<CatalogTitle> =
        get<TmdbPage>("/trending/all/week").results.mapNotNull { it.catalogTitle() }

    suspend fun popular(kind: MediaKind): List<CatalogTitle> =
        get<TmdbPage>("/${kind.raw}/popular", mapOf("region" to region)).results.mapNotNull { it.catalogTitle(kind) }

    suspend fun discover(
        kind: MediaKind,
        providers: List<Provider> = emptyList(),
        genres: List<Int> = emptyList(),
        sort: String = "popularity.desc",
        extra: Map<String, String?> = emptyMap(),
        page: Int = 1,
    ): List<CatalogTitle> {
        val query = mutableMapOf<String, String?>(
            "sort_by" to sort,
            "watch_region" to region,
            "include_adult" to "false",
            "page" to page.toString(),
        )
        if (providers.isNotEmpty()) {
            query["with_watch_providers"] = providers.flatMap { it.tmdbIds }.joinToString("|")
            query["with_watch_monetization_types"] = "flatrate|free|ads"
        }
        if (genres.isNotEmpty()) query["with_genres"] = genres.joinToString("|")
        query.putAll(extra)
        return get<TmdbPage>("/discover/${kind.raw}", query).results.mapNotNull { it.catalogTitle(kind) }
    }

    suspend fun freshOnStreaming(services: List<Provider>): List<CatalogTitle> = coroutineScope {
        val today = DateParsing.dayString(LocalDate.now())
        val monthAgo = DateParsing.dayString(LocalDate.now().minusDays(60))
        val providers = services.ifEmpty { Provider.streamers.take(8) }
        val movies = async {
            discover(MediaKind.MOVIE, providers, extra = mapOf("primary_release_date.gte" to monthAgo, "primary_release_date.lte" to today))
        }
        val shows = async {
            discover(MediaKind.TV, providers, extra = mapOf("air_date.gte" to monthAgo, "air_date.lte" to today))
        }
        interleave(movies.await(), shows.await())
    }

    suspend fun search(text: String): List<CatalogTitle> =
        get<TmdbPage>("/search/multi", mapOf("query" to text, "include_adult" to "false")).results.mapNotNull { it.catalogTitle() }

    suspend fun searchMovie(name: String, year: Int?): CatalogTitle? =
        get<TmdbPage>("/search/movie", mapOf("query" to name, "year" to year?.toString()))
            .results.firstOrNull()?.catalogTitle(MediaKind.MOVIE)

    suspend fun find(imdbId: String): CatalogTitle? {
        val result = get<TmdbFindResult>("/find/$imdbId", mapOf("external_source" to "imdb_id"))
        return result.tvResults.firstOrNull()?.catalogTitle(MediaKind.TV)
            ?: result.movieResults.firstOrNull()?.catalogTitle(MediaKind.MOVIE)
    }

    // Details

    suspend fun detail(ref: TitleRef): TitleDetail {
        val appended = if (ref.kind == MediaKind.MOVIE) {
            "credits,videos,watch/providers,recommendations,similar,external_ids,release_dates"
        } else {
            "aggregate_credits,credits,videos,watch/providers,recommendations,similar,external_ids,content_ratings"
        }
        val d = get<TmdbDetail>("/${ref.kind.raw}/${ref.id}", mapOf("append_to_response" to appended))
        return d.titleDetail(ref.kind, region)
    }

    suspend fun availability(ref: TitleRef): Availability =
        get<TmdbWatchProviders>("/${ref.kind.raw}/${ref.id}/watch/providers").availability(region)

    suspend fun episodes(showId: String, showName: String, season: Int, poster: String?): List<EpisodeInfo> {
        val s = get<TmdbSeasonDetail>("/tv/$showId/season/$season")
        val ref = TitleRef(CatalogSource.TMDB, MediaKind.TV, showId)
        return s.episodes.map { e -> e.toEpisodeInfo(ref, showName, poster) }
    }

    suspend fun upcomingEpisodes(showId: String): List<EpisodeInfo> {
        val d = get<TmdbDetail>("/tv/$showId")
        val next = d.nextEpisodeToAir ?: return emptyList()
        val poster = image(d.posterPath, "w342")
        val all = episodes(showId, d.name ?: "", next.seasonNumber, poster)
        val today = LocalDate.now()
        return all.filter { (it.airDate ?: LocalDate.MIN) >= today && it.number >= next.episodeNumber }
    }

    companion object {
        private const val BASE = "https://api.themoviedb.org/3"
        const val IMAGE_BASE = "https://image.tmdb.org/t/p/"

        fun image(path: String?, size: String): String? =
            if (path.isNullOrEmpty()) null else IMAGE_BASE + size + path
    }
}

// DTOs

@Serializable
class TmdbConfiguration

@Serializable
data class TmdbPage(val results: List<TmdbItem> = emptyList())

@Serializable
data class TmdbFindResult(
    @SerialName("movie_results") val movieResults: List<TmdbItem> = emptyList(),
    @SerialName("tv_results") val tvResults: List<TmdbItem> = emptyList(),
)

object TmdbGenres {
    val names: Map<Int, String> = mapOf(
        28 to "Action", 12 to "Adventure", 16 to "Animation", 35 to "Comedy", 80 to "Crime", 99 to "Documentary",
        18 to "Drama", 10751 to "Family", 14 to "Fantasy", 36 to "History", 27 to "Horror", 10402 to "Music",
        9648 to "Mystery", 10749 to "Romance", 878 to "Science Fiction", 10770 to "TV Movie", 53 to "Thriller",
        10752 to "War", 37 to "Western", 10759 to "Action & Adventure", 10762 to "Kids", 10763 to "News",
        10764 to "Reality", 10765 to "Sci-Fi & Fantasy", 10766 to "Soap", 10767 to "Talk", 10768 to "War & Politics",
    )
}

@Serializable
data class TmdbItem(
    val id: Int,
    val title: String? = null,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("vote_average") val voteAverage: Double? = null,
    val popularity: Double? = null,
    @SerialName("genre_ids") val genreIds: List<Int>? = null,
    @SerialName("media_type") val mediaType: String? = null,
) {
    fun catalogTitle(explicitKind: MediaKind? = null): CatalogTitle? {
        val kind = explicitKind ?: when (mediaType) {
            "movie" -> MediaKind.MOVIE
            "tv" -> MediaKind.TV
            else -> return null // people, collections…
        }
        val date = if (kind == MediaKind.MOVIE) releaseDate else firstAirDate
        return CatalogTitle(
            ref = TitleRef(CatalogSource.TMDB, kind, id.toString()),
            name = (if (kind == MediaKind.MOVIE) title else name) ?: title ?: name ?: "Untitled",
            overview = overview ?: "",
            posterUrl = TmdbClient.image(posterPath, "w500"),
            backdropUrl = TmdbClient.image(backdropPath, "w1280"),
            year = DateParsing.year(date),
            releaseDate = DateParsing.date(date),
            genres = (genreIds ?: emptyList()).mapNotNull { TmdbGenres.names[it] },
            score = voteAverage?.takeIf { it > 0 },
            popularity = popularity ?: 0.0,
        )
    }
}

@Serializable
data class TmdbNamed(val id: Int? = null, val name: String = "")

@Serializable
data class TmdbCast(
    val id: Int,
    val name: String,
    val character: String? = null,
    @SerialName("profile_path") val profilePath: String? = null,
    val roles: List<TmdbRole>? = null,
) {
    @Serializable
    data class TmdbRole(val character: String? = null)
}

@Serializable
data class TmdbCredits(val cast: List<TmdbCast> = emptyList())

@Serializable
data class TmdbVideo(val key: String, val site: String = "", val type: String = "", val official: Boolean? = null)

@Serializable
data class TmdbVideos(val results: List<TmdbVideo> = emptyList())

@Serializable
data class TmdbProviderEntry(
    @SerialName("provider_id") val providerId: Int,
    @SerialName("provider_name") val providerName: String = "",
    @SerialName("logo_path") val logoPath: String? = null,
    @SerialName("display_priority") val displayPriority: Int? = null,
)

@Serializable
data class TmdbRegionProviders(
    val link: String? = null,
    val flatrate: List<TmdbProviderEntry>? = null,
    val free: List<TmdbProviderEntry>? = null,
    val ads: List<TmdbProviderEntry>? = null,
    val rent: List<TmdbProviderEntry>? = null,
    val buy: List<TmdbProviderEntry>? = null,
)

@Serializable
data class TmdbWatchProviders(val results: Map<String, TmdbRegionProviders> = emptyMap()) {
    fun availability(region: String): Availability {
        val r = results[region] ?: return Availability(region = region)
        val offers = ArrayList<ProviderOffer>()
        val seen = HashSet<String>()
        fun add(entries: List<TmdbProviderEntry>?, kind: OfferKind) {
            for (e in (entries ?: emptyList()).sortedBy { it.displayPriority ?: 99 }) {
                val provider = Provider.withTmdbId(e.providerId)
                    ?: Provider.matching(e.providerName)
                    ?: Provider.adHoc(e.providerId, e.providerName)
                // Collapse e.g. "Netflix" + "Netflix basic with Ads" into one tile per kind.
                if (!seen.add("${provider.id}-${kind.raw}")) continue
                offers += ProviderOffer(provider = provider, kind = kind, logoUrl = TmdbClient.image(e.logoPath, "w154"))
            }
        }
        add(r.flatrate, OfferKind.STREAM)
        add(r.free, OfferKind.FREE)
        add(r.ads, OfferKind.ADS)
        add(r.rent, OfferKind.RENT)
        add(r.buy, OfferKind.BUY)
        return Availability(offers = offers, link = r.link, region = region)
    }
}

@Serializable
data class TmdbEpisode(
    val id: Int,
    val name: String? = null,
    val overview: String? = null,
    @SerialName("episode_number") val episodeNumber: Int = 0,
    @SerialName("season_number") val seasonNumber: Int = 0,
    @SerialName("air_date") val airDate: String? = null,
    val runtime: Int? = null,
    @SerialName("still_path") val stillPath: String? = null,
) {
    fun toEpisodeInfo(ref: TitleRef, showName: String, poster: String?): EpisodeInfo = EpisodeInfo(
        id = "tmdb-ep-$id", showRef = ref, showName = showName, season = seasonNumber, number = episodeNumber,
        name = name?.ifEmpty { null } ?: "Episode $episodeNumber", airDate = DateParsing.date(airDate), runtime = runtime,
        overview = overview ?: "", stillUrl = TmdbClient.image(stillPath, "w500"), showPosterUrl = poster,
    )
}

@Serializable
data class TmdbSeason(
    @SerialName("season_number") val seasonNumber: Int = 0,
    val name: String? = null,
    @SerialName("episode_count") val episodeCount: Int? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("air_date") val airDate: String? = null,
)

@Serializable
data class TmdbSeasonDetail(val episodes: List<TmdbEpisode> = emptyList())

@Serializable
data class TmdbExternalIds(@SerialName("imdb_id") val imdbId: String? = null)

@Serializable
data class TmdbReleaseDates(val results: List<Country> = emptyList()) {
    @Serializable
    data class Country(@SerialName("iso_3166_1") val iso31661: String = "", @SerialName("release_dates") val releaseDates: List<Entry> = emptyList())

    @Serializable
    data class Entry(val certification: String? = null)
}

@Serializable
data class TmdbContentRatings(val results: List<Country> = emptyList()) {
    @Serializable
    data class Country(@SerialName("iso_3166_1") val iso31661: String = "", val rating: String? = null)
}

@Serializable
data class TmdbDetail(
    val id: Int,
    val title: String? = null,
    val name: String? = null,
    val overview: String? = null,
    val tagline: String? = null,
    @SerialName("poster_path") val posterPath: String? = null,
    @SerialName("backdrop_path") val backdropPath: String? = null,
    @SerialName("release_date") val releaseDate: String? = null,
    @SerialName("first_air_date") val firstAirDate: String? = null,
    @SerialName("vote_average") val voteAverage: Double? = null,
    val popularity: Double? = null,
    val runtime: Int? = null,
    @SerialName("episode_run_time") val episodeRunTime: List<Int>? = null,
    val genres: List<TmdbNamed>? = null,
    val status: String? = null,
    val homepage: String? = null,
    @SerialName("imdb_id") val imdbId: String? = null,
    @SerialName("external_ids") val externalIds: TmdbExternalIds? = null,
    val credits: TmdbCredits? = null,
    @SerialName("aggregate_credits") val aggregateCredits: TmdbCredits? = null,
    val videos: TmdbVideos? = null,
    @SerialName("watch/providers") val watchProviders: TmdbWatchProviders? = null,
    val seasons: List<TmdbSeason>? = null,
    @SerialName("next_episode_to_air") val nextEpisodeToAir: TmdbEpisode? = null,
    val networks: List<TmdbNamed>? = null,
    val similar: TmdbPage? = null,
    val recommendations: TmdbPage? = null,
    @SerialName("created_by") val createdBy: List<TmdbNamed>? = null,
    @SerialName("release_dates") val releaseDates: TmdbReleaseDates? = null,
    @SerialName("content_ratings") val contentRatings: TmdbContentRatings? = null,
) {
    fun titleDetail(kind: MediaKind, region: String): TitleDetail {
        val date = if (kind == MediaKind.MOVIE) releaseDate else firstAirDate
        val ref = TitleRef(CatalogSource.TMDB, kind, id.toString())
        val availability = watchProviders?.availability(region) ?: Availability(region = region)
        val certification: String? = if (kind == MediaKind.MOVIE) {
            releaseDates?.results?.firstOrNull { it.iso31661 == region }?.releaseDates
                ?.mapNotNull { it.certification }?.firstOrNull { it.isNotEmpty() }
        } else {
            contentRatings?.results?.firstOrNull { it.iso31661 == region }?.rating?.ifEmpty { null }
        }
        val poster = TmdbClient.image(posterPath, "w500")
        val title = CatalogTitle(
            ref = ref,
            name = (if (kind == MediaKind.MOVIE) title else name) ?: "Untitled",
            overview = overview ?: "",
            posterUrl = poster,
            backdropUrl = TmdbClient.image(backdropPath, "original"),
            year = DateParsing.year(date),
            releaseDate = DateParsing.date(date),
            genres = genres?.map { it.name } ?: emptyList(),
            score = voteAverage?.takeIf { it > 0 },
            runtime = runtime ?: episodeRunTime?.firstOrNull(),
            providers = availability.offers(OfferKind.STREAM).map { it.provider },
            network = networks?.firstOrNull()?.name,
            status = status,
            certification = certification,
            homepage = homepage?.ifEmpty { null },
            imdbId = imdbId ?: externalIds?.imdbId,
            popularity = popularity ?: 0.0,
        )

        val castSource = (if (!aggregateCredits?.cast.isNullOrEmpty()) aggregateCredits else credits)?.cast ?: emptyList()
        val cast = castSource.take(20).map {
            CastMember(
                id = it.id.toString(), name = it.name,
                character = it.character ?: it.roles?.firstOrNull()?.character ?: "",
                photoUrl = TmdbClient.image(it.profilePath, "w185"),
            )
        }
        val trailer = videos?.results
            ?.filter { it.site == "YouTube" && (it.type == "Trailer" || it.type == "Teaser") }
            ?.sortedByDescending { it.official == true }
            ?.firstOrNull()
            ?.let { "https://www.youtube.com/watch?v=${it.key}" }
        val recs = (recommendations?.results ?: emptyList()) + (similar?.results ?: emptyList())
        val similarTitles = recs.distinctBy { it.id }.take(18).mapNotNull { it.catalogTitle(kind) }
        val next = nextEpisodeToAir?.toEpisodeInfo(ref, title.name, poster)
        val seasonInfos = (seasons ?: emptyList()).filter { it.seasonNumber > 0 }.map {
            SeasonInfo(
                number = it.seasonNumber, name = it.name?.ifEmpty { null } ?: "Season ${it.seasonNumber}",
                episodeCount = it.episodeCount, posterUrl = TmdbClient.image(it.posterPath, "w342"),
                airYear = DateParsing.year(it.airDate),
            )
        }
        return TitleDetail(
            title = title, tagline = tagline?.ifEmpty { null }, cast = cast, seasons = seasonInfos,
            availability = availability, similar = similarTitles, trailerUrl = trailer, nextEpisode = next,
            creators = createdBy?.map { it.name } ?: emptyList(),
        )
    }
}
