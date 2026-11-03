package com.nearbycoder.couchpotato

import com.nearbycoder.couchpotato.data.remote.Http
import com.nearbycoder.couchpotato.data.remote.ITunesClient
import com.nearbycoder.couchpotato.data.remote.ITunesLookup
import com.nearbycoder.couchpotato.domain.OfferKind
import com.nearbycoder.couchpotato.domain.Provider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ITunesClientTest {
    @Test
    fun `upscales mzstatic thumbnails to poster size`() {
        val thumb = "https://is1-ssl.mzstatic.com/image/thumb/Video/v4/ab/cd/ef/poster.jpg/100x100bb.jpg"
        assertEquals(
            "https://is1-ssl.mzstatic.com/image/thumb/Video/v4/ab/cd/ef/poster.jpg/600x900bb.jpg",
            ITunesClient.upscale(thumb),
        )
        assertEquals(
            "https://is1-ssl.mzstatic.com/image/thumb/x.png/300x450bb.jpg",
            ITunesClient.upscale("https://is1-ssl.mzstatic.com/image/thumb/x.png/60x60bb.png", "300x450bb"),
        )
    }

    @Test
    fun `leaves other urls alone`() {
        assertEquals("https://example.com/a.jpg", ITunesClient.upscale("https://example.com/a.jpg"))
        assertNull(ITunesClient.upscale(null))
        assertNull(ITunesClient.upscale(""))
    }

    @Test
    fun `lookup offers keep apple prices`() {
        val json = """
            {"resultCount":1,"results":[{"trackId":123,"trackName":"Heat","artworkUrl100":"https://x/100x100bb.jpg",
             "trackTimeMillis":10200000,"trackPrice":14.99,"trackRentalPrice":3.99,"trackHdPrice":19.99,"trackHdRentalPrice":4.99,
             "trackViewUrl":"https://tv.apple.com/movie/id123","releaseDate":"1995-12-15T08:00:00Z","primaryGenreName":"Thriller"}]}
        """.trimIndent()
        val lookup = Http.json.decodeFromString<ITunesLookup>(json)
        val track = lookup.results.single()
        val availability = track.availability()
        val rent = availability.offers(OfferKind.RENT).single()
        val buy = availability.offers(OfferKind.BUY).single()
        assertEquals(Provider.appleStore, rent.provider)
        assertEquals("$4.99", rent.price)
        assertEquals("$19.99", buy.price)
        assertEquals(170, track.catalogTitle.runtime)
        assertEquals(1995, track.catalogTitle.year)
        assertEquals("https://x/600x900bb.jpg", track.catalogTitle.posterUrl)
    }
}
