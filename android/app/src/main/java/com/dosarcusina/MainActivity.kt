package com.dosarcusina

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Radar
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Radar
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.dosarcusina.data.DosarDatabase
import com.dosarcusina.ocr.CameraXTextScanner
import com.dosarcusina.ui.RadarScreen
import com.dosarcusina.ui.VaultScreen
import com.dosarcusina.ui.theme.AppleBlue
import com.dosarcusina.ui.theme.DosarCuSinaTheme
import kotlinx.coroutines.launch

enum class AppDestination(
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
) {
    RADAR("Radar", Icons.Filled.Radar, Icons.Outlined.Radar),
    VAULT("Seif", Icons.Filled.Folder, Icons.Outlined.Folder),
    SCANNER("Scanner", Icons.Filled.CameraAlt, Icons.Outlined.CameraAlt)
}

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val database = DosarDatabase.getInstance(this)
        val eventDao = database.eventDao()
        val assetDao = database.assetDao()

        setContent {
            DosarCuSinaTheme {
                var currentDestination by remember { mutableStateOf(AppDestination.RADAR) }
                val scope = rememberCoroutineScope()

                val pendingEvents by eventDao.getPendingEvents().collectAsState(initial = emptyList())
                val allAssetsWithDetails by assetDao.getAllAssetsWithDetails().collectAsState(initial = emptyList())

                Scaffold(
                    bottomBar = {
                        if (currentDestination != AppDestination.SCANNER) {
                            NavigationBar(
                                containerColor = MaterialTheme.colorScheme.surface,
                                tonalElevation = 8.dp
                            ) {
                                AppDestination.entries.forEach { dest ->
                                    val isSelected = currentDestination == dest
                                    NavigationBarItem(
                                        selected = isSelected,
                                        onClick = { currentDestination = dest },
                                        icon = {
                                            Icon(
                                                imageVector = if (isSelected) dest.selectedIcon else dest.unselectedIcon,
                                                contentDescription = dest.title,
                                                modifier = Modifier.size(24.dp)
                                            )
                                        },
                                        label = {
                                            Text(
                                                text = dest.title,
                                                style = MaterialTheme.typography.labelSmall
                                            )
                                        },
                                        colors = NavigationBarItemDefaults.colors(
                                            selectedIconColor = AppleBlue,
                                            selectedTextColor = AppleBlue,
                                            indicatorColor = AppleBlue.copy(alpha = 0.12f)
                                        )
                                    )
                                }
                            }
                        }
                    }
                ) { paddingValues ->
                    Surface(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(paddingValues),
                        color = MaterialTheme.colorScheme.background
                    ) {
                        when (currentDestination) {
                            AppDestination.RADAR -> {
                                RadarScreen(
                                    events = pendingEvents,
                                    onToggleComplete = { eventId, completed ->
                                        scope.launch {
                                            val completedDate = if (completed) System.currentTimeMillis() else null
                                            eventDao.setCompletion(eventId, completed, completedDate)
                                        }
                                    },
                                    onAddClick = {
                                        currentDestination = AppDestination.SCANNER
                                    }
                                )
                            }
                            AppDestination.VAULT -> {
                                VaultScreen(
                                    assetsWithDetails = allAssetsWithDetails,
                                    onAddAssetClick = {
                                        // Trigger asset addition
                                    }
                                )
                            }
                            AppDestination.SCANNER -> {
                                CameraXTextScanner(
                                    onResultAccepted = { result ->
                                        // Return to Radar upon acceptance
                                        currentDestination = AppDestination.RADAR
                                    },
                                    onClose = {
                                        currentDestination = AppDestination.RADAR
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
