package com.nearbycoder.couchpotato

import com.nearbycoder.couchpotato.data.remote.Http
import com.nearbycoder.couchpotato.data.remote.TmdbWatchProviders
import com.nearbycoder.couchpotato.domain.OfferKind
import com.nearbycoder.couchpotato.domain.Provider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TmdbOffersTest {
    private val payload = """
        {"id":603,"results":{
          "US":{"link":"https://www.themoviedb.org/movie/603/watch?locale=US",
                "flatrate":[{"provider_id":1796,"provider_name":"Netflix basic with Ads","logo_path":"/ads.jpg","display_priority":5},
                            {"provider_id":8,"provider_name":"Netflix","logo_path":"/nf.jpg","display_priority":0},
                            {"provider_id":9000,"provider_name":"Mystery Stream","logo_path":"/ms.jpg","display_priority":3}],
                "free":[{"provider_id":73,"provider_name":"Tubi TV","logo_path":"/tubi.jpg","display_priority":9}],
                "rent":[{"provider_id":2,"provider_name":"Apple TV","logo_path":"/apple.jpg","display_priority":1},
                        {"provider_id":10,"provider_name":"Amazon Video","logo_path":"/amz.jpg","display_priority":2}],
                "buy":[{"provider_id":2,"provider_name":"Apple TV","logo_path":"/apple.jpg","display_priority":1}]},
          "GB":{"flatrate":[{"provider_id":8,"provider_name":"Netflix","logo_path":"/nf.jpg","display_priority":0}]}
        }}
    """.trimIndent()

    @Test
    fun `maps regional offers, collapses duplicates and resolves providers`() {
        val availability = Http.json.decodeFromString<TmdbWatchProviders>(payload).availability("US")
        val stream = availability.offers(OfferKind.STREAM)
        // Netflix + Netflix with ads collapse into one tile, sorted by display priority.
        assertEquals(listOf("netflix", "tmdb-9000"), stream.map { it.provider.id })
        assertEquals("https://image.tmdb.org/t/p/w154/nf.jpg", stream.first().logoUrl)
        assertEquals("Mystery Stream", stream[1].provider.name)

        assertEquals(listOf(Provider.tubi), availability.offers(OfferKind.FREE).map { it.provider })
        assertEquals(listOf(Provider.appleStore, Provider.prime), availability.offers(OfferKind.RENT).map { it.provider })
        assertEquals(listOf(Provider.appleStore), availability.offers(OfferKind.BUY).map { it.provider })
        assertEquals("https://www.themoviedb.org/movie/603/watch?locale=US", availability.link)
        assertEquals("US", availability.region)
        assertTrue(availability.providers.map { it.id }.containsAll(listOf("netflix", "tubi", "apple-store", "prime")))
    }

    @Test
    fun `unknown region yields empty availability`() {
        val availability = Http.json.decodeFromString<TmdbWatchProviders>(payload).availability("FR")
        assertTrue(availability.isEmpty)
        assertEquals("FR", availability.region)
    }
}
