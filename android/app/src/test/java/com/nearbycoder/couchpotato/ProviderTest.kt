package com.nearbycoder.couchpotato

import com.nearbycoder.couchpotato.domain.Provider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProviderTest {
    @Test
    fun `matches exact names and aliases`() {
        assertEquals(Provider.netflix, Provider.matching("Netflix"))
        assertEquals(Provider.hulu, Provider.matching("FX"))
        assertEquals(Provider.apple, Provider.matching("Apple TV+"))
        assertEquals(Provider.peacock, Provider.matching("NBC"))
        assertEquals(Provider.paramount, Provider.matching("CBS"))
    }

    @Test
    fun `matches longer aliases inside free-form network names`() {
        assertEquals(Provider.hbo, Provider.matching("Cinemax East"))
        assertEquals(Provider.disney, Provider.matching("Disney+ Hotstar"))
        assertEquals(Provider.prime, Provider.matching("Amazon Prime Video"))
    }

    @Test
    fun `short aliases never fuzzy match`() {
        // "max" and "hbo" are only 3 letters, so they only match exactly (mirrors the Swift app).
        assertNull(Provider.matching("Maxwell Network"))
        assertNull(Provider.matching("HBO Max Originals"))
        assertEquals(Provider.hbo, Provider.matching("HBO"))
        assertNull(Provider.matching("Some Unknown Channel"))
    }

    @Test
    fun `tmdb ids map to providers`() {
        assertEquals(Provider.netflix, Provider.withTmdbId(8))
        assertEquals(Provider.netflix, Provider.withTmdbId(1796))
        assertEquals(Provider.hbo, Provider.withTmdbId(1899))
        assertEquals(Provider.appleStore, Provider.withTmdbId(2))
        assertNull(Provider.withTmdbId(999_999))
    }

    @Test
    fun `search url encodes the title`() {
        val url = Provider.netflix.searchUrl("Dune: Part Two")
        assertNotNull(url)
        assertEquals("https://www.netflix.com/search?q=Dune%3A%20Part%20Two", url)
        assertNull(Provider.adHoc(42, "Odd Store").searchUrl("x"))
    }

    @Test
    fun `monograms are two letters`() {
        assertEquals("HM", Provider.hbo.monogram)
        assertEquals("PV", Provider.prime.monogram)
        assertEquals("Ne", Provider.netflix.monogram)
        assertTrue(Provider.all.all { it.monogram.length in 1..2 })
    }
}
