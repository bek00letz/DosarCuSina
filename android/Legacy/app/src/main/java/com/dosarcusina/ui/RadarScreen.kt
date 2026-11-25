package com.dosarcusina.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.dosarcusina.data.AssetCategory
import com.dosarcusina.data.EventWithAsset
import com.dosarcusina.data.LifecycleEventEntity
import com.dosarcusina.ui.theme.AppleBlue
import com.dosarcusina.ui.theme.AppleGreen
import com.dosarcusina.ui.theme.AppleOrange
import com.dosarcusina.ui.theme.AppleRed
import com.dosarcusina.ui.theme.PillShape
import com.dosarcusina.ui.theme.SquircleInnerBadge
import com.dosarcusina.ui.theme.SquircleOuterCard
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun RadarScreen(
    events: List<EventWithAsset> = emptyList(),
    selectedCategoryRaw: String? = null,
    onCategorySelect: (String?) -> Unit = {},
    onToggleComplete: (eventId: String, completed: Boolean) -> Unit = { _, _ -> },
    onEventClick: (eventId: String) -> Unit = {},
    onAddClick: () -> Unit = {}
) {
    var selectedCat by remember { mutableStateOf(selectedCategoryRaw) }

    val filteredEvents = remember(events, selectedCat) {
        if (selectedCat == null) events
        else events.filter { it.asset?.categoryRaw.equals(selectedCat, ignoreCase = true) }
    }

    val pendingEvents = filteredEvents.filter { !it.event.isCompleted }
    val urgentOrOverdue = pendingEvents.filter { it.event.isUrgent || it.event.isOverdue }
    val upcomingEvents = pendingEvents.filter { !it.event.isUrgent && !it.event.isOverdue && it.event.daysRemaining in 8..30 }
    val laterEvents = pendingEvents.filter { !it.event.isUrgent && !it.event.isOverdue && it.event.daysRemaining > 30 }
    val completedEvents = filteredEvents.filter { it.event.isCompleted }

    val totalCount = filteredEvents.size
    val completedCount = completedEvents.size
    val healthPercentage = if (totalCount == 0) 100 else ((completedCount.toFloat() / totalCount) * 100).toInt()

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddClick,
                containerColor = AppleBlue,
                contentColor = Color.White,
                shape = SquircleOuterCard
            ) {
                Icon(Icons.Default.Add, contentDescription = "Adaugă Eveniment")
            }
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .padding(paddingValues),
            contentPadding = PaddingValues(bottom = 80.dp)
        ) {
            // Header Title
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 16.dp)
                ) {
                    Text(
                        text = "Dosar cu Șină",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "Radar Termene",
                        style = MaterialTheme.typography.displayLarge,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Health Summary Ring Card
            item {
                HealthSummaryCard(
                    totalPending = pendingEvents.size,
                    urgentCount = urgentOrOverdue.size,
                    healthPercentage = healthPercentage,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                )
            }

            // Category Filter Pills
            item {
                CategoryPillsRow(
                    selectedCategory = selectedCat,
                    onSelect = {
                        selectedCat = it
                        onCategorySelect(it)
                    },
                    modifier = Modifier.padding(vertical = 12.dp)
                )
            }

            // Urgent Alert Banner (if any urgent or overdue exist)
            if (urgentOrOverdue.isNotEmpty()) {
                item {
                    UrgentAlertBanner(
                        urgentCount = urgentOrOverdue.size,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                    )
                }
            }

            // Section: Urgente & Depășite
            if (urgentOrOverdue.isNotEmpty()) {
                item {
                    SectionHeader(
                        title = "Urgente & Depășite",
                        count = urgentOrOverdue.size,
                        color = AppleRed
                    )
                }
                items(urgentOrOverdue, key = { it.event.id }) { item ->
                    EventRowCard(
                        eventWithAsset = item,
                        onToggle = { onToggleComplete(item.event.id, it) },
                        onClick = { onEventClick(item.event.id) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                    )
                }
            }

            // Section: În următoarele 30 de zile
            if (upcomingEvents.isNotEmpty()) {
                item {
                    SectionHeader(
                        title = "În următoarele 30 de zile",
                        count = upcomingEvents.size,
                        color = AppleOrange
                    )
                }
                items(upcomingEvents, key = { it.event.id }) { item ->
                    EventRowCard(
                        eventWithAsset = item,
                        onToggle = { onToggleComplete(item.event.id, it) },
                        onClick = { onEventClick(item.event.id) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                    )
                }
            }

            // Section: Planificate Ulterior
            if (laterEvents.isNotEmpty()) {
                item {
                    SectionHeader(
                        title = "Planificate Ulterior",
                        count = laterEvents.size,
                        color = AppleBlue
                    )
                }
                items(laterEvents, key = { it.event.id }) { item ->
                    EventRowCard(
                        eventWithAsset = item,
                        onToggle = { onToggleComplete(item.event.id, it) },
                        onClick = { onEventClick(item.event.id) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                    )
                }
            }

            // Section: Rezolvate Recent (if any)
            if (completedEvents.isNotEmpty()) {
                item {
                    SectionHeader(
                        title = "Rezolvate",
                        count = completedEvents.size,
                        color = AppleGreen
                    )
                }
                items(completedEvents, key = { it.event.id }) { item ->
                    EventRowCard(
                        eventWithAsset = item,
                        onToggle = { onToggleComplete(item.event.id, it) },
                        onClick = { onEventClick(item.event.id) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                    )
                }
            }

            // Empty State
            if (filteredEvents.isEmpty()) {
                item {
                    RadarEmptyState(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 48.dp, horizontal = 24.dp)
                    )
                }
            }
        }
    }
}

/**
 * Health Summary Card with animated circular progress ring.
 * $R_{inner} = R_{outer} - padding$
 */
@Composable
fun HealthSummaryCard(
    totalPending: Int,
    urgentCount: Int,
    healthPercentage: Int,
    modifier: Modifier = Modifier
) {
    val animatedProgress by animateFloatAsState(
        targetValue = healthPercentage / 100f,
        animationSpec = spring(),
        label = "HealthProgress"
    )

    Surface(
        shape = SquircleOuterCard,
        color = MaterialTheme.colorScheme.surface,
        modifier = modifier
            .fillMaxWidth()
            .border(0.5.dp, MaterialTheme.colorScheme.outline, SquircleOuterCard)
    ) {
        Row(
            modifier = Modifier
                .padding(18.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (urgentCount > 0) "Atenție la scadențe" else "Totul este sub control",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = if (totalPending == 0) "Nu ai nicio obligație activă"
                    else "$totalPending scadențe active, $urgentCount urgente",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )
            }

            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(68.dp)
                    .clip(PillShape)
            ) {
                CircularProgressIndicator(
                    progress = 1f,
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    strokeWidth = 7.dp,
                    strokeCap = StrokeCap.Round
                )
                CircularProgressIndicator(
                    progress = animatedProgress,
                    modifier = Modifier.fillMaxSize(),
                    color = when {
                        urgentCount > 0 -> AppleRed
                        totalPending > 0 -> AppleOrange
                        else -> AppleGreen
                    },
                    strokeWidth = 7.dp,
                    strokeCap = StrokeCap.Round
                )
                Text(
                    text = "$healthPercentage%",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
fun UrgentAlertBanner(
    urgentCount: Int,
    modifier: Modifier = Modifier
) {
    Surface(
        shape = SquircleOuterCard,
        color = AppleRed.copy(alpha = 0.12f),
        modifier = modifier
            .fillMaxWidth()
            .border(0.5.dp, AppleRed.copy(alpha = 0.3f), SquircleOuterCard)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = "Urgent",
                tint = AppleRed,
                modifier = Modifier.size(24.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = "Atenție: $urgentCount ${if (urgentCount == 1) "scadență critică" else "scadențe critice"}",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = AppleRed
                )
                Text(
                    text = "Termene depășite sau care expiră în următoarele 7 zile.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppleRed.copy(alpha = 0.85f)
                )
            }
        }
    }
}

@Composable
fun CategoryPillsRow(
    selectedCategory: String?,
    onSelect: (String?) -> Unit,
    modifier: Modifier = Modifier
) {
    val scrollState = rememberScrollState()
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(scrollState)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        CategoryPillItem(
            title = "Toate",
            isSelected = selectedCategory == null,
            onClick = { onSelect(null) }
        )
        AssetCategory.entries.forEach { cat ->
            CategoryPillItem(
                title = cat.title,
                isSelected = selectedCategory.equals(cat.rawValue, ignoreCase = true),
                onClick = { onSelect(cat.rawValue) }
            )
        }
    }
}

@Composable
fun CategoryPillItem(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        shape = PillShape,
        color = if (isSelected) AppleBlue else MaterialTheme.colorScheme.surface,
        modifier = Modifier
            .clickable(onClick = onClick)
            .border(
                0.5.dp,
                if (isSelected) AppleBlue else MaterialTheme.colorScheme.outline,
                PillShape
            )
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium,
            color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
        )
    }
}

