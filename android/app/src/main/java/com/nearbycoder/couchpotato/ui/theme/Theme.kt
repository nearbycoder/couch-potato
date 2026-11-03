package com.nearbycoder.couchpotato.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nearbycoder.couchpotato.domain.WatchStatus

/** Design tokens from DESIGN.md. */
@Immutable
data class CouchColors(
    val isDark: Boolean,
    val bg: Color,
    val surface: Color,
    val surfaceElevated: Color,
    val hairline: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val textTertiary: Color,
    val accent: Color,
    val onAccent: Color,
    val success: Color,
    val danger: Color,
    val info: Color,
    /** Secondary button fill: white 12% (dark) / black 6% (light). */
    val secondaryFill: Color,
    val shadow: Color,
) {
    fun statusColor(status: WatchStatus): Color = when (status) {
        WatchStatus.QUEUED -> info
        WatchStatus.WATCHING -> accent
        WatchStatus.WATCHED -> success
        WatchStatus.DROPPED -> textTertiary
    }
}

val DarkCouchColors = CouchColors(
    isDark = true,
    bg = Color(0xFF0C0C10),
    surface = Color(0xFF15151B),
    surfaceElevated = Color(0xFF1D1D25),
    hairline = Color(0x14FFFFFF),
    textPrimary = Color(0xFFF5F5F7),
    textSecondary = Color(0x9EF5F5F7),
    textTertiary = Color(0x66F5F5F7),
    accent = Color(0xFFF0A335),
    onAccent = Color(0xFF1A1200),
    success = Color(0xFF3DD68C),
    danger = Color(0xFFF2545B),
    info = Color(0xFF4C8DFF),
    secondaryFill = Color(0x1FFFFFFF),
    shadow = Color(0x73000000),
)

val LightCouchColors = CouchColors(
    isDark = false,
    bg = Color(0xFFF5F5F7),
    surface = Color(0xFFFFFFFF),
    surfaceElevated = Color(0xFFFFFFFF),
    hairline = Color(0x14000000),
    textPrimary = Color(0xFF111114),
    textSecondary = Color(0x9E111114),
    textTertiary = Color(0x66111114),
    accent = Color(0xFFD98A1C),
    onAccent = Color(0xFF1A1200),
    success = Color(0xFF1E9E62),
    danger = Color(0xFFD63E45),
    info = Color(0xFF2F6FE0),
    secondaryFill = Color(0x0F000000),
    shadow = Color(0x1A000000),
)

val LocalCouchColors = staticCompositionLocalOf { DarkCouchColors }

object Couch {
    val colors: CouchColors
        @Composable @ReadOnlyComposable get() = LocalCouchColors.current
}

private fun schemeFor(c: CouchColors): ColorScheme {
    val base = if (c.isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = c.accent,
        onPrimary = c.onAccent,
        primaryContainer = c.accent.copy(alpha = 0.18f),
        onPrimaryContainer = c.accent,
        secondary = c.accent,
        onSecondary = c.onAccent,
        secondaryContainer = c.accent.copy(alpha = 0.18f),
        onSecondaryContainer = c.accent,
        tertiary = c.info,
        onTertiary = Color.White,
        tertiaryContainer = c.info.copy(alpha = 0.18f),
        onTertiaryContainer = c.info,
        error = c.danger,
        onError = Color.White,
        errorContainer = c.danger.copy(alpha = 0.18f),
        onErrorContainer = c.danger,
        background = c.bg,
        onBackground = c.textPrimary,
        surface = c.bg,
        onSurface = c.textPrimary,
        surfaceVariant = c.surfaceElevated,
        onSurfaceVariant = c.textSecondary,
        surfaceContainerLowest = c.bg,
        surfaceContainerLow = c.surface,
        surfaceContainer = c.surface,
        surfaceContainerHigh = c.surfaceElevated,
        surfaceContainerHighest = c.surfaceElevated,
        surfaceBright = c.surfaceElevated,
        surfaceDim = c.bg,
        outline = if (c.isDark) Color(0x33FFFFFF) else Color(0x29000000),
        outlineVariant = c.hairline,
        scrim = Color.Black,
    )
}

private val systemFont = FontFamily.Default

val CouchTypography = Typography(
    displaySmall = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Bold, fontSize = 34.sp, lineHeight = 40.sp, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Bold, fontSize = 28.sp, lineHeight = 34.sp, letterSpacing = (-0.3).sp),
    headlineSmall = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, lineHeight = 28.sp),
    titleLarge = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 26.sp),
    titleMedium = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp),
    titleSmall = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, lineHeight = 20.sp),
    bodyLarge = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Normal, fontSize = 17.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 21.sp),
    bodySmall = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 20.sp),
    labelMedium = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp),
    labelSmall = TextStyle(fontFamily = systemFont, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
)

val CouchShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

object Radii {
    val posterThumb = 8.dp
    val posterRow = 10.dp
    val posterFeatured = 14.dp
    val card = 16.dp
    val sheet = 24.dp
}

@Composable
fun CouchPotatoTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val couch = if (darkTheme) DarkCouchColors else LightCouchColors
    CompositionLocalProvider(LocalCouchColors provides couch) {
        MaterialTheme(colorScheme = schemeFor(couch), typography = CouchTypography, shapes = CouchShapes, content = content)
    }
}
