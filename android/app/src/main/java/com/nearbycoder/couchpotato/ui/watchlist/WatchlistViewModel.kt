package com.nearbycoder.couchpotato.ui.watchlist

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.WatchStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class WatchlistSort(val label: String) {
    RECENT("Recently added"),
    ALPHA("A to Z"),
    RATING("Rating"),
    YEAR("Year"),
}

@Immutable
data class WatchlistFilters(
    val status: WatchStatus = WatchStatus.QUEUED,
    val kind: MediaKind? = null,
    val service: Provider? = null,
    val sort: WatchlistSort = WatchlistSort.RECENT,
)

@Immutable
data class WatchlistState(
    val all: List<SavedTitle> = emptyList(),
    val status: WatchStatus = WatchStatus.QUEUED,
    val kind: MediaKind? = null,
    val service: Provider? = null,
    val sort: WatchlistSort = WatchlistSort.RECENT,
) {
    val counts: Map<WatchStatus, Int> get() = WatchStatus.entries.associateWith { s -> all.count { it.watchStatus == s } }

    val availableServices: List<Provider>
        get() = Provider.streamers.filter { p -> all.any { it.watchStatus == status && p.id in it.providerIds } }

    val visible: List<SavedTitle>
        get() {
            val filtered = all.filter { t ->
                t.watchStatus == status &&
                    (kind == null || t.mediaKind == kind) &&
                    (service == null || service.id in t.providerIds)
            }
            return when (sort) {
                WatchlistSort.RECENT -> filtered.sortedByDescending { it.addedAt }
                WatchlistSort.ALPHA -> filtered.sortedBy { it.name.lowercase() }
                WatchlistSort.RATING -> filtered.sortedWith(compareByDescending<SavedTitle> { it.rating }.thenByDescending { it.updatedAt })
                WatchlistSort.YEAR -> filtered.sortedWith(compareByDescending<SavedTitle> { it.year ?: 0 }.thenBy { it.name })
            }
        }
}

class WatchlistViewModel(private val container: AppContainer) : ViewModel() {
    private val filters = MutableStateFlow(WatchlistFilters())

    val state: StateFlow<WatchlistState> = combine(container.library.savedTitles, filters) { titles, f ->
        WatchlistState(all = titles, status = f.status, kind = f.kind, service = f.service, sort = f.sort)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), WatchlistState(all = container.library.savedTitles.value))

    fun setStatus(status: WatchStatus) = filters.update { it.copy(status = status, service = null) }
    fun setKind(kind: MediaKind?) = filters.update { it.copy(kind = kind) }
    fun setService(service: Provider?) = filters.update { it.copy(service = service) }
    fun setSort(sort: WatchlistSort) = filters.update { it.copy(sort = sort) }

    fun setTitleStatus(key: String, status: WatchStatus) {
        viewModelScope.launch { container.library.setStatus(key, status) }
    }

    fun remove(key: String) {
        viewModelScope.launch { container.library.remove(key) }
    }
}
