package com.nearbycoder.couchpotato.ui.settings

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.data.local.Settings
import com.nearbycoder.couchpotato.data.remote.TmdbClient
import com.nearbycoder.couchpotato.domain.Backup
import com.nearbycoder.couchpotato.domain.CouchRank
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.domain.ai.AiStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

sealed interface KeyStatus {
    data object Idle : KeyStatus
    data object Checking : KeyStatus
    data object Ok : KeyStatus
    data class Failed(val message: String) : KeyStatus
}

@Immutable
data class SettingsState(
    val settings: Settings = Settings(),
    val rank: CouchRank = CouchRank(emptyList(), emptyList()),
    val titleCount: Int = 0,
    val nightCount: Int = 0,
)

class SettingsViewModel(private val container: AppContainer) : ViewModel() {
    private val repo = container.settings

    val aiStatus: StateFlow<AiStatus> = container.ai.status

    init { container.ai.checkIfNeeded() }

    /** Runs in the app scope so the download survives leaving Settings. */
    fun downloadModel() = container.ai.startDownload()

    val state: StateFlow<SettingsState> = combine(repo.settings, container.library.savedTitles, container.library.couchNights) { s, titles, nights ->
        SettingsState(settings = s, rank = CouchRank(titles, nights), titleCount = titles.size, nightCount = nights.size)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SettingsState(settings = repo.current))

    private val _keyStatus = MutableStateFlow<KeyStatus>(KeyStatus.Idle)
    val keyStatus: StateFlow<KeyStatus> = _keyStatus

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message

    fun clearMessage() { _message.value = null }

    fun setNickname(v: String) = viewModelScope.launch { repo.setNickname(v) }
    fun toggleService(p: Provider) = viewModelScope.launch { repo.toggleService(p); container.catalog.reset() }
    fun setRegion(code: String) = viewModelScope.launch { repo.setRegion(code); container.catalog.reset() }
    fun setOnlyMyServices(v: Boolean) = viewModelScope.launch { repo.setOnlyMyServices(v); container.catalog.reset() }
    fun setRemindMinutes(v: Int) = viewModelScope.launch { repo.setRemindMinutesBefore(v) }
    fun setAddToCalendar(v: Boolean) = viewModelScope.launch { repo.setAddNightsToCalendar(v) }
    fun setNewEpisodeAlerts(v: Boolean) = viewModelScope.launch { repo.setNewEpisodeAlerts(v) }

    fun testKey(key: String) {
        val trimmed = key.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch {
            _keyStatus.value = KeyStatus.Checking
            runCatching { TmdbClient(trimmed, repo.current.region).validate() }
                .onSuccess {
                    repo.setTmdbKey(trimmed)
                    container.catalog.reset()
                    _keyStatus.value = KeyStatus.Ok
                }
                .onFailure { t -> _keyStatus.value = KeyStatus.Failed(t.message ?: "That key didn't work.") }
        }
    }

    fun removeKey() {
        viewModelScope.launch {
            repo.setTmdbKey("")
            container.catalog.reset()
            _keyStatus.value = KeyStatus.Idle
        }
    }

    suspend fun exportJson(): String = withContext(Dispatchers.IO) {
        Backup.export(container.library.allTitles(), container.library.allNights())
    }

    fun exportTo(context: Context, uri: Uri) {
        viewModelScope.launch {
            runCatching {
                val json = exportJson()
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { it.write(json.toByteArray()) } ?: error("Couldn't open file")
                }
            }.onSuccess { _message.value = "Exported ${state.value.titleCount} titles and ${state.value.nightCount} plans." }
                .onFailure { _message.value = "Export failed: ${it.message}" }
        }
    }

    /** Writes the backup into the cache dir for sharing; returns the file. */
    suspend fun exportToCache(context: Context): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, "couch-potato-backup.json")
        file.writeText(exportJson())
        file
    }

    fun importFrom(context: Context, uri: Uri) {
        viewModelScope.launch {
            runCatching {
                val text = withContext(Dispatchers.IO) {
                    context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } ?: error("Couldn't read file")
                }
                val imported = Backup.import(text)
                container.library.importTitles(imported.titles) to container.library.importNights(imported.nights)
            }.onSuccess { (titles, nights) -> _message.value = "Imported $titles new or updated titles and $nights plans." }
                .onFailure { _message.value = "Import failed: ${it.message}" }
        }
    }
}
