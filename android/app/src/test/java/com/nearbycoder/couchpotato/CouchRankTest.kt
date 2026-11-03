package com.nearbycoder.couchpotato

import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.Backup
import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.CouchRank
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.TitleRef
import com.nearbycoder.couchpotato.domain.WatchStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CouchRankTest {
    private fun movie(id: String, status: WatchStatus, runtime: Int? = 120, rating: Int = 0) =
        SavedTitle.from(CatalogTitle(TitleRef(CatalogSource.TMDB, MediaKind.MOVIE, id), "Movie $id", runtime = runtime), status)
            .copy(rating = rating)

    private fun show(id: String, status: WatchStatus, season: Int, episode: Int, runtime: Int? = 45) =
        SavedTitle.from(CatalogTitle(TitleRef(CatalogSource.TVMAZE, MediaKind.TV, id), "Show $id", runtime = runtime), status)
            .copy(lastSeason = season, lastEpisode = episode)

    @Test
    fun `levels follow thresholds`() {
        assertEquals("Raw Spud", CouchRank.levelFor(0).name)
        assertEquals("Raw Spud", CouchRank.levelFor(2).name)
        assertEquals("Tater Tot", CouchRank.levelFor(3).name)
        assertEquals("Hash Brown", CouchRank.levelFor(10).name)
        assertEquals("Curly Fry", CouchRank.levelFor(25).name)
        assertEquals("Baked Legend", CouchRank.levelFor(50).name)
        assertEquals("Mashed Royalty", CouchRank.levelFor(1000).name)
    }

    @Test
    fun `points and hours come from watched titles, ratings, nights and episodes`() {
        val titles = listOf(
            movie("1", WatchStatus.WATCHED, runtime = 120, rating = 4),
            movie("2", WatchStatus.WATCHED, runtime = null),
            movie("3", WatchStatus.QUEUED, rating = 5),
            show("10", WatchStatus.WATCHED, season = 2, episode = 4, runtime = 30),
            show("11", WatchStatus.WATCHING, season = 1, episode = 6, runtime = 60),
        )
        val nights = listOf(
            CouchNight(titleKey = "x", titleName = "x", startsAt = 0, isDone = true),
            CouchNight(titleKey = "y", titleName = "y", startsAt = 0, isDone = false),
        )
        val rank = CouchRank(titles, nights)
        assertEquals(2, rank.moviesWatched)
        assertEquals(1, rank.showsWatched)
        // movies 2*2 + shows 1*4 + rated 2 + done nights 1 + episodes (4+8 + 6)/4 = 4
        assertEquals(4 + 4 + 2 + 1 + 4, rank.points)
        assertEquals("Hash Brown", rank.level.name)
        assertEquals("Curly Fry", rank.nextLevel?.name)
        // movie minutes 120 + 110 default; episodes: watched show max(10,4)*30 = 300, watching 6*60 = 360
        assertEquals((230 + 300 + 360) / 60, rank.hoursWatched)
        assertEquals(4.5, rank.averageRating!!, 0.001)
        assertTrue(rank.progressToNext > 0f && rank.progressToNext < 1f)
    }

    @Test
    fun `empty library is a raw spud with nothing to average`() {
        val rank = CouchRank(emptyList(), emptyList())
        assertEquals(0, rank.points)
        assertEquals("Raw Spud", rank.level.name)
        assertNull(rank.averageRating)
    }

    @Test
    fun `backup round-trips titles and nights`() {
        val titles = listOf(movie("1", WatchStatus.WATCHED, rating = 3).copy(notes = "Great"), show("9", WatchStatus.WATCHING, 1, 2))
        val nights = listOf(CouchNight(titleKey = titles[0].key, titleName = "Movie 1", startsAt = 1_700_000_000_000L, durationMinutes = 90, note = "popcorn"))
        val json = Backup.export(titles, nights)
        val imported = Backup.import(json)
        assertEquals(titles.map { it.key }, imported.titles.map { it.key })
        assertEquals(3, imported.titles[0].rating)
        assertEquals("Great", imported.titles[0].notes)
        assertEquals(1, imported.titles[1].lastSeason)
        assertEquals(2, imported.titles[1].lastEpisode)
        assertEquals(1_700_000_000_000L, imported.nights.single().startsAt)
        assertEquals("popcorn", imported.nights.single().note)
    }

    @Test
    fun `backup import accepts apple-style field names`() {
        val json = """{"titles":[{"key":"tmdb-movie-603","name":"The Matrix","statusRaw":"watched","potatoes":5,"addedAt":1700000000,"posterURLString":"https://p/x.jpg","genresCSV":"Action,Sci-Fi"}],"nights":[]}"""
        val imported = Backup.import(json)
        val t = imported.titles.single()
        assertEquals(WatchStatus.WATCHED, t.watchStatus)
        assertEquals(5, t.rating)
        assertEquals(1_700_000_000_000L, t.addedAt)
        assertEquals("https://p/x.jpg", t.posterUrl)
        assertEquals(listOf("Action", "Sci-Fi"), t.genres)
    }
}
