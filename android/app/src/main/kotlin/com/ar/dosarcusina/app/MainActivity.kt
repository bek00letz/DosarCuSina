package com.ar.dosarcusina.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.ar.dosarcusina.app.locale.AppLocale
import com.ar.dosarcusina.app.ui.PlaceholderScreen
import com.ar.dosarcusina.app.ui.theme.DosarTheme

class MainActivity : ComponentActivity() {
    // Romanian on every phone, before Android 13 too (AppLocale).
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLocale.wrap(newBase))
    }

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
