package com.nearbycoder.couchpotato.ui.ask

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.domain.ai.AiStatus
import com.nearbycoder.couchpotato.ui.components.EmptyState
import com.nearbycoder.couchpotato.ui.components.PosterGrid
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.navigation.screenInsets
import com.nearbycoder.couchpotato.ui.theme.Couch

/** "Ask Couch Potato": describe what you want to watch, get a grid of matches. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AskScreen(actions: NavActions) {
    val container = LocalAppContainer.current
    val vm: AskViewModel = viewModel { AskViewModel(container) }
    val state by vm.state.collectAsStateWithLifecycle()
    val status by vm.status.collectAsStateWithLifecycle()
    val colors = Couch.colors
    val isWide = isWideLayout()
    val focus = LocalFocusManager.current
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        if (state.phase == AskPhase.IDLE) runCatching { focusRequester.requestFocus() }
    }

    fun submit(text: String = state.text) {
        focus.clearFocus()
        vm.ask(text)
    }

    Scaffold(
        containerColor = colors.bg,
        contentWindowInsets = screenInsets(),
        topBar = {
            TopAppBar(
                title = { Text("Ask Couch Potato", style = MaterialTheme.typography.titleLarge, color = colors.textPrimary) },
                navigationIcon = {
                    IconButton(onClick = actions::back) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = colors.textPrimary)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = colors.bg, scrolledContainerColor = colors.bg),
            )
        },
    ) { padding ->
        PosterGrid(
            titles = if (state.phase == AskPhase.DONE) state.titles else emptyList(),
            isWide = isWide,
            onOpen = { actions.openTitle(it.ref.key) },
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 32.dp),
            header = {
                item(key = "field", span = { GridItemSpan(maxLineSpan) }) {
                    RequestField(
                        text = state.text,
                        onText = vm::setText,
                        onSubmit = { submit() },
                        enabled = !state.busy,
                        modifier = Modifier.focusRequester(focusRequester),
                    )
                }
                if (status is AiStatus.Downloadable || status is AiStatus.Downloading) {
                    item(key = "model", span = { GridItemSpan(maxLineSpan) }) {
                        ModelDownloadRow(status = status, onDownload = vm::download)
                    }
                }
                item(key = "examples", span = { GridItemSpan(maxLineSpan) }) {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(vm.examples.size, key = { vm.examples[it] }) { i ->
                            val example = vm.examples[i]
                            Pill(example, onClick = { vm.setText(example); submit(example) }, prominent = true)
                        }
                    }
                }
                item(key = "status", span = { GridItemSpan(maxLineSpan) }) {
                    ResultsHeader(state)
                }
            },
        )
    }
}

@Composable
private fun RequestField(
    text: String,
    onText: (String) -> Unit,
    onSubmit: () -> Unit,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = Couch.colors
    TextField(
        value = text,
        onValueChange = onText,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text("Describe what you want to watch", color = colors.textTertiary) },
        leadingIcon = { Icon(Icons.Outlined.AutoAwesome, contentDescription = null, tint = colors.accent) },
        trailingIcon = {
            IconButton(
                onClick = onSubmit,
                enabled = enabled && text.isNotBlank(),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = colors.accent,
                    contentColor = colors.onAccent,
                    disabledContainerColor = colors.secondaryFill,
                    disabledContentColor = colors.textTertiary,
                ),
                modifier = Modifier.padding(end = 4.dp).size(36.dp),
            ) {
                Icon(Icons.Outlined.ArrowUpward, contentDescription = "Find", modifier = Modifier.size(20.dp))
            }
        },
        singleLine = true,
        shape = CircleShape,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { if (enabled) onSubmit() }),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = colors.surfaceElevated,
            unfocusedContainerColor = colors.surface,
            disabledContainerColor = colors.surface,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            cursorColor = colors.accent,
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
        ),
    )
}

/** Small affordance to fetch Gemini Nano, or its progress while AICore downloads it. */
@Composable
private fun ModelDownloadRow(status: AiStatus, onDownload: () -> Unit) {
    val colors = Couch.colors
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.surface)
            .border(1.dp, colors.hairline, shape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (status is AiStatus.Downloading) "Downloading on-device model" else "Download on-device model",
                    style = MaterialTheme.typography.titleSmall,
                    color = colors.textPrimary,
                )
                Text(
                    "Understands requests in your own words. Until then, results come from a plain search.",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.textSecondary,
                )
            }
            if (status is AiStatus.Downloadable) {
                TextButton(onClick = onDownload) { Text("Download", color = colors.accent) }
            }
        }
        if (status is AiStatus.Downloading) {
            val progress = status.progress
            if (progress != null) {
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape),
                    color = colors.accent,
                    trackColor = colors.secondaryFill,
                    drawStopIndicator = {},
                )
            } else {
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape),
                    color = colors.accent,
                    trackColor = colors.secondaryFill,
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ResultsHeader(state: AskState) {
    val colors = Couch.colors
    Column(Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when (state.phase) {
            AskPhase.IDLE -> {}
            AskPhase.THINKING, AskPhase.SEARCHING -> Row(
                Modifier.fillMaxWidth().padding(vertical = 24.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(color = colors.accent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                Text(
                    if (state.phase == AskPhase.THINKING) "Reading your request" else "Finding titles",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.textSecondary,
                    modifier = Modifier.padding(start = 10.dp),
                )
            }
            AskPhase.DONE -> {
                val query = state.query
                if (query != null) {
                    Text(
                        query.summary.ifBlank { "“${state.request}”" },
                        style = MaterialTheme.typography.titleLarge,
                        color = colors.textPrimary,
                    )
                    val chips = query.chips
                    if (chips.isNotEmpty()) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            chips.forEach { Pill(it) }
                        }
                    }
                }
                state.modelError?.let { ErrorLine(it) }
                state.error?.let { ErrorLine(it) }
                if (state.relaxed && state.titles.isNotEmpty()) {
                    Text(
                        "Nothing matched exactly, so some filters were loosened.",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.textSecondary,
                    )
                }
                if (state.titles.isEmpty() && state.error == null) {
                    EmptyState(
                        icon = Icons.Outlined.SearchOff,
                        headline = "No matches",
                        footnote = "Try describing it differently, or ask for something broader.",
                    )
                }
            }
        }
    }
}

@Composable
private fun ErrorLine(message: String) {
    val colors = Couch.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = colors.danger, modifier = Modifier.size(16.dp))
        Text(message, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
    }
}

/** A capsule label; read-only unless [onClick] is given. */
@Composable
private fun Pill(label: String, onClick: (() -> Unit)? = null, prominent: Boolean = false) {
    val colors = Couch.colors
    Box(
        Modifier
            .clip(CircleShape)
            .background(colors.secondaryFill)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = if (prominent) 14.dp else 10.dp, vertical = if (prominent) 8.dp else 5.dp),
    ) {
        Text(
            label,
            style = if (prominent) MaterialTheme.typography.labelMedium else MaterialTheme.typography.labelSmall,
            color = if (prominent) colors.textPrimary else colors.textSecondary,
            maxLines = 1,
        )
    }
}
