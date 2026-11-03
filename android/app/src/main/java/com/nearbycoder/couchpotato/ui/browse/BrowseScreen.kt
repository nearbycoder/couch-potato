package com.nearbycoder.couchpotato.ui.browse

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.ui.components.ChipRow
import com.nearbycoder.couchpotato.ui.components.EmptyState
import com.nearbycoder.couchpotato.ui.components.ErrorBanner
import com.nearbycoder.couchpotato.ui.components.MoodGrid
import com.nearbycoder.couchpotato.ui.components.PosterGrid
import com.nearbycoder.couchpotato.ui.components.SectionHeader
import com.nearbycoder.couchpotato.ui.components.ServiceTile
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.screenInsets
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch

private val kindOptions = listOf("All", "Movies", "Series")
private fun kindAt(index: Int): MediaKind? = when (index) { 1 -> MediaKind.MOVIE; 2 -> MediaKind.TV; else -> null }
private fun indexOf(kind: MediaKind?): Int = when (kind) { MediaKind.MOVIE -> 1; MediaKind.TV -> 2; null -> 0 }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowseScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val vm: BrowseViewModel = viewModel { BrowseViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val isWide = isWideLayout()
    val colors = Couch.colors
    val focus = LocalFocusManager.current

    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        topBar = {
            Column(Modifier.fillMaxWidth()) {
                TopAppBar(
                    title = { Text("Browse", style = MaterialTheme.typography.headlineMedium, color = colors.textPrimary) },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
                )
                TextField(
                    value = state.query,
                    onValueChange = vm::setQuery,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                    placeholder = { Text("Movies, series, people", color = colors.textTertiary) },
                    leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null, tint = colors.textSecondary) },
                    trailingIcon = {
                        if (state.query.isNotEmpty()) {
                            IconButton(onClick = { vm.setQuery("") }) {
                                Icon(Icons.Outlined.Close, contentDescription = "Clear", tint = colors.textSecondary)
                            }
                        }
                    },
                    singleLine = true,
                    shape = CircleShape,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = colors.surfaceElevated,
                        unfocusedContainerColor = colors.surface,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent,
                        cursorColor = colors.accent,
                        focusedTextColor = colors.textPrimary,
                        unfocusedTextColor = colors.textPrimary,
                    ),
                )
                Spacer(Modifier.height(12.dp))
                ChipRow(
                    options = kindOptions,
                    selected = indexOf(state.kind),
                    onSelect = { vm.setKind(kindAt(it)) },
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                Spacer(Modifier.height(4.dp))
            }
        },
    ) { padding ->
        if (state.isIdle) {
            IdleBrowse(
                suggestions = vm.suggestions,
                onSuggest = vm::setQuery,
                onService = actions::openService,
                onMood = actions::openMood,
                isWide = isWide,
                modifier = Modifier.fillMaxSize().padding(padding),
            )
        } else {
            Box(Modifier.fillMaxSize().padding(padding)) {
                when {
                    state.error != null -> ErrorBanner(state.error!!, modifier = Modifier.padding(top = 16.dp), onRetry = { vm.setQuery(state.query + " ") })
                    state.searching && state.results.isEmpty() -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.Center))
                    state.filtered.isEmpty() && !state.searching -> EmptyState(
                        icon = Icons.Outlined.SearchOff,
                        headline = "No matches",
                        footnote = "Try another spelling, or clear the Movies/Series filter.",
                        modifier = Modifier.align(Alignment.Center),
                    )
                    else -> PosterGrid(titles = state.filtered, isWide = isWide, onOpen = { actions.openTitle(it.ref.key) })
                }
            }
        }
    }
}

