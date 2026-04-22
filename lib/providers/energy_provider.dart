/// Daily LLM-token budget tracker (Energy meter).
///
/// Surfaces real token economy to the player as a game resource. Agents can
/// only run on Opus/Sonnet up to per-day quotas; after the quota, the tier
/// downgrades to Haiku for the rest of the day. Window resets at local
/// midnight.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

/// Model tier strings align with the server's [hardwareToModel] output.
class EnergyState {
  /// Total input+output tokens consumed today.
  final int tokensUsedToday;
  final int opusTasksUsedToday;
  final int sonnetTasksUsedToday;

  final int dailyTokenCap;
  final int opusCapPerDay;
  final int sonnetCapPerDay;

  /// Midnight-aligned timestamp when the current window started.
  final DateTime windowStart;

  const EnergyState({
    this.tokensUsedToday = 0,
    this.opusTasksUsedToday = 0,
    this.sonnetTasksUsedToday = 0,
    this.dailyTokenCap = 500000,
    this.opusCapPerDay = 3,
    this.sonnetCapPerDay = 20,
    required this.windowStart,
  });

  double get tokenUsageRatio =>
      dailyTokenCap == 0 ? 1.0 : (tokensUsedToday / dailyTokenCap).clamp(0.0, 1.0);

  EnergyState copyWith({
    int? tokensUsedToday,
    int? opusTasksUsedToday,
    int? sonnetTasksUsedToday,
    int? dailyTokenCap,
    int? opusCapPerDay,
    int? sonnetCapPerDay,
    DateTime? windowStart,
  }) =>
      EnergyState(
        tokensUsedToday: tokensUsedToday ?? this.tokensUsedToday,
        opusTasksUsedToday: opusTasksUsedToday ?? this.opusTasksUsedToday,
        sonnetTasksUsedToday: sonnetTasksUsedToday ?? this.sonnetTasksUsedToday,
        dailyTokenCap: dailyTokenCap ?? this.dailyTokenCap,
        opusCapPerDay: opusCapPerDay ?? this.opusCapPerDay,
        sonnetCapPerDay: sonnetCapPerDay ?? this.sonnetCapPerDay,
        windowStart: windowStart ?? this.windowStart,
      );

  Map<String, dynamic> toJson() => {
        'tokensUsedToday': tokensUsedToday,
        'opusTasksUsedToday': opusTasksUsedToday,
        'sonnetTasksUsedToday': sonnetTasksUsedToday,
        'dailyTokenCap': dailyTokenCap,
        'opusCapPerDay': opusCapPerDay,
        'sonnetCapPerDay': sonnetCapPerDay,
        'windowStart': windowStart.toIso8601String(),
      };

  factory EnergyState.fromJson(Map<String, dynamic> j) => EnergyState(
        tokensUsedToday: j['tokensUsedToday'] as int? ?? 0,
        opusTasksUsedToday: j['opusTasksUsedToday'] as int? ?? 0,
        sonnetTasksUsedToday: j['sonnetTasksUsedToday'] as int? ?? 0,
        dailyTokenCap: j['dailyTokenCap'] as int? ?? 500000,
        opusCapPerDay: j['opusCapPerDay'] as int? ?? 3,
        sonnetCapPerDay: j['sonnetCapPerDay'] as int? ?? 20,
        windowStart: DateTime.parse(j['windowStart'] as String),
      );
}

class EnergyNotifier extends Notifier<EnergyState> {
  static const _prefsKey = 'energyState';

  @override
  EnergyState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_prefsKey);
    final today = _startOfToday();
    if (raw == null) return EnergyState(windowStart: today);
    try {
      final parsed =
          EnergyState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!_sameDay(parsed.windowStart, today)) {
        // New day: keep configured caps, reset usage counters.
        return EnergyState(
          windowStart: today,
          dailyTokenCap: parsed.dailyTokenCap,
          opusCapPerDay: parsed.opusCapPerDay,
          sonnetCapPerDay: parsed.sonnetCapPerDay,
        );
      }
      return parsed;
    } catch (_) {
      return EnergyState(windowStart: today);
    }
  }

  /// Record a completed task's token usage. [model] is the tier that actually
  /// ran ('haiku' / 'sonnet' / 'opus'), [tokens] is input + output combined.
  void recordTaskTokens(String model, int tokens) {
    state = state.copyWith(
      tokensUsedToday: state.tokensUsedToday + tokens.clamp(0, 1000000),
      opusTasksUsedToday:
          state.opusTasksUsedToday + (model == 'opus' ? 1 : 0),
      sonnetTasksUsedToday:
          state.sonnetTasksUsedToday + (model == 'sonnet' ? 1 : 0),
    );
    _persist();
  }

  /// Effective model after applying daily budgets: if we're over the total
  /// token cap, downgrade to haiku; opus/sonnet caps downgrade one tier.
  String effectiveModel({required String requested}) {
    if (state.tokensUsedToday >= state.dailyTokenCap) return 'haiku';
    if (requested == 'opus' &&
        state.opusTasksUsedToday >= state.opusCapPerDay) {
      return 'sonnet';
    }
    if (requested == 'sonnet' &&
        state.sonnetTasksUsedToday >= state.sonnetCapPerDay) {
      return 'haiku';
    }
    return requested;
  }

  void updateDailyCap(int cap) {
    state = state.copyWith(dailyTokenCap: cap);
    _persist();
  }

  void _persist() {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  static DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

final energyProvider =
    NotifierProvider<EnergyNotifier, EnergyState>(EnergyNotifier.new);
