import 'package:flutter/material.dart';

/// Colors switch with [darkMode]. Read them like before (AppColors.text etc.).
class AppColors {
  AppColors._();

  static final ValueNotifier<bool> darkMode = ValueNotifier<bool>(false);

  static bool get _dark => darkMode.value;

  // Light palette
  static const _lBackground = Color(0xFFFAF9F6);
  static const _lSurface = Color(0xFFFFFFFF);
  static const _lBorder = Color(0xFFE9E7E2);
  static const _lText = Color(0xFF23262B);
  static const _lSecondaryText = Color(0xFF76787E);
  static const _lAccent = Color(0xFF2F6B5E);
  static const _lSoftAccent = Color(0xFFE8F0ED);

  // Dark palette
  static const _dBackground = Color(0xFF121316);
  static const _dSurface = Color(0xFF1C1E22);
  static const _dBorder = Color(0xFF2C2F35);
  static const _dText = Color(0xFFF2F3F5);
  static const _dSecondaryText = Color(0xFF9AA0A8);
  static const _dAccent = Color(0xFF7CC4B0);
  static const _dSoftAccent = Color(0xFF243632);

  // Surfaces
  static Color get background => _dark ? _dBackground : _lBackground;
  static Color get surface => _dark ? _dSurface : _lSurface;
  static Color get border => _dark ? _dBorder : _lBorder;

  // Text
  static Color get text => _dark ? _dText : _lText;
  static Color get secondaryText => _dark ? _dSecondaryText : _lSecondaryText;

  // Accent
  static Color get accent => _dark ? _dAccent : _lAccent;
  static Color get softAccent => _dark ? _dSoftAccent : _lSoftAccent;

  // Backward compatibility
  static Color get softViolet => softAccent;

  static const white = Color(0xFFFFFFFF);
}