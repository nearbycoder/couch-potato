package com.nearbycoder.couchpotato.ui.planner

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nearbycoder.couchpotato.data.local.CouchNight
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.WatchStatus
import com.nearbycoder.couchpotato.domain.runtimeLabel
import com.nearbycoder.couchpotato.ui.components.ChipRow
import com.nearbycoder.couchpotato.ui.components.Poster
import com.nearbycoder.couchpotato.ui.components.PrimaryButton
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.theme.Couch
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.TemporalAdjusters

private data class QuickPick(val label: String, val at: () -> LocalDateTime)

private val quickPicks = listOf(
    QuickPick("Tonight 8pm") { LocalDate.now().atTime(20, 0) },
    QuickPick("Tomorrow 8pm") { LocalDate.now().plusDays(1).atTime(20, 0) },
    QuickPick("Saturday 7pm") { LocalDate.now().with(TemporalAdjusters.next(DayOfWeek.SATURDAY)).atTime(19, 0) },
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanNightSheet(
    saved: List<SavedTitle>,
    initialKey: String?,
    initialDay: LocalDate,
    onDismiss: () -> Unit,
    onPlan: (CouchNight, Boolean) -> Unit,
    isWide: Boolean,
) {
    val colors = Couch.colors
    val settings = LocalAppContainer.current.settings.current
    val sheetState = rememberBottomSheetState(initialValue = SheetValue.Hidden, enabledValues = setOf(SheetValue.Hidden, SheetValue.Expanded))
    val candidates = remember(saved) {
        saved.filter { it.watchStatus == WatchStatus.QUEUED || it.watchStatus == WatchStatus.WATCHING }
            .sortedByDescending { it.updatedAt }
            .let { list -> if (initialKey != null) list.sortedByDescending { it.key == initialKey } else list }
    }
    var selectedKey by remember { mutableStateOf(initialKey ?: candidates.firstOrNull()?.key) }
    val selected = remember(selectedKey, saved) { saved.firstOrNull { it.key == selectedKey } }
    var dateTime by remember {
        mutableStateOf(
            if (initialDay == LocalDate.now() && LocalTime.now().isAfter(LocalTime.of(20, 0))) {
                LocalDateTime.now().plusMinutes(30).withSecond(0).withNano(0)
            } else initialDay.atTime(20, 0),
        )
    }
    var duration by remember(selected?.key) { mutableIntStateOf(selected?.runtime?.takeIf { it > 0 }?.let { ((it + 14) / 15) * 15 } ?: 120) }
    var note by remember { mutableStateOf("") }
    var remind by remember { mutableStateOf(true) }
    var addToCalendar by remember { mutableStateOf(settings.addNightsToCalendar) }
    var showDate by remember { mutableStateOf(false) }
    var showTime by remember { mutableStateOf(false) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState, containerColor = colors.surfaceElevated) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Plan a night", style = MaterialTheme.typography.headlineSmall, color = colors.textPrimary, modifier = Modifier.padding(horizontal = 20.dp))

            if (candidates.isEmpty()) {
                Text(
                    "Add something to your watchlist first, then plan a night for it.",
                    style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            } else {
                LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(candidates, key = { it.key }) { t ->
                        val isSel = t.key == selectedKey
                        Column(
                            Modifier
                                .width(84.dp)
                                .clip(RoundedCornerShape(10.dp))
                                .clickable { selectedKey = t.key }
                                .padding(3.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Box(
                                Modifier
                                    .clip(RoundedCornerShape(10.dp))
                                    .then(if (isSel) Modifier.background(colors.accent).padding(2.dp) else Modifier.padding(2.dp)),
                            ) {
                                Poster(t.posterUrl, modifier = Modifier.fillMaxWidth(), radius = 8.dp)
                            }
                            Spacer(Modifier.height(4.dp))
                            Text(t.name, style = MaterialTheme.typography.labelSmall, color = if (isSel) colors.textPrimary else colors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }

            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("When", style = MaterialTheme.typography.labelMedium, color = colors.textSecondary)
                ChipRow(
                    options = quickPicks.map { it.label },
                    selected = quickPicks.indexOfFirst { it.at() == dateTime },
                    onSelect = { dateTime = quickPicks[it].at() },
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    FieldButton(dateTime.toLocalDate().format(DateTimeFormatter.ofPattern("EEE, MMM d")), modifier = Modifier.weight(1f)) { showDate = true }
                    FieldButton(dateTime.toLocalTime().format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)), modifier = Modifier.weight(1f)) { showTime = true }
                }
            }

            Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("How long", style = MaterialTheme.typography.labelMedium, color = colors.textSecondary)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    IconButton(onClick = { duration = (duration - 15).coerceAtLeast(15) }) {
                        Icon(Icons.Outlined.Remove, contentDescription = "Shorter", tint = colors.textPrimary)
                    }
                    Text(duration.runtimeLabel, style = MaterialTheme.typography.titleMedium, color = colors.textPrimary, modifier = Modifier.widthIn(min = 64.dp))
                    IconButton(onClick = { duration = (duration + 15).coerceAtMost(600) }) {
                        Icon(Icons.Outlined.Add, contentDescription = "Longer", tint = colors.textPrimary)
                    }
                    Spacer(Modifier.weight(1f))
                    Text(
                        "Ends " + dateTime.plusMinutes(duration.toLong()).toLocalTime().format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT)),
                        style = MaterialTheme.typography.bodySmall, color = colors.textSecondary,
                    )
                }
            }

            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                placeholder = { Text("Note (snacks, who's coming…)", color = colors.textTertiary) },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = colors.accent, unfocusedBorderColor = colors.hairline, cursorColor = colors.accent,
                    focusedTextColor = colors.textPrimary, unfocusedTextColor = colors.textPrimary,
                ),
            )

            Column(Modifier.padding(horizontal = 20.dp)) {
                ToggleRow("Remind me", "${settings.remindMinutesBefore} minutes before, as a notification.", remind) { remind = it }
                ToggleRow("Add to Calendar", "Opens your calendar app with the event filled in.", addToCalendar) { addToCalendar = it }
            }

            PrimaryButton(
                text = "Plan it",
                enabled = selected != null,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                onClick = {
                    val t = selected ?: return@PrimaryButton
                    val startsAt = dateTime.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
                    onPlan(
                        CouchNight(
                            titleKey = t.key, titleName = t.name, posterUrl = t.posterUrl, startsAt = startsAt,
                            durationMinutes = duration, note = note.trim(), remind = remind,
                        ),
                        addToCalendar,
                    )
                },
            )
        }
    }

    if (showDate) {
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = dateTime.toLocalDate().atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showDate = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { millis ->
                        val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        dateTime = date.atTime(dateTime.toLocalTime())
                    }
                    showDate = false
                }) { Text("OK", color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { showDate = false }) { Text("Cancel", color = colors.textSecondary) } },
        ) { DatePicker(state = pickerState) }
    }

    if (showTime) {
        val timeState = rememberTimePickerState(initialHour = dateTime.hour, initialMinute = dateTime.minute)
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showTime = false },
            confirmButton = {
                TextButton(onClick = {
                    dateTime = dateTime.toLocalDate().atTime(timeState.hour, timeState.minute)
                    showTime = false
                }) { Text("OK", color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { showTime = false }) { Text("Cancel", color = colors.textSecondary) } },
            text = { TimePicker(state = timeState) },
            containerColor = colors.surfaceElevated,
        )
    }
}

@Composable
private fun FieldButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = Couch.colors
    Box(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(colors.secondaryFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary, maxLines = 1)
    }
}

@Composable
private fun ToggleRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = Couch.colors
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
        }
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = colors.onAccent, checkedTrackColor = colors.accent),
        )
    }
}
