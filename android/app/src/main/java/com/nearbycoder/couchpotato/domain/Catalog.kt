package com.nearbycoder.couchpotato.domain

import com.nearbycoder.couchpotato.data.local.Settings
import com.nearbycoder.couchpotato.data.remote.HttpException
import com.nearbycoder.couchpotato.data.remote.ITunesClient
import com.nearbycoder.couchpotato.data.remote.MissingKeyException
import com.nearbycoder.couchpotato.data.remote.TmdbClient
import com.nearbycoder.couchpotato.data.remote.TvMazeClient
import com.nearbycoder.couchpotato.data.remote.TvmScheduleItem
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate

/**
 * One front door to every data source. With a TMDB key it uses TMDB for discovery,
 * search and all-provider availability; without one it blends TVmaze (series) and
 * Apple's iTunes charts (movies). Titles from any source can always be opened.
 */
class Catalog(private val settingsFlow: StateFlow<Settings>) {
    private val tvmaze = TvMazeClient()

    private val memoLock = Mutex()
    private val memo = HashMap<String, List<CatalogTitle>>()
    private var tvPool: List<CatalogTitle>? = null
    private val moviePool = HashMap<String, CatalogTitle>()

    private val settings: Settings get() = settingsFlow.value

    val tmdb: TmdbClient?
        get() {
            val key = settings.effectiveTmdbKey
            return if (key.isEmpty()) null else TmdbClient(key, settings.region)
        }

    val hasTmdb: Boolean get() = tmdb != null

    private val itunes: ITunesClient get() = ITunesClient(settings.region.lowercase())

    /** Drops cached lists (e.g. after the region, key or services change). */
    suspend fun reset() {
        memoLock.withLock {
            memo.clear()
            tvPool = null
            moviePool.clear()
        }
    }

    private suspend fun remember(key: String, load: suspend () -> List<CatalogTitle>): List<CatalogTitle> {
        val fullKey = "$key|${settings.region}|$hasTmdb"
        memoLock.withLock { memo[fullKey] }?.let { return it }
        val value = load()
        memoLock.withLock { memo[fullKey] = value }
        return value
    }

    // Home rows

    suspend fun trending(): List<CatalogTitle> = remember("trending") {
        tmdb?.let { return@remember it.trending() }
        coroutineScope {
            val shows = async { openTvPool() }
            val movies = async { openMovies(null) }
            interleave(movies.await().take(15), shows.await().take(15))
        }
    }

    suspend fun freshOnStreaming(): List<CatalogTitle> = remember("fresh-${settings.myServiceIds.sorted()}") {
        tmdb?.let { return@remember it.freshOnStreaming(settings.myServices) }
        val items = ArrayList<TvmScheduleItem>()
        for (offset in listOf(0L, -1L, -2L)) {
            items += runCatching { tvmaze.schedule(LocalDate.now().plusDays(offset), web = true) }.getOrDefault(emptyList())
        }
        uniqueShows(items).filter { it.providers.isNotEmpty() }
    }

    suspend fun popular(kind: MediaKind): List<CatalogTitle> = remember("popular-${kind.raw}") {
        tmdb?.let { return@remember it.popular(kind) }
        if (kind == MediaKind.MOVIE) openMovies(null) else openTvPool()
    }

    suspend fun onService(provider: Provider, kind: MediaKind? = null): List<CatalogTitle> =
        remember("service-${provider.id}-${kind?.raw ?: "all"}") {
            tmdb?.let { client ->
                if (kind != null) return@remember client.discover(kind, listOf(provider))
                return@remember coroutineScope {
                    val movies = async { client.discover(MediaKind.MOVIE, listOf(provider)) }
                    val shows = async { client.discover(MediaKind.TV, listOf(provider)) }
                    interleave(shows.await(), movies.await())
                }
            }
            if (kind == MediaKind.MOVIE) return@remember emptyList()
            openTvPool().filter { provider in it.providers }
        }

    suspend fun mood(mood: Mood, kind: MediaKind? = null): List<CatalogTitle> =
        remember("mood-${mood.id}-${kind?.raw ?: "all"}-${settings.onlyMyServices}") {
            tmdb?.let { client ->
                val services = if (settings.onlyMyServices) settings.myServices else emptyList()
                val extra = mapOf<String, String?>("vote_count.gte" to "150")
                return@remember coroutineScope {
                    val movies = async {
                        if (kind == MediaKind.TV) emptyList() else client.discover(MediaKind.MOVIE, services, mood.tmdbMovieGenres, extra = extra)
                    }
                    val shows = async {
                        if (kind == MediaKind.MOVIE) emptyList() else client.discover(MediaKind.TV, services, mood.tmdbTvGenres, extra = extra)
                    }
                    interleave(movies.await(), shows.await())
                }
            }
            val movies = ArrayList<CatalogTitle>()
            if (kind != MediaKind.TV) {
                for (genre in mood.itunesGenreIds) movies += runCatching { openMovies(genre) }.getOrDefault(emptyList())
            }
            val shows = if (kind == MediaKind.MOVIE) emptyList() else openTvPool().filter(mood::matches)
            interleave(movies.distinctBy { it.id }, shows)
        }

