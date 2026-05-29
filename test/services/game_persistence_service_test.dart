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

  test('soft-migrates one-version-back save additively (v5 → v6)', () async {
    final prevVersion = GameState.currentSchemaVersion - 1;
    // A v5 save with placed rooms / agents / furniture — none of which the
    // hard-wipe whitelist would have preserved. Soft migration must keep them.
    final json = '{'
        '"schemaVersion":$prevVersion,'
        '"grymni":4321,'
        '"totalEarned":12345,'
        '"placedRooms":[{"id":"r1","type":0,"col":1,"row":1}],'
        '"placedFurniture":[{"itemId":"old_desk","col":2,"row":2}],'
        '"agents":{"inst_a":{"instanceId":"inst_a","roleType":"coder",'
            '"nickname":"Test","hardware":0}}'
        '}';
    SharedPreferences.setMockInitialValues({'pixelcode_game_state': json});
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    // Schema bumped to current.
    expect(loaded.schemaVersion, GameState.currentSchemaVersion);
    // No reset flag — soft migration is silent.
    expect(prefs.getBool('schemaResetFlag'), isNot(isTrue));
    // Pre-migration data preserved verbatim.
    expect(loaded.grymni, 4321);
    expect(loaded.totalEarned, 12345);
    expect(loaded.placedRooms, hasLength(1));
    expect(loaded.placedRooms.first.id, 'r1');
    expect(loaded.placedFurniture, hasLength(1));
    expect(loaded.agents, contains('inst_a'));
    // New v6 fields default to safe empties.
    expect(loaded.placedCorridors, isEmpty);
    expect(loaded.ownedWallSkinPacks, isEmpty);
    expect(loaded.ownedFloorSkinPacks, isEmpty);
  });

  test('PlacedRoom v5 JSON loads with default rotation/skin overrides', () {
    final v5Json = {
      'id': 'r1',
      'type': 0, // RoomType.workstation
      'col': 2,
      'row': 3,
    };
    final room = PlacedRoom.fromJson(v5Json);
    expect(room.rotation, 0);
    expect(room.wallSkinId, isNull);
    expect(room.floorSkinId, isNull);
    expect(room.footprintWidth, room.type.widthTiles);
    expect(room.footprintHeight, room.type.heightTiles);
  });

  test('PlacedRoom rotation 90/270 swaps footprint axes', () {
    final base = PlacedRoom(
      id: 'r1',
      type: RoomType.meetingRoom, // 3×2
      col: 1,
      row: 1,
    );
    expect(base.footprintWidth, 3);
    expect(base.footprintHeight, 2);

    final rotated = base.copyWith(rotation: 90);
    expect(rotated.footprintWidth, 2);
    expect(rotated.footprintHeight, 3);

    final rotated180 = base.copyWith(rotation: 180);
    expect(rotated180.footprintWidth, 3);
    expect(rotated180.footprintHeight, 2);
  });

  test('PlacedRoom skin overrides round-trip through JSON', () {
    final original = PlacedRoom(
      id: 'r1',
      type: RoomType.workstation,
      col: 1,
      row: 1,
      rotation: 270,
      wallSkinId: 'brick_pack',
      floorSkinId: 'carpet_pack',
    );
    final round = PlacedRoom.fromJson(original.toJson());
    expect(round.rotation, 270);
    expect(round.wallSkinId, 'brick_pack');
    expect(round.floorSkinId, 'carpet_pack');
  });

  // ─── Empty-roster guard ────────────────────────────────────────────────

  test('load re-seeds the roster if a saved state has zero agents', () async {
    // A v6 save with an empty agents map — possible after a buggy migration,
    // corrupted server sync, or manual JSON edit. The guard reseeds the
    // singleton manager/coder so chat & dispatch loops still have a team.
    final json =
        '{"schemaVersion":${GameState.currentSchemaVersion},"grymni":888,'
        '"agents":{}}';
    SharedPreferences.setMockInitialValues({'pixelcode_game_state': json});
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    // Non-agent fields are preserved (this is NOT a hard wipe).
    expect(loaded.grymni, 888);

    // Roster is reseeded — at minimum a manager must be present so the
    // selectedAgentProvider can resolve.
    expect(loaded.agents, isNotEmpty);
    final hasManager =
        loaded.agents.values.any((a) => a.roleType == 'manager');
    expect(hasManager, isTrue, reason: 'Manager must be reseeded.');
  });

  test('load preserves agents when the saved roster is non-empty', () async {
    // Negative case: the empty-roster guard must NOT clobber a valid roster.
    final json =
        '{"schemaVersion":${GameState.currentSchemaVersion},"grymni":111,'
        '"agents":{"coder#1":{"instanceId":"coder#1","roleType":"coder",'
        '"nickname":"Solo","hardware":0}}}';
    SharedPreferences.setMockInitialValues({'pixelcode_game_state': json});
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    expect(loaded.grymni, 111);
    expect(loaded.agents.keys, equals({'coder#1'}));
    expect(loaded.agents['coder#1']!.nickname, 'Solo');
  });

  test('PlacedCorridor round-trips through JSON', () {
    final original = PlacedCorridor(
      id: 'c1',
      tiles: const [
        (col: 1, row: 1),
        (col: 2, row: 1),
        (col: 3, row: 1),
      ],
      wide: true,
      skinId: 'corridor_neon',
    );
    final round = PlacedCorridor.fromJson(original.toJson());
    expect(round.id, 'c1');
    expect(round.tiles, hasLength(3));
    expect(round.tiles[1].col, 2);
    expect(round.wide, isTrue);
    expect(round.skinId, 'corridor_neon');
  });
}
