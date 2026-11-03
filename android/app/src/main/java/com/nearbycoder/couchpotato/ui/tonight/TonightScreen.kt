package com.nearbycoder.couchpotato.ui.tonight

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.domain.WatchStatus
import com.nearbycoder.couchpotato.ui.components.ErrorBanner
import com.nearbycoder.couchpotato.ui.components.HeroCarousel
import com.nearbycoder.couchpotato.ui.components.MoodGrid
import com.nearbycoder.couchpotato.ui.components.PosterCard
import com.nearbycoder.couchpotato.ui.components.PosterRow
import com.nearbycoder.couchpotato.ui.components.PosterRowPlaceholder
import com.nearbycoder.couchpotato.ui.components.SectionHeader
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.edgeToEdgeInsets
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch

@Composable
fun TonightScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val vm: TonightViewModel = viewModel { TonightViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val saved by vm.saved.collectAsStateWithLifecycle()
    val isWide = isWideLayout()
    val colors = Couch.colors
    val posterWidth = if (isWide) 150.dp else 120.dp
    val savedKeys = remember(saved) { saved.map { it.key }.toSet() }
    val upNext = remember(saved) {
        val watching = saved.filter { it.watchStatus == WatchStatus.WATCHING }.sortedByDescending { it.updatedAt }
        val queued = saved.filter { it.watchStatus == WatchStatus.QUEUED }.sortedByDescending { it.addedAt }
        (watching + queued).take(12)
    }

    Scaffold(containerColor = colors.bg, contentWindowInsets = edgeToEdgeInsets()) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            item(key = "hero") {
                if (state.hero.isNotEmpty()) {
                    HeroCarousel(
                        titles = state.hero,
                        isWide = isWide,
                        isSaved = { it.ref.key in savedKeys },
                        onToggleSave = vm::toggleSave,
                        onDetails = { actions.openTitle(it.ref.key) },
                        topOverlay = { TonightHeader(nickname = state.nickname, onSettings = actions::openSettings) },
                    )
                } else {
                    Column(Modifier.fillMaxWidth()) {
                        TonightHeader(nickname = state.nickname, onSettings = actions::openSettings)
                        if (state.loading) {
                            Spacer(Modifier.height(8.dp))
                            PosterRowPlaceholder(title = "Trending this week", posterWidth = posterWidth)
                        }
                    }
                }
            }

            if (state.error != null) {
                item(key = "error") { ErrorBanner(message = state.error!!, onRetry = vm::load) }
            }

            if (upNext.isNotEmpty()) {
                item(key = "upnext") {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        SectionHeader(
                            title = if (upNext.any { it.watchStatus == WatchStatus.WATCHING }) "Continue watching" else "Up next",
                            actionLabel = "See All",
                            onAction = { actions.selectTab(com.nearbycoder.couchpotato.ui.navigation.WatchlistRoute) },
                        )
                        LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(upNext, key = { it.key }) { item ->
                                PosterCard(
                                    title = item.asCatalogTitle,
                                    width = posterWidth,
                                    onClick = { actions.openTitle(item.key) },
                                    subtitle = item.progressLabel ?: item.watchStatus.label,
                                    status = item.watchStatus,
                                )
                            }
                        }
                    }
                }
            }

            item(key = "trending") {
                if (state.trending.isNotEmpty()) {
                    PosterRow("Trending this week", state.trending, posterWidth, { actions.openTitle(it.ref.key) })
                } else if (state.loading && state.hero.isEmpty()) {
                    PosterRowPlaceholder("New on streaming", posterWidth)
                }
            }

            item(key = "fresh") {
                if (state.fresh.isNotEmpty()) {
                    PosterRow("New on streaming", state.fresh, posterWidth, { actions.openTitle(it.ref.key) })
                } else if (state.loading) {
                    PosterRowPlaceholder("New on streaming", posterWidth)
                }
            }

            items(state.serviceRows, key = { "service-${it.provider.id}" }) { row ->
                PosterRow(
                    title = "Popular on ${row.provider.name}",
                    titles = row.titles,
                    posterWidth = posterWidth,
                    onOpen = { actions.openTitle(it.ref.key) },
                    actionLabel = "See All",
                    onAction = { actions.openService(row.provider) },
                )
            }

            item(key = "movies") {
                if (state.popularMovies.isNotEmpty()) {
                    PosterRow("Popular movies", state.popularMovies, posterWidth, { actions.openTitle(it.ref.key) })
                } else if (state.loading) {
                    PosterRowPlaceholder("Popular movies", posterWidth)
                }
            }

            item(key = "series") {
                if (state.popularSeries.isNotEmpty()) {
                    PosterRow("Popular series", state.popularSeries, posterWidth, { actions.openTitle(it.ref.key) })
                } else if (state.loading) {
                    PosterRowPlaceholder("Popular series", posterWidth)
                }
            }

            item(key = "moods") {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader(title = "Moods", subtitle = "Pick a feeling, get a shortlist.")
                    MoodGrid(onOpen = actions::openMood, columns = if (isWide) 3 else 2)
                }
            }

            item(key = "attribution") {
                Text(
                    text = if (state.hasTmdb) {
                        "Data from TMDB and JustWatch. This product uses the TMDB API but is not endorsed or certified by TMDB."
                    } else {
                        "Series data from TVmaze (CC BY-SA). Movie charts and prices from Apple. Add a TMDB key in Settings for the full catalog."
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.textTertiary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun TonightHeader(nickname: String, onSettings: () -> Unit) {
    val colors = Couch.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(start = 16.dp, end = 4.dp, top = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text("Tonight", style = MaterialTheme.typography.displaySmall, color = colors.textPrimary)
            if (nickname.isNotBlank()) {
                Text("Good evening, $nickname.", style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
            }
        }
        IconButton(onClick = onSettings) {
            Icon(Icons.Outlined.Settings, contentDescription = "Settings", tint = colors.textPrimary)
        }
    }
}
