package com.nearbycoder.couchpotato.ui.tonight

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.WatchStatus
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@Immutable
data class ServiceRow(val provider: Provider, val titles: List<CatalogTitle>)

@Immutable
data class TonightState(
    val loading: Boolean = true,
    val error: String? = null,
    val hasTmdb: Boolean = false,
    val nickname: String = "",
    val trending: List<CatalogTitle> = emptyList(),
    val fresh: List<CatalogTitle> = emptyList(),
    val serviceRows: List<ServiceRow> = emptyList(),
    val popularMovies: List<CatalogTitle> = emptyList(),
    val popularSeries: List<CatalogTitle> = emptyList(),
) {
    val hero: List<CatalogTitle> get() = trending.filter { it.backdropUrl != null || it.posterUrl != null }.take(8)
}

class TonightViewModel(private val container: AppContainer) : ViewModel() {
    private val catalog = container.catalog
    private val library = container.library

    private val _state = MutableStateFlow(TonightState())
    val state: StateFlow<TonightState> = _state
    val saved: StateFlow<List<SavedTitle>> = library.savedTitles

    private var loadJob: Job? = null

    init {
        viewModelScope.launch {
            container.settings.settings
                .map { Triple(it.myServiceIds, it.region, it.effectiveTmdbKey) to it.nickname }
                .distinctUntilChanged()
                .collect { (_, nickname) ->
                    _state.update { it.copy(nickname = nickname) }
                    load()
                }
        }
    }

    fun load() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val settings = container.settings.current
            _state.update { it.copy(loading = true, error = null, hasTmdb = settings.hasTmdb) }
            var firstError: String? = null
            fun fail(t: Throwable) { if (firstError == null) firstError = t.message ?: "Something went wrong." }

            val trendingJob = launch {
                runCatching { catalog.trending() }
                    .onSuccess { list -> _state.update { it.copy(trending = list) } }
                    .onFailure(::fail)
            }
            val freshJob = launch {
                runCatching { catalog.freshOnStreaming() }
                    .onSuccess { list -> _state.update { it.copy(fresh = list) } }
                    .onFailure(::fail)
            }
            val moviesJob = launch {
                runCatching { catalog.popular(MediaKind.MOVIE) }
                    .onSuccess { list -> _state.update { it.copy(popularMovies = list) } }
                    .onFailure(::fail)
            }
            val seriesJob = launch {
                runCatching { catalog.popular(MediaKind.TV) }
                    .onSuccess { list -> _state.update { it.copy(popularSeries = list) } }
                    .onFailure(::fail)
            }
            val services = settings.feedServices
            val serviceJobs = services.map { provider ->
                launch {
                    val titles = runCatching { catalog.onService(provider) }.getOrDefault(emptyList())
                    _state.update { s ->
                        val rows = (s.serviceRows.filter { it.provider != provider } + ServiceRow(provider, titles))
                            .filter { it.titles.isNotEmpty() }
                            .sortedBy { services.indexOf(it.provider) }
                        s.copy(serviceRows = rows)
                    }
                }
            }
            _state.update { it.copy(serviceRows = it.serviceRows.filter { row -> row.provider in services }) }
            (listOf(trendingJob, freshJob, moviesJob, seriesJob) + serviceJobs).forEach { it.join() }
            _state.update { s ->
                val nothingLoaded = s.trending.isEmpty() && s.popularMovies.isEmpty() && s.popularSeries.isEmpty()
                s.copy(loading = false, error = if (nothingLoaded) firstError else null)
            }
        }
    }

    fun toggleSave(title: CatalogTitle) {
        viewModelScope.launch {
            val existing = library.saved(title.ref.key)
            if (existing == null) library.save(title, WatchStatus.QUEUED) else library.remove(title.ref.key)
        }
    }
}
