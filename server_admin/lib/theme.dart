/// PixelDock visual language — palette + typography + reusable bits.
///
/// Mirrors PixelCode's default theme (dark navy, cyan accent, gold highlight)
/// so the admin app feels like a sibling to the main client. Pixel-art
/// "Press Start 2P" is reserved for chrome (app name, section headers,
/// badges) — body text and values use the system font / mono so long log
/// lines and paths stay readable.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PixelPalette {
  const PixelPalette._();

  static const background = Color(0xFF0E0E11);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceDim = Color(0xFF141418);
  static const surfaceHi = Color(0xFF24242C);
  static const accent = Color(0xFF00C0D1);
  static const accentSoft = Color(0xFF1F8A93);
  static const gold = Color(0xFFFFD700);
  static const ice = Color(0xFF7DD3FC);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
  static const warn = Color(0xFFE0A44A);
  static const textHigh = Color(0xFFE8E8EC);
  static const textMed = Color(0xFF9898A4);
  static const textLow = Color(0xFF5A5A66);
  static const border = Color(0xFF2A2A30);
  static const divider = Color(0xFF222228);
}

ThemeData buildPixelTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: PixelPalette.background,
    colorScheme: const ColorScheme.dark(
      primary: PixelPalette.accent,
      secondary: PixelPalette.gold,
      surface: PixelPalette.surface,
      surfaceContainerLowest: PixelPalette.background,
      surfaceContainerLow: PixelPalette.surfaceDim,
      surfaceContainer: PixelPalette.surface,
      surfaceContainerHigh: PixelPalette.surfaceHi,
      surfaceContainerHighest: PixelPalette.surfaceHi,
      onSurface: PixelPalette.textHigh,
      onSurfaceVariant: PixelPalette.textMed,
      outline: PixelPalette.border,
      outlineVariant: PixelPalette.divider,
      error: PixelPalette.error,
      onError: Colors.white,
    ),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    appBarTheme: const AppBarTheme(
      backgroundColor: PixelPalette.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: PixelPalette.surfaceHi,
      contentTextStyle: TextStyle(color: PixelPalette.textHigh),
    ),
  );
}

/// Pixel-art display font — use only for chrome (titles, section headers,
/// badges). At body-text sizes it becomes unreadable, so callers pass small
/// font sizes (10–14) and let the chunky look do the heavy lifting.
TextStyle pixelFont({
  double size = 11,
  Color color = PixelPalette.textHigh,
  double letterSpacing = 1.0,
  FontWeight weight = FontWeight.w400,
}) {
  return GoogleFonts.pressStart2p(
    textStyle: TextStyle(
      fontSize: size,
      color: color,
      letterSpacing: letterSpacing,
      fontWeight: weight,
      height: 1.4,
    ),
  );
}

/// Glowing pixel-art LED dot — green/amber/red for status surfaces.
class GlowDot extends StatelessWidget {
  const GlowDot({super.key, required this.color, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 8, spreadRadius: 1),
          BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14, spreadRadius: 2),
        ],
      ),
    );
  }
}

/// Card with PixelCode-flavored chrome: dark surface, sharp 1px border, a
/// title strip in pixel font over a dimmer background.
class PixelCard extends StatelessWidget {
  const PixelCard({
    super.key,
    required this.title,
    required this.child,
    this.titleColor,
    this.expand = false,
  });
  final String title;
  final Widget child;
  final Color? titleColor;

  /// When true, the body grows to fill remaining vertical space — required
  /// when `child` itself contains an `Expanded` (e.g. a long log list). The
  /// caller must place the card in a bounded-height parent (Expanded/SizedBox).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: const EdgeInsets.all(16), child: child);
    return Container(
      decoration: BoxDecoration(
        color: PixelPalette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PixelPalette.border),
      ),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: PixelPalette.surfaceDim,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
              border: Border(bottom: BorderSide(color: PixelPalette.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: titleColor ?? PixelPalette.accent,
                    boxShadow: [
                      BoxShadow(
                        color: (titleColor ?? PixelPalette.accent).withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title.toUpperCase(),
                  style: pixelFont(
                    size: 9,
                    color: titleColor ?? PixelPalette.accent,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

/// Outlined button styled to match the PixelCode dark UI — square corners,
/// thin border, accent-on-hover.
ButtonStyle pixelOutlinedStyle({Color? foreground}) {
  final fg = foreground ?? PixelPalette.textHigh;
  return ButtonStyle(
    foregroundColor: WidgetStatePropertyAll(fg),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return const BorderSide(color: PixelPalette.border);
      }
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
        return BorderSide(color: fg);
      }
      return const BorderSide(color: PixelPalette.border);
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) return PixelPalette.surfaceHi;
      return PixelPalette.surfaceDim;
    }),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    textStyle: WidgetStatePropertyAll(pixelFont(size: 9, color: fg, letterSpacing: 1.4)),
  );
}

ButtonStyle pixelFilledStyle({required Color color}) {
  return ButtonStyle(
    foregroundColor: const WidgetStatePropertyAll(Color(0xFF0A0A0F)),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return color.withValues(alpha: 0.35);
      if (states.contains(WidgetState.hovered)) return Color.lerp(color, Colors.white, 0.12)!;
      return color;
    }),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    textStyle: WidgetStatePropertyAll(pixelFont(size: 9, color: const Color(0xFF0A0A0F), letterSpacing: 1.4)),
  );
}
