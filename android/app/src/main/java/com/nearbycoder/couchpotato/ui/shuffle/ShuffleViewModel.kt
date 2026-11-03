package com.nearbycoder.couchpotato.ui.shuffle

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.TimeBudget
import com.nearbycoder.couchpotato.domain.WatchStatus
import com.nearbycoder.couchpotato.domain.ai.AiStatus
import com.nearbycoder.couchpotato.domain.ai.Prompts
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class ShufflePool(val label: String) { WATCHLIST("Watchlist"), DISCOVER("Discover") }

@Immutable
data class ShuffleState(
    val pool: ShufflePool = ShufflePool.WATCHLIST,
    val mood: Mood? = null,
    val budget: TimeBudget = TimeBudget.ALL_NIGHT,
    val loading: Boolean = false,
    val candidates: List<CatalogTitle> = emptyList(),
    val error: String? = null,
    val spinning: Boolean = false,
    val winner: CatalogTitle? = null,
    val spinId: Int = 0,
    /** "Why tonight": a short on-device pitch for the winner; null when unavailable. */
    val pitch: String? = null,
    val pitchLoading: Boolean = false,
)

class ShuffleViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(ShuffleState())
    val state: StateFlow<ShuffleState> = _state

    private var pitchJob: Job? = null

    init {
        container.ai.checkIfNeeded()
        refresh()
    }

    fun setPool(pool: ShufflePool) { clearPitch(); _state.update { it.copy(pool = pool, winner = null) }; refresh() }
    fun setMood(mood: Mood?) { clearPitch(); _state.update { it.copy(mood = mood, winner = null) }; refresh() }
    fun setBudget(budget: TimeBudget) { clearPitch(); _state.update { it.copy(budget = budget, winner = null) }; refresh() }

    fun refresh() {
        viewModelScope.launch {
            val s = _state.value
            _state.update { it.copy(loading = true, error = null) }
            val result = runCatching {
                when (s.pool) {
                    ShufflePool.WATCHLIST -> container.library.savedTitles.value
                        .filter { it.watchStatus == WatchStatus.QUEUED || it.watchStatus == WatchStatus.WATCHING }
                        .map { it.asCatalogTitle }
                        .filter { s.mood == null || s.mood.matches(it) }
                    ShufflePool.DISCOVER -> {
                        val mood = s.mood
                        val base = if (mood != null) container.catalog.mood(mood) else {
                            val a = container.catalog.trending()
                            val b = runCatching { container.catalog.popular(MediaKind.MOVIE) }.getOrDefault(emptyList())
                            val c = runCatching { container.catalog.popular(MediaKind.TV) }.getOrDefault(emptyList())
                            (a + b + c).distinctBy { it.id }
                        }
                        base
                    }
                }.filter { it.posterUrl != null && s.budget.fits(it.runtime) }
            }
            result
                .onSuccess { list -> _state.update { it.copy(loading = false, candidates = list.shuffled()) } }
                .onFailure { t -> _state.update { it.copy(loading = false, error = t.message ?: "Couldn't build a pool.") } }
        }
    }

    fun spin() {
        val s = _state.value
        if (s.candidates.isEmpty() || s.spinning) return
        clearPitch()
        _state.update { it.copy(spinning = true, winner = null, spinId = it.spinId + 1, candidates = it.candidates.shuffled()) }
    }

    fun land(winner: CatalogTitle) {
        _state.update { it.copy(spinning = false, winner = winner) }
        startPitch(winner)
    }

    /** Streams a short pitch for [winner] when the on-device model is ready. Silent on failure. */
    private fun startPitch(winner: CatalogTitle) {
        clearPitch()
        if (container.ai.status.value !is AiStatus.Ready) return
        val s = _state.value
        pitchJob = viewModelScope.launch {
            _state.update { it.copy(pitchLoading = true) }
            try {
                container.ai.stream(
                    prompt = Prompts.pitchRequest(winner, s.mood, s.budget),
                    instructions = Prompts.PITCH_INSTRUCTIONS,
                    temperature = 0.7f,
                    maxTokens = 96,
                ).collect { text ->
                    val clean = Prompts.cleanPitch(text)
                    if (clean.isNotEmpty() && _state.value.winner?.id == winner.id) _state.update { it.copy(pitch = clean) }
                }
                _state.update { it.copy(pitchLoading = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                _state.update { it.copy(pitch = null, pitchLoading = false) }
            }
        }
    }

    private fun clearPitch() {
        pitchJob?.cancel()
        pitchJob = null
        _state.update { it.copy(pitch = null, pitchLoading = false) }
    }

    fun watchNow(title: CatalogTitle, done: () -> Unit) {
        viewModelScope.launch {
            container.library.save(title, WatchStatus.WATCHING)
            done()
        }
    }

    fun ensureSaved(title: CatalogTitle, done: () -> Unit) {
        viewModelScope.launch {
            if (container.library.saved(title.ref.key) == null) container.library.save(title, WatchStatus.QUEUED)
            done()
        }
    }
}
