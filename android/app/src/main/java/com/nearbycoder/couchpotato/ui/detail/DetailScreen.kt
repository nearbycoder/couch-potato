package com.nearbycoder.couchpotato.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nearbycoder.couchpotato.data.local.SavedTitle
import com.nearbycoder.couchpotato.domain.CatalogSource
import com.nearbycoder.couchpotato.domain.EpisodeInfo
import com.nearbycoder.couchpotato.domain.MediaKind
import com.nearbycoder.couchpotato.domain.OfferKind
import com.nearbycoder.couchpotato.domain.ProviderOffer
import com.nearbycoder.couchpotato.domain.TitleDetail
import com.nearbycoder.couchpotato.domain.WatchStatus
import com.nearbycoder.couchpotato.domain.runtimeLabel
import com.nearbycoder.couchpotato.ui.components.Artwork
import com.nearbycoder.couchpotato.ui.components.Avatar
import com.nearbycoder.couchpotato.ui.components.ChipRow
import com.nearbycoder.couchpotato.ui.components.ErrorBanner
import com.nearbycoder.couchpotato.ui.components.GroupCard
import com.nearbycoder.couchpotato.ui.components.Poster
import com.nearbycoder.couchpotato.ui.components.PosterRow
import com.nearbycoder.couchpotato.ui.components.PrimaryButton
import com.nearbycoder.couchpotato.ui.components.ProviderTile
import com.nearbycoder.couchpotato.ui.components.SecondaryButton
import com.nearbycoder.couchpotato.ui.components.SectionHeader
import com.nearbycoder.couchpotato.ui.components.StarRating
import com.nearbycoder.couchpotato.ui.components.StatusBadge
import com.nearbycoder.couchpotato.ui.navigation.LocalAppContainer
import com.nearbycoder.couchpotato.ui.navigation.LocalAppEvents
import com.nearbycoder.couchpotato.ui.navigation.NavActions
import com.nearbycoder.couchpotato.ui.navigation.edgeToEdgeInsets
import com.nearbycoder.couchpotato.ui.navigation.PlannerRoute
import com.nearbycoder.couchpotato.ui.navigation.isWideLayout
import com.nearbycoder.couchpotato.ui.theme.Couch
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@Composable
fun DetailScreen(titleKey: String, actions: NavActions) {
    val container = LocalAppContainer.current
    val events = LocalAppEvents.current
    val vm: DetailViewModel = viewModel(key = "detail-$titleKey") { DetailViewModel(container, titleKey) }
    val state by vm.state.collectAsStateWithLifecycle()
    val saved by vm.saved.collectAsStateWithLifecycle()
    val colors = Couch.colors
    val isWide = isWideLayout()
    val uriHandler = LocalUriHandler.current
    val posterWidth = if (isWide) 150.dp else 120.dp

    Scaffold(containerColor = colors.bg, contentWindowInsets = edgeToEdgeInsets()) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            val detail = state.detail
            when {
                detail != null -> DetailContent(
                    detail = detail,
                    state = state,
                    saved = saved,
                    isWide = isWide,
                    posterWidth = posterWidth,
                    vm = vm,
                    actions = actions,
                    onPlan = {
                        if (saved == null) vm.save(WatchStatus.QUEUED)
                        events.pendingPlanKey = titleKey
                        actions.selectTab(PlannerRoute)
                    },
                    onOpen = { url -> runCatching { uriHandler.openUri(url) } },
                )
                state.loading -> CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.Center))
                else -> Column(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars)) {
                    Spacer(Modifier.height(16.dp))
                    ErrorBanner(state.error ?: "Couldn't load this title.", onRetry = vm::load)
                }
            }
            BackButton(onClick = actions::back, modifier = Modifier.align(Alignment.TopStart))
        }
    }
}

@Composable
private fun BackButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    IconButton(
        onClick = onClick,
        modifier = modifier
            .windowInsetsPadding(WindowInsets.statusBars)
            .padding(8.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.35f)),
    ) {
        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = Color.White)
    }
}

