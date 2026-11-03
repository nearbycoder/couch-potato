package com.nearbycoder.couchpotato

import android.content.Context
import com.nearbycoder.couchpotato.data.local.AppDatabase
import com.nearbycoder.couchpotato.data.local.SettingsRepository
import com.nearbycoder.couchpotato.data.remote.Http
import com.nearbycoder.couchpotato.domain.Catalog
import com.nearbycoder.couchpotato.domain.Library
import com.nearbycoder.couchpotato.domain.ai.AskFinder
import com.nearbycoder.couchpotato.domain.ai.OnDeviceAI
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Hand-rolled dependency container; one per process. */
class AppContainer(context: Context) {
    val appContext: Context = context.applicationContext
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val settings = SettingsRepository(appContext, scope)
    val database = AppDatabase.build(appContext)
    val library = Library(database, scope)
    val catalog = Catalog(settings.settings)

    /** On-device model (Gemini Nano). The client is created on first use. */
    val ai = OnDeviceAI(scope)
    val askFinder = AskFinder(catalog) { settings.current }

    init {
        Http.init(appContext)
    }
}
