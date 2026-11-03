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
import com.nearbycoder.couchpotato.domain.strippingHtml
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.net.URI
import java.time.LocalDate

/**
 * TVmaze: a free, key-less TV catalog with schedules and the streamer/network
 * each show lives on. Data is CC BY-SA, credited in Settings.
 */
class TvMazeClient {

    private suspend inline fun <reified T> get(path: String, query: Map<String, String?> = emptyMap()): T =
        Http.get(Http.url(BASE, path, query))

    suspend fun search(text: String): List<CatalogTitle> =
        get<List<TvmSearchResult>>("/search/shows", mapOf("q" to text)).map { it.show.catalogTitle }

    /** Every series known to stream on a service, from the catalog built by scripts/build_catalog.py. */
    suspend fun publishedSeries(serviceId: String): List<TvmShow> = Http.get("$CATALOG_BASE/$serviceId.json")

    /** Episodes released on streaming services (`web`) or US broadcast on a given day. */
    suspend fun schedule(date: LocalDate, web: Boolean): List<TvmScheduleItem> {
        val day = DateParsing.dayString(date)
        return if (web) get("/schedule/web", mapOf("date" to day)) else get("/schedule", mapOf("date" to day, "country" to "US"))
    }

    suspend fun detail(id: String): Pair<TvmShow, TitleDetail> {
        val show: TvmShow = Http.get("$BASE/shows/$id?embed[]=cast&embed[]=seasons&embed[]=images&embed[]=nextepisode")
        val base = show.catalogTitle
        val backdrop = show.embedded?.images
            ?.filter { it.type == "background" }
            ?.sortedByDescending { it.main == true }
            ?.firstOrNull()?.resolutions?.original?.url
        val title = base.copy(backdropUrl = backdrop)
        val cast = (show.embedded?.cast ?: emptyList()).take(20).map {
            CastMember(
                id = it.person.id.toString(), name = it.person.name, character = it.character?.name ?: "",
                photoUrl = it.person.image?.medium,
            )
        }
        val seasons = (show.embedded?.seasons ?: emptyList()).filter { it.number > 0 }.map {
            SeasonInfo(
                number = it.number, name = it.name?.ifEmpty { null } ?: "Season ${it.number}",
                episodeCount = it.episodeOrder, posterUrl = it.image?.original, airYear = DateParsing.year(it.premiereDate),
            )
        }
        val next = show.embedded?.nextepisode?.episodeInfo(base)
        val offers = base.providers.map { provider ->
            var link = provider.searchUrl(base.name)
            val siteHost = show.officialSite?.let { runCatching { URI(it).host }.getOrNull() }
            val templateHost = provider.searchTemplate?.let { runCatching { URI(it).host }.getOrNull() }
            if (siteHost != null && templateHost != null && hostMatches(siteHost, templateHost)) link = show.officialSite
            ProviderOffer(provider = provider, kind = OfferKind.STREAM, link = link)
        }
        val detail = TitleDetail(
            title = title, cast = cast, seasons = seasons,
            availability = Availability(offers = offers, link = show.url, region = "US"),
            nextEpisode = next,
        )
        return show to detail
    }

    suspend fun episodes(showId: String): List<TvmEpisode> = get("/shows/$showId/episodes")

    private fun hostMatches(a: String, b: String): Boolean {
        fun strip(h: String) = h.split(".").takeLast(2).joinToString(".")
        return strip(a) == strip(b)
    }

    companion object {
        private const val BASE = "https://api.tvmaze.com"
        const val CATALOG_BASE = "https://nearbycoder.github.io/couch-potato/catalog/v1"
    }
}

// DTOs

@Serializable
data class TvmImage(val medium: String? = null, val original: String? = null)

@Serializable
data class TvmChannel(val id: Int = 0, val name: String = "", val officialSite: String? = null)

@Serializable
data class TvmRating(val average: Double? = null)

@Serializable
data class TvmExternals(val imdb: String? = null, val thetvdb: Int? = null)

