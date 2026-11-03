package com.nearbycoder.couchpotato.ui.browse

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.Provider
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@Immutable
data class BrowseState(
    val query: String = "",
    val kind: MediaKind? = null,
    val searching: Boolean = false,
    val results: List<CatalogTitle> = emptyList(),
    val error: String? = null,
) {
    val isIdle: Boolean get() = query.trim().length < 2
    val filtered: List<CatalogTitle> get() = kind?.let { k -> results.filter { it.kind == k } } ?: results
}

class BrowseViewModel(container: AppContainer) : ViewModel() {
    private val catalog = container.catalog
    private val _state = MutableStateFlow(BrowseState())
    val state: StateFlow<BrowseState> = _state
    private val queries = MutableStateFlow("")

    val suggestions = listOf("Severance", "The Bear", "Dune", "Shogun", "Succession", "Interstellar", "Fallout", "Past Lives")

    init {
        @OptIn(FlowPreview::class)
        viewModelScope.launch {
            queries.debounce(350).distinctUntilChanged().collect { q ->
                if (q.trim().length < 2) {
                    _state.update { it.copy(results = emptyList(), searching = false, error = null) }
                    return@collect
                }
                _state.update { it.copy(searching = true, error = null) }
                runCatching { catalog.search(q) }
                    .onSuccess { list -> _state.update { it.copy(results = list, searching = false) } }
                    .onFailure { t -> _state.update { it.copy(searching = false, error = t.message ?: "Search failed.") } }
            }
        }
    }

    fun setQuery(q: String) {
        _state.update { it.copy(query = q) }
        queries.value = q
    }

    fun setKind(kind: MediaKind?) = _state.update { it.copy(kind = kind) }
}

@Immutable
data class ListState(
    val loading: Boolean = true,
    val titles: List<CatalogTitle> = emptyList(),
    val kind: MediaKind? = null,
    val error: String? = null,
)

/** Grid for one service. */
class ServiceViewModel(container: AppContainer, val provider: Provider) : ViewModel() {
    private val catalog = container.catalog
    private val _state = MutableStateFlow(ListState())
    val state: StateFlow<ListState> = _state

    init { load() }

    fun setKind(kind: MediaKind?) {
        _state.update { it.copy(kind = kind) }
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching { catalog.onService(provider, _state.value.kind) }
                .onSuccess { list -> _state.update { it.copy(titles = list, loading = false) } }
                .onFailure { t -> _state.update { it.copy(loading = false, error = t.message ?: "Couldn't load titles.") } }
        }
    }
}

/** Grid for one mood. */
class MoodViewModel(container: AppContainer, val mood: Mood) : ViewModel() {
    private val catalog = container.catalog
    private val _state = MutableStateFlow(ListState())
    val state: StateFlow<ListState> = _state

    init { load() }

    fun setKind(kind: MediaKind?) {
        _state.update { it.copy(kind = kind) }
        load()
    }

    fun load() {
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            runCatching { catalog.mood(mood, _state.value.kind) }
                .onSuccess { list -> _state.update { it.copy(titles = list, loading = false) } }
                .onFailure { t -> _state.update { it.copy(loading = false, error = t.message ?: "Couldn't load titles.") } }
        }
    }
}
