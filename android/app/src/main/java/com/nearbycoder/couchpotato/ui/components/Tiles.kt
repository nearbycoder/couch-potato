package com.nearbycoder.couchpotato.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.SentimentSatisfied
import androidx.compose.material.icons.outlined.Weekend
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.ui.theme.Couch

fun Provider.brandColor(): Color = Color(("FF$colorHex").toLong(16))

/** 36 dp rounded-square logo (TMDB) or 2-letter monogram on the brand color. */
@Composable
fun ProviderLogo(provider: Provider, modifier: Modifier = Modifier, logoUrl: String? = null, size: Dp = 36.dp) {
    val colors = Couch.colors
    val shape = RoundedCornerShape(size * 0.25f)
    val context = LocalContext.current
    Box(
        modifier = modifier
            .size(size)
            .clip(shape)
            .background(if (logoUrl != null) colors.surfaceElevated else provider.brandColor())
            .border(1.dp, colors.hairline, shape),
        contentAlignment = Alignment.Center,
    ) {
        if (logoUrl != null) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(logoUrl).crossfade(true).build(),
                contentDescription = provider.name,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            val onBrand = if (provider.brandColor().luminanceApprox() > 0.6f) Color(0xFF111114) else Color.White
            Text(
                provider.monogram,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = onBrand,
                maxLines = 1,
            )
        }
    }
}

private fun Color.luminanceApprox(): Float = 0.2126f * red + 0.7152f * green + 0.0722f * blue

/** Logo + name beneath in Caption, optionally with a price. */
@Composable
fun ProviderTile(
    provider: Provider,
    modifier: Modifier = Modifier,
    logoUrl: String? = null,
    caption: String? = null,
    selected: Boolean? = null,
    onClick: (() -> Unit)? = null,
) {
    val colors = Couch.colors
    val alpha = if (selected == false) 0.45f else 1f
    Column(
        modifier = modifier
            .width(72.dp)
            .clip(RoundedCornerShape(12.dp))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box {
            ProviderLogo(provider, logoUrl = logoUrl, modifier = Modifier.alpha(alpha))
            if (selected == true) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(top = 0.dp, end = 0.dp)
                        .size(12.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(colors.bg)
                        .padding(2.dp)
                        .clip(RoundedCornerShape(4.dp))
                        .background(colors.success),
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            provider.shortName,
            style = MaterialTheme.typography.labelSmall,
            color = if (alpha < 1f) colors.textTertiary else colors.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        if (caption != null) {
            Text(caption, style = MaterialTheme.typography.labelSmall, color = colors.textSecondary, maxLines = 1, textAlign = TextAlign.Center)
        }
    }
}

/** Wide tile for "Browse by service". */
@Composable
fun ServiceTile(provider: Provider, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Couch.colors
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(14.dp))
            .background(colors.surface)
            .border(1.dp, colors.hairline, RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ProviderLogo(provider, size = 32.dp)
        Text(
            provider.name,
            style = MaterialTheme.typography.titleSmall,
            color = colors.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

val Mood.icon: ImageVector
    get() = when (this) {
        Mood.COZY -> Icons.Outlined.Weekend
        Mood.LAUGHS -> Icons.Outlined.SentimentSatisfied
        Mood.THRILLS -> Icons.Outlined.Bolt
        Mood.FEELS -> Icons.Outlined.FavoriteBorder
        Mood.SPOOKY -> Icons.Outlined.DarkMode
        Mood.BRAINY -> Icons.Outlined.Psychology
    }

/** 16:10 duotone tile with an outlined symbol top-left and the title bottom-left. */
@Composable
fun MoodTile(mood: Mood, onClick: () -> Unit, modifier: Modifier = Modifier, compact: Boolean = false) {
    val colors = Couch.colors
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier = modifier
            .aspectRatio(16f / 10f)
            .clip(shape)
            .background(Brush.linearGradient(listOf(Color(mood.gradientFrom), Color(mood.gradientTo))))
            .border(1.dp, colors.hairline, shape)
            .clickable(onClick = onClick)
            .padding(14.dp),
    ) {
        Icon(
            mood.icon,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.92f),
            modifier = Modifier.align(Alignment.TopStart).size(24.dp),
        )
        Column(modifier = Modifier.align(Alignment.BottomStart)) {
            Text(
                mood.title,
                style = if (compact) MaterialTheme.typography.titleMedium else MaterialTheme.typography.headlineSmall,
                color = Color.White,
                maxLines = 1,
            )
            if (!compact) {
                Text(mood.blurb, style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.72f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
fun MoodGrid(onOpen: (Mood) -> Unit, modifier: Modifier = Modifier, columns: Int = 2) {
    Column(modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Mood.entries.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { mood -> MoodTile(mood, onClick = { onOpen(mood) }, modifier = Modifier.weight(1f)) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
