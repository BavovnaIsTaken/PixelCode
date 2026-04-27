/// App settings with persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/logo_path_program.dart' show validateLogoPathScript;

// ─── Keys ───────────────────────────────────────────────────────────────────

const _keyShowArkanoidButton = 'settings_show_arkanoid_button';
const _keyDeskHeight = 'settings_desk_height';
const _keyGlitchEnabled = 'settings_glitch_enabled';
const _keyGlitchIntensity = 'settings_glitch_intensity';
const _keyGlitchSpeed = 'settings_glitch_speed';
const _keyGlitchBandHeight = 'settings_glitch_band_height';
const _keyGlitchBandHeightMin = 'settings_glitch_band_height_min';
const _keyGlitchShift = 'settings_glitch_shift';
const _keyGlitchChroma = 'settings_glitch_chroma';
const _keyLaunchCount = 'settings_launch_count';
const _keyLogoPathScript = 'settings_logo_path_script';
const _keyLogoAnimationDurationMs = 'settings_logo_animation_duration_ms';
const _keyHideDirectMessagingHint = 'settings_hide_direct_messaging_hint';
const _keyLearningConsent = 'settings_learning_consent';

/// Default duration of the shutdown logo flight (icon moves from top-left
/// to the opposite corner). The native window collapse that follows adds
/// 400 ms, so the full shutdown sequence lasts [kDefaultLogoAnimationDurationMs]
/// + 400 ms.
const int kDefaultLogoAnimationDurationMs = 1100;
const int _minLogoAnimationDurationMs = 400;
const int _maxLogoAnimationDurationMs = 3000;

// ─── Settings model ─────────────────────────────────────────────────────────

class AppSettings {
  final bool showArkanoidButton;
  final double deskHeight;
  final bool glitchEnabled;

  /// Fraction of pixel blocks affected during glitch (0.01–0.30).
  final double glitchIntensity;

  /// Animation speed multiplier (0.5–3.0). Higher = faster.
  final double glitchSpeed;

  /// Max height of each scanline band in display pixels (1–8).
  final int glitchBandHeight;

  /// Min height of each scanline band in display pixels (1–glitchBandHeight).
  final int glitchBandHeightMin;

  /// Horizontal shift strength (0.0–1.0). 1.0 = ±50% of display width.
  final double glitchShift;

  /// Chromatic aberration strength (0.0–1.0). 0 = off.
  final double glitchChroma;

  final int launchCount;

  /// Custom DSL script for logo path animation, or null to use the built-in
  /// zigzag algorithm. See [kDefaultLogoPathScript] for the default.
  final String? logoPathScript;

  /// Duration of the shutdown icon flight in milliseconds, or null to use
  /// [kDefaultLogoAnimationDurationMs]. The native window collapse phase
  /// (400 ms) is appended automatically.
  final int? logoAnimationDurationMs;

  /// When true, the chat panel suppresses the "you're messaging a non-captain"
  /// hint. The user opted out explicitly.
  final bool hideDirectMessagingHint;

  /// When true, the server records lessons from agent sessions (auto-learning).
  /// User can opt out to disable automatic lesson extraction.
  final bool learningConsentEnabled;

  const AppSettings({
    this.showArkanoidButton = false,
    this.deskHeight = 74.0,
    this.glitchEnabled = true,
    this.glitchIntensity = 0.06,
    this.glitchSpeed = 1.0,
    this.glitchBandHeight = 3,
    this.glitchBandHeightMin = 1,
    this.glitchShift = 0.5,
    this.glitchChroma = 0.5,
    this.launchCount = 0,
    this.logoPathScript,
    this.logoAnimationDurationMs,
    this.hideDirectMessagingHint = false,
    this.learningConsentEnabled = true,
  });

  AppSettings copyWith({
    bool? showArkanoidButton,
    double? deskHeight,
    bool? glitchEnabled,
    double? glitchIntensity,
    double? glitchSpeed,
    int? glitchBandHeight,
    int? glitchBandHeightMin,
    double? glitchShift,
    double? glitchChroma,
    int? launchCount,
    Object? logoPathScript = _sentinel,
    Object? logoAnimationDurationMs = _sentinel,
    bool? hideDirectMessagingHint,
    bool? learningConsentEnabled,
  }) =>
      AppSettings(
        showArkanoidButton: showArkanoidButton ?? this.showArkanoidButton,
        deskHeight: deskHeight ?? this.deskHeight,
        glitchEnabled: glitchEnabled ?? this.glitchEnabled,
        glitchIntensity: glitchIntensity ?? this.glitchIntensity,
        glitchSpeed: glitchSpeed ?? this.glitchSpeed,
        glitchBandHeight: glitchBandHeight ?? this.glitchBandHeight,
        glitchBandHeightMin: glitchBandHeightMin ?? this.glitchBandHeightMin,
        glitchShift: glitchShift ?? this.glitchShift,
        glitchChroma: glitchChroma ?? this.glitchChroma,
        launchCount: launchCount ?? this.launchCount,
        logoPathScript: identical(logoPathScript, _sentinel)
            ? this.logoPathScript
            : logoPathScript as String?,
        logoAnimationDurationMs:
            identical(logoAnimationDurationMs, _sentinel)
                ? this.logoAnimationDurationMs
                : logoAnimationDurationMs as int?,
        hideDirectMessagingHint:
            hideDirectMessagingHint ?? this.hideDirectMessagingHint,
        learningConsentEnabled:
            learningConsentEnabled ?? this.learningConsentEnabled,
      );
}

