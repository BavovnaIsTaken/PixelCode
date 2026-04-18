/// PixelCode theme system — standard, premium & seasonal themes.
///
/// Each theme defines a semantic colour palette. Premium themes are
/// purchasable with гримні and support user customisation (accent colour,
/// background shade, highlight tint). The catalog is designed to be
/// extended with seasonal/event themes without changing schema.
library;

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/material.dart' show ThemeExtension, BuildContext, Theme;

// ─── Theme category ───────────────────────────────────────────────────────

enum ThemeCategory {
  standard,
  premium,
  seasonal,
}

extension ThemeCategoryExt on ThemeCategory {
  String get label => switch (this) {
        ThemeCategory.standard => 'Стандартні',
        ThemeCategory.premium => 'Преміум',
        ThemeCategory.seasonal => 'Сезонні',
      };
}

// ─── Semantic colour slots ────────────────────────────────────────────────

class ThemeColors {
  final Color background;
  final Color surface;
  final Color surfaceDim;
  final Color accent;
  final Color accentDim;
  final Color gold;
  final Color success;
  final Color error;
  final Color textHigh;
  final Color textMedium;
  final Color textLow;
  final Color border;
  final Color divider;

  const ThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceDim,
    required this.accent,
    required this.accentDim,
    required this.gold,
    required this.success,
    required this.error,
    required this.textHigh,
    required this.textMedium,
    required this.textLow,
    required this.border,
    required this.divider,
  });

  ThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceDim,
    Color? accent,
    Color? accentDim,
    Color? gold,
    Color? success,
    Color? error,
    Color? textHigh,
    Color? textMedium,
    Color? textLow,
    Color? border,
    Color? divider,
  }) =>
      ThemeColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceDim: surfaceDim ?? this.surfaceDim,
        accent: accent ?? this.accent,
        accentDim: accentDim ?? this.accentDim,
        gold: gold ?? this.gold,
        success: success ?? this.success,
        error: error ?? this.error,
        textHigh: textHigh ?? this.textHigh,
        textMedium: textMedium ?? this.textMedium,
        textLow: textLow ?? this.textLow,
        border: border ?? this.border,
        divider: divider ?? this.divider,
      );
}

// ─── Flutter ThemeExtension for easy access via Theme.of(context) ─────────

class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final ThemeColors colors;

  const AppColorsExtension(this.colors);

  @override
  AppColorsExtension copyWith({ThemeColors? colors}) =>
      AppColorsExtension(colors ?? this.colors);

  @override
  AppColorsExtension lerp(covariant AppColorsExtension? other, double t) {
    if (other == null) return this;
    return AppColorsExtension(ThemeColors(
      background: Color.lerp(colors.background, other.colors.background, t)!,
      surface: Color.lerp(colors.surface, other.colors.surface, t)!,
      surfaceDim: Color.lerp(colors.surfaceDim, other.colors.surfaceDim, t)!,
      accent: Color.lerp(colors.accent, other.colors.accent, t)!,
      accentDim: Color.lerp(colors.accentDim, other.colors.accentDim, t)!,
      gold: Color.lerp(colors.gold, other.colors.gold, t)!,
      success: Color.lerp(colors.success, other.colors.success, t)!,
      error: Color.lerp(colors.error, other.colors.error, t)!,
      textHigh: Color.lerp(colors.textHigh, other.colors.textHigh, t)!,
      textMedium: Color.lerp(colors.textMedium, other.colors.textMedium, t)!,
      textLow: Color.lerp(colors.textLow, other.colors.textLow, t)!,
      border: Color.lerp(colors.border, other.colors.border, t)!,
      divider: Color.lerp(colors.divider, other.colors.divider, t)!,
    ));
  }
}

/// Convenience accessor: `context.appColors`.
extension AppColorsX on BuildContext {
  ThemeColors get appColors =>
      Theme.of(this).extension<AppColorsExtension>()?.colors ?? defaultThemeColors;
}

// ─── Theme definition ─────────────────────────────────────────────────────

class AppThemeDefinition {
  final String id;
  final String name;
  final String description;
  final String emoji;
  final ThemeCategory category;
  final int cost;
  final bool isCustomizable;
  final ThemeColors colors;

  /// Curated accent palette for customizable themes.
  final List<Color> accentPalette;

  /// Curated background shades: [darker, default, lighter].
  final List<Color> backgroundShades;

