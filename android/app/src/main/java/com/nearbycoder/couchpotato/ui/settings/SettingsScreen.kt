package com.nearbycoder.couchpotato.ui.settings

import android.content.Intent
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.data.local.SettingsRepository
import com.nearbycoder.couchpotato.domain.CouchRank
import com.nearbycoder.couchpotato.domain.Provider
import com.nearbycoder.couchpotato.ui.components.GroupCard
import com.nearbycoder.couchpotato.ui.components.Hairline
import com.nearbycoder.couchpotato.ui.components.ProviderTile
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.screenInsets
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val vm: SettingsViewModel = viewModel { SettingsViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val keyStatus by vm.keyStatus.collectAsStateWithLifecycle()
    val message by vm.message.collectAsStateWithLifecycle()
    val colors = Couch.colors
    val isWide = isWideLayout()
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val settings = state.settings

    var nickname by remember(settings.nickname) { mutableStateOf(settings.nickname) }
    var keyDraft by remember { mutableStateOf(settings.tmdbKey) }

    LaunchedEffect(message) {
        message?.let { snackbar.showSnackbar(it); vm.clearMessage() }
    }
    LaunchedEffect(nickname) {
        if (nickname != settings.nickname) {
            kotlinx.coroutines.delay(500)
            vm.setNickname(nickname)
        }
    }

    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        uri?.let { vm.exportTo(context, it) }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { vm.importFrom(context, it) }
    }

    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        snackbarHost = { SnackbarHost(snackbar) { data -> Snackbar(data, containerColor = colors.surfaceElevated, contentColor = colors.textPrimary) } },
        topBar = {
            TopAppBar(
                title = { Text("Settings", style = MaterialTheme.typography.titleLarge, color = colors.textPrimary) },
                navigationIcon = {
                    IconButton(onClick = actions::back) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = colors.textPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            item(key = "rank") { Box(Modifier.widthIn(max = 720.dp)) { RankCard(state.rank) } }

            item(key = "you") {
                Section("You") {
                    OutlinedTextField(
                        value = nickname,
                        onValueChange = { nickname = it },
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        label = { Text("Nickname") },
                        singleLine = true,
                        shape = RoundedCornerShape(12.dp),
                        colors = fieldColors(),
                    )
                }
            }

            item(key = "services") {
                Section("My streaming services", footer = "Tonight builds its rows around the services you pick.") {
                    val columns = if (isWide) 7 else 4
                    Column(Modifier.padding(horizontal = 8.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Provider.streamers.chunked(columns).forEach { row ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                                row.forEach { p ->
                                    ProviderTile(provider = p, selected = settings.isMine(p), onClick = { vm.toggleService(p) })
                                }
                                repeat(columns - row.size) { Spacer(Modifier.size(72.dp, 1.dp)) }
                            }
                        }
                    }
                    Hairline()
                    ToggleRow("Prefer my services in Moods", "Moods lean on what you can already stream.", settings.onlyMyServices, vm::setOnlyMyServices)
                    Hairline()
                    RegionRow(current = settings.region, onSelect = vm::setRegion)
                }
            }

            item(key = "data") {
                Section(
                    "Data sources",
                    footer = "Streaming availability is provided by JustWatch via TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB. Series data from TVmaze (CC BY-SA).",
                ) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(if (settings.hasTmdb) colors.success else colors.accent))
                        Text(
                            if (settings.hasTmdb) "TMDB connected: every movie, series and service" else "Free mode: TVmaze series and Apple movie charts",
                            style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary,
                        )
                    }
                    OutlinedTextField(
                        value = keyDraft,
                        onValueChange = { keyDraft = it },
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                        label = { Text("TMDB API key or read token") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        shape = RoundedCornerShape(12.dp),
                        colors = fieldColors(),
                    )
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = { vm.testKey(keyDraft) },
                            enabled = keyDraft.isNotBlank() && keyStatus != KeyStatus.Checking,
                            shape = CircleShape,
                            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.onAccent),
                        ) { Text("Save & test") }
                        if (settings.tmdbKey.isNotEmpty()) {
                            TextButton(onClick = { keyDraft = ""; vm.removeKey() }) { Text("Remove", color = colors.danger) }
                        }
                        Spacer(Modifier.weight(1f))
                        when (val s = keyStatus) {
                            KeyStatus.Idle -> {}
                            KeyStatus.Checking -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.size(18.dp))
                            KeyStatus.Ok -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = colors.success, modifier = Modifier.size(18.dp))
                                Text("Works", color = colors.success, style = MaterialTheme.typography.labelMedium)
                            }
                            is KeyStatus.Failed -> Text(s.message, color = colors.danger, style = MaterialTheme.typography.labelSmall, modifier = Modifier.widthIn(max = 180.dp))
                        }
                    }
                    Hairline()
                    LinkRow("Get a free TMDB key") { uriHandler.openUri("https://www.themoviedb.org/settings/api") }
                }
            }

            item(key = "planner") {
                Section("Planner") {
                    ReminderRow(current = settings.remindMinutesBefore, onSelect = vm::setRemindMinutes)
                    Hairline()
                    ToggleRow("Add new couch nights to Calendar", "Pre-fills the calendar switch when planning.", settings.addNightsToCalendar, vm::setAddToCalendar)
                    Hairline()
                    ToggleRow("New episode alerts", "For series you follow.", settings.newEpisodeAlerts, vm::setNewEpisodeAlerts)
                }
            }

            item(key = "backup") {
                Section(
                    "Export / Import",
                    footer = "A JSON file with your watchlist, ratings, notes, progress and plans. Import it in Couch Potato on another device, including the Apple app.",
                ) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("${state.titleCount} titles · ${state.nightCount} plans", style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary)
                        }
                    }
                    Hairline()
                    LinkRow("Export to file", trailing = null) { exportLauncher.launch("couch-potato-backup.json") }
                    Hairline()
                    LinkRow("Share backup", trailing = null) {
                        scope.launch {
                            runCatching {
                                val file = vm.exportToCache(context)
                                val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = "application/json"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(Intent.createChooser(send, "Share backup"))
                            }
                        }
                    }
                    Hairline()
                    LinkRow("Import from file", trailing = null) { importLauncher.launch(arrayOf("application/json", "text/plain", "*/*")) }
                }
            }

            item(key = "about") {
                Section("About") {
                    LinkRow("Couch Potato on GitHub") { uriHandler.openUri("https://github.com/nearbycoder/couch-potato") }
                    Hairline()
                    LinkRow("Website") { uriHandler.openUri("https://nearbycoder.github.io/couch-potato/") }
                    Hairline()
                    LinkRow("Privacy") { uriHandler.openUri("https://nearbycoder.github.io/couch-potato/privacy.html") }
                    Hairline()
                    Row(Modifier.padding(16.dp)) {
                        Text("Version", style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary, modifier = Modifier.weight(1f))
                        Text("1.0", style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
                    }
                    Hairline()
                    Text(
                        "This product uses the TMDB API but is not endorsed or certified by TMDB. Series data from TVmaze (CC BY-SA). Couch Potato isn't affiliated with any streaming service. Spud, the couch mark on the icon, says hello.",
                        style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, modifier = Modifier.padding(16.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = Couch.colors.accent,
    unfocusedBorderColor = Couch.colors.hairline,
    cursorColor = Couch.colors.accent,
    focusedTextColor = Couch.colors.textPrimary,
    unfocusedTextColor = Couch.colors.textPrimary,
    focusedLabelColor = Couch.colors.accent,
    unfocusedLabelColor = Couch.colors.textSecondary,
)

@Composable
private fun Section(title: String, footer: String? = null, content: @Composable () -> Unit) {
    val colors = Couch.colors
    Column(Modifier.widthIn(max = 720.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, color = colors.textPrimary, modifier = Modifier.padding(horizontal = 4.dp))
        GroupCard { Column { content() } }
        if (footer != null) {
            Text(footer, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

@Composable
private fun ToggleRow(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit) {
    val colors = Couch.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
        }
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = colors.onAccent, checkedTrackColor = colors.accent),
        )
    }
}

@Composable
private fun LinkRow(title: String, trailing: androidx.compose.ui.graphics.vector.ImageVector? = Icons.AutoMirrored.Outlined.OpenInNew, onClick: () -> Unit) {
    val colors = Couch.colors
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary, modifier = Modifier.weight(1f))
        Icon(trailing ?: Icons.Outlined.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun RegionRow(current: String, onSelect: (String) -> Unit) {
    val colors = Couch.colors
    var open by remember { mutableStateOf(false) }
    val name = SettingsRepository.regions.firstOrNull { it.code == current }?.name ?: current
    Box {
        Row(
            Modifier.fillMaxWidth().clickable { open = true }.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Region", style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary, modifier = Modifier.weight(1f))
            Text(name, style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
            Spacer(Modifier.size(6.dp))
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            SettingsRepository.regions.forEach { region ->
                DropdownMenuItem(
                    text = { Text("${region.name} (${region.code})", color = if (region.code == current) colors.accent else colors.textPrimary) },
                    onClick = { onSelect(region.code); open = false },
                )
            }
        }
    }
}

@Composable
private fun ReminderRow(current: Int, onSelect: (Int) -> Unit) {
    val colors = Couch.colors
    var open by remember { mutableStateOf(false) }
    val options = listOf(0 to "At start time", 5 to "5 minutes before", 15 to "15 minutes before", 30 to "30 minutes before", 60 to "1 hour before")
    Box {
        Row(
            Modifier.fillMaxWidth().clickable { open = true }.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Couch night reminder", style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary, modifier = Modifier.weight(1f))
            Text(options.firstOrNull { it.first == current }?.second ?: "$current min before", style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
            Spacer(Modifier.size(6.dp))
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = colors.textTertiary, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (minutes, label) ->
                DropdownMenuItem(
                    text = { Text(label, color = if (minutes == current) colors.accent else colors.textPrimary) },
                    onClick = { onSelect(minutes); open = false },
                )
            }
        }
    }
}

@Composable
private fun RankCard(rank: CouchRank) {
    val colors = Couch.colors
    GroupCard {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("CouchRank", style = MaterialTheme.typography.labelMedium, color = colors.textSecondary)
                Text(rank.level.name, style = MaterialTheme.typography.headlineSmall, color = colors.textPrimary)
                Text(rank.level.quip, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
            }
            val next = rank.nextLevel
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                LinearProgressIndicator(
                    progress = { rank.progressToNext },
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(CircleShape),
                    color = colors.accent,
                    trackColor = colors.secondaryFill,
                    drawStopIndicator = {},
                )
                Text(
                    if (next != null) "${rank.points} points · ${next.threshold - rank.points} to ${next.name}" else "${rank.points} points · top level",
                    style = MaterialTheme.typography.labelSmall, color = colors.textSecondary,
                )
            }
            Row(Modifier.fillMaxWidth()) {
                Stat(rank.moviesWatched.toString(), "movies", Modifier.weight(1f))
                Stat(rank.showsWatched.toString(), "series", Modifier.weight(1f))
                Stat("${rank.hoursWatched}h", "watched", Modifier.weight(1f))
                Stat(rank.averageRating?.let { "%.1f".format(it) } ?: "–", "avg rating", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun Stat(value: String, label: String, modifier: Modifier = Modifier) {
    val colors = Couch.colors
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleLarge, color = colors.textPrimary, textAlign = TextAlign.Center)
        Text(label, style = MaterialTheme.typography.labelSmall, color = colors.textSecondary, textAlign = TextAlign.Center)
    }
}
