package com.nearbycoder.couchpotato

import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.Genre
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.TimeBudget
import com.nearbycoder.couchpotato.domain.TitleFilter
import com.nearbycoder.couchpotato.domain.TitleRef
import com.nearbycoder.couchpotato.domain.TitleSort
import com.nearbycoder.couchpotato.domain.YearRange
import com.nearbycoder.couchpotato.domain.ai.AskQuery
import com.nearbycoder.couchpotato.domain.ai.Prompts
import com.nearbycoder.couchpotato.domain.ai.mergeInterleaved
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AskQueryTest {
    private val full = """
        {"kind": "series", "genre": "scifi", "years": "last5", "minRating": 7, "sort": "rating",
         "mood": "brainy", "maxMinutes": 50, "services": ["netflix", "hbo"],
         "keywords": "", "summary": "Recent sci-fi series on Netflix"}
    """.trimIndent()

    private fun title(id: String, kind: MediaKind = MediaKind.TV, runtime: Int? = null) =
        CatalogTitle(ref = TitleRef(CatalogSource.TMDB, kind, id), name = "Title $id", runtime = runtime)

    // Parsing

    @Test fun parsesEveryField() {
        val q = AskQuery.parse(full)!!
        assertEquals(MediaKind.TV, q.kind)
        assertEquals(TitleFilter(sort = TitleSort.RATING, years = YearRange.LAST5, genre = Genre.SCIFI, minRating = 7.0), q.filter)
        assertEquals(Mood.BRAINY, q.mood)
        assertEquals(50, q.maxMinutes)
        assertEquals(listOf(Provider.netflix, Provider.hbo), q.services)
        assertEquals("", q.keywords)
        assertEquals("Recent sci-fi series on Netflix", q.summary)
    }

    @Test fun stripsCodeFencesAndSurroundingProse() {
        val fenced = "```json\n$full\n```"
        assertEquals(AskQuery.parse(full), AskQuery.parse(fenced))
        val chatty = "Sure! Here you go:\n```\n$full\n```\nEnjoy."
        assertEquals(AskQuery.parse(full), AskQuery.parse(chatty))
    }

    @Test fun returnsNullWithoutJson() {
        assertNull(AskQuery.parse("I'm not sure what you mean."))
        assertNull(AskQuery.parse("{ not json"))
        assertNull(AskQuery.parse(""))
    }

    @Test fun unknownValuesFallBackToDefaults() {
        val q = AskQuery.parse(
            """{"kind":"podcast","genre":"western","years":"1970s","minRating":"lots","sort":"random",
               "mood":"angry","maxMinutes":-5,"services":["myspace", 3],"extra":{"nested":true}}""",
        )!!
        assertNull(q.kind)
        assertEquals(TitleFilter(), q.filter)
        assertNull(q.mood)
        assertEquals(0, q.maxMinutes)
        assertTrue(q.services.isEmpty())
        assertEquals("", q.summary)
    }

    @Test fun emptyObjectIsAllDefaults() {
        assertEquals(AskQuery(), AskQuery.parse("{}"))
    }

    @Test fun mapsEnumNamesLeniently() {
        val q = AskQuery.parse(
            """{"kind":"Movie","genre":"Sci-Fi","years":"thisYear","minRating":"8","sort":"NEWEST","mood":"thrills","maxMinutes":"90"}""",
        )!!
        assertEquals(MediaKind.MOVIE, q.kind)
        assertEquals(Genre.SCIFI, q.filter.genre)
        assertEquals(YearRange.THIS_YEAR, q.filter.years)
        assertEquals(8.0, q.filter.minRating)
        assertEquals(TitleSort.NEWEST, q.filter.sort)
        assertEquals(Mood.THRILLS, q.mood)
        assertEquals(90, q.maxMinutes)
    }

    @Test fun mapsEveryYearRangeName() {
        val expected = mapOf(
            "any" to YearRange.ANY, "thisYear" to YearRange.THIS_YEAR, "last5" to YearRange.LAST5,
            "y2020s" to YearRange.Y2020S, "y2010s" to YearRange.Y2010S, "y2000s" to YearRange.Y2000S,
            "y1990s" to YearRange.Y1990S, "older" to YearRange.OLDER,
        )
        expected.forEach { (raw, range) -> assertEquals(raw, range, AskQuery.parse("""{"years":"$raw"}""")!!.filter.years) }
    }

    @Test fun mapsEveryGenreAndMoodName() {
        for (genre in Genre.entries) {
            assertEquals(genre, AskQuery.parse("""{"genre":"${genre.name.lowercase()}"}""")!!.filter.genre)
        }
        assertNull(AskQuery.parse("""{"genre":"none"}""")!!.filter.genre)
        for (mood in Mood.entries) {
            assertEquals(mood, AskQuery.parse("""{"mood":"${mood.name.lowercase()}"}""")!!.mood)
        }
        assertNull(AskQuery.parse("""{"mood":"none"}""")!!.mood)
    }

    @Test fun ratingSnapsToFilterFloors() {
        fun rating(v: String) = AskQuery.parse("""{"minRating":$v}""")!!.filter.minRating
        assertNull(rating("0"))
        assertNull(rating("5.5"))
        assertEquals(6.0, rating("6"))
        assertEquals(7.0, rating("7.5"))
        assertEquals(8.0, rating("9"))
        assertEquals(7.0, rating("75"))
    }

    @Test fun servicesAcceptIdsNamesAndCommaStrings() {
        val q = AskQuery.parse("""{"services":["Disney+","Prime Video","netflix","netflix"]}""")!!
        assertEquals(listOf(Provider.disney, Provider.prime, Provider.netflix), q.services)
        val s = AskQuery.parse("""{"services":"hulu, apple"}""")!!
        assertEquals(listOf(Provider.hulu, Provider.apple), s.services)
    }

    @Test fun fallbackSearchesTheUsersWords() {
        val q = AskQuery.fallback("  movies like Arrival ")
        assertEquals("movies like Arrival", q.keywords)
        assertEquals(TitleFilter(), q.filter)
        assertTrue(q.summary.contains("movies like Arrival"))
    }

    // Constraints against the request text

    private fun overfilled(extra: String = "") = AskQuery.parse(
        """{"kind":"series","genre":"mystery","years":"last5","minRating":6,"sort":"popular","mood":"cozy",
           "maxMinutes":60,"services":["netflix"],"keywords":"british mystery"$extra}""",
    )!!

    @Test fun dropsInventedFieldsForADescriptiveRequest() {
        val q = overfilled().constrained("a cozy british mystery series from the last few years")
        assertTrue(q.services.isEmpty())
        assertEquals(0, q.maxMinutes)
        assertNull(q.filter.minRating)
        assertEquals("", q.keywords)
        // What was asked for stays.
        assertEquals(Genre.MYSTERY, q.filter.genre)
        assertEquals(Mood.COZY, q.mood)
        assertEquals(YearRange.LAST5, q.filter.years)
        assertEquals(MediaKind.TV, q.kind)
    }

    @Test fun keepsServicesTheRequestNames() {
        val parsed = AskQuery.parse("""{"services":["netflix","hbo","disney","prime","apple"]}""")!!
        assertEquals(listOf(Provider.netflix), parsed.constrained("A thriller on Netflix").services)
        assertEquals(listOf(Provider.hbo), parsed.constrained("something on max tonight").services)
        assertEquals(emptyList<Provider>(), parsed.constrained("maximum fun").services)
        assertEquals(listOf(Provider.disney), parsed.constrained("anything on disney plus").services)
        assertEquals(listOf(Provider.prime), parsed.constrained("free with amazon").services)
        assertEquals(listOf(Provider.apple), parsed.constrained("best of Apple TV").services)
    }

    @Test fun keepsRuntimeOnlyWithATimeWordOrDigit() {
        val q = overfilled()
        assertEquals(60, q.constrained("Something funny under an hour").maxMinutes)
        assertEquals(60, q.constrained("a 90 minute movie").maxMinutes)
        assertEquals(60, q.constrained("something quick").maxMinutes)
        assertEquals(60, q.constrained("a short comedy").maxMinutes)
        assertEquals(0, q.constrained("a thriller").maxMinutes)
    }

    @Test fun keepsRatingOnlyWithAQualityWord() {
        val q = overfilled()
        assertEquals(6.0, q.constrained("Highly rated sci-fi").filter.minRating)
        assertEquals(6.0, q.constrained("award-winning drama").filter.minRating)
        assertEquals(6.0, q.constrained("the best heist movies").filter.minRating)
        assertNull(q.constrained("a heist movie").filter.minRating)
    }

    @Test fun keepsKeywordsOnlyForNonDescriptiveRequests() {
        val person = AskQuery.parse("""{"kind":"movie","keywords":"Tom Hanks"}""")!!
        assertEquals("Tom Hanks", person.constrained("movies with Tom Hanks").keywords)
        val bare = AskQuery.parse("""{"keywords":"heist"}""")!!
        assertEquals("heist", bare.constrained("heist").keywords)
        // Genre, mood, years or a named service make it descriptive: keywords go.
        val genre = AskQuery.parse("""{"genre":"crime","keywords":"heist"}""")!!
        assertEquals("", genre.constrained("a heist thriller").keywords)
        val service = AskQuery.parse("""{"services":["netflix"],"keywords":"heist"}""")!!
        assertEquals("", service.constrained("heist on netflix").keywords)
    }

    @Test fun matchesWholeWordsOnly() {
        val q = overfilled()
        // "min" and "top" inside other words don't count.
        assertEquals(0, q.constrained("a criminal mastermind").maxMinutes)
        assertNull(q.constrained("a stop-motion film").filter.minRating)
        assertEquals(listOf(Provider.paramount), AskQuery.parse("""{"services":["paramount"]}""")!!.constrained("on paramount+").services)
    }

    @Test fun relaxationsLoosenInOrder() {
        val q = AskQuery(
            filter = TitleFilter(years = YearRange.LAST5, minRating = 7.0, genre = Genre.DRAMA),
            maxMinutes = 90,
            services = listOf(Provider.netflix),
        )
        val steps = q.relaxations()
        assertEquals(5, steps.size)
        assertEquals(q, steps[0])
        assertEquals(0, steps[1].maxMinutes)
        assertEquals(7.0, steps[1].filter.minRating)
        assertNull(steps[2].filter.minRating)
        assertEquals(YearRange.LAST5, steps[2].filter.years)
        assertEquals(YearRange.ANY, steps[3].filter.years)
        assertEquals(listOf(Provider.netflix), steps[3].services)
        assertTrue(steps[4].services.isEmpty())
        // Genre is never relaxed.
        assertTrue(steps.all { it.filter.genre == Genre.DRAMA })
    }

    @Test fun relaxationsSkipNoOpSteps() {
        val q = AskQuery(filter = TitleFilter(years = YearRange.Y1990S))
        assertEquals(2, q.relaxations().size)
        assertEquals(1, AskQuery().relaxations().size)
    }

    // Local filtering and merging

    @Test fun runtimeAndKindChecks() {
        val q = AskQuery(kind = MediaKind.MOVIE, maxMinutes = 60)
        assertTrue(q.fitsRuntime(title("1", runtime = 45)))
        assertTrue(q.fitsRuntime(title("2", runtime = null)))
        assertFalse(q.fitsRuntime(title("3", runtime = 120)))
        assertTrue(AskQuery().fitsRuntime(title("4", runtime = 300)))
        assertTrue(q.fitsKind(title("5", kind = MediaKind.MOVIE)))
        assertFalse(q.fitsKind(title("6", kind = MediaKind.TV)))
    }

    @Test fun mergeInterleavesAndDedupes() {
        val a = listOf(title("1"), title("2"), title("3"))
        val b = listOf(title("2"), title("4"))
        val c = listOf(title("5"))
        assertEquals(listOf("1", "2", "5", "4", "3"), mergeInterleaved(listOf(a, b, c)).map { it.ref.id })
        assertTrue(mergeInterleaved(emptyList()).isEmpty())
    }

    @Test fun chipsDescribeTheInterpretation() {
        val q = AskQuery.parse(full)!!
        assertEquals(
            listOf("Series", "Sci-Fi & Fantasy", "Brainy", "Last 5 Years", "★ 7+", "Under 50m", "Netflix", "HBO Max", "Highest Rated"),
            q.chips,
        )
        assertTrue(AskQuery().chips.isEmpty())
    }

    // Prompts

    @Test fun askInstructionsListAllowedValues() {
        val text = Prompts.askInstructions()
        listOf("thisYear", "y1990s", "crunchyroll", "brainy", "reality", "maxMinutes", "Leave every field at its default").forEach {
            assertTrue(it, text.contains(it))
        }
    }

    @Test fun pitchRequestIncludesContext() {
        val t = CatalogTitle(
            ref = TitleRef(CatalogSource.TMDB, MediaKind.MOVIE, "1"), name = "Arrival", year = 2016,
            genres = listOf("Drama", "Science Fiction"), runtime = 116, overview = "A linguist is recruited.",
        )
        val text = Prompts.pitchRequest(t, Mood.BRAINY, TimeBudget.EVENING)
        assertTrue(text.contains("Title: Arrival"))
        assertTrue(text.contains("Year: 2016"))
        assertTrue(text.contains("Kind: movie"))
        assertTrue(text.contains("Runtime: 1h 56m"))
        assertTrue(text.contains("Premise: A linguist"))
        assertTrue(text.contains("Brainy"))
        assertTrue(text.contains("an evening"))
        assertFalse(Prompts.pitchRequest(t, null, TimeBudget.ALL_NIGHT).contains("Time available"))
    }

    @Test fun cleanPitchTidiesModelOutput() {
        assertEquals("A quiet, clever first-contact story.", Prompts.cleanPitch("\"A quiet, clever first-contact story.\" 👽 #scifi"))
        assertEquals("One. Two.", Prompts.cleanPitch("One. Two. Three."))
        assertEquals("Still streaming in", Prompts.cleanPitch("  Still   streaming in"))
        assertEquals("", Prompts.cleanPitch("   "))
    }

    @Test fun parseWithRequestAppliesConstraints() {
        val q = AskQuery.parse(full, "sci-fi series")
        assertNotNull(q)
        assertTrue(q!!.services.isEmpty())
        assertEquals(0, q.maxMinutes)
        assertNull(q.filter.minRating)
    }
}
