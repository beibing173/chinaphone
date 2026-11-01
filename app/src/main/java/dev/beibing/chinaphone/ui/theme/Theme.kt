package dev.beibing.chinaphone.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

// 海洋蓝主题 —— 呼应「鲸鱼」意象
private val OceanBlue = Color(0xFF1565C0)
private val OceanLight = Color(0xFF5E92F3)
private val DeepSea = Color(0xFF003C8F)
private val AlertRed = Color(0xFFD32F2F)
private val WarnAmber = Color(0xFFF57C00)
private val SafeGreen = Color(0xFF2E7D32)

private val LightColors = lightColorScheme(
    primary = OceanBlue,
    secondary = OceanLight,
    tertiary = DeepSea,
    error = AlertRed,
)

private val DarkColors = darkColorScheme(
    primary = OceanLight,
    secondary = OceanBlue,
    tertiary = Color(0xFF82B1FF),
    error = Color(0xFFEF5350),
)

object RiskColors {
    val high = AlertRed
    val medium = WarnAmber
    val low = SafeGreen
}

@Composable
fun ChinaPhoneTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColors
        else -> LightColors
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view)
                .isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
