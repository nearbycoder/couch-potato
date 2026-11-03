package com.nearbycoder.couchpotato.data.remote

import com.nearbycoder.couchpotato.domain.Availability
import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.OfferKind
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.ProviderOffer
import com.nearbycoder.couchpotato.domain.TitleRef
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.Locale

/**
 * Apple's public iTunes charts + lookup: key-less movie box art, charts by genre,
 * and Apple TV Store rent/buy prices.
 */
class ITunesClient(private val country: String = "us") {

    suspend fun topMovies(genre: Int? = null, limit: Int = 50): List<CatalogTitle> {
        val genrePart = genre?.let { "/genre=$it" } ?: ""
        val url = "https://itunes.apple.com/$country/rss/topmovies/limit=$limit$genrePart/json"
        val feed: ITunesFeed = Http.get(url)
        return (feed.feed.entry ?: emptyList()).mapIndexed { index, entry -> entry.catalogTitle(index) }
    }

    suspend fun lookup(id: String): Pair<CatalogTitle, ITunesTrack> {
        val result: ITunesLookup = Http.get("https://itunes.apple.com/lookup?id=$id&country=$country")
        val track = result.results.firstOrNull() ?: throw HttpException(404)
        return track.catalogTitle to track
    }

    companion object {
        private val sizeSuffix = Regex("/\\d+x\\d+bb\\.(png|jpg)$")

        /** Bumps an mzstatic thumbnail URL to a crisp poster size. */
        fun upscale(urlString: String?, size: String = "600x900bb"): String? {
            if (urlString.isNullOrEmpty()) return null
            return urlString.replace(sizeSuffix, "/$size.jpg")
        }
    }
}

@Serializable
data class ITunesLabel(val label: String = "")

@Serializable
data class ITunesFeed(val feed: Feed = Feed()) {
    @Serializable
    data class Feed(val entry: List<ITunesEntry>? = null)
}

@Serializable
data class ITunesEntry(
    @SerialName("im:name") val name: ITunesLabel = ITunesLabel(),
    val summary: ITunesLabel? = null,
    @SerialName("im:image") val images: List<ITunesLabel>? = null,
    val id: Id = Id(),
    val category: Category? = null,
    @SerialName("im:releaseDate") val releaseDate: ITunesLabel? = null,
    @SerialName("im:rentalPrice") val rentalPrice: ITunesLabel? = null,
) {
    @Serializable
    data class Id(val attributes: Attributes = Attributes()) {
        @Serializable
        data class Attributes(@SerialName("im:id") val id: String = "")
    }

    @Serializable
    data class Category(val attributes: Attributes = Attributes()) {
        @Serializable
        data class Attributes(val label: String = "")
    }

    fun catalogTitle(rank: Int): CatalogTitle {
        val date = DateParsing.date(releaseDate?.label)
        return CatalogTitle(
            ref = TitleRef(CatalogSource.ITUNES, MediaKind.MOVIE, id.attributes.id),
            name = name.label,
            overview = summary?.label ?: "",
            posterUrl = ITunesClient.upscale(images?.lastOrNull()?.label),
            year = date?.year,
            releaseDate = date,
            genres = category?.let { listOf(it.attributes.label) } ?: emptyList(),
            providers = listOf(Provider.appleStore),
            popularity = (100 - rank).toDouble(),
        )
    }
}

@Serializable
data class ITunesLookup(val results: List<ITunesTrack> = emptyList())

@Serializable
data class ITunesTrack(
    val trackId: Long,
    val trackName: String = "",
    val artistName: String? = null,
    val artworkUrl100: String? = null,
    val longDescription: String? = null,
    val primaryGenreName: String? = null,
    val releaseDate: String? = null,
    val trackTimeMillis: Long? = null,
    val contentAdvisoryRating: String? = null,
    val trackViewUrl: String? = null,
    val trackPrice: Double? = null,
    val trackRentalPrice: Double? = null,
    val trackHdPrice: Double? = null,
    val trackHdRentalPrice: Double? = null,
    val previewUrl: String? = null,
) {
    val catalogTitle: CatalogTitle
        get() {
            val date = DateParsing.date(releaseDate)
            return CatalogTitle(
                ref = TitleRef(CatalogSource.ITUNES, MediaKind.MOVIE, trackId.toString()),
                name = trackName,
                overview = longDescription ?: "",
                posterUrl = ITunesClient.upscale(artworkUrl100),
                year = date?.year,
                releaseDate = date,
                genres = primaryGenreName?.let { listOf(it) } ?: emptyList(),
                runtime = trackTimeMillis?.let { (it / 60_000).toInt() },
                providers = listOf(Provider.appleStore),
                certification = contentAdvisoryRating,
                homepage = trackViewUrl,
            )
        }

    fun availability(): Availability {
        fun price(value: Double?): String? = value?.takeIf { it > 0 }?.let { String.format(Locale.US, "$%.2f", it) }
        val offers = ArrayList<ProviderOffer>()
        price(trackHdRentalPrice ?: trackRentalPrice)?.let {
            offers += ProviderOffer(provider = Provider.appleStore, kind = OfferKind.RENT, price = it, link = trackViewUrl)
        }
        price(trackHdPrice ?: trackPrice)?.let {
            offers += ProviderOffer(provider = Provider.appleStore, kind = OfferKind.BUY, price = it, link = trackViewUrl)
        }
        return Availability(offers = offers, link = trackViewUrl)
    }
}
