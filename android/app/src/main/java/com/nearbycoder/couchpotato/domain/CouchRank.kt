package com.nearbycoder.couchpotato.domain

import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.local.SavedTitle

/** CouchRank: a light progression system based on what you've watched. */
class CouchRank(titles: List<SavedTitle>, nights: List<CouchNight>) {
    data class Level(val name: String, val threshold: Int, val quip: String)

    val points: Int
    val moviesWatched: Int
    val showsWatched: Int
    val hoursWatched: Int
    val ratedCount: Int
    val averageRating: Double?

    init {
        val watched = titles.filter { it.watchStatus == WatchStatus.WATCHED }
        moviesWatched = watched.count { it.mediaKind == MediaKind.MOVIE }
        showsWatched = watched.count { it.mediaKind == MediaKind.TV }
        val rated = titles.filter { it.rating > 0 }
        ratedCount = rated.size
        averageRating = if (rated.isEmpty()) null else rated.sumOf { it.rating }.toDouble() / rated.size
        val doneNights = nights.count { it.isDone }
        val episodes = titles.filter { it.mediaKind == MediaKind.TV }
            .sumOf { maxOf(0, it.lastEpisode) + maxOf(0, it.lastSeason - 1) * 8 }
        points = moviesWatched * 2 + showsWatched * 4 + rated.size + doneNights + episodes / 4
        val movieMinutes = watched.filter { it.mediaKind == MediaKind.MOVIE }.sumOf { it.runtime ?: 110 }
        val episodeMinutes = titles.filter { it.mediaKind == MediaKind.TV }.sumOf { t ->
            val eps = if (t.watchStatus == WatchStatus.WATCHED) maxOf(10, t.lastEpisode) else maxOf(0, t.lastEpisode)
            eps * (t.runtime ?: 45)
        }
        hoursWatched = (movieMinutes + episodeMinutes) / 60
    }

    val level: Level get() = levels.lastOrNull { points >= it.threshold } ?: levels[0]
    val nextLevel: Level? get() = levels.firstOrNull { it.threshold > points }

    val progressToNext: Float
        get() {
            val next = nextLevel ?: return 1f
            val span = (next.threshold - level.threshold).toFloat()
            return if (span <= 0f) 1f else ((points - level.threshold) / span).coerceIn(0f, 1f)
        }

    companion object {
        val levels: List<Level> = listOf(
            Level("Raw Spud", 0, "Freshly dug. The couch awaits."),
            Level("Tater Tot", 3, "Small, round, full of potential."),
            Level("Hash Brown", 10, "Crispy around the edges."),
            Level("Curly Fry", 25, "You've developed a twist."),
            Level("Baked Legend", 50, "Loaded with toppings and lore."),
            Level("Mashed Royalty", 100, "The couch bows to you."),
        )

        fun levelFor(points: Int): Level = levels.lastOrNull { points >= it.threshold } ?: levels[0]
    }
}
