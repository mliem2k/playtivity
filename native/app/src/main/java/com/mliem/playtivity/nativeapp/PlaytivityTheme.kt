package com.mliem.playtivity.nativeapp

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

object PlaytivityColors {
    val background = Color(0xFF121212)
    val surfaceRaised = Color(0xFF181818)
    val surfaceElevated = Color(0xFF282828)
    val primary = Color(0xFF1DB954)
    val primaryActive = Color(0xFF1ED760)
    val textSecondary = Color(0xFFA7A7A7)
    val textSubdued = Color(0xFF8E8E8E)
    val divider = Color(0xFF282828)
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

val playtivityFont = FontFamily(
    Font(R.font.montserrat_regular, FontWeight.Normal),
    Font(R.font.montserrat_medium, FontWeight.Medium),
    Font(R.font.montserrat_semibold, FontWeight.SemiBold),
    Font(R.font.montserrat_bold, FontWeight.Bold),
    Font(R.font.montserrat_extrabold, FontWeight.ExtraBold),
)

private val defaults = Typography()
private val type = Typography(
    headlineLarge = defaults.headlineLarge.copy(fontFamily = playtivityFont),
    titleLarge = defaults.titleLarge.copy(fontFamily = playtivityFont),
    titleMedium = defaults.titleMedium.copy(fontFamily = playtivityFont),
    bodyLarge = defaults.bodyLarge.copy(fontFamily = playtivityFont),
    bodyMedium = defaults.bodyMedium.copy(fontFamily = playtivityFont),
    bodySmall = defaults.bodySmall.copy(fontFamily = playtivityFont),
    labelLarge = defaults.labelLarge.copy(fontFamily = playtivityFont),
)

@Composable
fun PlaytivityTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = scheme, typography = type, content = content)
}
