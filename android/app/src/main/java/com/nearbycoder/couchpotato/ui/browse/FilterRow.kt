package com.nearbycoder.couchpotato.ui.browse

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nearbycoder.couchpotato.domain.Genre
import com.nearbycoder.couchpotato.domain.TitleFilter
import com.nearbycoder.couchpotato.domain.TitleSort
import com.nearbycoder.couchpotato.domain.YearRange
import com.nearbycoder.couchpotato.ui.theme.Couch

private val ratingOptions: List<Double?> = listOf(null, 6.0, 7.0, 8.0)
private fun ratingLabel(min: Double?): String = min?.let { "${it.toInt()}+" } ?: "Any"

/** Sort, year, genre and rating dropdown chips that wrap on narrow screens, plus Reset. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FilterRow(
    filter: TitleFilter,
    onChange: (TitleFilter) -> Unit,
    showGenre: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = Couch.colors
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        FilterChipMenu(
            label = "Sort: ${filter.sort.label}",
            active = filter.sort != TitleSort.POPULAR,
            options = TitleSort.entries,
            selected = filter.sort,
            optionLabel = { it.label },
            onSelect = { onChange(filter.copy(sort = it)) },
        )
        FilterChipMenu(
            label = "Year: " + if (filter.years == YearRange.ANY) "Any" else filter.years.label,
            active = filter.years != YearRange.ANY,
            options = YearRange.entries,
            selected = filter.years,
            optionLabel = { it.label },
            onSelect = { onChange(filter.copy(years = it)) },
        )
        if (showGenre) {
            FilterChipMenu(
                label = "Genre: ${filter.genre?.label ?: "Any"}",
                active = filter.genre != null,
                options = listOf<Genre?>(null) + Genre.entries,
                selected = filter.genre,
                optionLabel = { it?.label ?: "Any Genre" },
                onSelect = { onChange(filter.copy(genre = it)) },
            )
        }
        FilterChipMenu(
            label = "Rating: ${ratingLabel(filter.minRating)}",
            active = filter.minRating != null,
            options = ratingOptions,
            selected = filter.minRating,
            optionLabel = { it?.let { r -> "${r.toInt()}+" } ?: "Any Rating" },
            onSelect = { onChange(filter.copy(minRating = it)) },
        )
        if (!filter.isDefault) {
            TextButton(
                onClick = { onChange(TitleFilter()) },
                contentPadding = PaddingValues(horizontal = 10.dp),
                modifier = Modifier.heightIn(min = 32.dp),
            ) {
                Text("Reset", style = MaterialTheme.typography.labelMedium, color = colors.accent)
            }
        }
    }
}

@Composable
private fun <T> FilterChipMenu(
    label: String,
    active: Boolean,
    options: List<T>,
    selected: T,
    optionLabel: (T) -> String,
    onSelect: (T) -> Unit,
) {
    val colors = Couch.colors
    var open by remember { mutableStateOf(false) }
    val content = if (active) colors.accent else colors.textPrimary
    Box {
        Row(
            modifier = Modifier
                .clip(CircleShape)
                .background(if (active) colors.accent.copy(alpha = 0.16f) else colors.secondaryFill)
                .then(if (active) Modifier.border(1.dp, colors.accent.copy(alpha = 0.45f), CircleShape) else Modifier)
                .clickable(role = Role.DropdownList) { open = true }
                .padding(start = 12.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = content, maxLines = 1)
            Spacer(Modifier.width(2.dp))
            Icon(Icons.Outlined.ExpandMore, contentDescription = null, tint = content, modifier = Modifier.size(16.dp))
        }
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false },
            containerColor = colors.surfaceElevated,
        ) {
            options.forEach { option ->
                val isSelected = option == selected
                DropdownMenuItem(
                    text = {
                        Text(
                            optionLabel(option),
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (isSelected) colors.accent else colors.textPrimary,
                        )
                    },
                    trailingIcon = {
                        if (isSelected) Icon(Icons.Outlined.Check, contentDescription = "Selected", tint = colors.accent, modifier = Modifier.size(18.dp))
                    },
                    onClick = {
                        open = false
                        if (!isSelected) onSelect(option)
                    },
                )
            }
        }
    }
}