// Sentinel for nullable copyWith
const _sentinel = Object();

/// Discards persisted scripts that don't parse under the current DSL
/// (e.g. a legacy `Point(x,y)` formula from an older build).
String? _loadValidScript(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return validateLogoPathScript(raw) == null ? raw : null;
}

/// Coerces out-of-range persisted values back to `null` (→ default).
int? _loadValidAnimationDurationMs(int? raw) {
  if (raw == null) return null;
  if (raw < _minLogoAnimationDurationMs || raw > _maxLogoAnimationDurationMs) {
    return null;
  }
  return raw;
}

int _clampLogoAnimationDurationMs(int value) => value.clamp(
      _minLogoAnimationDurationMs,
      _maxLogoAnimationDurationMs,
    );

// ─── SharedPreferences instance ─────────────────────────────────────────────

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden at startup');
});

// ─── Settings notifier ──────────────────────────────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.read(sharedPrefsProvider);
    return AppSettings(
      showArkanoidButton: prefs.getBool(_keyShowArkanoidButton) ?? false,
      deskHeight: prefs.getDouble(_keyDeskHeight) ?? 74.0,
      glitchEnabled: prefs.getBool(_keyGlitchEnabled) ?? true,
      glitchIntensity: prefs.getDouble(_keyGlitchIntensity) ?? 0.06,
      glitchSpeed: prefs.getDouble(_keyGlitchSpeed) ?? 1.0,
      glitchBandHeight: prefs.getInt(_keyGlitchBandHeight) ?? 3,
      glitchBandHeightMin: prefs.getInt(_keyGlitchBandHeightMin) ?? 1,
      glitchShift: prefs.getDouble(_keyGlitchShift) ?? 0.5,
      glitchChroma: prefs.getDouble(_keyGlitchChroma) ?? 0.5,
      launchCount: prefs.getInt(_keyLaunchCount) ?? 0,
      logoPathScript: _loadValidScript(prefs.getString(_keyLogoPathScript)),
      logoAnimationDurationMs: _loadValidAnimationDurationMs(
        prefs.getInt(_keyLogoAnimationDurationMs),
      ),
      hideDirectMessagingHint:
          prefs.getBool(_keyHideDirectMessagingHint) ?? false,
      learningConsentEnabled:
          prefs.getBool(_keyLearningConsent) ?? true,
    );
  }

  Future<void> setHideDirectMessagingHint(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyHideDirectMessagingHint, value);
    state = state.copyWith(hideDirectMessagingHint: value);
  }

  Future<void> setLearningConsentEnabled(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyLearningConsent, value);
    state = state.copyWith(learningConsentEnabled: value);
  }

  Future<void> incrementLaunchCount() async {
    final prefs = ref.read(sharedPrefsProvider);
    final next = state.launchCount + 1;
    await prefs.setInt(_keyLaunchCount, next);
    state = state.copyWith(launchCount: next);
  }

  Future<void> setShowArkanoidButton(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyShowArkanoidButton, value);
    state = state.copyWith(showArkanoidButton: value);
  }

  Future<void> setDeskHeight(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyDeskHeight, value);
    state = state.copyWith(deskHeight: value);
  }

  Future<void> setGlitchEnabled(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyGlitchEnabled, value);
    state = state.copyWith(glitchEnabled: value);
  }

  Future<void> setGlitchIntensity(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyGlitchIntensity, value);
    state = state.copyWith(glitchIntensity: value);
  }

  Future<void> setGlitchSpeed(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyGlitchSpeed, value);
    state = state.copyWith(glitchSpeed: value);
  }

  Future<void> setGlitchBandHeight(int value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setInt(_keyGlitchBandHeight, value);
    // Keep min ≤ max; bump min down if the user lowered max below it.
    final newMin = value < state.glitchBandHeightMin ? value : state.glitchBandHeightMin;
    if (newMin != state.glitchBandHeightMin) {
      await prefs.setInt(_keyGlitchBandHeightMin, newMin);
    }
    state = state.copyWith(glitchBandHeight: value, glitchBandHeightMin: newMin);
  }

  Future<void> setGlitchBandHeightMin(int value) async {
    final prefs = ref.read(sharedPrefsProvider);
    final clamped = value > state.glitchBandHeight ? state.glitchBandHeight : value;
    await prefs.setInt(_keyGlitchBandHeightMin, clamped);
    state = state.copyWith(glitchBandHeightMin: clamped);
  }

  Future<void> setGlitchShift(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyGlitchShift, value);
    state = state.copyWith(glitchShift: value);
  }

  Future<void> setGlitchChroma(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyGlitchChroma, value);
    state = state.copyWith(glitchChroma: value);
  }

  Future<void> setLogoPathScript(String? value) async {
    final prefs = ref.read(sharedPrefsProvider);
    if (value == null) {
      await prefs.remove(_keyLogoPathScript);
    } else {
      await prefs.setString(_keyLogoPathScript, value);
    }
    state = state.copyWith(logoPathScript: value);
  }

  Future<void> setLogoAnimationDurationMs(int? value) async {
    final prefs = ref.read(sharedPrefsProvider);
    if (value == null) {
      await prefs.remove(_keyLogoAnimationDurationMs);
      state = state.copyWith(logoAnimationDurationMs: null);
      return;
    }
    final clamped = _clampLogoAnimationDurationMs(value);
    await prefs.setInt(_keyLogoAnimationDurationMs, clamped);
    state = state.copyWith(logoAnimationDurationMs: clamped);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
