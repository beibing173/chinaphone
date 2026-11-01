package dev.beibing.chinaphone

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.beibing.chinaphone.ui.ChinaPhoneApp
import dev.beibing.chinaphone.ui.theme.ChinaPhoneTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ChinaPhoneTheme {
                ChinaPhoneApp()
            }
        }
    }
}
