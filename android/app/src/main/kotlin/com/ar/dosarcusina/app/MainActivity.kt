package com.ar.dosarcusina.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.ar.dosarcusina.app.ui.PlaceholderScreen
import com.ar.dosarcusina.app.ui.theme.DosarTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            DosarTheme {
                PlaceholderScreen()
            }
        }
    }
}
