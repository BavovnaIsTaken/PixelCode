/// Derived Riverpod providers that resolve the active theme into usable
/// [ThemeColors] and a ready-to-use [ThemeData] for MaterialApp.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_theme.dart';
import '../models/game_economy.dart';
import '../models/send_button_style.dart';
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

/// The currently equipped send-button cosmetic variant (falls back to
/// [SendButtonVariant.classic] when nothing is equipped).
///
/// On Apple platforms, [SendButtonVariant.pixelArcade] is automatically
/// substituted with [SendButtonVariant.liquidGlass] so the chat send button
/// follows the iOS 26 / macOS Tahoe Liquid Glass design language without
/// breaking pixel-art identity on other platforms.
final activeSendButtonVariantProvider = Provider<SendButtonVariant>((ref) {
  final equipped = ref.watch(gameEconomyProvider).equippedCosmetics;
  final variant =
      sendButtonVariantForId(equipped[CosmeticType.sendButtonStyle.index]);
  return resolveSendButtonVariantForPlatform(variant);
});

/// Visible for testing. Returns the variant that should actually render on
/// the current platform — Apple platforms swap pixel-arcade for liquid-glass.
SendButtonVariant resolveSendButtonVariantForPlatform(
  SendButtonVariant variant, {
  bool? isApplePlatformOverride,
}) {
  final isApple = isApplePlatformOverride ??
      (!kIsWeb && (Platform.isIOS || Platform.isMacOS));
  if (isApple && variant == SendButtonVariant.pixelArcade) {
    return SendButtonVariant.liquidGlass;
  }
  return variant;
}

/// A complete [ThemeData] built from the active theme, ready for MaterialApp.
final appThemeDataProvider = Provider<ThemeData>((ref) {
  final colors = ref.watch(activeThemeColorsProvider);
  return _buildThemeData(colors);
});

ThemeData _buildThemeData(ThemeColors c) {
  final isMacOS = !kIsWeb && Platform.isMacOS;
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
    tooltipTheme: isMacOS
        ? const TooltipThemeData(
            waitDuration: Duration(milliseconds: 1500),
            showDuration: Duration(seconds: 10),
          )
        : null,
    extensions: [AppColorsExtension(c)],
  );
}
