import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: brightness,
        surface: AppColors.surface,
      ),
      fontFamily: 'Roboto',
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: AppColors.text,
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        bodyLarge: TextStyle(
          color: AppColors.secondaryText,
          fontSize: 16,
          height: 1.5,
        ),
      ),
    );
  }
}