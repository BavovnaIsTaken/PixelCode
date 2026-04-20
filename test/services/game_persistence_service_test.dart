import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelcode/services/game_persistence_service.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  test('load returns fresh state if schema version mismatches', () async {
    SharedPreferences.setMockInitialValues({
      'pixelcode_game_state': '{"schemaVersion":1,"grymni":999999}',
    });
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    expect(loaded.schemaVersion, GameState.currentSchemaVersion);
    expect(loaded.grymni, lessThan(999999));
    expect(prefs.getBool('schemaResetFlag'), isTrue);
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
