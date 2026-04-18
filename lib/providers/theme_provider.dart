/// Derived Riverpod providers that resolve the active theme into usable
/// [ThemeColors] and a ready-to-use [ThemeData] for MaterialApp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_theme.dart';
import 'game_economy_provider.dart';

/// The currently active [AppThemeDefinition] (looked up from game state).
final activeThemeDefProvider = Provider<AppThemeDefinition>((ref) {
  final themeState = ref.watch(gameEconomyProvider).themeState;
  return themeById(themeState.activeThemeId) ?? themeCatalog.first;
});

/// Resolved [ThemeColors] with user customisations applied.
final activeThemeColorsProvider = Provider<ThemeColors>((ref) {
  final themeDef = ref.watch(activeThemeDefProvider);
  final themeState = ref.watch(gameEconomyProvider).themeState;
  final customization = themeState.customizations[themeDef.id];
  return resolveThemeColors(themeDef, customization);
});

/// A complete [ThemeData] built from the active theme, ready for MaterialApp.
final appThemeDataProvider = Provider<ThemeData>((ref) {
  final colors = ref.watch(activeThemeColorsProvider);
  return _buildThemeData(colors);
});

ThemeData _buildThemeData(ThemeColors c) {
  return ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: c.background,
    colorScheme: ColorScheme.dark(
      primary: c.accent,
      secondary: c.accent,
      surface: c.surface,
      error: c.error,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: c.textHigh,
      onError: Colors.white,
    ),
    extensions: [AppColorsExtension(c)],
  );
}
