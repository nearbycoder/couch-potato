package com.nearbycoder.couchpotato.ui.planner

import android.content.Context
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.EpisodeInfo
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.reminders.Reminders
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate

@Immutable
data class PlannerState(
    val nights: List<CouchNight> = emptyList(),
    val saved: List<SavedTitle> = emptyList(),
    val selectedDay: LocalDate = LocalDate.now(),
    val weekStart: LocalDate = LocalDate.now(),
    val upcoming: List<EpisodeInfo> = emptyList(),
    val upcomingLoading: Boolean = false,
)

class PlannerViewModel(private val container: AppContainer) : ViewModel() {
    private val library = container.library
    private val selection = MutableStateFlow(LocalDate.now() to LocalDate.now().minusDays(3))
    private val upcoming = MutableStateFlow<List<EpisodeInfo>>(emptyList())
    private val upcomingLoading = MutableStateFlow(false)

    val state: StateFlow<PlannerState> = combine(
        library.couchNights, library.savedTitles, selection, upcoming, upcomingLoading,
    ) { nights, saved, (day, weekStart), eps, loading ->
        PlannerState(nights = nights, saved = saved, selectedDay = day, weekStart = weekStart, upcoming = eps, upcomingLoading = loading)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlannerState())

    private var loadedFollowKeys: Set<String> = emptySet()

    init {
        viewModelScope.launch {
            library.savedTitles.collect { titles ->
                val followed = titles.filter { it.mediaKind == MediaKind.TV && it.isFollowing && it.watchStatus.raw != "dropped" }
                val keys = followed.map { it.key }.toSet()
                if (keys != loadedFollowKeys) {
                    loadedFollowKeys = keys
                    loadUpcoming(followed)
                }
            }
        }
    }

    private fun loadUpcoming(followed: List<SavedTitle>) {
        viewModelScope.launch {
            upcomingLoading.value = true
            val all = ArrayList<EpisodeInfo>()
            for (show in followed.take(12)) {
                all += container.catalog.upcomingEpisodes(show.ref, show.name, show.posterUrl).take(3)
            }
            upcoming.value = all.sortedWith(compareBy({ it.airDate }, { it.showName })).take(20)
            upcomingLoading.value = false
        }
    }

    fun selectDay(day: LocalDate) = selection.update { it.copy(first = day) }
    fun shiftWeek(days: Long) = selection.update { (day, start) -> day.plusDays(days) to start.plusDays(days) }

    fun add(context: Context, night: CouchNight) {
        viewModelScope.launch {
            library.addNight(night)
            Reminders.schedule(context, night, container.settings.current.remindMinutesBefore)
        }
    }

    fun toggleDone(context: Context, night: CouchNight) {
        viewModelScope.launch {
            val updated = night.copy(isDone = !night.isDone)
            library.updateNight(updated)
            Reminders.schedule(context, updated, container.settings.current.remindMinutesBefore)
        }
    }

    fun delete(context: Context, night: CouchNight) {
        viewModelScope.launch {
            Reminders.cancel(context, night)
            library.deleteNight(night)
        }
    }
}