@Serializable
data class TvmEpisode(
    val id: Int,
    val name: String? = null,
    val season: Int = 0,
    val number: Int? = null,
    val airdate: String? = null,
    val airstamp: String? = null,
    val runtime: Int? = null,
    val summary: String? = null,
    val image: TvmImage? = null,
) {
    fun episodeInfo(show: CatalogTitle): EpisodeInfo {
        val stamp = DateParsing.instantMillis(airstamp)
        return EpisodeInfo(
            id = "tvmaze-ep-$id", showRef = show.ref, showName = show.name, season = season, number = number ?: 0,
            name = name?.ifEmpty { null } ?: "Episode ${number ?: 0}",
            airDate = stamp?.let { DateParsing.localDate(it) } ?: DateParsing.date(airdate),
            airTimeEpochMillis = stamp,
            runtime = runtime ?: show.runtime, overview = summary?.strippingHtml() ?: "",
            stillUrl = image?.original ?: image?.medium, showPosterUrl = show.posterUrl,
        )
    }
}

@Serializable
data class TvmSeason(
    val number: Int = 0,
    val name: String? = null,
    val episodeOrder: Int? = null,
    val premiereDate: String? = null,
    val image: TvmImage? = null,
)

@Serializable
data class TvmCastCredit(val person: Person, val character: Character? = null) {
    @Serializable
    data class Person(val id: Int, val name: String, val image: TvmImage? = null)

    @Serializable
    data class Character(val name: String = "")
}

@Serializable
data class TvmShowImage(val type: String? = null, val main: Boolean? = null, val resolutions: Resolutions = Resolutions()) {
    @Serializable
    data class Resolutions(val original: Res? = null)

    @Serializable
    data class Res(val url: String)
}

@Serializable
data class TvmEmbedded(
    val cast: List<TvmCastCredit>? = null,
    val seasons: List<TvmSeason>? = null,
    val images: List<TvmShowImage>? = null,
    val nextepisode: TvmEpisode? = null,
)

@Serializable
data class TvmShow(
    val id: Int,
    val url: String? = null,
    val name: String,
    val type: String? = null,
    val language: String? = null,
    val genres: List<String>? = null,
    val status: String? = null,
    val runtime: Int? = null,
    val averageRuntime: Int? = null,
    val premiered: String? = null,
    val officialSite: String? = null,
    val rating: TvmRating? = null,
    val weight: Int? = null,
    val network: TvmChannel? = null,
    val webChannel: TvmChannel? = null,
    val externals: TvmExternals? = null,
    val image: TvmImage? = null,
    val summary: String? = null,
    @SerialName("_embedded") val embedded: TvmEmbedded? = null,
) {
    val catalogTitle: CatalogTitle
        get() {
            val channels = listOfNotNull(webChannel?.name, network?.name)
            val providers = ArrayList<Provider>()
            for (channel in channels) {
                val p = Provider.matching(channel)
                if (p != null && p !in providers) providers += p
            }
            return CatalogTitle(
                ref = TitleRef(CatalogSource.TVMAZE, MediaKind.TV, id.toString()),
                name = name,
                overview = summary?.strippingHtml() ?: "",
                posterUrl = image?.original ?: image?.medium,
                year = DateParsing.year(premiered),
                releaseDate = DateParsing.date(premiered),
                genres = genres ?: emptyList(),
                score = rating?.average,
                runtime = averageRuntime ?: runtime,
                providers = providers,
                network = webChannel?.name ?: network?.name,
                status = status,
                homepage = officialSite,
                imdbId = externals?.imdb,
                popularity = (weight ?: 0).toDouble(),
            )
        }
}

@Serializable
data class TvmSearchResult(val show: TvmShow)

@Serializable
data class TvmScheduleItem(
    val id: Int,
    val season: Int? = null,
    val number: Int? = null,
    val airstamp: String? = null,
    @SerialName("_embedded") val embedded: Embedded? = null,
    val show: TvmShow? = null,
) {
    @Serializable
    data class Embedded(val show: TvmShow)

    /** `/schedule/web` embeds the show; `/schedule` inlines it. */
    val resolvedShow: TvmShow? get() = embedded?.show ?: show
}
