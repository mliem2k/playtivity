import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const Color background = Color(0xFF121212);
  static const Color surfaceRaised = Color(0xFF181818);
  static const Color surfaceElevated = Color(0xFF282828);
  static const Color primary = Color(0xFF1DB954);
  static const Color primaryActive = Color(0xFF1ED760);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA7A7A7);
  static const Color textSubdued = Color(0xFF535353);
  static const Color onPrimary = Color(0xFF000000);
  static const Color errorRed = Color(0xFFE91429);
  static const Color loginBackground = Color(0xFF000000);
  static const Color dividerColor = Color(0xFF282828);

  static ThemeData get darkTheme {
    final base = ThemeData.dark().textTheme.apply(fontFamily: 'Montserrat');
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: background,
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 32,
          letterSpacing: -0.5,
          color: textPrimary,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: textPrimary,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: textPrimary,
        ),
        titleSmall: base.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: textPrimary,
        ),
        bodyLarge: base.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: textPrimary,
        ),
        bodyMedium: base.bodyMedium?.copyWith(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: textSecondary,
        ),
        labelSmall: base.labelSmall?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 11,
          letterSpacing: 1.0,
          color: textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: loginBackground,
        selectedItemColor: textPrimary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w500,
          fontSize: 11,
          letterSpacing: 1.0,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w500,
          fontSize: 11,
          letterSpacing: 1.0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: const StadiumBorder(),
          minimumSize: const Size(double.infinity, 56),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'Montserrat',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        labelStyle: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: primary, width: 2),
          insets: EdgeInsets.symmetric(horizontal: 24),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: surfaceRaised,
        onPrimary: onPrimary,
        onSecondary: onPrimary,
        onSurface: textPrimary,
        error: errorRed,
      ),
    );
  }
}
