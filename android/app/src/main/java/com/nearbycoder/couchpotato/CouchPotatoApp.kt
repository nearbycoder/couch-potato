package com.nearbycoder.couchpotato

import android.app.Application
import android.content.Context
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.disk.directory
import coil3.memory.MemoryCache
import coil3.request.crossfade
import com.nearbycoder.couchpotato.reminders.Reminders
import java.io.File

class CouchPotatoApp : Application(), SingletonImageLoader.Factory {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        Reminders.ensureChannel(this)
    }

    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .crossfade(250)
            .memoryCache {
                MemoryCache.Builder().maxSizePercent(context, 0.2).build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(File(cacheDir, "images"))
                    .maxSizeBytes(256L * 1024 * 1024)
                    .build()
            }
            .build()
}

val Context.appContainer: AppContainer
    get() = (applicationContext as CouchPotatoApp).container
