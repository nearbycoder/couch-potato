package com.nearbycoder.couchpotato.ui.planner

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.remote.DateParsing
import com.nearbycoder.couchpotato.domain.EpisodeInfo
import com.nearbycoder.couchpotato.reminders.CalendarBridge
import com.nearbycoder.couchpotato.ui.components.Artwork
import com.nearbycoder.couchpotato.ui.components.EmptyState
import com.nearbycoder.couchpotato.ui.components.GroupCard
import com.nearbycoder.couchpotato.ui.components.Poster
import com.nearbycoder.couchpotato.ui.components.SectionHeader
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.LocalAppEvents
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.screenInsets
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlannerScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val events = LocalAppEvents.current
    val context = LocalContext.current
    val vm: PlannerViewModel = viewModel { PlannerViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val colors = Couch.colors
    val isWide = isWideLayout()
    var sheetKey by remember { mutableStateOf<String?>(null) }
    var showSheet by remember { mutableStateOf(false) }

    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }

    LaunchedEffect(events.pendingPlanKey) {
        val key = events.pendingPlanKey ?: return@LaunchedEffect
        sheetKey = key
        showSheet = true
        events.pendingPlanKey = null
    }

    val dayNights = remember(state.nights, state.selectedDay) {
        state.nights.filter { DateParsing.localDate(it.startsAt) == state.selectedDay }.sortedBy { it.startsAt }
    }
    val daysWithPlans = remember(state.nights) { state.nights.map { DateParsing.localDate(it.startsAt) }.toSet() }

    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        topBar = {
            TopAppBar(
                title = { Text("Planner", style = MaterialTheme.typography.headlineMedium, color = colors.textPrimary) },
                actions = {
                    IconButton(onClick = { sheetKey = null; showSheet = true }) {
                        Icon(Icons.Outlined.Add, contentDescription = "Plan a night", tint = colors.textPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item(key = "week") {
                WeekStrip(
                    weekStart = state.weekStart,
                    selected = state.selectedDay,
                    hasPlans = { it in daysWithPlans },
                    onSelect = vm::selectDay,
                    onShift = vm::shiftWeek,
                )
            }
            item(key = "agenda-header") {
                SectionHeader(
                    title = state.selectedDay.format(DateTimeFormatter.ofPattern("EEEE, MMM d")),
                    subtitle = when (dayNights.size) {
                        0 -> "Nothing planned."
                        1 -> "One couch night."
                        else -> "${dayNights.size} couch nights."
                    },
                    actionLabel = "Plan a night",
                    onAction = { sheetKey = null; showSheet = true },
                )
            }
            if (dayNights.isEmpty()) {
                item(key = "agenda-empty") {
                    EmptyState(
                        icon = Icons.Outlined.Event,
                        headline = "A free evening",
                        footnote = "Plan a night from any title, or pick one from your watchlist.",
                        actionLabel = "Plan a night",
                        onAction = { sheetKey = null; showSheet = true },
                    )
                }
            } else {
                items(dayNights, key = { it.id }) { night ->
                    NightCard(
                        night = night,
                        onOpen = { actions.openTitle(night.titleKey) },
                        onToggleDone = { vm.toggleDone(context, night) },
                        onDelete = { vm.delete(context, night) },
                        onCalendar = { runCatching { context.startActivity(CalendarBridge.insertIntent(night)) } },
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                }
            }
            item(key = "upcoming-header") {
                SectionHeader(
                    title = "Coming up on shows you follow",
                    subtitle = if (state.upcomingLoading) "Checking air dates…" else if (state.upcoming.isEmpty()) "Follow a series from its page to see new episodes here." else null,
                )
            }
            items(state.upcoming, key = { it.id }) { ep ->
                UpcomingRow(ep, onOpen = { actions.openTitle(ep.showRef.key) }, modifier = Modifier.padding(horizontal = 16.dp))
            }
        }
    }

    if (showSheet) {
        PlanNightSheet(
            saved = state.saved,
            initialKey = sheetKey,
            initialDay = state.selectedDay,
            onDismiss = { showSheet = false },
            onPlan = { night, addToCalendar ->
                if (night.remind && Build.VERSION.SDK_INT >= 33) {
                    notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
                vm.add(context, night)
                if (addToCalendar) runCatching { context.startActivity(CalendarBridge.insertIntent(night)) }
                vm.selectDay(DateParsing.localDate(night.startsAt))
                showSheet = false
            },
            isWide = isWide,
        )
    }
}

@Composable
private fun WeekStrip(
    weekStart: LocalDate,
    selected: LocalDate,
    hasPlans: (LocalDate) -> Boolean,
    onSelect: (LocalDate) -> Unit,
    onShift: (Long) -> Unit,
) {
    val colors = Couch.colors
    val today = LocalDate.now()
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onShift(-7) }) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowLeft, contentDescription = "Previous week", tint = colors.textSecondary)
        }
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.SpaceBetween) {
            (0L until 7L).map { weekStart.plusDays(it) }.forEach { day ->
                val isSelected = day == selected
                Column(
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .clickable { onSelect(day) }
                        .padding(horizontal = 4.dp, vertical = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        day.format(DateTimeFormatter.ofPattern("EEE")).take(3),
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.textSecondary,
                    )
                    Box(
                        Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(if (isSelected) colors.accent else androidx.compose.ui.graphics.Color.Transparent),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            day.dayOfMonth.toString(),
                            style = MaterialTheme.typography.titleSmall,
                            color = when {
                                isSelected -> colors.onAccent
                                day == today -> colors.accent
                                else -> colors.textPrimary
                            },
                        )
                    }
                    Box(
                        Modifier.size(4.dp).clip(CircleShape)
                            .background(if (hasPlans(day)) colors.accent else androidx.compose.ui.graphics.Color.Transparent),
                    )
                }
            }
        }
        IconButton(onClick = { onShift(7) }) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = "Next week", tint = colors.textSecondary)
        }
    }
}

