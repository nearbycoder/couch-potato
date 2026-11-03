package com.nearbycoder.couchpotato.ui.shuffle

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.CircleShape
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.domain.CatalogTitle
import com.nearbycoder.couchpotato.domain.Mood
import com.nearbycoder.couchpotato.domain.TimeBudget
import com.nearbycoder.couchpotato.ui.components.Artwork
import com.nearbycoder.couchpotato.ui.components.ChipRow
import com.nearbycoder.couchpotato.ui.components.EmptyState
import com.nearbycoder.couchpotato.ui.components.ErrorBanner
import com.nearbycoder.couchpotato.ui.components.Poster
import com.nearbycoder.couchpotato.ui.components.PrimaryButton
import com.nearbycoder.couchpotato.ui.components.SecondaryButton
import com.nearbycoder.couchpotato.ui.navigation.BrowseRoute
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.LocalAppEvents
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.screenInsets
import com.nearbycoder.couchpotato.ui.navigation.PlannerRoute
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch
import kotlinx.coroutines.delay

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShuffleScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val events = LocalAppEvents.current
    val vm: ShuffleViewModel = viewModel { ShuffleViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val colors = Couch.colors
    val isWide = isWideLayout()

    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        topBar = {
            TopAppBar(
                title = { Text("Shuffle", style = MaterialTheme.typography.headlineMedium, color = colors.textPrimary) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Filters(state = state, vm = vm)

            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = if (isWide) 440.dp else 420.dp)
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    state.loading -> CircularProgressIndicator(color = colors.accent)
                    state.error != null -> ErrorBanner(state.error!!, onRetry = vm::refresh)
                    state.candidates.isEmpty() -> EmptyState(
                        icon = Icons.Outlined.Shuffle,
                        headline = if (state.pool == ShufflePool.WATCHLIST) "Nothing to shuffle" else "No matches",
                        footnote = if (state.pool == ShufflePool.WATCHLIST) "Add a few titles to your watchlist, or switch the pool to Discover." else "Try a different mood or time budget.",
                        actionLabel = if (state.pool == ShufflePool.WATCHLIST) "Browse titles" else null,
                        onAction = { actions.selectTab(BrowseRoute) },
                    )
                    state.winner != null && !state.spinning -> WinnerCard(
                        title = state.winner!!,
                        isWide = isWide,
                        onWatchNow = { vm.watchNow(state.winner!!) { actions.openTitle(state.winner!!.ref.key) } },
                        onPlan = {
                            vm.ensureSaved(state.winner!!) {
                                events.pendingPlanKey = state.winner!!.ref.key
                                actions.selectTab(PlannerRoute)
                            }
                        },
                        onAgain = vm::spin,
                    )
                    else -> PosterStack(
                        candidates = state.candidates,
                        spinning = state.spinning,
                        spinId = state.spinId,
                        onLand = vm::land,
                        onSpin = vm::spin,
                        isWide = isWide,
                    )
                }
            }
        }
    }
}

@Composable
private fun Filters(state: ShuffleState, vm: ShuffleViewModel) {
    val colors = Couch.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Pool", style = MaterialTheme.typography.labelMedium, color = colors.textSecondary, modifier = Modifier.width(56.dp))
            ChipRow(
                options = ShufflePool.entries.map { it.label },
                selected = state.pool.ordinal,
                onSelect = { vm.setPool(ShufflePool.entries[it]) },
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Mood", style = MaterialTheme.typography.labelMedium, color = colors.textSecondary, modifier = Modifier.padding(start = 16.dp).width(56.dp))
            LazyRow(contentPadding = PaddingValues(end = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                item(key = "any") {
                    MoodChip(label = "Any", selected = state.mood == null) { vm.setMood(null) }
                }
                items(Mood.entries.size, key = { Mood.entries[it].id }) { i ->
                    val mood = Mood.entries[i]
                    MoodChip(label = mood.title, selected = state.mood == mood) { vm.setMood(if (state.mood == mood) null else mood) }
                }
            }
        }
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Time", style = MaterialTheme.typography.labelMedium, color = colors.textSecondary, modifier = Modifier.width(56.dp))
            ChipRow(
                options = TimeBudget.entries.map { it.shortLabel },
                selected = state.budget.ordinal,
                onSelect = { vm.setBudget(TimeBudget.entries[it]) },
            )
        }
    }
}