@Composable
fun SectionHeader(
    title: String,
    count: Int,
    color: Color
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            color = color
        )
        Surface(
            shape = PillShape,
            color = color.copy(alpha = 0.12f)
        ) {
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = color,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
            )
        }
    }
}

/**
 * Event row card with tactile checkbox, strikethrough upon completion, and concentric polish.
 */
@Composable
fun EventRowCard(
    eventWithAsset: EventWithAsset,
    onToggle: (Boolean) -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val event = eventWithAsset.event
    val asset = eventWithAsset.asset
    val dateFormat = remember { SimpleDateFormat("dd MMM yyyy", Locale("ro", "RO")) }
    val formattedDate = remember(event.dueDate) { dateFormat.format(Date(event.dueDate)) }

    val badgeColor = when {
        event.isCompleted -> AppleGreen
        event.isOverdue -> AppleRed
        event.isUrgent -> AppleOrange
        else -> AppleBlue
    }

    Surface(
        shape = SquircleOuterCard,
        color = MaterialTheme.colorScheme.surface,
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .border(0.5.dp, MaterialTheme.colorScheme.outline, SquircleOuterCard)
    ) {
        Row(
            modifier = Modifier
                .padding(14.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Tactile Checkbox
            IconButton(
                onClick = { onToggle(!event.isCompleted) },
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = if (event.isCompleted) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                    contentDescription = if (event.isCompleted) "Rezolvat" else "Marchează rezolvat",
                    tint = if (event.isCompleted) AppleGreen else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                    modifier = Modifier.size(24.dp)
                )
            }

            Spacer(modifier = Modifier.width(10.dp))

            Column(modifier = Modifier.weight(1f)) {
                // Event Title with Strikethrough
                Text(
                    text = event.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    textDecoration = if (event.isCompleted) TextDecoration.LineThrough else TextDecoration.None,
                    color = if (event.isCompleted) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                    else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                Spacer(modifier = Modifier.height(2.dp))

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (asset != null) {
                        Text(
                            text = asset.name,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "•",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                        )
                    }
                    Text(
                        text = formattedDate,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }

                // Cost display if present
                if (event.cost != null && event.cost > 0) {
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = "${String.format(Locale.US, "%.2f", event.cost)} ${event.currency}",
                        style = MaterialTheme.typography.labelSmall,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            // Status Badge Pill
            Surface(
                shape = PillShape,
                color = badgeColor.copy(alpha = 0.12f)
            ) {
                Text(
                    text = event.statusBadgeText,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    color = badgeColor,
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                )
            }
        }
    }
}

@Composable
fun RadarEmptyState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Outlined.Notifications,
            contentDescription = null,
            tint = AppleBlue.copy(alpha = 0.5f),
            modifier = Modifier.size(56.dp)
        )
        Spacer(modifier = Modifier.height(14.dp))
        Text(
            text = "Niciun termen programat",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Adaugă primul tău activ sau scadență folosind butonul + de mai jos.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}
