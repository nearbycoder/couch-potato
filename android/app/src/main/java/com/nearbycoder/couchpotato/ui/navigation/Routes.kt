package com.nearbycoder.couchpotato.ui.navigation

import kotlinx.serialization.Serializable

@Serializable
object TonightRoute

@Serializable
object BrowseRoute

@Serializable
object WatchlistRoute

@Serializable
object PlannerRoute

@Serializable
object ShuffleRoute

@Serializable
object SettingsRoute

@Serializable
data class DetailRoute(val key: String)

@Serializable
data class ServiceRoute(val providerId: String)

@Serializable
data class MoodRoute(val moodId: String)
