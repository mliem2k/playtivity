import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Spotify brand colors
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color spotifyBlack = Color(0xFF191414);
  static const Color spotifyDarkGray = Color(0xFF282828);
  static const Color spotifyLightGray = Color(0xFFB3B3B3);
  static const Color spotifyWhite = Color(0xFFFFFFFF);
  
  // Additional theme-aware colors
  static const Color lightTextSecondary = Color(0xFF666666);
  static const Color lightTextTertiary = Color(0xFF999999);
  static const Color lightCardBackground = Color(0xFFFAFAFA);
  static const Color lightBorder = Color(0xFFE0E0E0);
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primarySwatch: Colors.green,
      primaryColor: spotifyGreen,
      scaffoldBackgroundColor: spotifyWhite,
      appBarTheme: AppBarTheme(
        backgroundColor: spotifyWhite.withValues(alpha: 0.85), // Transparent effect
        foregroundColor: spotifyBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: spotifyWhite.withValues(alpha: 0.85), // Transparent effect
        selectedItemColor: spotifyGreen,
        unselectedItemColor: lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: spotifyGreen,
          foregroundColor: spotifyWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          elevation: 2,
          shadowColor: spotifyGreen.withValues(alpha: 0.3),
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCardBackground,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      colorScheme: const ColorScheme.light(
        primary: spotifyGreen,
        secondary: spotifyGreen,
        surface: lightCardBackground,
        onPrimary: spotifyWhite,
        onSecondary: spotifyWhite,
        onSurface: spotifyBlack,
        outline: lightBorder,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primarySwatch: Colors.green,
      primaryColor: spotifyGreen,
      scaffoldBackgroundColor: spotifyBlack,
      appBarTheme: AppBarTheme(
        backgroundColor: spotifyBlack.withValues(alpha: 0.9), // Increased opacity for better visibility in dark mode
        foregroundColor: spotifyWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: spotifyBlack.withValues(alpha: 0.85), // Transparent effect
        selectedItemColor: spotifyGreen,
        unselectedItemColor: spotifyLightGray,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: spotifyGreen,
          foregroundColor: spotifyWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      cardTheme: CardThemeData(
        color: spotifyDarkGray,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: spotifyGreen,
        secondary: spotifyGreen,
        surface: spotifyDarkGray,
        onPrimary: spotifyWhite,
        onSecondary: spotifyWhite,
        onSurface: spotifyWhite,
      ),
    );
  }

  // Helper methods for theme-aware colors
  static Color getSecondaryTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? spotifyLightGray : lightTextSecondary;
  }
  
  static Color getTertiaryTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? spotifyLightGray : lightTextTertiary;
  }
  
  static Color getCardBackgroundColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? spotifyDarkGray : lightCardBackground;
  }
}