import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Spotify brand colors
  static const Color spotifyGreen = Color(0xFF1DB954);
  static const Color spotifyBlack = Color(0xFF191414);
  static const Color spotifyDarkGray = Color(0xFF282828);
  static const Color spotifyLightGray = Color(0xFFB3B3B3);
  static const Color spotifyWhite = Color(0xFFFFFFFF);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primarySwatch: Colors.green,
      primaryColor: spotifyGreen,
      scaffoldBackgroundColor: spotifyWhite,
      appBarTheme: AppBarTheme(
        backgroundColor: spotifyWhite.withOpacity(0.85), // Transparent effect
        foregroundColor: spotifyBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: spotifyWhite.withOpacity(0.85), // Transparent effect
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
        color: spotifyWhite,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      colorScheme: const ColorScheme.light(
        primary: spotifyGreen,
        secondary: spotifyGreen,
        surface: spotifyWhite,
        background: spotifyWhite,
        onPrimary: spotifyWhite,
        onSecondary: spotifyWhite,
        onSurface: spotifyBlack,
        onBackground: spotifyBlack,
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
        backgroundColor: spotifyBlack.withOpacity(0.85), // Transparent effect
        foregroundColor: spotifyWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: spotifyBlack.withOpacity(0.85), // Transparent effect
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
        background: spotifyBlack,
        onPrimary: spotifyWhite,
        onSecondary: spotifyWhite,
        onSurface: spotifyWhite,
        onBackground: spotifyWhite,
      ),
    );
  }
} 