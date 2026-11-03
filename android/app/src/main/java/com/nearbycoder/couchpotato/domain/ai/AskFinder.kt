package com.nearbycoder.couchpotato.domain.ai

import com.nearbycoder.couchpotato.data.local.Settings
import com.nearbycoder.couchpotato.domain.Catalog
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Provider
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/** What a search found, and the (possibly relaxed) query that found it. */
data class AskResult(val query: AskQuery, val titles: List<CatalogTitle>, val relaxed: Boolean)

/** Turns an [AskQuery] into titles using the regular catalog. Same pipeline as the Apple app. */
class AskFinder(private val catalog: Catalog, private val settings: () -> Settings) {

    /**
     * Runs [query], loosening it step by step until something matches. A step that fails is
     * skipped; the last error is thrown only if no step found anything.
     */
    suspend fun find(query: AskQuery): AskResult {
        var lastError: Throwable? = null
        for ((index, step) in query.relaxations().withIndex()) {
            val titles = attempt { fetch(step) }
                .onFailure { lastError = it }
                .getOrDefault(emptyList())
                .filter(step::fitsRuntime)
                .distinctBy { it.id }
                .take(AskQuery.MAX_RESULTS)
            if (titles.isNotEmpty()) return AskResult(step, titles, relaxed = index > 0)
        }
        lastError?.let { throw it }
        return AskResult(query, emptyList(), relaxed = false)
    }

    private suspend fun fetch(q: AskQuery): List<CatalogTitle> = when {
        // a. Named services.
        q.services.isNotEmpty() -> onServices(q, q.services)
        // b. A genre across your services.
        q.filter.genre != null -> broad(q)
        // c. A mood.
        q.mood != null -> catalog.mood(q.mood, q.kind, page = 1, filter = q.filter)
        // d. A specific title, person or topic.
        q.keywords.isNotBlank() -> q.filter.apply(catalog.search(q.keywords).filter(q::fitsKind))
        // e. Anything popular on your services.
        else -> broad(q)
    }

    /** Your services (or the first six streamers), plus popular movies when there's no TMDB key. */
    private suspend fun broad(q: AskQuery): List<CatalogTitle> {
        val services = settings().myServices.ifEmpty { Provider.streamers.take(6) }
        val includeMovies = q.kind != MediaKind.TV && !catalog.hasTmdb
        return coroutineScope {
            val onServices = async { onServices(q, services) }
            val movies = async {
                if (!includeMovies) emptyList() else attempt { q.filter.apply(catalog.popular(MediaKind.MOVIE)) }.getOrDefault(emptyList())
            }
            // Key-less service pages are series only; movies from the charts follow them.
            onServices.await() + movies.await()
        }
    }

    /** One page from each service, interleaved. Fails only if every service fails. */
    private suspend fun onServices(q: AskQuery, services: List<Provider>): List<CatalogTitle> = coroutineScope {
        val pages = services.map { p -> async { attempt { catalog.onService(p, q.kind, page = 1, filter = q.filter) } } }.awaitAll()
        val lists = pages.mapNotNull { it.getOrNull() }
        if (lists.isEmpty()) pages.firstNotNullOfOrNull { it.exceptionOrNull() }?.let { throw it }
        mergeInterleaved(lists).filter(q::fitsKind)
    }

    private inline fun <T> attempt(block: () -> T): Result<T> = try {
        Result.success(block())
    } catch (e: CancellationException) {
        throw e
    } catch (t: Throwable) {
        Result.failure(t)
    }
}
