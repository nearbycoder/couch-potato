package com.nearbycoder.couchpotato.ui.navigation

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.systemBars
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import com.nearbycoder.couchpotato.AppContainer

val LocalAppContainer = staticCompositionLocalOf<AppContainer> { error("AppContainer not provided") }

/** Cross-screen requests that don't belong in navigation arguments. */
@Stable
class AppEvents {
    /** Title key the Planner should open a "Plan a night" sheet for. */
    var pendingPlanKey by mutableStateOf<String?>(null)
}

val LocalAppEvents = compositionLocalOf { AppEvents() }

/** Current window width in dp, from the window container size. */
@Composable
fun windowWidthDp(): Float {
    val size = LocalWindowInfo.current.containerSize
    return with(LocalDensity.current) { size.width.toDp() }.value
}

/** True on tablets, desktops and unfolded foldables (width >= 600 dp). */
@Composable
fun isWideLayout(): Boolean = windowWidthDp() >= 600f

/** True on very wide windows (>= 840 dp), where two-pane detail layouts make sense. */
@Composable
fun isExpandedLayout(): Boolean = windowWidthDp() >= 840f

/** True when the app shows a navigation rail (>= 840 dp) instead of a bottom bar. */
@Composable
fun hasNavigationRail(): Boolean = windowWidthDp() >= 840f

/**
 * Insets a screen's Scaffold should pad for. Under a bottom bar the bar already covers the
 * navigation-bar inset, so only the status bar is needed; next to a rail both apply.
 */
@Composable
fun screenInsets(): WindowInsets = if (hasNavigationRail()) WindowInsets.systemBars else WindowInsets.statusBars

/** Insets for edge-to-edge screens (hero at the top): only the bottom system bar next to a rail. */
@Composable
fun edgeToEdgeInsets(): WindowInsets = if (hasNavigationRail()) WindowInsets.navigationBars else WindowInsets(0, 0, 0, 0)
