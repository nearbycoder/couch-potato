package com.nearbycoder.couchpotato

import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.Genre
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.TitleFilter
import com.nearbycoder.couchpotato.domain.TitleRef
import com.nearbycoder.couchpotato.domain.TitleSort
import com.nearbycoder.couchpotato.domain.YearRange
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class TitleFilterTest {
    private val today = LocalDate.of(2026, 11, 3)

    private fun title(
        id: String,
        name: String = "Title $id",
        year: Int? = null,
        date: LocalDate? = null,
        genres: List<String> = emptyList(),
        score: Double? = null,
    ) = CatalogTitle(
        ref = TitleRef(CatalogSource.TVMAZE, MediaKind.TV, id),
        name = name,
        year = year ?: date?.year,
        releaseDate = date,
        genres = genres,
        score = score,
    )

    private fun ids(list: List<CatalogTitle>) = list.map { it.ref.id }

    @Test
    fun `default filter is default and keeps everything in order`() {
        val f = TitleFilter()
        assertTrue(f.isDefault)
        assertEquals("POPULAR|ANY|-|-", f.key)
        val list = listOf(title("b", year = 1980), title("a"), title("c", score = 9.0))
        assertEquals(listOf("b", "a", "c"), ids(f.apply(list, today)))
    }

    @Test
    fun `key changes with every field`() {
        val keys = setOf(
            TitleFilter().key,
            TitleFilter(sort = TitleSort.NEWEST).key,
            TitleFilter(years = YearRange.Y1990S).key,
            TitleFilter(genre = Genre.COMEDY).key,
            TitleFilter(minRating = 7.0).key,
        )
        assertEquals(5, keys.size)
        assertFalse(TitleFilter(minRating = 7.0).isDefault)
    }

    @Test
    fun `year ranges`() {
        val list = listOf(
            title("y2026", year = 2026), title("y2022", year = 2022), title("y2021", year = 2021),
            title("y2015", year = 2015), title("y2003", year = 2003), title("y1995", year = 1995),
            title("y1989", year = 1989), title("y1970", year = 1970), title("none"),
        )
        fun only(range: YearRange) = ids(TitleFilter(years = range).apply(list, today))
        assertEquals(ids(list), only(YearRange.ANY))
        assertEquals(listOf("y2026"), only(YearRange.THIS_YEAR))
        assertEquals(listOf("y2026", "y2022"), only(YearRange.LAST5))
        assertEquals(listOf("y2026", "y2022", "y2021"), only(YearRange.Y2020S))
        assertEquals(listOf("y2015"), only(YearRange.Y2010S))
        assertEquals(listOf("y2003"), only(YearRange.Y2000S))
        assertEquals(listOf("y1995"), only(YearRange.Y1990S))
        assertEquals(listOf("y1989", "y1970"), only(YearRange.OLDER))
    }

    @Test
    fun `genre matches tvmaze names and label words case-insensitively`() {
        val list = listOf(
            title("adventure", genres = listOf("Adventure")),
            title("tmdbAction", genres = listOf("Action & Adventure")),
            title("comedy", genres = listOf("Drama", "comedy")),
            title("scifi", genres = listOf("Science-Fiction")),
            title("itunesScifi", genres = listOf("Sci-Fi & Fantasy")),
            title("kids", genres = listOf("Children")),
            title("itunesKids", genres = listOf("Kids & Family")),
            title("legal", genres = listOf("Legal")),
            title("none"),
        )
        fun only(g: Genre) = ids(TitleFilter(genre = g).apply(list, today))
        assertEquals(listOf("adventure", "tmdbAction"), only(Genre.ACTION))
        assertEquals(listOf("comedy"), only(Genre.COMEDY))
        assertEquals(listOf("scifi", "itunesScifi"), only(Genre.SCIFI))
        assertEquals(listOf("kids", "itunesKids"), only(Genre.FAMILY))
        assertEquals(listOf("legal"), only(Genre.CRIME))
        assertEquals(listOf("comedy"), only(Genre.DRAMA))
        assertEquals(emptyList<String>(), only(Genre.REALITY))
    }

    @Test
    fun `min rating treats missing scores as zero`() {
        val list = listOf(title("a", score = 8.2), title("b", score = 7.0), title("c", score = 6.4), title("d"))
        assertEquals(listOf("a", "b", "c"), ids(TitleFilter(minRating = 6.0).apply(list, today)))
        assertEquals(listOf("a", "b"), ids(TitleFilter(minRating = 7.0).apply(list, today)))
        assertEquals(listOf("a"), ids(TitleFilter(minRating = 8.0).apply(list, today)))
    }

    @Test
    fun `newest sorts by date and drops future titles`() {
        val list = listOf(
            title("old", date = LocalDate.of(2001, 5, 1)),
            title("future", date = LocalDate.of(2026, 12, 25)),
            title("recent", date = LocalDate.of(2026, 10, 1)),
            title("yearOnly", year = 2024),
            title("futureYear", year = 2027),
            title("undated"),
            title("today", date = today),
        )
        assertEquals(
            listOf("today", "recent", "yearOnly", "old", "undated"),
            ids(TitleFilter(sort = TitleSort.NEWEST).apply(list, today)),
        )
    }

    @Test
    fun `rating sorts by score with unscored last`() {
        val list = listOf(title("mid", score = 7.1), title("none"), title("top", score = 9.0), title("low", score = 5.0))
        assertEquals(listOf("top", "mid", "low", "none"), ids(TitleFilter(sort = TitleSort.RATING).apply(list, today)))
    }

    @Test
    fun `title sorts alphabetically ignoring case`() {
        val list = listOf(title("1", name = "zodiac"), title("2", name = "Alien"), title("3", name = "beef"))
        assertEquals(listOf("2", "3", "1"), ids(TitleFilter(sort = TitleSort.TITLE).apply(list, today)))
    }

    @Test
    fun `filters combine`() {
        val list = listOf(
            title("hit", year = 2015, genres = listOf("Comedy"), score = 8.1),
            title("lowScore", year = 2015, genres = listOf("Comedy"), score = 6.0),
            title("wrongDecade", year = 2005, genres = listOf("Comedy"), score = 9.0),
            title("wrongGenre", year = 2016, genres = listOf("Horror"), score = 9.0),
        )
        val f = TitleFilter(years = YearRange.Y2010S, genre = Genre.COMEDY, minRating = 7.0)
        assertEquals(listOf("hit"), ids(f.apply(list, today)))
    }

    @Test
    fun `tmdb params per kind`() {
        val newest = TitleFilter(sort = TitleSort.NEWEST, years = YearRange.Y2010S)
        assertEquals("primary_release_date.desc", newest.tmdbSort(MediaKind.MOVIE))
        assertEquals("first_air_date.desc", newest.tmdbSort(MediaKind.TV))
        val tv = newest.tmdbParams(MediaKind.TV, today = today)
        assertEquals("2010-01-01", tv["first_air_date.gte"])
        assertEquals("2019-12-31", tv["first_air_date.lte"])

        val thisYear = TitleFilter(sort = TitleSort.NEWEST, years = YearRange.THIS_YEAR).tmdbParams(MediaKind.MOVIE, today = today)
        assertEquals("2026-01-01", thisYear["primary_release_date.gte"])
        assertEquals("2026-11-03", thisYear["primary_release_date.lte"])

        val rated = TitleFilter(sort = TitleSort.RATING, minRating = 7.0).tmdbParams(MediaKind.MOVIE, today = today)
        assertEquals("vote_average.desc", TitleFilter(sort = TitleSort.RATING).tmdbSort(MediaKind.MOVIE))
        assertEquals("200", rated["vote_count.gte"])
        assertEquals("7", rated["vote_average.gte"])

        val floor = TitleFilter(minRating = 6.0).tmdbParams(MediaKind.TV, today = today)
        assertEquals("50", floor["vote_count.gte"])
        val moodFloor = TitleFilter(minRating = 6.0).tmdbParams(MediaKind.TV, mapOf("vote_count.gte" to "150"), today)
        assertEquals("150", moodFloor["vote_count.gte"])

        assertEquals("title.asc", TitleFilter(sort = TitleSort.TITLE).tmdbSort(MediaKind.MOVIE))
        assertEquals("name.asc", TitleFilter(sort = TitleSort.TITLE).tmdbSort(MediaKind.TV))
        assertNull(TitleFilter().tmdbParams(MediaKind.MOVIE, today = today)["primary_release_date.lte"])
    }
}
