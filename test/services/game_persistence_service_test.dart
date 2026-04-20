import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelcode/services/game_persistence_service.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  test('load returns fresh state if schema version mismatches', () async {
    SharedPreferences.setMockInitialValues({
      'pixelcode_game_state':
          '{"schemaVersion":1,"grymni":999999,"totalEarned":12345,'
              '"ownedCosmetics":["hat_1"],'
              '"agents":{"inst_a":{"roleType":"dev","level":3}}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    // Schema is bumped to current.
    expect(loaded.schemaVersion, GameState.currentSchemaVersion);
    // Reset flag is set.
    expect(prefs.getBool('schemaResetFlag'), isTrue);

    // Whitelisted fields ARE preserved.
    expect(loaded.grymni, equals(999999));
    expect(loaded.totalEarned, equals(12345));
    expect(loaded.ownedCosmetics, contains('hat_1'));

    // Non-whitelisted fields ARE reset — old agent instance is gone.
    expect(loaded.agents.containsKey('inst_a'), isFalse);
    // Office is reset to defaults (garage, no expansions, no placed rooms).
    expect(loaded.officeLevel, OfficeLevel.garage);
    expect(loaded.officeExpansions, equals(0));
    expect(loaded.placedRooms, isEmpty);
  });

  test('load preserves state when schema matches', () async {
    final json =
        '{"schemaVersion":${GameState.currentSchemaVersion},"grymni":777}';
    SharedPreferences.setMockInitialValues({'pixelcode_game_state': json});
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    expect(loaded.grymni, 777);
  });
}
