import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/app_theme.dart';

// Minimal ThemeColors for test setup (avoids repeating all 13 fields everywhere)
ThemeColors _colors({Color accent = const Color(0xFF00C0D1)}) => ThemeColors(
      background: const Color(0xFF0E0E11),
      surface: const Color(0xFF1A1A1F),
      surfaceDim: const Color(0xFF141418),
      accent: accent,
      accentDim: accent,
      gold: const Color(0xFFFFD700),
      success: const Color(0xFF22C55E),
      error: const Color(0xFFEF4444),
      textHigh: const Color(0xFFE8E8EC),
      textMedium: const Color(0xFF9898A4),
      textLow: const Color(0xFF5A5A66),
      border: const Color(0xFF2A2A30),
      divider: const Color(0xFF222228),
    );

AppThemeDefinition _theme({
  String id = 'test',
  int cost = 0,
  ThemeCategory category = ThemeCategory.standard,
  List<Color> accentPalette = const [],
  List<Color> backgroundShades = const [],
  List<Color> highlightTints = const [],
  DateTime? availableFrom,
  DateTime? availableUntil,
}) =>
    AppThemeDefinition(
      id: id,
      name: 'Test',
      description: '',
      emoji: '🧪',
      category: category,
      cost: cost,
      colors: _colors(),
      accentPalette: accentPalette,
      backgroundShades: backgroundShades,
      highlightTints: highlightTints,
      availableFrom: availableFrom,
      availableUntil: availableUntil,
    );

