package com.nearbycoder.couchpotato.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.WatchStatus
import com.nearbycoder.couchpotato.ui.theme.Couch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun PosterCard(
    title: CatalogTitle,
    width: Dp,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = title.subtitle,
    status: WatchStatus? = null,
    radius: Dp = 10.dp,
    onLongClick: (() -> Unit)? = null,
) {
    val colors = Couch.colors
    Column(
        modifier = modifier
            .width(width)
            .clip(RoundedCornerShape(radius))
            .then(
                if (onLongClick != null) Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick)
                else Modifier.clickable(onClick = onClick),
            ),
    ) {
        Box {
            Poster(url = title.posterUrl, modifier = Modifier.fillMaxWidth(), radius = radius, contentDescription = title.name)
            if (status != null) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp)
                        .size(10.dp)
                        .clip(CircleShape)
                        .background(colors.bg)
                        .padding(2.dp)
                        .clip(CircleShape)
                        .background(colors.statusColor(status)),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(
            title.name,
            style = MaterialTheme.typography.titleSmall,
            color = colors.textPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 2.dp),
        )
        if (!subtitle.isNullOrEmpty()) {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 2.dp),
            )
        }
    }
}

/** Horizontally scrolling posters under a section header. */
@Composable
fun PosterRow(
    title: String,
    titles: List<CatalogTitle>,
    posterWidth: Dp,
    onOpen: (CatalogTitle) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
    subtitleFor: (CatalogTitle) -> String? = { it.subtitle },
) {
    if (titles.isEmpty()) return
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(title = title, subtitle = subtitle, actionLabel = actionLabel, onAction = onAction)
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(titles, key = { it.id }) { item ->
                PosterCard(title = item, width = posterWidth, onClick = { onOpen(item) }, subtitle = subtitleFor(item))
            }
        }
    }
}

/** Skeleton row shown while a section loads. */
@Composable
fun PosterRowPlaceholder(title: String, posterWidth: Dp, modifier: Modifier = Modifier) {
    val colors = Couch.colors
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(title = title)
        Row(modifier = Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(4) {
                Column(Modifier.width(posterWidth)) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(posterWidth * 1.5f)
                            .clip(RoundedCornerShape(10.dp))
                            .background(colors.surfaceElevated),
                    )
                    Spacer(Modifier.height(8.dp))
                    Box(Modifier.width(posterWidth * 0.7f).height(12.dp).clip(CircleShape).background(colors.surfaceElevated))
                }
            }
        }
    }
}

/** Adaptive poster grid: 110–120 min on phones, 150–170 on larger screens. */
@Composable
fun PosterGrid(
    titles: List<CatalogTitle>,
    isWide: Boolean,
    onOpen: (CatalogTitle) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(16.dp),
    statusFor: (CatalogTitle) -> WatchStatus? = { null },
    subtitleFor: (CatalogTitle) -> String? = { it.subtitle },
    onLongPress: ((CatalogTitle) -> Unit)? = null,
    header: (LazyGridScope.() -> Unit)? = null,
) {
    val minSize = if (isWide) 156.dp else 112.dp
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize),
        modifier = modifier,
        contentPadding = contentPadding,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        header?.invoke(this)
        items(titles, key = { it.id }) { item ->
            PosterCard(
                title = item,
                width = minSize,
                onClick = { onOpen(item) },
                modifier = Modifier.fillMaxWidth(),
                subtitle = subtitleFor(item),
                status = statusFor(item),
                onLongClick = onLongPress?.let { cb -> { cb(item) } },
            )
        }
    }
}