  /// Curated highlight tints for gold/premium elements.
  final List<Color> highlightTints;

  /// For seasonal themes: when it becomes available.
  final DateTime? availableFrom;

  /// For seasonal themes: when it expires.
  final DateTime? availableUntil;

  /// Tags for filtering (e.g. 'winter', 'halloween', 'anniversary').
  final List<String> tags;

  const AppThemeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.category,
    required this.cost,
    required this.colors,
    this.isCustomizable = false,
    this.accentPalette = const [],
    this.backgroundShades = const [],
    this.highlightTints = const [],
    this.availableFrom,
    this.availableUntil,
    this.tags = const [],
  });

  bool get isFree => cost == 0;
  bool get isPremium => category == ThemeCategory.premium;
  bool get isSeasonal => category == ThemeCategory.seasonal;

  /// Check if a seasonal theme is currently available.
  bool isAvailableNow([DateTime? now]) {
    if (availableFrom == null && availableUntil == null) return true;
    final current = now ?? DateTime.now();
    if (availableFrom != null && current.isBefore(availableFrom!)) return false;
    if (availableUntil != null && current.isAfter(availableUntil!)) return false;
    return true;
  }
}

// ─── User customisation for a single theme ────────────────────────────────

class ThemeCustomization {
  /// Index into [AppThemeDefinition.accentPalette], or null for default.
  final int? accentIndex;

  /// Index into [AppThemeDefinition.backgroundShades], or null for default.
  final int? backgroundIndex;

  /// Index into [AppThemeDefinition.highlightTints], or null for default.
  final int? highlightIndex;

  const ThemeCustomization({
    this.accentIndex,
    this.backgroundIndex,
    this.highlightIndex,
  });

  bool get isEmpty =>
      accentIndex == null && backgroundIndex == null && highlightIndex == null;

  Map<String, dynamic> toJson() => {
        if (accentIndex != null) 'a': accentIndex,
        if (backgroundIndex != null) 'b': backgroundIndex,
        if (highlightIndex != null) 'h': highlightIndex,
      };

  factory ThemeCustomization.fromJson(Map<String, dynamic> json) =>
      ThemeCustomization(
        accentIndex: json['a'] as int?,
        backgroundIndex: json['b'] as int?,
        highlightIndex: json['h'] as int?,
      );
}

// ─── Theme state (persisted as part of GameState) ─────────────────────────

class ThemeState {
  final String activeThemeId;
  final Set<String> ownedThemes;
  final Map<String, ThemeCustomization> customizations;

  const ThemeState({
    this.activeThemeId = 'midnight',
    this.ownedThemes = const {},
    this.customizations = const {},
  });

  ThemeState copyWith({
    String? activeThemeId,
    Set<String>? ownedThemes,
    Map<String, ThemeCustomization>? customizations,
  }) =>
      ThemeState(
        activeThemeId: activeThemeId ?? this.activeThemeId,
        ownedThemes: ownedThemes ?? this.ownedThemes,
        customizations: customizations ?? this.customizations,
      );

  Map<String, dynamic> toJson() => {
        'activeThemeId': activeThemeId,
        'ownedThemes': ownedThemes.toList(),
        'customizations': {
          for (final e in customizations.entries)
            if (!e.value.isEmpty) e.key: e.value.toJson(),
        },
      };

  factory ThemeState.fromJson(Map<String, dynamic> json) => ThemeState(
        activeThemeId: json['activeThemeId'] as String? ?? 'midnight',
        ownedThemes: {
          for (final id in (json['ownedThemes'] as List<dynamic>?) ?? [])
            id as String,
        },
        customizations: {
          for (final e
              in (json['customizations'] as Map<String, dynamic>? ?? {})
                  .entries)
            e.key: ThemeCustomization.fromJson(
                e.value as Map<String, dynamic>),
        },
      );

  String encode() => jsonEncode(toJson());