void main() {
  // ─── ThemeCategoryExt.label ─────────────────────────────────────────────

  group('ThemeCategoryExt.label', () {
    test('standard label', () {
      expect(ThemeCategory.standard.label, 'Стандартні');
    });

    test('premium label', () {
      expect(ThemeCategory.premium.label, 'Преміум');
    });

    test('seasonal label', () {
      expect(ThemeCategory.seasonal.label, 'Сезонні');
    });
  });

  // ─── ThemeCustomization ─────────────────────────────────────────────────

  group('ThemeCustomization.isEmpty', () {
    test('true when all null', () {
      expect(const ThemeCustomization().isEmpty, isTrue);
    });

    test('false when accentIndex set', () {
      expect(const ThemeCustomization(accentIndex: 0).isEmpty, isFalse);
    });

    test('false when backgroundIndex set', () {
      expect(const ThemeCustomization(backgroundIndex: 1).isEmpty, isFalse);
    });

    test('false when highlightIndex set', () {
      expect(const ThemeCustomization(highlightIndex: 2).isEmpty, isFalse);
    });
  });

  group('ThemeCustomization toJson/fromJson', () {
    test('empty customization serializes to empty map', () {
      expect(const ThemeCustomization().toJson(), isEmpty);
    });

    test('round-trips all three fields', () {
      const c = ThemeCustomization(accentIndex: 1, backgroundIndex: 2, highlightIndex: 0);
      final restored = ThemeCustomization.fromJson(c.toJson());
      expect(restored.accentIndex, 1);
      expect(restored.backgroundIndex, 2);
      expect(restored.highlightIndex, 0);
    });

    test('round-trips partial fields (only accent)', () {
      const c = ThemeCustomization(accentIndex: 3);
      final restored = ThemeCustomization.fromJson(c.toJson());
      expect(restored.accentIndex, 3);
      expect(restored.backgroundIndex, isNull);
      expect(restored.highlightIndex, isNull);
    });

    test('fromJson with empty map defaults all to null', () {
      final c = ThemeCustomization.fromJson({});
      expect(c.isEmpty, isTrue);
    });
  });

  // ─── ThemeState ─────────────────────────────────────────────────────────

  group('ThemeState defaults', () {
    test('activeThemeId defaults to midnight', () {
      expect(const ThemeState().activeThemeId, 'midnight');
    });

    test('ownedThemes defaults to empty', () {
      expect(const ThemeState().ownedThemes, isEmpty);
    });

    test('customizations defaults to empty', () {
      expect(const ThemeState().customizations, isEmpty);
    });
  });

  group('ThemeState.copyWith', () {
    const base = ThemeState(activeThemeId: 'terminal');

    test('changes activeThemeId', () {
      expect(base.copyWith(activeThemeId: 'ocean').activeThemeId, 'ocean');
    });

    test('preserves unchanged fields', () {
      final s = base.copyWith(ownedThemes: {'cyberpunk'});
      expect(s.activeThemeId, 'terminal');
      expect(s.ownedThemes, {'cyberpunk'});
    });
  });

  group('ThemeState toJson/fromJson', () {
    test('round-trips activeThemeId', () {
      const s = ThemeState(activeThemeId: 'sakura');
      final r = ThemeState.fromJson(s.toJson());
      expect(r.activeThemeId, 'sakura');
    });

    test('round-trips ownedThemes set', () {
      const s = ThemeState(ownedThemes: {'cyberpunk', 'dracula'});
      final r = ThemeState.fromJson(s.toJson());
      expect(r.ownedThemes, {'cyberpunk', 'dracula'});
    });

    test('round-trips customizations map', () {
      const s = ThemeState(
        customizations: {'cyberpunk': ThemeCustomization(accentIndex: 2)},
      );
      final r = ThemeState.fromJson(s.toJson());
      expect(r.customizations['cyberpunk']?.accentIndex, 2);
    });

    test('empty customizations not written to json', () {
      const s = ThemeState(
        customizations: {'cyberpunk': ThemeCustomization()},
      );
      final json = s.toJson();
      final customMap = json['customizations'] as Map;
      expect(customMap, isEmpty);
    });

    test('fromJson with missing fields gets defaults', () {
      final r = ThemeState.fromJson({});
      expect(r.activeThemeId, 'midnight');
      expect(r.ownedThemes, isEmpty);
      expect(r.customizations, isEmpty);
    });
  });

  group('ThemeState encode/decode', () {
    test('round-trips via encode/decode', () {
      const s = ThemeState(
        activeThemeId: 'aurora',
        ownedThemes: {'aurora', 'synthwave'},
      );
      final r = ThemeState.decode(s.encode());
      expect(r.activeThemeId, 'aurora');
      expect(r.ownedThemes, {'aurora', 'synthwave'});
    });
  });

  // ─── AppThemeDefinition ──────────────────────────────────────────────────

  group('AppThemeDefinition.isFree / isPremium / isSeasonal', () {
    test('isFree when cost=0', () {
      expect(_theme(cost: 0).isFree, isTrue);
    });

    test('not isFree when cost>0', () {
      expect(_theme(cost: 500).isFree, isFalse);
    });

    test('isPremium when category=premium', () {
      expect(_theme(category: ThemeCategory.premium).isPremium, isTrue);
    });

    test('isSeasonal when category=seasonal', () {
      expect(_theme(category: ThemeCategory.seasonal).isSeasonal, isTrue);
    });
  });

  group('AppThemeDefinition.isAvailableNow', () {
    final past = DateTime(2020, 1, 1);
    final future = DateTime(2099, 1, 1);
    final now = DateTime(2026, 6, 1);

    test('no date constraints → always available', () {
      expect(_theme().isAvailableNow(now), isTrue);
    });

    test('availableFrom in past → available', () {
      expect(_theme(availableFrom: past).isAvailableNow(now), isTrue);
    });

    test('availableFrom in future → not available', () {
      expect(_theme(availableFrom: future).isAvailableNow(now), isFalse);
    });

    test('availableUntil in past → not available', () {
      expect(_theme(availableUntil: past).isAvailableNow(now), isFalse);
    });

    test('availableUntil in future → available', () {
      expect(_theme(availableUntil: future).isAvailableNow(now), isTrue);
    });

    test('within valid range → available', () {
      expect(_theme(availableFrom: past, availableUntil: future).isAvailableNow(now), isTrue);
    });

    test('before valid range → not available', () {
      final early = DateTime(2019, 1, 1);
      expect(_theme(availableFrom: past, availableUntil: future).isAvailableNow(early), isFalse);
    });
  });

  // ─── resolveThemeColors ──────────────────────────────────────────────────

  group('resolveThemeColors', () {
    final palette = [
      const Color(0xFFFF0000),
      const Color(0xFF00FF00),
    ];
    final backgrounds = [
      const Color(0xFF111111),
      const Color(0xFF222222),
    ];
    final highlights = [
      const Color(0xFFAAAA00),
      const Color(0xFFBBBB00),
    ];
    final theme = AppThemeDefinition(
      id: 'test',
      name: 'Test',
      description: '',
      emoji: '🧪',
      category: ThemeCategory.premium,
      cost: 1000,
      isCustomizable: true,
      colors: _colors(accent: const Color(0xFF00C0D1)),
      accentPalette: palette,
      backgroundShades: backgrounds,
      highlightTints: highlights,
    );

    test('null customization returns original colors', () {
      final result = resolveThemeColors(theme, null);
      expect(result.accent, const Color(0xFF00C0D1));
    });

    test('empty customization returns original colors', () {
      final result = resolveThemeColors(theme, const ThemeCustomization());
      expect(result.accent, const Color(0xFF00C0D1));
    });

    test('accentIndex overrides accent color', () {
      final result = resolveThemeColors(theme, const ThemeCustomization(accentIndex: 0));
      expect(result.accent, const Color(0xFFFF0000));
    });

    test('accentIndex=1 picks second palette color', () {
      final result = resolveThemeColors(theme, const ThemeCustomization(accentIndex: 1));
      expect(result.accent, const Color(0xFF00FF00));
    });

    test('backgroundIndex overrides background', () {
      final result = resolveThemeColors(theme, const ThemeCustomization(backgroundIndex: 0));
      expect(result.background, const Color(0xFF111111));
    });

    test('highlightIndex overrides gold', () {
      final result = resolveThemeColors(theme, const ThemeCustomization(highlightIndex: 1));
      expect(result.gold, const Color(0xFFBBBB00));
    });

    test('out-of-bounds accentIndex is ignored', () {
      final result = resolveThemeColors(theme, const ThemeCustomization(accentIndex: 99));
      expect(result.accent, const Color(0xFF00C0D1));
    });

    test('out-of-bounds backgroundIndex is ignored', () {
      final result = resolveThemeColors(theme, const ThemeCustomization(backgroundIndex: 99));
      expect(result.background, const Color(0xFF0E0E11));
    });
  });

  // ─── Catalog helpers ─────────────────────────────────────────────────────

  group('themeById', () {
    test('finds existing theme', () {
      expect(themeById('midnight'), isNotNull);
      expect(themeById('midnight')!.id, 'midnight');
    });

    test('returns null for unknown id', () {
      expect(themeById('nonexistent'), isNull);
    });

    test('finds cyberpunk', () {
      expect(themeById('cyberpunk'), isNotNull);
    });
  });

  group('standardThemes', () {
    test('contains only cost=0 themes', () {
      expect(standardThemes.every((t) => t.cost == 0), isTrue);
    });

    test('is non-empty', () {
      expect(standardThemes, isNotEmpty);
    });

    test('midnight is in standard themes', () {
      expect(standardThemes.any((t) => t.id == 'midnight'), isTrue);
    });
  });

  group('premiumThemes', () {
    test('contains only premium category', () {
      expect(premiumThemes.every((t) => t.category == ThemeCategory.premium), isTrue);
    });

    test('all premium themes have cost > 0', () {
      expect(premiumThemes.every((t) => t.cost > 0), isTrue);
    });

    test('cyberpunk is in premium themes', () {
      expect(premiumThemes.any((t) => t.id == 'cyberpunk'), isTrue);
    });
  });

  group('availableSeasonalThemes', () {
    test('returns empty when no seasonal themes in catalog', () {
      expect(availableSeasonalThemes(), isEmpty);
    });
  });
}
