package com.nearbycoder.couchpotato.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.ui.theme.Couch

/**
 * Edge-to-edge backdrop carousel: 16:9 on wide layouts, 4:5 on phones, gradient fade into bg,
 * bottom-aligned title, metadata line, primary + secondary actions and page dots.
 */
@Composable
fun HeroCarousel(
    titles: List<CatalogTitle>,
    isWide: Boolean,
    isSaved: (CatalogTitle) -> Boolean,
    onToggleSave: (CatalogTitle) -> Unit,
    onDetails: (CatalogTitle) -> Unit,
    modifier: Modifier = Modifier,
    topOverlay: @Composable () -> Unit = {},
) {
    val colors = Couch.colors
    val pagerState = rememberPagerState(pageCount = { titles.size })
    val ratio = if (isWide) 16f / 9f else 4f / 5f
    Box(modifier = modifier.fillMaxWidth().aspectRatio(ratio)) {
        HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize(), key = { titles[it].id }) { page ->
            val title = titles[page]
            HeroPage(
                title = title,
                isWide = isWide,
                saved = isSaved(title),
                onToggleSave = { onToggleSave(title) },
                onDetails = { onDetails(title) },
            )
        }
        // Top scrim so overlaid chrome stays readable.
        Box(
            Modifier
                .fillMaxWidth()
                .height(120.dp)
                .background(Brush.verticalGradient(listOf(colors.bg.copy(alpha = 0.75f), Color.Transparent))),
        )
        topOverlay()
        if (titles.size > 1) {
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                repeat(titles.size.coerceAtMost(10)) { index ->
                    val active = pagerState.currentPage % titles.size.coerceAtMost(10) == index
                    Box(
                        Modifier
                            .size(if (active) 7.dp else 5.dp)
                            .clip(CircleShape)
                            .background(if (active) colors.accent else colors.textTertiary),
                    )
                }
            }
        }
    }
}

@Composable
private fun HeroPage(
    title: CatalogTitle,
    isWide: Boolean,
    saved: Boolean,
    onToggleSave: () -> Unit,
    onDetails: () -> Unit,
) {
    val colors = Couch.colors
    val hasBackdrop = title.backdropUrl != null
    Box(Modifier.fillMaxSize()) {
        if (hasBackdrop) {
            Artwork(
                url = title.backdropUrl,
                modifier = Modifier.fillMaxSize(),
                shape = RectangleShape,
                contentScale = ContentScale.Crop,
                placeholderIcon = null,
                bordered = false,
            )
        } else {
            // No backdrop (key-less catalogs): a blurred poster fills the frame behind the sharp poster.
            Artwork(
                url = title.posterUrl,
                modifier = Modifier.fillMaxSize().blur(40.dp).alpha(0.9f),
                shape = RectangleShape,
                contentScale = ContentScale.Crop,
                placeholderIcon = null,
                bordered = false,
            )
            Box(Modifier.fillMaxSize().background(colors.bg.copy(alpha = 0.35f)))
            if (isWide) {
                Box(Modifier.fillMaxSize().padding(horizontal = 32.dp, vertical = 24.dp), contentAlignment = Alignment.CenterEnd) {
                    Poster(url = title.posterUrl, modifier = Modifier.fillMaxHeight(0.86f), radius = 14.dp, contentDescription = title.name)
                }
            } else {
                Artwork(
                    url = title.posterUrl,
                    modifier = Modifier.fillMaxSize(),
                    shape = RectangleShape,
                    contentScale = ContentScale.Crop,
                    placeholderIcon = null,
                    bordered = false,
                )
            }
        }
        // Fade into bg over the bottom 55%.
        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.45f to Color.Transparent,
                        1f to colors.bg,
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 16.dp, end = 16.dp, bottom = 28.dp)
                .widthIn(max = if (isWide) 560.dp else 480.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                title.name,
                style = MaterialTheme.typography.headlineMedium,
                color = colors.textPrimary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                title.metadataLine.ifEmpty { title.kind.label },
                style = MaterialTheme.typography.bodyMedium,
                color = colors.textSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(2.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PrimaryButton(
                    text = if (saved) "In Watchlist" else "Add to Watchlist",
                    onClick = onToggleSave,
                    icon = if (saved) Icons.Outlined.Check else Icons.Outlined.Add,
                )
                SecondaryButton(text = "Details", onClick = onDetails, onDark = colors.isDark)
            }
        }
    }
}
