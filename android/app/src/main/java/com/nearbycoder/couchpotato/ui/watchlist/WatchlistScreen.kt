package com.nearbycoder.couchpotato.ui.watchlist

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bookmarks
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.WatchStatus
import com.nearbycoder.couchpotato.ui.components.ChipRow
import com.nearbycoder.couchpotato.ui.components.EmptyState
import com.nearbycoder.couchpotato.ui.components.Poster
import com.nearbycoder.couchpotato.ui.components.PosterGrid
import com.nearbycoder.couchpotato.ui.components.ProviderTile
import com.nearbycoder.couchpotato.ui.components.StatusBadge
import com.nearbycoder.couchpotato.ui.navigation.BrowseRoute
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.LocalAppEvents
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.screenInsets
import com.nearbycoder.couchpotato.ui.navigation.PlannerRoute
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchlistScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val events = LocalAppEvents.current
    val vm: WatchlistViewModel = viewModel { WatchlistViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val colors = Couch.colors
    val isWide = isWideLayout()
    var sortMenu by remember { mutableStateOf(false) }
    var sheetFor by remember { mutableStateOf<SavedTitle?>(null) }

    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        topBar = {
            Column {
                TopAppBar(
                    title = { Text("Watchlist", style = MaterialTheme.typography.headlineMedium, color = colors.textPrimary) },
                    actions = {
                        Box {
                            IconButton(onClick = { sortMenu = true }) {
                                Icon(Icons.Outlined.SwapVert, contentDescription = "Sort", tint = colors.textPrimary)
                            }
                            DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                                WatchlistSort.entries.forEach { sort ->
                                    DropdownMenuItem(
                                        text = { Text(sort.label, color = if (sort == state.sort) colors.accent else colors.textPrimary) },
                                        onClick = { vm.setSort(sort); sortMenu = false },
                                    )
                                }
                            }
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
                )
                StatusTabs(counts = state.counts, selected = state.status, onSelect = vm::setStatus)
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ChipRow(
                        options = listOf("All", "Movies", "Series"),
                        selected = when (state.kind) { MediaKind.MOVIE -> 1; MediaKind.TV -> 2; null -> 0 },
                        onSelect = { vm.setKind(when (it) { 1 -> MediaKind.MOVIE; 2 -> MediaKind.TV; else -> null }) },
                    )
                }
                if (state.availableServices.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(state.availableServices.size, key = { state.availableServices[it].id }) { i ->
                            val p = state.availableServices[i]
                            val selected = state.service == p
                            androidx.compose.material3.FilterChip(
                                selected = selected,
                                onClick = { vm.setService(if (selected) null else p) },
                                label = { Text(p.shortName) },
                                shape = CircleShape,
                            )
                        }
                    }
                }
                Spacer(Modifier.height(4.dp))
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (state.visible.isEmpty()) {
                EmptyState(
                    icon = Icons.Outlined.Bookmarks,
                    headline = emptyHeadline(state.status, state.all.isEmpty()),
                    footnote = emptyFootnote(state.status, state.all.isEmpty()),
                    actionLabel = if (state.all.isEmpty()) "Browse titles" else null,
                    onAction = { actions.selectTab(BrowseRoute) },
                    modifier = Modifier.align(Alignment.Center),
                )
            } else {
                PosterGrid(
                    titles = state.visible.map { it.asCatalogTitle },
                    isWide = isWide,
                    onOpen = { actions.openTitle(it.ref.key) },
                    statusFor = { t -> state.visible.firstOrNull { it.key == t.id }?.watchStatus },
                    subtitleFor = { t ->
                        val saved = state.visible.firstOrNull { it.key == t.id }
                        saved?.progressLabel ?: if (saved != null && saved.rating > 0) "${"★".repeat(saved.rating)}" else t.subtitle
                    },
                    onLongPress = { t -> sheetFor = state.visible.firstOrNull { it.key == t.id } },
                )
            }
        }
    }

    sheetFor?.let { saved ->
        ModalBottomSheet(onDismissRequest = { sheetFor = null }, containerColor = colors.surfaceElevated) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Poster(saved.posterUrl, modifier = Modifier.width(48.dp), radius = 8.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(saved.name, style = MaterialTheme.typography.titleMedium, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(4.dp))
                        StatusBadge(saved.watchStatus)
                    }
                }
                HorizontalDivider(color = colors.hairline)
                WatchStatus.entries.forEach { status ->
                    DropdownMenuItem(
                        text = { Text(status.label, color = colors.textPrimary) },
                        leadingIcon = {
                            Box(Modifier.width(10.dp).height(10.dp).padding(0.dp)) {
                                androidx.compose.foundation.Canvas(Modifier.fillMaxSize()) { drawCircle(colors.statusColor(status)) }
                            }
                        },
                        trailingIcon = { if (status == saved.watchStatus) Text("Current", style = MaterialTheme.typography.labelSmall, color = colors.textSecondary) },
                        onClick = { vm.setTitleStatus(saved.key, status); sheetFor = null },
                    )
                }
                HorizontalDivider(color = colors.hairline)
                DropdownMenuItem(
                    text = { Text("Plan a night", color = colors.textPrimary) },
                    onClick = {
                        events.pendingPlanKey = saved.key
                        sheetFor = null
                        actions.selectTab(PlannerRoute)
                    },
                )
                DropdownMenuItem(
                    text = { Text("Remove from Watchlist", color = colors.danger) },
                    onClick = { vm.remove(saved.key); sheetFor = null },
                )
            }
        }
    }
}

@Composable
private fun StatusTabs(counts: Map<WatchStatus, Int>, selected: WatchStatus, onSelect: (WatchStatus) -> Unit) {
    val colors = Couch.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        WatchStatus.entries.forEach { status ->
            val isSelected = status == selected
            Column(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onSelect(status) }
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        status.label,
                        style = MaterialTheme.typography.labelLarge,
                        color = if (isSelected) colors.textPrimary else colors.textSecondary,
                    )
                    Text(
                        (counts[status] ?: 0).toString(),
                        style = MaterialTheme.typography.labelSmall,
                        color = if (isSelected) colors.accent else colors.textTertiary,
                    )
                }
                Spacer(Modifier.height(6.dp))
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(2.dp)
                        .clip(CircleShape)
                        .background(if (isSelected) colors.accent else androidx.compose.ui.graphics.Color.Transparent),
                )
            }
        }
    }
}

private fun emptyHeadline(status: WatchStatus, nothingSaved: Boolean): String = when {
    nothingSaved -> "Your watchlist is empty"
    status == WatchStatus.QUEUED -> "Nothing queued"
    status == WatchStatus.WATCHING -> "Nothing in progress"
    status == WatchStatus.WATCHED -> "Nothing finished yet"
    else -> "Nothing dropped"
}

private fun emptyFootnote(status: WatchStatus, nothingSaved: Boolean): String = when {
    nothingSaved -> "Save titles from Tonight or Browse and they'll show up here."
    status == WatchStatus.QUEUED -> "Add a title to Want to Watch and it will land here."
    status == WatchStatus.WATCHING -> "Mark a title as Watching from its page."
    status == WatchStatus.WATCHED -> "Finished titles count toward your CouchRank."
    else -> "Titles you give up on are kept here, out of the way."
}