@Composable
private fun MoodChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val colors = Couch.colors
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        shape = CircleShape,
        border = null,
        colors = FilterChipDefaults.filterChipColors(
            containerColor = colors.secondaryFill,
            labelColor = colors.textPrimary,
            selectedContainerColor = colors.accent,
            selectedLabelColor = colors.onAccent,
        ),
    )
}

/** A stack of posters that cycles quickly and decelerates to a stop. */
@Composable
private fun PosterStack(
    candidates: List<CatalogTitle>,
    spinning: Boolean,
    spinId: Int,
    onLand: (CatalogTitle) -> Unit,
    onSpin: () -> Unit,
    isWide: Boolean,
) {
    val colors = Couch.colors
    val haptics = LocalHapticFeedback.current
    var index by remember { mutableIntStateOf(0) }
    val scale = remember { Animatable(1f) }
    val posterWidth = if (isWide) 220.dp else 180.dp

    LaunchedEffect(spinId, spinning) {
        if (!spinning) return@LaunchedEffect
        scale.snapTo(0.96f)
        val total = (candidates.size * 2 + 10).coerceIn(14, 34)
        var tick = 0
        while (tick < total) {
            index = (index + 1) % candidates.size
            haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
            // Fast at first, then decelerate.
            val t = tick.toFloat() / total
            val wait = (55 + 420 * t * t * t).toLong()
            delay(wait)
            tick++
        }
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        scale.animateTo(1.04f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
        scale.animateTo(1f, tween(180))
        onLand(candidates[index])
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.height(posterWidth * 1.5f + 24.dp)) {
            // Cards behind the current one, offset and faded.
            for (depth in 3 downTo 1) {
                val i = (index + depth) % candidates.size
                Box(
                    Modifier
                        .padding(top = (depth * 10).dp)
                        .scale(1f - depth * 0.06f)
                        .alpha(0.55f - depth * 0.12f),
                ) {
                    Poster(candidates[i].posterUrl, modifier = Modifier.width(posterWidth), radius = 14.dp)
                }
            }
            Box(Modifier.scale(scale.value)) {
                Poster(candidates[index % candidates.size].posterUrl, modifier = Modifier.width(posterWidth), radius = 14.dp)
            }
        }
        Text(
            if (spinning) "Shuffling…" else "${candidates.size} titles in the pool",
            style = MaterialTheme.typography.bodySmall,
            color = colors.textSecondary,
        )
        PrimaryButton(text = if (spinning) "Shuffling" else "Shuffle", icon = Icons.Outlined.Shuffle, onClick = onSpin, enabled = !spinning)
    }
}

@Composable
private fun WinnerCard(
    title: CatalogTitle,
    isWide: Boolean,
    onWatchNow: () -> Unit,
    onPlan: () -> Unit,
    onAgain: () -> Unit,
) {
    val colors = Couch.colors
    val shape = RoundedCornerShape(20.dp)
    Box(
        Modifier
            .widthIn(max = if (isWide) 640.dp else 520.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(colors.surface)
            .border(1.dp, colors.hairline, shape),
    ) {
        Artwork(
            url = title.backdropUrl ?: title.posterUrl,
            modifier = Modifier.matchParentSize().blur(28.dp).alpha(0.55f),
            shape = RectangleShape,
            placeholderIcon = null,
            bordered = false,
        )
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(Color.Transparent, colors.bg.copy(alpha = 0.85f)))))
        Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Tonight's pick", style = MaterialTheme.typography.labelMedium, color = colors.accent)
            Poster(title.posterUrl, modifier = Modifier.width(if (isWide) 200.dp else 160.dp), radius = 14.dp)
            Text(title.name, style = MaterialTheme.typography.headlineSmall, color = colors.textPrimary, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(title.metadataLine.ifEmpty { title.kind.label }, style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary, textAlign = TextAlign.Center, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PrimaryButton(text = "Watch now", icon = Icons.Outlined.PlayArrow, onClick = onWatchNow)
                SecondaryButton(text = "Plan it", icon = Icons.Outlined.Event, onClick = onPlan)
            }
            SecondaryButton(text = "Shuffle again", icon = Icons.Outlined.Shuffle, onClick = onAgain)
        }
    }
}
