/// Persistence for game economy state — saves to SharedPreferences.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_economy.dart';

class GamePersistenceService {
  static const _key = 'pixelcode_game_state';

  static GameState load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return GameState.initial();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final version = json['schemaVersion'] as int? ?? 1;
      if (version != GameState.currentSchemaVersion) {
        // Schema mismatch: drop state but preserve cosmetic ownership so
        // players don't lose purchased items across breaking schema changes.
        // Set a flag so the UI can show a one-time reset toast.
        prefs.setBool('schemaResetFlag', true);
        final fresh = GameState.initial();
        return fresh.copyWith(
          ownedCosmetics: _parseStringSet(
            json['ownedCosmetics'],
            fresh.ownedCosmetics,
          ),
        );
      }
      return GameState.fromJson(json);
    } catch (_) {
      return GameState.initial();
    }
  }

  static Future<void> save(SharedPreferences prefs, GameState state) async {
    await prefs.setString(_key, state.encode());
  }

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_key);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Set<String> _parseStringSet(
    dynamic raw,
    Set<String> fallback,
  ) {
    if (raw is List) {
      return {for (final id in raw) if (id is String) id};
    }
    return fallback;
  }
}
