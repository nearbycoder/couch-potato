package com.nearbycoder.couchpotato.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import com.nearbycoder.couchpotato.ui.theme.Couch

/** A 2:3 poster with hairline border and a quiet placeholder. */
@Composable
fun Poster(
    url: String?,
    modifier: Modifier = Modifier,
    radius: Dp = 10.dp,
    contentDescription: String? = null,
    placeholderIcon: ImageVector = Icons.Outlined.Movie,
) {
    Artwork(
        url = url,
        modifier = modifier.aspectRatio(2f / 3f),
        shape = RoundedCornerShape(radius),
        contentDescription = contentDescription,
        placeholderIcon = placeholderIcon,
    )
}

@Composable
fun Artwork(
    url: String?,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(10.dp),
    contentDescription: String? = null,
    contentScale: ContentScale = ContentScale.Crop,
    placeholderIcon: ImageVector? = Icons.Outlined.Movie,
    bordered: Boolean = true,
) {
    val colors = Couch.colors
    val context = LocalContext.current
    Box(
        modifier = modifier
            .clip(shape)
            .background(colors.surfaceElevated)
            .then(if (bordered) Modifier.border(1.dp, colors.hairline, shape) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        if (placeholderIcon != null) {
            Icon(placeholderIcon, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(28.dp))
        }
        if (!url.isNullOrEmpty()) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(url).crossfade(true).build(),
                contentDescription = contentDescription,
                contentScale = contentScale,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun Avatar(url: String?, size: Dp, modifier: Modifier = Modifier) {
    Artwork(
        url = url,
        modifier = modifier.size(size),
        shape = RoundedCornerShape(size / 2),
        placeholderIcon = Icons.Outlined.Person,
    )
}
