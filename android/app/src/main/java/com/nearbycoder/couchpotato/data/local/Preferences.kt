package com.nearbycoder.couchpotato.data.local

import android.content.Context
import androidx.compose.runtime.Immutable
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.nearbycoder.couchpotato.domain.Provider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.runBlocking
import java.util.Locale

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

@Immutable
data class Settings(
    val myServiceIds: Set<String> = emptySet(),
    val region: String = "US",
    val tmdbKey: String = "",
    val onlyMyServices: Boolean = false,
    val nickname: String = "",
    val remindMinutesBefore: Int = 15,
    val addNightsToCalendar: Boolean = false,
    val newEpisodeAlerts: Boolean = true,
    val hasOnboarded: Boolean = false,
) {
    val effectiveTmdbKey: String get() = tmdbKey.trim()
    val hasTmdb: Boolean get() = effectiveTmdbKey.isNotEmpty()
    val myServices: List<Provider> get() = Provider.streamers.filter { it.id in myServiceIds }

    /** Services the home feed is built around: yours, or a sensible default set. */
    val feedServices: List<Provider> get() = myServices.ifEmpty { Provider.defaults }

    fun isMine(provider: Provider): Boolean = provider.id in myServiceIds
}

/** User settings backed by DataStore Preferences. */
class SettingsRepository(context: Context, scope: CoroutineScope) {
    private val store = context.applicationContext.settingsStore

    private object Keys {
        val myServices = stringSetPreferencesKey("myServices")
        val region = stringPreferencesKey("region")
        val tmdbKey = stringPreferencesKey("tmdbKey")
        val onlyMyServices = booleanPreferencesKey("onlyMyServices")
        val nickname = stringPreferencesKey("nickname")
        val remindMinutesBefore = intPreferencesKey("remindMinutesBefore")
        val addNightsToCalendar = booleanPreferencesKey("addNightsToCalendar")
        val newEpisodeAlerts = booleanPreferencesKey("newEpisodeAlerts")
        val hasOnboarded = booleanPreferencesKey("hasOnboarded")
    }

    private val defaultRegion: String = Locale.getDefault().country
        .takeIf { code -> regions.any { it.code == code } } ?: "US"

    private fun Preferences.toSettings() = Settings(
        myServiceIds = this[Keys.myServices] ?: emptySet(),
        region = this[Keys.region]?.takeIf { code -> regions.any { it.code == code } } ?: defaultRegion,
        tmdbKey = this[Keys.tmdbKey] ?: "",
        onlyMyServices = this[Keys.onlyMyServices] ?: false,
        nickname = this[Keys.nickname] ?: "",
        remindMinutesBefore = this[Keys.remindMinutesBefore] ?: 15,
        addNightsToCalendar = this[Keys.addNightsToCalendar] ?: false,
        newEpisodeAlerts = this[Keys.newEpisodeAlerts] ?: true,
        hasOnboarded = this[Keys.hasOnboarded] ?: false,
    )

    val settings: StateFlow<Settings> = store.data
        .map { it.toSettings() }
        .stateIn(scope, SharingStarted.Eagerly, runBlocking { store.data.first().toSettings() })

    val current: Settings get() = settings.value

    suspend fun toggleService(provider: Provider) {
        store.edit { prefs ->
            val set = (prefs[Keys.myServices] ?: emptySet()).toMutableSet()
            if (!set.remove(provider.id)) set += provider.id
            prefs[Keys.myServices] = set
        }
    }

    suspend fun setRegion(code: String) = store.edit { it[Keys.region] = code }
    suspend fun setTmdbKey(key: String) = store.edit { it[Keys.tmdbKey] = key.trim() }
    suspend fun setOnlyMyServices(value: Boolean) = store.edit { it[Keys.onlyMyServices] = value }
    suspend fun setNickname(value: String) = store.edit { it[Keys.nickname] = value }
    suspend fun setRemindMinutesBefore(value: Int) = store.edit { it[Keys.remindMinutesBefore] = value }
    suspend fun setAddNightsToCalendar(value: Boolean) = store.edit { it[Keys.addNightsToCalendar] = value }
    suspend fun setNewEpisodeAlerts(value: Boolean) = store.edit { it[Keys.newEpisodeAlerts] = value }
    suspend fun setHasOnboarded(value: Boolean) = store.edit { it[Keys.hasOnboarded] = value }

    data class Region(val code: String, val name: String)

    companion object {
        val regions: List<Region> = listOf(
            Region("US", "United States"), Region("CA", "Canada"), Region("GB", "United Kingdom"),
            Region("AU", "Australia"), Region("NZ", "New Zealand"), Region("IE", "Ireland"),
            Region("DE", "Germany"), Region("FR", "France"), Region("ES", "Spain"), Region("IT", "Italy"),
            Region("NL", "Netherlands"), Region("SE", "Sweden"), Region("BR", "Brazil"), Region("MX", "Mexico"),
            Region("IN", "India"), Region("JP", "Japan"), Region("KR", "South Korea"),
        )
    }
}
