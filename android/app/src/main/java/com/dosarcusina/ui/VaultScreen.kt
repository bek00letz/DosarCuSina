package com.dosarcusina.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.dosarcusina.data.AssetCategory
import com.dosarcusina.data.AssetEntity
import com.dosarcusina.data.AssetWithDetails
import com.dosarcusina.ui.theme.AppleBlue
import com.dosarcusina.ui.theme.AppleGreen
import com.dosarcusina.ui.theme.AppleOrange
import com.dosarcusina.ui.theme.AppleRed
import com.dosarcusina.ui.theme.PillShape
import com.dosarcusina.ui.theme.SquircleInnerBadge
import com.dosarcusina.ui.theme.SquircleOuterCard
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun VaultScreen(
    assetsWithDetails: List<AssetWithDetails> = emptyList(),
    selectedCategoryRaw: String? = null,
    onCategorySelect: (String?) -> Unit = {},
    onAssetClick: (assetId: String) -> Unit = {},
    onAddAssetClick: () -> Unit = {}
) {
    var selectedCat by remember { mutableStateOf(selectedCategoryRaw) }

    val filteredAssets = remember(assetsWithDetails, selectedCat) {
        if (selectedCat == null) assetsWithDetails
        else assetsWithDetails.filter { it.asset.categoryRaw.equals(selectedCat, ignoreCase = true) }
    }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = onAddAssetClick,
                containerColor = AppleBlue,
                contentColor = Color.White,
                shape = SquircleOuterCard
            ) {
                Icon(Icons.Default.Add, contentDescription = "Adaugă Activ")
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
            // Header
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
                        text = "Seif Active",
                        style = MaterialTheme.typography.displayLarge,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Category Filter Pills
            item {
                CategoryPillsRow(
                    selectedCategory = selectedCat,
                    onSelect = {
                        selectedCat = it
                        onCategorySelect(it)
                    },
                    modifier = Modifier.padding(bottom = 12.dp)
                )
            }

            // Assets List
            if (filteredAssets.isNotEmpty()) {
                items(filteredAssets, key = { it.asset.id }) { item ->
                    AssetCard(
                        assetWithDetails = item,
                        onClick = { onAssetClick(item.asset.id) },
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
                    )
                }
            } else {
                item {
                    VaultEmptyState(
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
 * Concentric Asset Card ($R_{inner} = R_{outer} - padding$).
 * Displays category icon, name, pending & urgent count, metric indicator, next deadline, and dynamic fields.
 */
@Composable
fun AssetCard(
    assetWithDetails: AssetWithDetails,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val asset = assetWithDetails.asset
    val events = assetWithDetails.events
    val dynamicFields = assetWithDetails.dynamicFields

    val pendingCount = events.filter { !it.isCompleted }.size
    val urgentCount = events.filter { !it.isCompleted && (it.isUrgent || it.isOverdue) }.size
    val nextEvent = events
        .filter { !it.isCompleted }
        .minByOrNull { it.dueDate }

    val category = asset.category
    val accentColor = remember(asset.accentColorHex) {
        try {
            val hex = asset.accentColorHex.removePrefix("#")
            Color(android.graphics.Color.parseColor("#$hex"))
        } catch (e: Exception) {
            AppleBlue
        }
    }

    val iconVector = getCategoryIconVector(category)

    Surface(
        shape = SquircleOuterCard,
        color = MaterialTheme.colorScheme.surface,
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .border(0.5.dp, MaterialTheme.colorScheme.outline, SquircleOuterCard)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Concentric Icon Container: 18dp outer - 4dp margin = 12dp inner
                Surface(
                    shape = SquircleInnerBadge,
                    color = accentColor.copy(alpha = 0.14f),
                    modifier = Modifier.size(48.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = iconVector,
                            contentDescription = category.title,
                            tint = accentColor,
                            modifier = Modifier.size(24.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.width(12.dp))

                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = asset.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    if (!asset.subtitle.isNullOrBlank()) {
                        Spacer(modifier = Modifier.height(2.dp))
                        Text(
                            text = asset.subtitle,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }

                Spacer(modifier = Modifier.width(8.dp))

                // Urgency or Active Pill
                if (urgentCount > 0) {
                    Surface(
                        shape = PillShape,
                        color = AppleRed.copy(alpha = 0.12f)
                    ) {
                        Text(
                            text = "$urgentCount ${if (urgentCount == 1) "urgent" else "urgente"}",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = AppleRed,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                } else if (pendingCount > 0) {
                    Surface(
                        shape = PillShape,
                        color = AppleBlue.copy(alpha = 0.12f)
                    ) {
                        Text(
                            text = "$pendingCount ${if (pendingCount == 1) "activ" else "active"}",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = AppleBlue,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                } else {
                    Surface(
                        shape = PillShape,
                        color = AppleGreen.copy(alpha = 0.12f)
                    ) {
                        Text(
                            text = "La zi",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Bold,
                            color = AppleGreen,
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp)
                        )
                    }
                }
            }

            // Next Scheduled Deadline Preview
            if (nextEvent != null) {
                Spacer(modifier = Modifier.height(12.dp))
                val dateFormat = remember { SimpleDateFormat("dd MMM yyyy", Locale("ro", "RO")) }
                val nextDateStr = dateFormat.format(Date(nextEvent.dueDate))

                Surface(
                    shape = SquircleInnerBadge,
                    color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(
                            text = "Scadență: ${nextEvent.title}",
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = nextDateStr,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                        )
                    }
                }
            }

            // Telemetry Metric Indicator (e.g. km, hours, cycles)
            if (asset.currentMetricValue != null && asset.currentMetricValue > 0) {
                Spacer(modifier = Modifier.height(8.dp))
                val symbols = DecimalFormatSymbols(Locale.GERMANY).apply { groupingSeparator = '.' }
                val metricFormatter = DecimalFormat("#,###", symbols)
                val formattedMetric = metricFormatter.format(asset.currentMetricValue)
                val unit = asset.metricUnit ?: "km"

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Speed,
                        contentDescription = "Telemetrie",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                    Text(
                        text = "$formattedMetric $unit",
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            // Dynamic Fields display snippet
            if (dynamicFields.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    dynamicFields.take(3).forEach { field ->
                        val valueDisplay = when {
                            field.stringValue != null -> field.stringValue
                            field.numberValue != null -> String.format(Locale.US, "%.1f", field.numberValue)
                            field.boolValue != null -> if (field.boolValue) "Da" else "Nu"
                            else -> null
                        }
                        if (valueDisplay != null) {
                            Surface(
                                shape = PillShape,
                                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.7f)
                            ) {
                                Text(
                                    text = "${field.label}: $valueDisplay",
                                    style = MaterialTheme.typography.labelSmall,
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

fun getCategoryIconVector(category: AssetCategory): ImageVector {
    return when (category) {
        AssetCategory.HOME -> Icons.Default.Home
        AssetCategory.VEHICLE -> Icons.Default.DirectionsCar
        AssetCategory.PET -> Icons.Default.Pets
        AssetCategory.HEALTH -> Icons.Default.Favorite
        AssetCategory.DOCUMENTS -> Icons.Default.Folder
        AssetCategory.WARRANTIES -> Icons.Default.Security
        AssetCategory.SUBSCRIPTIONS -> Icons.Outlined.CreditCard
        AssetCategory.CUSTOM -> Icons.Outlined.Widgets
    }
}

@Composable
fun VaultEmptyState(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Outlined.Inventory2,
            contentDescription = null,
            tint = AppleBlue.copy(alpha = 0.5f),
            modifier = Modifier.size(56.dp)
        )
        Spacer(modifier = Modifier.height(14.dp))
        Text(
            text = "Seiful este gol",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Adaugă primul tău activ (casă, mașină, animal de companie etc.) pentru a începe organizarea.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center
        )
    }
}