    suspend fun search(text: String): List<CatalogTitle> {
        val query = text.trim()
        if (query.length < 2) return emptyList()
        tmdb?.let { return it.search(query) }
        return coroutineScope {
            val shows = async { tvmaze.search(query) }
            if (memoLock.withLock { moviePool.isEmpty() }) runCatching { openMovies(null) }
            val needle = query.lowercase()
            val movies = memoLock.withLock { moviePool.values.filter { it.name.lowercase().contains(needle) } }
            interleave(movies.sortedByDescending { it.popularity }, shows.await())
        }
    }

    // Details

    suspend fun detail(ref: TitleRef): TitleDetail = when (ref.source) {
        CatalogSource.TMDB -> (tmdb ?: throw MissingKeyException()).detail(ref)
        CatalogSource.TVMAZE -> {
            val (show, detail) = tvmaze.detail(ref.id)
            val showGenres = (show.genres ?: emptyList()).toSet()
            val similar = runCatching { openTvPool() }.getOrDefault(emptyList())
                .filter { it.ref != ref && it.genres.any { g -> g in showGenres } }
                .take(15)
            val enriched = tmdbAvailability(show.externals?.imdb)
            detail.copy(similar = similar, availability = enriched ?: detail.availability)
        }
        CatalogSource.ITUNES -> {
            val (title, track) = itunes.lookup(ref.id)
            var availability = track.availability()
            tmdb?.let { client ->
                val match = runCatching { client.searchMovie(title.name, title.year) }.getOrNull()
                val tmdbAvailability = match?.let { runCatching { client.availability(it.ref) }.getOrNull() }
                if (tmdbAvailability != null) {
                    // Keep Apple's exact prices, add everything else TMDB knows about.
                    val merged = availability.offers + tmdbAvailability.offers.filter { it.provider != Provider.appleStore }
                    availability = availability.copy(offers = merged.sortedBy { it.kind.ordinal })
                }
            }
            val titleGenres = title.genres.toSet()
            val similar = runCatching { openMovies(null) }.getOrDefault(emptyList())
                .filter { it.ref != ref && it.genres.any { g -> g in titleGenres } }
                .take(15)
            TitleDetail(
                title = title, availability = availability, similar = similar,
                trailerUrl = track.previewUrl, creators = track.artistName?.let { listOf(it) } ?: emptyList(),
            )
        }
    }

    private suspend fun tmdbAvailability(imdbId: String?): Availability? {
        val client = tmdb ?: return null
        if (imdbId.isNullOrEmpty()) return null
        val match = runCatching { client.find(imdbId) }.getOrNull() ?: return null
        val availability = runCatching { client.availability(match.ref) }.getOrNull() ?: return null
        return if (availability.isEmpty) null else availability
    }

    suspend fun episodes(ref: TitleRef, showName: String, season: Int, poster: String?): List<EpisodeInfo> =
        when (ref.source) {
            CatalogSource.TMDB -> (tmdb ?: throw MissingKeyException()).episodes(ref.id, showName, season, poster)
            CatalogSource.TVMAZE -> {
                val show = CatalogTitle(ref = ref, name = showName, posterUrl = poster)
                tvmaze.episodes(ref.id).filter { it.season == season }.map { it.episodeInfo(show) }
            }
            CatalogSource.ITUNES -> emptyList()
        }

    /** Future episodes for a followed show, soonest first. */
    suspend fun upcomingEpisodes(ref: TitleRef, showName: String, poster: String?): List<EpisodeInfo> {
        val today = LocalDate.now()
        return when (ref.source) {
            CatalogSource.TMDB -> runCatching { tmdb?.upcomingEpisodes(ref.id) }.getOrNull() ?: emptyList()
            CatalogSource.TVMAZE -> {
                val show = CatalogTitle(ref = ref, name = showName, posterUrl = poster)
                val all = runCatching { tvmaze.episodes(ref.id) }.getOrDefault(emptyList())
                all.map { it.episodeInfo(show) }.filter { (it.airDate ?: LocalDate.MIN) >= today }
            }
            CatalogSource.ITUNES -> emptyList()
        }
    }

    // Key-less pools

    /** Shows airing now across streamers + US networks, most popular first. */
    private suspend fun openTvPool(): List<CatalogTitle> {
        memoLock.withLock { tvPool }?.let { return it }
        val today = LocalDate.now()
        val days = (-6L..1L).map { today.plusDays(it) }
        val items = coroutineScope {
            val web = days.map { day -> async { runCatching { tvmaze.schedule(day, web = true) }.getOrDefault(emptyList()) } }
            val broadcast = days.takeLast(3).map { day -> async { runCatching { tvmaze.schedule(day, web = false) }.getOrDefault(emptyList()) } }
            (web + broadcast).flatMap { it.await() }
        }
        val pool = uniqueShows(items).filter { it.posterUrl != null }
        if (pool.isEmpty()) throw HttpException(503)
        memoLock.withLock { tvPool = pool }
        return pool
    }

    private suspend fun openMovies(genre: Int?): List<CatalogTitle> = remember("itunes-${genre ?: 0}") {
        val movies = itunes.topMovies(genre)
        memoLock.withLock { for (movie in movies) moviePool[movie.id] = movie }
        movies
    }

    private fun uniqueShows(items: List<TvmScheduleItem>): List<CatalogTitle> {
        val seen = HashSet<Int>()
        return items.mapNotNull { it.resolvedShow }
            .filter { seen.add(it.id) && (it.language ?: "English") == "English" }
            .map { it.catalogTitle }
            .sortedByDescending { it.popularity }
    }
}