@Composable
private fun DetailContent(
    detail: TitleDetail,
    state: DetailState,
    saved: SavedTitle?,
    isWide: Boolean,
    posterWidth: androidx.compose.ui.unit.Dp,
    vm: DetailViewModel,
    actions: NavActions,
    onPlan: () -> Unit,
    onOpen: (String) -> Unit,
) {
    val colors = Couch.colors
    val title = detail.title
    LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        item(key = "header") {
            Header(detail = detail, saved = saved, isWide = isWide, vm = vm, onPlan = onPlan, onOpen = onOpen)
        }

        if (!detail.availability.isEmpty || title.providers.isNotEmpty()) {
            item(key = "where") {
                WhereToWatch(detail = detail, usesTmdb = state.usesTmdbAvailability, onOpen = onOpen)
            }
        }

        if (title.overview.isNotBlank() || title.genres.isNotEmpty()) {
            item(key = "overview") {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (detail.tagline != null) {
                        Text(detail.tagline, style = MaterialTheme.typography.titleMedium, color = colors.textSecondary)
                    }
                    if (title.overview.isNotBlank()) {
                        Text(title.overview, style = MaterialTheme.typography.bodyLarge, color = colors.textPrimary, modifier = Modifier.widthIn(max = 720.dp))
                    }
                    if (title.genres.isNotEmpty()) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                items(title.genres, key = { it }) { genre ->
                                    Box(
                                        Modifier.clip(CircleShape).background(colors.secondaryFill).padding(horizontal = 12.dp, vertical = 6.dp),
                                    ) { Text(genre, style = MaterialTheme.typography.labelMedium, color = colors.textPrimary) }
                                }
                            }
                        }
                    }
                    val facts = buildList {
                        detail.creators.takeIf { it.isNotEmpty() }?.let { add((if (title.kind == MediaKind.TV) "Created by " else "By ") + it.joinToString(", ")) }
                        title.network?.let { add(it) }
                        title.status?.let { add(it) }
                        title.certification?.let { add("Rated $it") }
                    }
                    if (facts.isNotEmpty()) {
                        Text(facts.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                    }
                }
            }
        }

        if (saved != null) {
            item(key = "personal") { PersonalSection(saved = saved, vm = vm) }
        }

        detail.nextEpisode?.let { next ->
            item(key = "next") { NextEpisodeCard(next) }
        }

        if (detail.seasons.isNotEmpty()) {
            item(key = "seasons") {
                SeasonsSection(detail = detail, state = state, saved = saved, onSelect = vm::selectSeason, onMark = vm::markWatchedThrough)
            }
        }

        if (detail.cast.isNotEmpty()) {
            item(key = "cast") {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    SectionHeader(title = "Cast")
                    LazyRow(contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                        items(detail.cast, key = { it.id }) { member ->
                            Column(Modifier.width(84.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                Avatar(member.photoUrl, size = 68.dp)
                                Spacer(Modifier.height(6.dp))
                                Text(member.name, style = MaterialTheme.typography.labelMedium, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                                if (member.character.isNotBlank()) {
                                    Text(member.character, style = MaterialTheme.typography.labelSmall, color = colors.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
            }
        }

        if (detail.similar.isNotEmpty()) {
            item(key = "similar") {
                PosterRow(title = "More like this", titles = detail.similar, posterWidth = posterWidth, onOpen = { actions.openTitle(it.ref.key) })
            }
        }

        item(key = "source") {
            Text(
                "Source: ${title.ref.source.displayName}",
                style = MaterialTheme.typography.labelSmall,
                color = colors.textTertiary,
                modifier = Modifier.padding(horizontal = 16.dp).clickable { onOpen(title.ref.webUrl) },
            )
        }
    }
}

@Composable
private fun Header(
    detail: TitleDetail,
    saved: SavedTitle?,
    isWide: Boolean,
    vm: DetailViewModel,
    onPlan: () -> Unit,
    onOpen: (String) -> Unit,
) {
    val colors = Couch.colors
    val title = detail.title
    var statusMenu by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().aspectRatio(if (isWide) 21f / 9f else 16f / 10f)) {
            Artwork(
                url = title.backdropUrl ?: title.posterUrl,
                modifier = Modifier.fillMaxSize(),
                shape = RectangleShape,
                placeholderIcon = null,
                bordered = false,
            )
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(0f to colors.bg.copy(alpha = 0.35f), 0.35f to Color.Transparent, 1f to colors.bg),
                ),
            )
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(horizontal = 16.dp)
                .offsetY(if (isWide) 56.dp else 72.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Poster(title.posterUrl, modifier = Modifier.width(if (isWide) 150.dp else 112.dp), radius = 14.dp, contentDescription = title.name)
            Column(Modifier.weight(1f).padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(title.name, style = MaterialTheme.typography.headlineMedium, color = colors.textPrimary, maxLines = 3, overflow = TextOverflow.Ellipsis)
                Text(
                    buildList {
                        title.year?.let { add(it.toString()) }
                        add(title.kind.label)
                        title.runtime?.takeIf { it > 0 }?.let { add(it.runtimeLabel + if (title.kind == MediaKind.TV) " eps" else "") }
                        detail.seasons.takeIf { it.isNotEmpty() }?.let { add("${it.size} season${if (it.size == 1) "" else "s"}") }
                    }.joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary,
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    title.score?.let {
                        Text("★ " + "%.1f".format(it), style = MaterialTheme.typography.titleSmall, color = colors.accent)
                    }
                    if (saved != null) StatusBadge(saved.watchStatus)
                }
            }
        }
    }
    Spacer(Modifier.height(if (isWide) 64.dp else 80.dp))
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box {
            if (saved == null) {
                PrimaryButton(text = "Add to Watchlist", icon = Icons.Outlined.Add, onClick = { vm.save(WatchStatus.QUEUED) })
            } else {
                PrimaryButton(text = saved.watchStatus.label, icon = Icons.Outlined.KeyboardArrowDown, onClick = { statusMenu = true })
            }
            DropdownMenu(expanded = statusMenu, onDismissRequest = { statusMenu = false }) {
                WatchStatus.entries.forEach { status ->
                    DropdownMenuItem(
                        text = { Text(status.label, color = if (status == saved?.watchStatus) colors.accent else colors.textPrimary) },
                        onClick = { vm.setStatus(status); statusMenu = false },
                    )
                }
                DropdownMenuItem(text = { Text("Remove from Watchlist", color = colors.danger) }, onClick = { vm.remove(); statusMenu = false })
            }
        }
        SecondaryButton(text = "Plan it", icon = Icons.Outlined.Event, onClick = onPlan)
        detail.trailerUrl?.let { url ->
            SecondaryButton(text = "Trailer", icon = Icons.Outlined.PlayArrow, onClick = { onOpen(url) })
        }
    }
}

private fun Modifier.offsetY(y: androidx.compose.ui.unit.Dp): Modifier = this.offset(y = y)

@Composable
private fun WhereToWatch(detail: TitleDetail, usesTmdb: Boolean, onOpen: (String) -> Unit) {
    val colors = Couch.colors
    val availability = detail.availability
    val groups: List<Pair<String, List<ProviderOffer>>> = buildList {
        val stream = availability.offers(OfferKind.STREAM)
        val free = availability.offers(OfferKind.FREE) + availability.offers(OfferKind.ADS)
        val rent = availability.offers(OfferKind.RENT)
        val buy = availability.offers(OfferKind.BUY)
        if (stream.isNotEmpty()) add("Stream" to stream)
        if (free.isNotEmpty()) add("Free" to free)
        if (rent.isNotEmpty()) add("Rent" to rent)
        if (buy.isNotEmpty()) add("Buy" to buy)
        if (isEmpty() && detail.title.providers.isNotEmpty()) {
            add("Stream" to detail.title.providers.map { ProviderOffer(provider = it, kind = OfferKind.STREAM, link = it.searchUrl(detail.title.name)) })
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(
            title = "Where to Watch",
            subtitle = "Region ${availability.region}",
            actionLabel = availability.link?.let { "More" },
            onAction = availability.link?.let { link -> { onOpen(link) } },
        )
        GroupCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            Column(Modifier.padding(vertical = 8.dp)) {
                groups.forEach { (label, offers) ->
                    Row(Modifier.padding(start = 16.dp, top = 8.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(label, style = MaterialTheme.typography.labelMedium, color = colors.textSecondary)
                    }
                    LazyRow(contentPadding = PaddingValues(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(offers, key = { it.id }) { offer ->
                            ProviderTile(
                                provider = offer.provider,
                                logoUrl = offer.logoUrl,
                                caption = offer.price,
                                onClick = {
                                    val link = offer.link ?: offer.provider.searchUrl(detail.title.name) ?: availability.link
                                    if (link != null) onOpen(link)
                                },
                            )
                        }
                    }
                }
                if (groups.isEmpty()) {
                    Text("No streaming info for this region yet.", style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, modifier = Modifier.padding(16.dp))
                }
            }
        }
        if (usesTmdb) {
            Text(
                "Streaming availability provided by JustWatch via TMDB.",
                style = MaterialTheme.typography.labelSmall,
                color = colors.textTertiary,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

@Composable
private fun PersonalSection(saved: SavedTitle, vm: DetailViewModel) {
    val colors = Couch.colors
    var notes by remember(saved.key) { mutableStateOf(saved.notes) }
    LaunchedEffect(notes) {
        if (notes != saved.notes) {
            kotlinx.coroutines.delay(600)
            vm.setNotes(notes)
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(title = "Your take")
        GroupCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Rating", style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    StarRating(rating = saved.rating, size = 24.dp, onChange = vm::setRating)
                }
                if (saved.mediaKind == MediaKind.TV) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("Follow new episodes", style = MaterialTheme.typography.bodyMedium, color = colors.textPrimary)
                            Text("Shows up in Planner when a new episode airs.", style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                        }
                        Switch(
                            checked = saved.isFollowing,
                            onCheckedChange = vm::setFollowing,
                            colors = SwitchDefaults.colors(checkedThumbColor = colors.onAccent, checkedTrackColor = colors.accent),
                        )
                    }
                }
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Notes", color = colors.textTertiary) },
                    minLines = 2,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.hairline,
                        cursorColor = colors.accent,
                        focusedTextColor = colors.textPrimary,
                        unfocusedTextColor = colors.textPrimary,
                    ),
                )
            }
        }
    }
}

@Composable
private fun NextEpisodeCard(next: EpisodeInfo) {
    val colors = Couch.colors
    val dateText = next.airDate?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(title = "Next episode")
        GroupCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Artwork(url = next.stillUrl ?: next.showPosterUrl, modifier = Modifier.width(112.dp).aspectRatio(16f / 9f), shape = RoundedCornerShape(8.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(next.code + (if (next.name.isNotBlank()) " · ${next.name}" else ""), style = MaterialTheme.typography.titleSmall, color = colors.textPrimary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (dateText != null) Text(dateText, style = MaterialTheme.typography.bodySmall, color = colors.accent)
                    if (next.overview.isNotBlank()) Text(next.overview, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun SeasonsSection(
    detail: TitleDetail,
    state: DetailState,
    saved: SavedTitle?,
    onSelect: (Int) -> Unit,
    onMark: (EpisodeInfo) -> Unit,
) {
    val colors = Couch.colors
    val seasons = detail.seasons
    val selectedIndex = seasons.indexOfFirst { it.number == state.selectedSeason }.coerceAtLeast(0)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeader(title = "Episodes", subtitle = saved?.progressLabel ?: "Tap an episode to mark watched through there.")
        Row(Modifier.padding(horizontal = 16.dp)) {
            androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(seasons, key = { it.number }) { season ->
                    val isSelected = seasons.indexOf(season) == selectedIndex
                    Box(
                        Modifier
                            .clip(CircleShape)
                            .background(if (isSelected) colors.accent else colors.secondaryFill)
                            .clickable { onSelect(season.number) }
                            .padding(horizontal = 14.dp, vertical = 8.dp),
                    ) {
                        Text(season.name, style = MaterialTheme.typography.labelMedium, color = if (isSelected) colors.onAccent else colors.textPrimary)
                    }
                }
            }
        }
        GroupCard(modifier = Modifier.padding(horizontal = 16.dp)) {
            if (state.episodesLoading) {
                Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = colors.accent, modifier = Modifier.size(24.dp))
                }
            } else if (state.episodes.isEmpty()) {
                Text("No episode list available.", style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, modifier = Modifier.padding(16.dp))
            } else {
                Column {
                    state.episodes.forEachIndexed { index, ep ->
                        val watched = saved != null && (saved.lastSeason > ep.season || (saved.lastSeason == ep.season && saved.lastEpisode >= ep.number))
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable { onMark(ep) }
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Icon(
                                if (watched) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                                contentDescription = if (watched) "Watched" else "Not watched",
                                tint = if (watched) colors.success else colors.textTertiary,
                                modifier = Modifier.size(22.dp),
                            )
                            Column(Modifier.weight(1f)) {
                                Text("${ep.number}. ${ep.name}", style = MaterialTheme.typography.bodyMedium, color = if (watched) colors.textSecondary else colors.textPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                val meta = listOfNotNull(
                                    ep.airDate?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)),
                                    ep.runtime?.takeIf { it > 0 }?.runtimeLabel,
                                )
                                if (meta.isNotEmpty()) Text(meta.joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                            }
                        }
                        if (index < state.episodes.lastIndex) {
                            Box(Modifier.fillMaxWidth().padding(start = 46.dp).height(1.dp).background(colors.hairline))
                        }
                    }
                }
            }
        }
        if (detail.title.ref.source == CatalogSource.TVMAZE) {
            Text("Episode data from TVmaze (CC BY-SA).", style = MaterialTheme.typography.labelSmall, color = colors.textTertiary, modifier = Modifier.padding(horizontal = 16.dp))
        }
    }
}
