import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode get themeMode => ThemeMode.dark;
  bool get isDarkMode => true;
} 