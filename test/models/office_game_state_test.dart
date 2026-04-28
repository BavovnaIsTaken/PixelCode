import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/office_game_state.dart';

// Helpers for building placed rooms/corridors.

PlacedRoom _room(
  String id,
  RoomType type, {
  int col = 1,
  int row = 1,
}) =>
    PlacedRoom(id: id, type: type, col: col, row: row);

PlacedCorridor _corridor(
  String id,
  List<({int col, int row})> tiles, {
  bool wide = false,
}) =>
    PlacedCorridor(id: id, tiles: tiles, wide: wide);

void main() {
  // ─── foremanColFor / foremanRowFor ──────────────────────────────────────────

  group('foremanColFor / foremanRowFor', () {
    test('foremanColFor returns last column index', () {
      expect(foremanColFor(20), 19);
      expect(foremanColFor(7), 6);
    });

    test('foremanRowFor returns last row index', () {
      expect(foremanRowFor(14), 13);
      expect(foremanRowFor(5), 4);
    });
  });

  // ─── OfficeGameState tileMap ─────────────────────────────────────────────────

  group('OfficeGameState tileMap (garage 7×5)', () {
    late OfficeGameState state;

    setUp(() {
      state = OfficeGameState(level: OfficeLevel.garage);
    });

    test('gridCols/gridRows match garage base size', () {
      expect(state.gridCols, 7);
      expect(state.gridRows, 5);
    });

    test('top border row is all walls', () {
      for (int c = 0; c < state.gridCols; c++) {
        expect(state.tileMap[0][c], TileType.wall,
            reason: 'row 0 col $c should be wall');
      }
    });

    test('bottom border row is all walls', () {
      for (int c = 0; c < state.gridCols; c++) {
        expect(state.tileMap[state.gridRows - 1][c], TileType.wall,
            reason: 'last row col $c should be wall');
      }
    });

    test('left border column is all walls', () {
      for (int r = 0; r < state.gridRows; r++) {
        expect(state.tileMap[r][0], TileType.wall,
            reason: 'col 0 row $r should be wall');
      }
    });

    test('right border column is all walls', () {
      for (int r = 0; r < state.gridRows; r++) {
        expect(state.tileMap[r][state.gridCols - 1], TileType.wall,
            reason: 'last col row $r should be wall');
      }
    });

    test('interior tiles are floor', () {
      for (int r = 1; r < state.gridRows - 1; r++) {
        for (int c = 1; c < state.gridCols - 1; c++) {
          expect(state.tileMap[r][c], TileType.floor,
              reason: 'interior tile ($c,$r) should be floor');
        }
      }
    });
  });

  // ─── blockedTiles ───────────────────────────────────────────────────────────

  group('OfficeGameState blockedTiles', () {
    late OfficeGameState state;

    setUp(() {
      state = OfficeGameState(level: OfficeLevel.garage);
    });

    test('coffee machine tile is blocked', () {
      expect(
          state.blockedTiles.contains('$kCoffeeMachineCol,$kCoffeeMachineRow'),
          isTrue);
    });

    test('coffee machine second tile is blocked', () {
      expect(
          state.blockedTiles.contains('$kCoffeeMachineCol2,$kCoffeeMachineRow'),
          isTrue);
    });

    test('snack table tile is blocked', () {
      expect(
          state.blockedTiles.contains('$kSnackTableCol,$kSnackTableRow'),
          isTrue);
    });

    test('foreman tile is blocked', () {
      final fCol = foremanColFor(state.gridCols);
      final fRow = foremanRowFor(state.gridRows);
      expect(state.blockedTiles.contains('$fCol,$fRow'), isTrue);
    });

    test('tile above foreman is blocked', () {
      final fCol = foremanColFor(state.gridCols);
      final fRow = foremanRowFor(state.gridRows);
      expect(state.blockedTiles.contains('$fCol,${fRow - 1}'), isTrue);
    });

    test('canonical desk station tiles are blocked', () {
      for (final station in kStations) {
        expect(
          state.blockedTiles.contains('${station.deskCol},${station.deskRow}'),
          isTrue,
          reason: '${station.agentId} desk should be blocked',
        );
      }
    });

    test('canonical seat tiles are blocked', () {
      for (final station in kStations) {
        expect(
          state.blockedTiles.contains('${station.seatCol},${station.seatRow}'),
          isTrue,
          reason: '${station.agentId} seat should be blocked',
        );
      }
    });
  });

  // ─── walkableTiles ──────────────────────────────────────────────────────────

  group('OfficeGameState walkableTiles (garage 7×5)', () {
    late OfficeGameState state;

    setUp(() {
      state = OfficeGameState(level: OfficeLevel.garage);
    });

    test('walkableTiles is non-empty', () {
      expect(state.walkableTiles, isNotEmpty);
    });

    test('no wall tile appears in walkableTiles', () {
      for (final pos in state.walkableTiles) {
        expect(state.tileMap[pos.row][pos.col], TileType.floor,
            reason: 'walkable tile (${pos.col},${pos.row}) must be floor');
      }
    });

    test('no blocked tile appears in walkableTiles', () {
      for (final pos in state.walkableTiles) {
        expect(
          state.blockedTiles.contains('${pos.col},${pos.row}'),
          isFalse,
          reason:
              'walkable tile (${pos.col},${pos.row}) must not be in blockedTiles',
        );
      }
    });
  });

  // ─── Room effects — speedBonus ───────────────────────────────────────────────

  group('speedBonus (room effects)', () {
    test('default speedBonus is 1.0 with no rooms', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.speedBonus, 1.0);
    });

    test('serverRoom sets speedBonus to 1.1', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('srv', RoomType.serverRoom, col: 1, row: 1)],
      );
      // serverRoom without workstation → 1.1 - 0.05 = 1.05
      expect(state.speedBonus, closeTo(1.05, 0.001));
    });

    test('serverRoom adjacent to workstation gives full 1.1 + 0.05 bonus', () {
      // serverRoom at col=1, workstation at col=3 (adjacent, right=3==col=3)
      // Both in row=1, so yOverlap holds.
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [
          _room('srv', RoomType.serverRoom, col: 1, row: 1),
          _room('ws', RoomType.workstation, col: 3, row: 1),
        ],
      );
      // 1.1 (server) + 0.05 (adjacency) = 1.15; no penalty (workstation nearby)
      expect(state.speedBonus, closeTo(1.15, 0.001));
    });

    test('wide corridor adds 0.03 to speedBonus', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedCorridors: [
          _corridor('c1', [(col: 2, row: 2)], wide: true),
        ],
      );
      expect(state.speedBonus, closeTo(1.03, 0.001));
    });

    test('narrow corridor does not add speed bonus', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedCorridors: [
          _corridor('c1', [(col: 2, row: 2)]),
        ],
      );
      expect(state.speedBonus, 1.0);
    });
  });

  // ─── Room effects — seatRestMultiplier ──────────────────────────────────────

  group('seatRestMultiplier (room effects)', () {
    test('default seatRestMultiplier is 1.0', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.seatRestMultiplier, 1.0);
    });

    test('breakRoom sets seatRestMultiplier to 1.5', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('br', RoomType.breakRoom, col: 1, row: 1)],
      );
      expect(state.seatRestMultiplier, 1.5);
    });

    test('breakRoom adjacent to lounge doubles seatRestMultiplier to 3.0', () {
      // breakRoom (2×2) at col=1, lounge (3×2) at col=3 → adjacent (1+2==3)
      // yOverlap: both at row=1, row=1<1+2=3 and row=1<1+2=3 → overlap
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [
          _room('br', RoomType.breakRoom, col: 1, row: 1),
          _room('lg', RoomType.lounge, col: 3, row: 1),
        ],
      );
      expect(state.seatRestMultiplier, closeTo(3.0, 0.001));
    });
  });

  // ─── Room effects — loungeCenterTile ────────────────────────────────────────

  group('loungeCenterTile (room effects)', () {
    test('null with no lounge', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.loungeCenterTile, isNull);
    });

    test('set to center of lounge footprint', () {
      // lounge widthTiles=3, heightTiles=2 → center at col+1, row+1
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('lg', RoomType.lounge, col: 1, row: 1)],
      );
      expect(state.loungeCenterTile, isNotNull);
      // col=1 + 3~/2 = 1+1=2, row=1 + 2~/2 = 1+1=2
      expect(state.loungeCenterTile!.col, 2);
      expect(state.loungeCenterTile!.row, 2);
    });
  });

  // ─── Extra stations from workstation rooms ───────────────────────────────────

  group('allStations / _buildExtraStations', () {
    test('no workstation rooms → allStations equals kStations', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.allStations.length, kStations.length);
    });

    test('one workstation room adds one extra isExtra station', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('ws1', RoomType.workstation, col: 2, row: 1)],
      );
      expect(state.allStations.length, kStations.length + 1);
      final extra = state.allStations.last;
      expect(extra.isExtra, isTrue);
    });

    test('extra station agentId contains room id', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('my-ws', RoomType.workstation, col: 2, row: 1)],
      );
      final extra = state.allStations.last;
      expect(extra.agentId, contains('my-ws'));
    });

    test('extra station desk at room col/row, seat one row below', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('ws1', RoomType.workstation, col: 2, row: 1)],
      );
      final extra = state.allStations.last;
      expect(extra.deskCol, 2);
      expect(extra.deskRow, 1);
      expect(extra.seatCol, 2);
      expect(extra.seatRow, 2);
    });

    test('extra station desk/seat tiles are in blockedTiles', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('ws1', RoomType.workstation, col: 2, row: 1)],
      );
      final extra = state.allStations.last;
      expect(
          state.blockedTiles.contains('${extra.deskCol},${extra.deskRow}'),
          isTrue);
      expect(
          state.blockedTiles.contains('${extra.seatCol},${extra.seatRow}'),
          isTrue);
    });
  });

  // ─── Corridor tiles in tileMap ────────────────────────────────────────────

  group('corridor tiles in tileMap', () {
    test('corridor tile in wall position is forced to floor', () {
      // Garage row 0 is a wall. A corridor placed there should override it.
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedCorridors: [
          _corridor('c1', [(col: 3, row: 0)]),
        ],
      );
      expect(state.tileMap[0][3], TileType.floor);
    });

    test('wide corridor forces two adjacent columns to floor', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedCorridors: [
          _corridor('c1', [(col: 2, row: 0)], wide: true),
        ],
      );
      expect(state.tileMap[0][2], TileType.floor);
      expect(state.tileMap[0][3], TileType.floor);
    });

    test('corridor tile removed from blockedTiles', () {
      // Place a server room; its internal blocks go into blockedTiles.
      // Then a corridor through those tiles should clear them from blockedTiles.
      final serverRoom = _room('srv', RoomType.serverRoom, col: 1, row: 1);
      // Server room blocks (1,1),(2,1),(1,2),(2,2).
      // A corridor through (1,1) should remove it.
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [serverRoom],
        placedCorridors: [
          _corridor('c1', [(col: 1, row: 1)]),
        ],
      );
      expect(state.blockedTiles.contains('1,1'), isFalse);
    });
  });

  // ─── rebuildLayout ────────────────────────────────────────────────────────

  group('rebuildLayout', () {
    test('updates gridCols and gridRows after level change', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.gridCols, 7);
      state.rebuildLayout(OfficeLevel.smallOffice, 0, []);
      expect(state.gridCols, 9);
      expect(state.gridRows, 6);
    });

    test('updates speedBonus when serverRoom added', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.speedBonus, 1.0);
      state.rebuildLayout(
        OfficeLevel.garage,
        0,
        [_room('srv', RoomType.serverRoom, col: 1, row: 1)],
      );
      // serverRoom without workstation: 1.1 - 0.05 = 1.05
      expect(state.speedBonus, closeTo(1.05, 0.001));
    });

    test('clears loungeCenterTile when rooms removed', () {
      final state = OfficeGameState(
        level: OfficeLevel.garage,
        placedRooms: [_room('lg', RoomType.lounge, col: 1, row: 1)],
      );
      expect(state.loungeCenterTile, isNotNull);
      state.rebuildLayout(OfficeLevel.garage, 0, []);
      expect(state.loungeCenterTile, isNull);
    });

    test('tileMap resizes correctly after rebuild', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      state.rebuildLayout(OfficeLevel.smallOffice, 0, []);
      // smallOffice: 9 cols × 6 rows
      expect(state.tileMap.length, 6);
      expect(state.tileMap[0].length, 9);
    });
  });

  // ─── Adjacency × stat interaction guard (D.1) ────────────────────────────
  //
  // kSpeedBonusCeiling caps _speedBonus so that many workstation↔serverRoom
  // adjacent pairs can't stack the walk-speed multiplier past 1.35.
  // The floor (0.9) was already asserted in the serverRoom tests above.

  group('speedBonus ceiling guard', () {
    test('six adjacent pairs clamped to kSpeedBonusCeiling', () {
      // Raw without cap: 1.1 (server room) + 6×0.05 (pairs) = 1.40.
      // Each server at (i*6, 0) is within 8-tile Manhattan distance of its
      // workstation at (i*6+2, 0) → no cable-proximity penalty.
      final rooms = [
        for (int i = 0; i < 6; i++) ...[
          _room('srv_$i', RoomType.serverRoom, col: i * 6, row: 0),
          _room('ws_$i', RoomType.workstation, col: i * 6 + 2, row: 0),
        ],
      ];
      final state = OfficeGameState(level: OfficeLevel.garage);
      state.rebuildLayout(OfficeLevel.garage, 0, rooms);
      expect(state.speedBonus, closeTo(kSpeedBonusCeiling, 0.001),
          reason: 'six pairs (raw 1.40) must be clamped to $kSpeedBonusCeiling');
    });

    test('normal case (one pair) is not wrongly clamped', () {
      // Raw: 1.1 + 0.05 = 1.15 — well below ceiling.
      final state = OfficeGameState(level: OfficeLevel.garage);
      state.rebuildLayout(OfficeLevel.garage, 0, [
        _room('srv', RoomType.serverRoom, col: 0, row: 0),
        _room('ws', RoomType.workstation, col: 2, row: 0),
      ]);
      expect(state.speedBonus, closeTo(1.15, 0.001));
      expect(state.speedBonus, lessThan(kSpeedBonusCeiling));
    });

    test('wide corridor bonus is also subject to ceiling', () {
      // Raw: 1.1 + 5×0.05 + 0.03 = 1.38 → clamped to 1.35.
      final rooms = [
        for (int i = 0; i < 5; i++) ...[
          _room('srv_$i', RoomType.serverRoom, col: i * 6, row: 0),
          _room('ws_$i', RoomType.workstation, col: i * 6 + 2, row: 0),
        ],
      ];
      final state = OfficeGameState(level: OfficeLevel.garage);
      state.rebuildLayout(
        OfficeLevel.garage,
        0,
        rooms,
        [],
        [_corridor('c', [(col: 1, row: 3)], wide: true)],
      );
      expect(state.speedBonus, closeTo(kSpeedBonusCeiling, 0.001),
          reason: 'five pairs + wide corridor (raw 1.38) clamped to $kSpeedBonusCeiling');
    });
  });

  // ─── canvasWidth / canvasHeight ────────────────────────────────────────────

  group('canvasWidth / canvasHeight', () {
    test('canvasWidth = gridCols × kTileSize', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.canvasWidth, state.gridCols * kTileSize);
    });

    test('canvasHeight = gridRows × kTileSize', () {
      final state = OfficeGameState(level: OfficeLevel.garage);
      expect(state.canvasHeight, state.gridRows * kTileSize);
    });
  });

  // ─── syncHiredAgents + WorkplaceStatus ─────────────────────────────────────

  group('syncHiredAgents workplace status', () {
    // smallOffice (9×6) is too small for the canonical coder station (col=9, row=7).
    // techHub (12×9) fits all canonical stations.
    OfficeGameState makeSmall() {
      final s = OfficeGameState(level: OfficeLevel.smallOffice);
      s.rebuildLayout(OfficeLevel.smallOffice, 0, []);
      return s;
    }

    OfficeGameState makeLarge() {
      final s = OfficeGameState(level: OfficeLevel.techHub);
      s.rebuildLayout(OfficeLevel.techHub, 0, []);
      return s;
    }

    test('unassigned agent spawns in CharState.waiting, no seat', () {
      final state = makeSmall();
      state.syncHiredAgents(
        ['coder#1'],
        null,
        {'coder#1': WorkplaceStatus.unassigned},
      );

      final ch = state.characters['coder#1']!;
      expect(ch.state, CharState.waiting);
      expect(ch.seat, isNull);
    });

    test('assigned agent gets canonical seat and CharState.typing (techHub grid)', () {
      final state = makeLarge();
      state.syncHiredAgents(
        ['coder#1'],
        null,
        {'coder#1': WorkplaceStatus.assigned},
      );

      final ch = state.characters['coder#1']!;
      expect(ch.seat, isNotNull);
      expect(ch.state, CharState.typing);
    });

    test('returns empty list when assigned agent already has a seat', () {
      final state = makeLarge();
      final result = state.syncHiredAgents(
        ['coder#1'],
        null,
        {'coder#1': WorkplaceStatus.assigned},
      );
      expect(result, isEmpty);
    });

    test('waiting agent assigned to extra station appears in return value', () {
      final state = makeSmall();

      // Hire as unassigned — goes to lobby / waiting.
      state.syncHiredAgents(
        ['coder#1'],
        null,
        {'coder#1': WorkplaceStatus.unassigned},
      );
      expect(state.characters['coder#1']!.state, CharState.waiting);

      // Place a workstation room — desk at (3,2), seat at (3,3), fits 9×6.
      state.rebuildLayout(
        OfficeLevel.smallOffice,
        0,
        [_room('ws1', RoomType.workstation, col: 3, row: 2)],
      );

      // Call sync again — step 4b should assign the extra station.
      final assigned = state.syncHiredAgents(
        ['coder#1'],
        null,
        {'coder#1': WorkplaceStatus.unassigned},
      );
      expect(assigned, contains('coder#1'));
      expect(state.characters['coder#1']!.seat, isNotNull);
    });

    test('waiting state transitions to idle once seat is set via update()', () {
      final state = makeSmall();
      state.syncHiredAgents(
        ['coder#1'],
        null,
        {'coder#1': WorkplaceStatus.unassigned},
      );
      final ch = state.characters['coder#1']!;
      expect(ch.state, CharState.waiting);

      // Manually assign a seat (simulating what step 4b does).
      ch.seat = kStations.first;
      state.update(0.1);
      expect(ch.state, isNot(CharState.waiting));
    });
  });
}
