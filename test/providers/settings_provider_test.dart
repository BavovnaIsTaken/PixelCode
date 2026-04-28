import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/settings_provider.dart';

Future<ProviderContainer> _makeContainer([
  Map<String, Object> prefsValues = const {},
]) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  // ─── AppSettings defaults ────────────────────────────────────────────────

  group('AppSettings defaults', () {
    test('builds with default values from empty prefs', () async {
      final c = await _makeContainer();
      final s = c.read(settingsProvider);
      expect(s.showArkanoidButton, isFalse);
      expect(s.deskHeight, 74.0);
      expect(s.glitchEnabled, isTrue);
      expect(s.glitchIntensity, 0.06);
      expect(s.glitchSpeed, 1.0);
      expect(s.glitchBandHeight, 3);
      expect(s.glitchBandHeightMin, 1);
      expect(s.glitchShift, 0.5);
      expect(s.glitchChroma, 0.5);
      expect(s.launchCount, 0);
      expect(s.logoPathScript, isNull);
      expect(s.logoAnimationDurationMs, isNull);
      expect(s.hideDirectMessagingHint, isFalse);
      expect(s.learningConsentEnabled, isTrue);
    });

    test('loads persisted values from prefs', () async {
      final c = await _makeContainer({
        'settings_show_arkanoid_button': true,
        'settings_desk_height': 90.0,
        'settings_launch_count': 5,
      });
      final s = c.read(settingsProvider);
      expect(s.showArkanoidButton, isTrue);
      expect(s.deskHeight, 90.0);
      expect(s.launchCount, 5);
    });
  });

  // ─── AppSettings.copyWith sentinel pattern ───────────────────────────────

  group('AppSettings.copyWith', () {
    const base = AppSettings(logoPathScript: 'stamp trail', logoAnimationDurationMs: 1000);

    test('logoPathScript: null clears it', () {
      final s = base.copyWith(logoPathScript: null);
      expect(s.logoPathScript, isNull);
    });

    test('logoPathScript: omitted preserves existing value', () {
      final s = base.copyWith(glitchEnabled: false);
      expect(s.logoPathScript, 'stamp trail');
    });

    test('logoAnimationDurationMs: null clears it', () {
      final s = base.copyWith(logoAnimationDurationMs: null);
      expect(s.logoAnimationDurationMs, isNull);
    });

    test('logoAnimationDurationMs: omitted preserves existing value', () {
      final s = base.copyWith(glitchEnabled: false);
      expect(s.logoAnimationDurationMs, 1000);
    });
  });

  // ─── Boolean setters ─────────────────────────────────────────────────────

  group('setShowArkanoidButton', () {
    test('updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setShowArkanoidButton(true);
      expect(c.read(settingsProvider).showArkanoidButton, isTrue);
    });

    test('persists to prefs', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setShowArkanoidButton(true);
      final prefs = c.read(sharedPrefsProvider);
      expect(prefs.getBool('settings_show_arkanoid_button'), isTrue);
    });
  });

  group('setGlitchEnabled', () {
    test('sets glitchEnabled to false', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setGlitchEnabled(false);
      expect(c.read(settingsProvider).glitchEnabled, isFalse);
    });
  });

  group('setHideDirectMessagingHint', () {
    test('updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setHideDirectMessagingHint(true);
      expect(c.read(settingsProvider).hideDirectMessagingHint, isTrue);
    });
  });

  group('setLearningConsentEnabled', () {
    test('updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setLearningConsentEnabled(false);
      expect(c.read(settingsProvider).learningConsentEnabled, isFalse);
    });
  });

  // ─── Numeric setters ─────────────────────────────────────────────────────

  group('setDeskHeight', () {
    test('updates deskHeight', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setDeskHeight(90.0);
      expect(c.read(settingsProvider).deskHeight, 90.0);
    });
  });

  group('setGlitchIntensity / Speed / Shift / Chroma', () {
    test('setGlitchIntensity updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setGlitchIntensity(0.15);
      expect(c.read(settingsProvider).glitchIntensity, 0.15);
    });

    test('setGlitchSpeed updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setGlitchSpeed(2.0);
      expect(c.read(settingsProvider).glitchSpeed, 2.0);
    });

    test('setGlitchShift updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setGlitchShift(0.8);
      expect(c.read(settingsProvider).glitchShift, 0.8);
    });

    test('setGlitchChroma updates state', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setGlitchChroma(0.3);
      expect(c.read(settingsProvider).glitchChroma, 0.3);
    });
  });

  // ─── glitchBandHeight guard ──────────────────────────────────────────────

  group('setGlitchBandHeight', () {
    test('updates glitchBandHeight', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setGlitchBandHeight(5);
      expect(c.read(settingsProvider).glitchBandHeight, 5);
    });

    test('bumps min down when new max < current min', () async {
      final c = await _makeContainer({'settings_glitch_band_height_min': 4});
      // current min=4; set max to 2 → min must become 2
      await c.read(settingsProvider.notifier).setGlitchBandHeight(2);
      final s = c.read(settingsProvider);
      expect(s.glitchBandHeight, 2);
      expect(s.glitchBandHeightMin, 2);
    });

    test('does not change min when new max >= current min', () async {
      final c = await _makeContainer({'settings_glitch_band_height_min': 2});
      await c.read(settingsProvider.notifier).setGlitchBandHeight(6);
      expect(c.read(settingsProvider).glitchBandHeightMin, 2);
    });
  });

  group('setGlitchBandHeightMin', () {
    test('updates min normally', () async {
      final c = await _makeContainer({'settings_glitch_band_height': 5});
      await c.read(settingsProvider.notifier).setGlitchBandHeightMin(3);
      expect(c.read(settingsProvider).glitchBandHeightMin, 3);
    });

    test('clamps min to current max if too large', () async {
      final c = await _makeContainer({'settings_glitch_band_height': 3});
      await c.read(settingsProvider.notifier).setGlitchBandHeightMin(6);
      expect(c.read(settingsProvider).glitchBandHeightMin, 3);
    });
  });

  // ─── incrementLaunchCount ────────────────────────────────────────────────

  group('incrementLaunchCount', () {
    test('increments by 1 each call', () async {
      final c = await _makeContainer();
      final notifier = c.read(settingsProvider.notifier);
      await notifier.incrementLaunchCount();
      await notifier.incrementLaunchCount();
      expect(c.read(settingsProvider).launchCount, 2);
    });
  });

  // ─── setLogoPathScript ───────────────────────────────────────────────────

  group('setLogoPathScript', () {
    test('sets valid script', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setLogoPathScript('stamp trail');
      expect(c.read(settingsProvider).logoPathScript, 'stamp trail');
    });

    test('null removes the script', () async {
      final c = await _makeContainer({'settings_logo_path_script': 'stamp trail'});
      await c.read(settingsProvider.notifier).setLogoPathScript(null);
      expect(c.read(settingsProvider).logoPathScript, isNull);
    });

    test('invalid script stored but discarded on reload', () async {
      // setLogoPathScript stores whatever the user typed (validation is UI-side)
      // but build() calls _loadValidScript which filters it on next load
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setLogoPathScript('bad script!!!');
      // state is updated immediately (trust the user typed it correctly)
      expect(c.read(settingsProvider).logoPathScript, 'bad script!!!');

      // A fresh container with the same prefs should discard the invalid script
      final prefs = c.read(sharedPrefsProvider);
      final c2 = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(settingsProvider).logoPathScript, isNull);
    });
  });

  // ─── setLogoAnimationDurationMs ──────────────────────────────────────────

  group('setLogoAnimationDurationMs', () {
    test('null removes the value', () async {
      final c = await _makeContainer({'settings_logo_animation_duration_ms': 1200});
      await c.read(settingsProvider.notifier).setLogoAnimationDurationMs(null);
      expect(c.read(settingsProvider).logoAnimationDurationMs, isNull);
    });

    test('valid value within range is stored as-is', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setLogoAnimationDurationMs(1500);
      expect(c.read(settingsProvider).logoAnimationDurationMs, 1500);
    });

    test('value below minimum is clamped to 400', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setLogoAnimationDurationMs(100);
      expect(c.read(settingsProvider).logoAnimationDurationMs, 400);
    });

    test('value above maximum is clamped to 3000', () async {
      final c = await _makeContainer();
      await c.read(settingsProvider.notifier).setLogoAnimationDurationMs(9999);
      expect(c.read(settingsProvider).logoAnimationDurationMs, 3000);
    });

    test('out-of-range persisted value is discarded on build', () async {
      final c = await _makeContainer({'settings_logo_animation_duration_ms': 50});
      expect(c.read(settingsProvider).logoAnimationDurationMs, isNull);
    });
  });
}