@Composable
private fun IdleBrowse(
    suggestions: List<String>,
    onSuggest: (String) -> Unit,
    onService: (Provider) -> Unit,
    onMood: (Mood) -> Unit,
    isWide: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = Couch.colors
    val serviceColumns = if (isWide) 4 else 2
    LazyColumn(modifier = modifier, contentPadding = PaddingValues(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item(key = "suggestions") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader(title = "Try searching for")
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(suggestions.size, key = { suggestions[it] }) { i ->
                            androidx.compose.material3.SuggestionChip(
                                onClick = { onSuggest(suggestions[i]) },
                                label = { Text(suggestions[i], color = colors.textPrimary) },
                                shape = CircleShape,
                                border = null,
                                colors = androidx.compose.material3.SuggestionChipDefaults.suggestionChipColors(containerColor = colors.secondaryFill),
                            )
                        }
                    }
                }
            }
        }
        item(key = "services") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader(title = "Browse by service")
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Provider.streamers.chunked(serviceColumns).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            row.forEach { p -> ServiceTile(p, onClick = { onService(p) }, modifier = Modifier.weight(1f)) }
                            repeat(serviceColumns - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
        item(key = "moods") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SectionHeader(title = "Moods")
                MoodGrid(onOpen = onMood, columns = if (isWide) 3 else 2)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ServiceScreen(providerId: String, actions: NavActions) {
    val container = LocalAppContainer.current
    val provider = remember(providerId) { Provider.withId(providerId) ?: Provider.netflix }
    val vm: ServiceViewModel = viewModel(key = "service-$providerId") { ServiceViewModel(container, provider) }
    val state by vm.state.collectAsStateWithLifecycle()
    GridScreen(
        title = provider.name,
        subtitle = "Popular on ${provider.name}",
        state = state,
        onKind = vm::setKind,
        onRetry = vm::load,
        onNearEnd = vm::loadMore,
        actions = actions,
        emptyFootnote = if (!container.catalog.hasTmdb) "Series only. Add a free TMDB key in Settings to include ${provider.name} movies." else "Nothing here right now.",
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoodScreen(moodId: String, actions: NavActions) {
    val container = LocalAppContainer.current
    val mood = remember(moodId) { Mood.withId(moodId) ?: Mood.COZY }
    val vm: MoodViewModel = viewModel(key = "mood-$moodId") { MoodViewModel(container, mood) }
    val state by vm.state.collectAsStateWithLifecycle()
    GridScreen(
        title = mood.title,
        subtitle = mood.blurb,
        state = state,
        onKind = vm::setKind,
        onRetry = vm::load,
        onNearEnd = vm::loadMore,
        actions = actions,
        emptyFootnote = "Nothing matches this mood right now.",
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GridScreen(
    title: String,
    subtitle: String,
    state: ListState,
    onKind: (MediaKind?) -> Unit,
    onRetry: () -> Unit,
    onNearEnd: () -> Unit,
    actions: NavActions,
    emptyFootnote: String,
) {
    val colors = Couch.colors
    val isWide = isWideLayout()
    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        topBar = {
            TopAppBar(
                title = { Text(title, style = MaterialTheme.typography.titleLarge, color = colors.textPrimary) },
                navigationIcon = {
                    IconButton(onClick = actions::back) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = colors.textPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            val header: LazyGridScope.() -> Unit = {
                item(key = "filters", span = { GridItemSpan(maxLineSpan) }) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
                        ChipRow(options = kindOptions, selected = indexOf(state.kind), onSelect = { onKind(kindAt(it)) })
                    }
                }
            }
            when {
                state.loading -> {
                    Column(Modifier.fillMaxSize()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
                            ChipRow(options = kindOptions, selected = indexOf(state.kind), onSelect = { onKind(kindAt(it)) })
                        }
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = colors.accent)
                        }
                    }
                }
                state.error != null -> Column {
                    Spacer(Modifier.height(16.dp))
                    ErrorBanner(state.error, onRetry = onRetry)
                }
                state.titles.isEmpty() -> Column(Modifier.fillMaxSize()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
                        ChipRow(options = kindOptions, selected = indexOf(state.kind), onSelect = { onKind(kindAt(it)) })
                    }
                    EmptyState(icon = Icons.Outlined.SearchOff, headline = "Nothing to show", footnote = emptyFootnote)
                }
                else -> PosterGrid(
                    titles = state.titles,
                    isWide = isWide,
                    onOpen = { actions.openTitle(it.ref.key) },
                    header = header,
                    loadingMore = state.loadingMore,
                    onNearEnd = onNearEnd,
                )
            }
        }
    }
}