@Composable
fun NightCard(
    night: CouchNight,
    onOpen: () -> Unit,
    onToggleDone: () -> Unit,
    onDelete: () -> Unit,
    onCalendar: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = Couch.colors
    val zone = ZoneId.systemDefault()
    val timeFmt = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)
    val start = Instant.ofEpochMilli(night.startsAt).atZone(zone).toLocalTime().format(timeFmt)
    val end = Instant.ofEpochMilli(night.endsAt).atZone(zone).toLocalTime().format(timeFmt)
    GroupCard(modifier = modifier) {
        Row(
            Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Poster(night.posterUrl, modifier = Modifier.width(52.dp), radius = 8.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    night.titleName,
                    style = MaterialTheme.typography.titleSmall,
                    color = if (night.isDone) colors.textSecondary else colors.textPrimary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text("$start – $end", style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (night.remind && !night.isDone) {
                        Icon(Icons.Outlined.NotificationsActive, contentDescription = "Reminder on", tint = colors.textTertiary, modifier = Modifier.size(14.dp))
                    }
                    Icon(
                        Icons.Outlined.CalendarMonth,
                        contentDescription = "Add to calendar",
                        tint = colors.textTertiary,
                        modifier = Modifier.size(14.dp).clickable(onClick = onCalendar),
                    )
                    if (night.note.isNotBlank()) {
                        Text(night.note, style = MaterialTheme.typography.labelSmall, color = colors.textTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            IconButton(onClick = onDelete) {
                Icon(Icons.Outlined.Delete, contentDescription = "Delete", tint = colors.textTertiary, modifier = Modifier.size(20.dp))
            }
            IconButton(onClick = onToggleDone) {
                Icon(
                    if (night.isDone) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                    contentDescription = if (night.isDone) "Done" else "Mark done",
                    tint = if (night.isDone) colors.success else colors.textSecondary,
                )
            }
        }
    }
}

@Composable
private fun UpcomingRow(ep: EpisodeInfo, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Couch.colors
    val date = ep.airDate?.let {
        when (it) {
            LocalDate.now() -> "Today"
            LocalDate.now().plusDays(1) -> "Tomorrow"
            else -> it.format(DateTimeFormatter.ofPattern("EEE, MMM d"))
        }
    }
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onOpen)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Artwork(url = ep.stillUrl ?: ep.showPosterUrl, modifier = Modifier.width(72.dp).height(44.dp), shape = RoundedCornerShape(8.dp))
        Column(Modifier.weight(1f)) {
            Text(ep.showName, style = MaterialTheme.typography.titleSmall, color = colors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${ep.code} · ${ep.name}", style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (date != null) Text(date, style = MaterialTheme.typography.labelMedium, color = colors.accent)
    }
}
