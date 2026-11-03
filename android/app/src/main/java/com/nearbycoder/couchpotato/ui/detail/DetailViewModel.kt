package com.nearbycoder.couchpotato.ui.detail

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.EpisodeInfo
import com.nearbycoder.couchpotato.domain.TitleDetail
import com.nearbycoder.couchpotato.domain.TitleRef
import com.nearbycoder.couchpotato.domain.WatchStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@Immutable
data class DetailState(
    val loading: Boolean = true,
    val error: String? = null,
    val detail: TitleDetail? = null,
    val selectedSeason: Int? = null,
    val episodes: List<EpisodeInfo> = emptyList(),
    val episodesLoading: Boolean = false,
    val usesTmdbAvailability: Boolean = false,
)

class DetailViewModel(private val container: AppContainer, private val key: String) : ViewModel() {
    private val catalog = container.catalog
    private val library = container.library
    val ref: TitleRef? = TitleRef.parse(key)

    private val _state = MutableStateFlow(DetailState())
    val state: StateFlow<DetailState> = _state

    val saved: StateFlow<SavedTitle?> = library.observe(key)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init { load() }

    fun load() {
        val ref = ref
        if (ref == null) {
            _state.update { it.copy(loading = false, error = "That link doesn't point at a title.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching { catalog.detail(ref) }
                .onSuccess { detail ->
                    val usesTmdb = detail.availability.offers.any { it.logoUrl != null } || ref.source.raw == "tmdb"
                    _state.update { it.copy(loading = false, detail = detail, usesTmdbAvailability = usesTmdb) }
                    // Keep the saved copy fresh with better artwork / runtime.
                    library.saved(key)?.let { existing -> library.update(existing.updated(detail.title)) }
                    val season = saved.value?.lastSeason?.takeIf { s -> s > 0 } ?: detail.seasons.firstOrNull()?.number
                    if (season != null) selectSeason(season)
                }
                .onFailure { t -> _state.update { it.copy(loading = false, error = t.message ?: "Couldn't load this title.") } }
        }
    }

    fun selectSeason(season: Int) {
        val detail = _state.value.detail ?: return
        val ref = ref ?: return
        _state.update { it.copy(selectedSeason = season, episodesLoading = true) }
        viewModelScope.launch {
            val eps = runCatching { catalog.episodes(ref, detail.title.name, season, detail.title.posterUrl) }.getOrDefault(emptyList())
            if (_state.value.selectedSeason == season) _state.update { it.copy(episodes = eps, episodesLoading = false) }
        }
    }

    fun save(status: WatchStatus = WatchStatus.QUEUED) {
        val title = _state.value.detail?.title ?: return
        viewModelScope.launch { library.save(title, status) }
    }

    fun setStatus(status: WatchStatus) {
        viewModelScope.launch {
            if (library.saved(key) == null) save(status) else library.setStatus(key, status)
        }
    }

    fun remove() {
        viewModelScope.launch { library.remove(key) }
    }

    fun setRating(rating: Int) {
        viewModelScope.launch { library.setRating(key, rating) }
    }

    fun setNotes(notes: String) {
        viewModelScope.launch { library.setNotes(key, notes) }
    }

    fun setFollowing(following: Boolean) {
        viewModelScope.launch { library.setFollowing(key, following) }
    }

    fun markWatchedThrough(episode: EpisodeInfo) {
        viewModelScope.launch {
            val existing = library.saved(key)
            if (existing == null) {
                val title = _state.value.detail?.title ?: return@launch
                library.save(title, WatchStatus.WATCHING)
            }
            val current = library.saved(key) ?: return@launch
            val already = current.lastSeason == episode.season && current.lastEpisode == episode.number
            if (already) {
                // Tapping the current mark steps back one episode.
                val prev = _state.value.episodes.filter { it.number < episode.number }.maxByOrNull { it.number }
                if (prev != null) library.setProgress(key, prev.season, prev.number) else library.setProgress(key, 0, 0)
            } else {
                library.setProgress(key, episode.season, episode.number)
            }
        }
    }
}
