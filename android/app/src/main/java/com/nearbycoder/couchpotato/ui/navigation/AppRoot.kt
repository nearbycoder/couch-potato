package com.nearbycoder.couchpotato.ui.navigation

import android.net.Uri
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.outlined.Bookmarks
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.ShortNavigationBarItemDefaults
import androidx.compose.material3.WideNavigationRailDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.nearbycoder.couchpotato.AppContainer
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.ui.browse.BrowseScreen
import com.nearbycoder.couchpotato.ui.browse.MoodScreen
import com.nearbycoder.couchpotato.ui.browse.ServiceScreen
import com.nearbycoder.couchpotato.ui.detail.DetailScreen
import com.nearbycoder.couchpotato.ui.planner.PlannerScreen
import com.nearbycoder.couchpotato.ui.settings.SettingsScreen
import com.nearbycoder.couchpotato.ui.shuffle.ShuffleScreen
import com.nearbycoder.couchpotato.ui.theme.Couch
import com.nearbycoder.couchpotato.ui.tonight.TonightScreen
import com.nearbycoder.couchpotato.ui.watchlist.WatchlistScreen
import kotlin.reflect.KClass

private data class TopLevel(
    val route: Any,
    val routeClass: KClass<*>,
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector,
)

private val topLevels = listOf(
    TopLevel(TonightRoute, TonightRoute::class, "Tonight", Icons.Outlined.Home, Icons.Filled.Home),
    TopLevel(BrowseRoute, BrowseRoute::class, "Browse", Icons.Outlined.Search, Icons.Filled.Search),
    TopLevel(WatchlistRoute, WatchlistRoute::class, "Watchlist", Icons.Outlined.Bookmarks, Icons.Filled.Bookmarks),
    TopLevel(PlannerRoute, PlannerRoute::class, "Planner", Icons.Outlined.CalendarMonth, Icons.Filled.CalendarMonth),
    TopLevel(ShuffleRoute, ShuffleRoute::class, "Shuffle", Icons.Outlined.Shuffle, Icons.Filled.Shuffle),
)

/** Navigation actions shared by every screen. */
@Composable
fun rememberNavActions(navController: NavHostController): NavActions = remember(navController) { NavActions(navController) }

class NavActions(private val nav: NavHostController) {
    fun openTitle(key: String) = nav.navigate(DetailRoute(key))
    fun openService(provider: Provider) = nav.navigate(ServiceRoute(provider.id))
    fun openMood(mood: Mood) = nav.navigate(MoodRoute(mood.id))
    fun openSettings() = nav.navigate(SettingsRoute)
    fun back() { nav.popBackStack() }

    fun selectTab(route: Any) {
        nav.navigate(route) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppRoot(container: AppContainer, deepLink: Uri?, onDeepLinkConsumed: () -> Unit) {
    val navController = rememberNavController()
    val actions = rememberNavActions(navController)
    val events = remember { AppEvents() }
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = backStackEntry?.destination
    val colors = Couch.colors
    val widthDp = windowWidthDp()
    val suiteType = when {
        widthDp >= 840f -> NavigationSuiteType.WideNavigationRailCollapsed
        widthDp >= 600f -> NavigationSuiteType.ShortNavigationBarMedium
        else -> NavigationSuiteType.ShortNavigationBarCompact
    }

    LaunchedEffect(deepLink) {
        val uri = deepLink ?: return@LaunchedEffect
        when (uri.host) {
            "title" -> uri.pathSegments.firstOrNull()?.let { actions.openTitle(it) }
            "shuffle" -> actions.selectTab(ShuffleRoute)
            "planner" -> actions.selectTab(PlannerRoute)
            "watchlist" -> actions.selectTab(WatchlistRoute)
            "browse" -> actions.selectTab(BrowseRoute)
            else -> actions.selectTab(TonightRoute)
        }
        onDeepLinkConsumed()
    }

    val itemColors = ShortNavigationBarItemDefaults.colors(
        selectedIconColor = colors.accent,
        selectedTextColorTopIconPosition = colors.textPrimary,
        selectedTextColorStartIconPosition = colors.textPrimary,
        selectedIndicatorColor = colors.accent.copy(alpha = 0.16f),
        unselectedIconColor = colors.textSecondary,
        unselectedTextColor = colors.textSecondary,
    )

    CompositionLocalProvider(LocalAppContainer provides container, LocalAppEvents provides events) {
        NavigationSuiteScaffold(
            navigationItems = {
                topLevels.forEach { item ->
                    val selected = currentDestination?.hierarchy?.any { it.hasRoute(item.routeClass) } == true
                    NavigationSuiteItem(
                        selected = selected,
                        onClick = { actions.selectTab(item.route) },
                        icon = { Icon(if (selected) item.selectedIcon else item.icon, contentDescription = item.label) },
                        label = { Text(item.label) },
                        navigationSuiteType = suiteType,
                        colors = itemColors,
                    )
                }
            },
            navigationSuiteType = suiteType,
            navigationSuiteColors = NavigationSuiteDefaults.colors(
                navigationBarContainerColor = colors.surface,
                navigationRailContainerColor = colors.surface,
                shortNavigationBarContainerColor = colors.surface,
                wideNavigationRailColors = WideNavigationRailDefaults.colors(containerColor = colors.surface),
            ),
            containerColor = colors.bg,
            contentColor = colors.textPrimary,
        ) {
            NavHost(
                navController = navController,
                startDestination = TonightRoute,
                modifier = Modifier.fillMaxSize(),
                enterTransition = { fadeIn(tween(220)) + slideInHorizontally(tween(260)) { it / 12 } },
                exitTransition = { fadeOut(tween(180)) },
                popEnterTransition = { fadeIn(tween(220)) },
                popExitTransition = { fadeOut(tween(180)) + slideOutHorizontally(tween(260)) { it / 12 } },
            ) {
                composable<TonightRoute> { TonightScreen(actions) }
                composable<BrowseRoute> { BrowseScreen(actions) }
                composable<WatchlistRoute> { WatchlistScreen(actions) }
                composable<PlannerRoute> { PlannerScreen(actions) }
                composable<ShuffleRoute> { ShuffleScreen(actions) }
                composable<SettingsRoute> { SettingsScreen(actions) }
                composable<DetailRoute> { entry ->
                    val route = entry.toRoute<DetailRoute>()
                    DetailScreen(titleKey = route.key, actions = actions)
                }
                composable<ServiceRoute> { entry ->
                    val route = entry.toRoute<ServiceRoute>()
                    ServiceScreen(providerId = route.providerId, actions = actions)
                }
                composable<MoodRoute> { entry ->
                    val route = entry.toRoute<MoodRoute>()
                    MoodScreen(moodId = route.moodId, actions = actions)
                }
            }
        }
    }
}