  factory ThemeState.decode(String source) =>
      ThemeState.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

// ─── Resolve theme colours with user customisation applied ────────────────

/// Returns the effective [ThemeColors] after applying any user overrides.
ThemeColors resolveThemeColors(
  AppThemeDefinition theme, [
  ThemeCustomization? customization,
]) {
  if (customization == null || customization.isEmpty) return theme.colors;

  var colors = theme.colors;

  if (customization.accentIndex != null &&
      customization.accentIndex! < theme.accentPalette.length) {
    final accent = theme.accentPalette[customization.accentIndex!];
    colors = colors.copyWith(
      accent: accent,
      accentDim: accent.withValues(alpha: 0.15),
    );
  }

  if (customization.backgroundIndex != null &&
      customization.backgroundIndex! < theme.backgroundShades.length) {
    colors = colors.copyWith(
      background: theme.backgroundShades[customization.backgroundIndex!],
    );
  }

  if (customization.highlightIndex != null &&
      customization.highlightIndex! < theme.highlightTints.length) {
    colors = colors.copyWith(
      gold: theme.highlightTints[customization.highlightIndex!],
    );
  }

  return colors;
}

// ─── Default theme colours (matches current hardcoded app palette) ────────

const defaultThemeColors = ThemeColors(
  background: Color(0xFF0E0E11),
  surface: Color(0xFF1A1A1F),
  surfaceDim: Color(0xFF141418),
  accent: Color(0xFF00C0D1),
  accentDim: Color(0xFF00C0D1),
  gold: Color(0xFFFFD700),
  success: Color(0xFF22C55E),
  error: Color(0xFFEF4444),
  textHigh: Color(0xFFE8E8EC),
  textMedium: Color(0xFF9898A4),
  textLow: Color(0xFF5A5A66),
  border: Color(0xFF2A2A30),
  divider: Color(0xFF222228),
);

// ─── Theme catalog ────────────────────────────────────────────────────────

const themeCatalog = <AppThemeDefinition>[
  // ── Standard (free) ──────────────────────────────────────────────────

  AppThemeDefinition(
    id: 'midnight',
    name: 'Midnight',
    description: 'Класична темна тема з бірюзовим акцентом. Дефолт.',
    emoji: '🌙',
    category: ThemeCategory.standard,
    cost: 0,
    colors: defaultThemeColors,
  ),

  AppThemeDefinition(
    id: 'terminal',
    name: 'Terminal',
    description: 'Зелений на чорному. Хакерська класика.',
    emoji: '💚',
    category: ThemeCategory.standard,
    cost: 0,
    colors: ThemeColors(
      background: Color(0xFF0A0A0A),
      surface: Color(0xFF121212),
      surfaceDim: Color(0xFF0D0D0D),
      accent: Color(0xFF00FF41),
      accentDim: Color(0xFF00FF41),
      gold: Color(0xFFFFD700),
      success: Color(0xFF00FF41),
      error: Color(0xFFFF3333),
      textHigh: Color(0xFF00DD38),
      textMedium: Color(0xFF00AA2C),
      textLow: Color(0xFF006B1C),
      border: Color(0xFF1A2A1A),
      divider: Color(0xFF152015),
    ),
  ),

  AppThemeDefinition(
    id: 'ocean',
    name: 'Ocean',
    description: 'Глибокий синій з бірюзовими відтінками.',
    emoji: '🌊',
    category: ThemeCategory.standard,
    cost: 0,
    colors: ThemeColors(
      background: Color(0xFF0B1021),
      surface: Color(0xFF111833),
      surfaceDim: Color(0xFF0D1329),
      accent: Color(0xFF38BDF8),
      accentDim: Color(0xFF38BDF8),
      gold: Color(0xFFFFD700),
      success: Color(0xFF34D399),
      error: Color(0xFFFB7185),
      textHigh: Color(0xFFE0E7FF),
      textMedium: Color(0xFF94A3C8),
      textLow: Color(0xFF4B5888),
      border: Color(0xFF1E2A4A),
      divider: Color(0xFF182040),
    ),
  ),

  AppThemeDefinition(
    id: 'monokai',
    name: 'Monokai',
    description: 'Тепла палітра улюбленого редактора.',
    emoji: '🔥',
    category: ThemeCategory.standard,
    cost: 0,
    colors: ThemeColors(
      background: Color(0xFF272822),
      surface: Color(0xFF2D2E27),
      surfaceDim: Color(0xFF23241E),
      accent: Color(0xFFF92672),
      accentDim: Color(0xFFF92672),
      gold: Color(0xFFE6DB74),
      success: Color(0xFFA6E22E),
      error: Color(0xFFF92672),
      textHigh: Color(0xFFF8F8F2),
      textMedium: Color(0xFFBFBDB0),
      textLow: Color(0xFF75715E),
      border: Color(0xFF3E3D32),
      divider: Color(0xFF35342A),
    ),
  ),

  // ── Premium ──────────────────────────────────────────────────────────

  AppThemeDefinition(
    id: 'cyberpunk',
    name: 'Cyberpunk',
    description: 'Неон, фуксія, глітч. Нічне місто в коді.',
    emoji: '🌃',
    category: ThemeCategory.premium,
    cost: 2000,
    isCustomizable: true,
    accentPalette: [
      Color(0xFFFF2D7B), // neon pink (default)
      Color(0xFF00FFFF), // cyan
      Color(0xFFFF00FF), // magenta
      Color(0xFFBF00FF), // purple
      Color(0xFF00FF88), // neon green
      Color(0xFFFFFF00), // yellow neon
    ],
    backgroundShades: [
      Color(0xFF050510), // darker
      Color(0xFF0D0D1A), // default
      Color(0xFF15152A), // lighter
    ],
    highlightTints: [
      Color(0xFFFFD700), // gold
      Color(0xFFC0C0C0), // silver
      Color(0xFFFF69B4), // hot pink
    ],
    colors: ThemeColors(
      background: Color(0xFF0D0D1A),
      surface: Color(0xFF161630),
      surfaceDim: Color(0xFF111125),
      accent: Color(0xFFFF2D7B),
      accentDim: Color(0xFFFF2D7B),
      gold: Color(0xFFFFD700),
      success: Color(0xFF00FF88),
      error: Color(0xFFFF3366),
      textHigh: Color(0xFFF0E0FF),
      textMedium: Color(0xFFA090C0),
      textLow: Color(0xFF605080),
      border: Color(0xFF2A2050),
      divider: Color(0xFF201840),
    ),
  ),

  AppThemeDefinition(
    id: 'sakura',
    name: 'Sakura',
    description: 'Ніжні рожеві тони. Спокій японських садів.',
    emoji: '🌸',
    category: ThemeCategory.premium,
    cost: 1500,
    isCustomizable: true,
    accentPalette: [
      Color(0xFFFF7EB3), // sakura pink (default)
      Color(0xFFFF9CC2), // light pink
      Color(0xFFE87BA4), // rose
      Color(0xFFD4628A), // deep rose
      Color(0xFFB8A0D6), // lavender
      Color(0xFF7ECAB8), // sage green
    ],
    backgroundShades: [
      Color(0xFF100A0F), // darker
      Color(0xFF1A1018), // default
      Color(0xFF241820), // lighter
    ],
    highlightTints: [
      Color(0xFFFFD700), // gold
      Color(0xFFFFC0CB), // pink gold
      Color(0xFFFFF0F5), // lavender blush
    ],
    colors: ThemeColors(
      background: Color(0xFF1A1018),
      surface: Color(0xFF241820),
      surfaceDim: Color(0xFF1E1318),
      accent: Color(0xFFFF7EB3),
      accentDim: Color(0xFFFF7EB3),
      gold: Color(0xFFFFD700),
      success: Color(0xFF7ECAB8),
      error: Color(0xFFFF6B8A),
      textHigh: Color(0xFFFFF0F5),
      textMedium: Color(0xFFBFA0B0),
      textLow: Color(0xFF7A6070),
      border: Color(0xFF3A2030),
      divider: Color(0xFF2E1828),
    ),
  ),

  AppThemeDefinition(
    id: 'synthwave',
    name: 'Synthwave',
    description: 'Ретро-хвиля 80-х. Фіолет, помаранч, неон.',
    emoji: '🎹',
    category: ThemeCategory.premium,
    cost: 2500,
    isCustomizable: true,
    accentPalette: [
      Color(0xFFE040FB), // purple neon (default)
      Color(0xFFFF6E40), // orange
      Color(0xFFFF40A0), // hot magenta
      Color(0xFF40C4FF), // sky blue
      Color(0xFFFFD740), // amber
      Color(0xFF69F0AE), // mint
    ],
    backgroundShades: [
      Color(0xFF0A0515), // darker
      Color(0xFF120A20), // default
      Color(0xFF1A1030), // lighter
    ],
    highlightTints: [
      Color(0xFFFFD700), // gold
      Color(0xFFFF6E40), // orange glow
      Color(0xFFE040FB), // purple glow
    ],
    colors: ThemeColors(
      background: Color(0xFF120A20),
      surface: Color(0xFF1C1235),
      surfaceDim: Color(0xFF160E28),
      accent: Color(0xFFE040FB),
      accentDim: Color(0xFFE040FB),
      gold: Color(0xFFFFD700),
      success: Color(0xFF69F0AE),
      error: Color(0xFFFF5252),
      textHigh: Color(0xFFEDE0FF),
      textMedium: Color(0xFFA890C8),
      textLow: Color(0xFF685080),
      border: Color(0xFF2A1848),
      divider: Color(0xFF221440),
    ),
  ),

  AppThemeDefinition(
    id: 'dracula',
    name: 'Dracula',
    description: 'Класика від Дракули. Фіолет і рожевий.',
    emoji: '🧛',
    category: ThemeCategory.premium,
    cost: 1000,
    isCustomizable: true,
    accentPalette: [
      Color(0xFFBD93F9), // purple (default)
      Color(0xFFFF79C6), // pink
      Color(0xFF50FA7B), // green
      Color(0xFF8BE9FD), // cyan
      Color(0xFFFFB86C), // orange
      Color(0xFFF1FA8C), // yellow
    ],
    backgroundShades: [
      Color(0xFF21222C), // darker
      Color(0xFF282A36), // default
      Color(0xFF2E303E), // lighter
    ],
    highlightTints: [
      Color(0xFFFFD700), // gold
      Color(0xFFF1FA8C), // dracula yellow
      Color(0xFFFF79C6), // dracula pink
    ],
    colors: ThemeColors(
      background: Color(0xFF282A36),
      surface: Color(0xFF313340),
      surfaceDim: Color(0xFF2C2E3A),
      accent: Color(0xFFBD93F9),
      accentDim: Color(0xFFBD93F9),
      gold: Color(0xFFF1FA8C),
      success: Color(0xFF50FA7B),
      error: Color(0xFFFF5555),
      textHigh: Color(0xFFF8F8F2),
      textMedium: Color(0xFFBBBBC8),
      textLow: Color(0xFF6272A4),
      border: Color(0xFF44475A),
      divider: Color(0xFF3A3D4F),
    ),
  ),

  AppThemeDefinition(
    id: 'aurora',
    name: 'Aurora',
    description: 'Північне сяйво. Переливи синього та зеленого.',
    emoji: '🌌',
    category: ThemeCategory.premium,
    cost: 3000,
    isCustomizable: true,
    accentPalette: [
      Color(0xFF88C0D0), // frost blue (default)
      Color(0xFFA3BE8C), // aurora green
      Color(0xFF81A1C1), // deep frost
      Color(0xFFB48EAD), // aurora purple
      Color(0xFF5E81AC), // glacier blue
      Color(0xFFEBCB8B), // gold shimmer
    ],
    backgroundShades: [
      Color(0xFF1A1E26), // darker
      Color(0xFF2E3440), // default
      Color(0xFF353C4A), // lighter
    ],
    highlightTints: [
      Color(0xFFEBCB8B), // nord yellow
      Color(0xFFD08770), // nord orange
      Color(0xFF88C0D0), // frost blue
    ],
    colors: ThemeColors(
      background: Color(0xFF2E3440),
      surface: Color(0xFF3B4252),
      surfaceDim: Color(0xFF343B4A),
      accent: Color(0xFF88C0D0),
      accentDim: Color(0xFF88C0D0),
      gold: Color(0xFFEBCB8B),
      success: Color(0xFFA3BE8C),
      error: Color(0xFFBF616A),
      textHigh: Color(0xFFECEFF4),
      textMedium: Color(0xFFD8DEE9),
      textLow: Color(0xFF7A8494),
      border: Color(0xFF4C566A),
      divider: Color(0xFF434C5E),
    ),
  ),
];

/// Lookup a theme definition by ID.
AppThemeDefinition? themeById(String id) {
  for (final theme in themeCatalog) {
    if (theme.id == id) return theme;
  }
  return null;
}

/// All standard (free) themes from the catalog.
List<AppThemeDefinition> get standardThemes =>
    themeCatalog.where((t) => t.category == ThemeCategory.standard).toList();

/// All premium themes from the catalog.
List<AppThemeDefinition> get premiumThemes =>
    themeCatalog.where((t) => t.category == ThemeCategory.premium).toList();

/// All currently available seasonal themes.
List<AppThemeDefinition> availableSeasonalThemes([DateTime? now]) =>
    themeCatalog
        .where((t) => t.category == ThemeCategory.seasonal && t.isAvailableNow(now))
        .toList();
