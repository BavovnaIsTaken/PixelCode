/// Persistence for game economy state — saves to SharedPreferences.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_economy.dart';

class GamePersistenceService {
  static const _key = 'pixelcode_game_state';

  static GameState load(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return GameState.initial();
    try {
      return GameState.decode(raw);
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
}
