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
        // Soft migration: same logical shape with purely additive fields. We
        // accept saves exactly one version back and rely on fromJson to fill
        // safe defaults for missing keys. Players keep agents / placed rooms /
        // grymni intact; no reset toast.
        if (version == GameState.currentSchemaVersion - 1) {
          try {
            final migrated = GameState.fromJson(json)
                .copyWith(schemaVersion: GameState.currentSchemaVersion);
            prefs.setString(_key, migrated.encode());
            return migrated;
          } catch (_) {
            // Parse failed — fall through to the hard wipe below.
          }
        }

        // Hard wipe: schema is too old or soft-migration failed. Preserve
        // whitelisted fields so players don't lose currency or purchased
        // items, and set a flag for the one-time reset toast.
        prefs.setBool('schemaResetFlag', true);
        final fresh = GameState.initial();
        final migrated = fresh.copyWith(
          grymni: json['grymni'] as int? ?? fresh.grymni,
          totalEarned: json['totalEarned'] as int? ?? fresh.totalEarned,
          ownedCosmetics: _parseStringSet(
            json['ownedCosmetics'],
            fresh.ownedCosmetics,
          ),
        );
        // Persist immediately so a quick restart doesn't re-trigger
        // migration (and the reset toast) on the next launch.
        prefs.setString(_key, migrated.encode());
        return migrated;
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
