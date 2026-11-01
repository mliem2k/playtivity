package com.mliem.playtivity.nativeapp

import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.MaterialTheme

object PlaytivityColors {
    val background = Color(0xFF121212)
    val surfaceRaised = Color(0xFF181818)
    val surfaceElevated = Color(0xFF282828)
    val primary = Color(0xFF1DB954)
    val textSecondary = Color(0xFFA7A7A7)
    val error = Color(0xFFE91429)
}

private val scheme = darkColorScheme(
    primary = PlaytivityColors.primary,
    onPrimary = Color.Black,
    background = PlaytivityColors.background,
    onBackground = Color.White,
    surface = PlaytivityColors.background,
    onSurface = Color.White,
    surfaceVariant = PlaytivityColors.surfaceElevated,
    onSurfaceVariant = PlaytivityColors.textSecondary,
    error = PlaytivityColors.error,
)

@Composable
fun PlaytivityTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, content = content)
}
