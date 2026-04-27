import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/office_game_state.dart';

// Helpers — build a PlacedCorridor with minimal boilerplate.
PlacedCorridor _narrow(String id, List<({int col, int row})> tiles) =>
    PlacedCorridor(id: id, tiles: tiles);

PlacedCorridor _wide(String id, List<({int col, int row})> tiles) =>
    PlacedCorridor(id: id, tiles: tiles, wide: true);

// Garage grid: 7 cols (0–6) × 5 rows (0–4).
// Walls: row 0, row 4, col 0, col 6.
// Inner floor: rows 1–3, cols 1–5.

void main() {
  group('_buildTileMap — corridor tiles', () {
    test('narrow corridor on border wall becomes TileType.floor', () {
      // col=0 is the left-edge wall; a corridor through it must become walkable.
      final state = OfficeGameState(
        placedCorridors: [_narrow('c1', [(col: 0, row: 2)])],
      );
      expect(state.tileMap[2][0], TileType.floor);
    });

    test('wide corridor marks col AND col+1 as TileType.floor', () {
      // col=5 is inner floor; col+1=6 is the right-edge wall.
      // After a wide corridor both must be floor.
      final state = OfficeGameState(
        placedCorridors: [_wide('c1', [(col: 5, row: 2)])],
      );
      expect(state.tileMap[2][5], TileType.floor);
      expect(state.tileMap[2][6], TileType.floor); // right-border wall overridden
    });

    test('zero corridors: border tiles are walls, inner tiles are floors', () {
      final state = OfficeGameState();
      // Corners / borders stay walls.
      expect(state.tileMap[0][0], TileType.wall);
      expect(state.tileMap[4][6], TileType.wall);
      expect(state.tileMap[0][3], TileType.wall);
      // Centre inner tile is floor.
      expect(state.tileMap[2][3], TileType.floor);
    });
  });

  group('_buildBlockedTiles — corridor priority over room internals', () {
    test('corridor tile overlapping room-internal-block is removed from blockedTiles', () {
      // serverRoom at (1,1) yields internal blocks: (1,1),(2,1),(1,2),(2,2).
      // A corridor at (1,1) must strip that tile from blockedTiles so agents can pass.
      final state = OfficeGameState(
        placedRooms: [
          PlacedRoom(id: 'r1', type: RoomType.serverRoom, col: 1, row: 1),
        ],
        placedCorridors: [_narrow('c1', [(col: 1, row: 1)])],
      );
      expect(state.blockedTiles.contains('1,1'), isFalse);
    });

    test('wide corridor removes both col and col+1 from blockedTiles', () {
      // serverRoom at (2,1) blocks (2,1),(3,1),(2,2),(3,2).
      // Wide corridor at col=2,row=1 must clear the entire first-row pair.
      final state = OfficeGameState(
        placedRooms: [
          PlacedRoom(id: 'r1', type: RoomType.serverRoom, col: 2, row: 1),
        ],
        placedCorridors: [_wide('c1', [(col: 2, row: 1)])],
      );
      expect(state.blockedTiles.contains('2,1'), isFalse);
      expect(state.blockedTiles.contains('3,1'), isFalse);
    });
  });

  group('_buildTileMap / _buildBlockedTiles — edge cases', () {
    test('corridor tiles outside grid bounds are ignored without crash or OOB', () {
      // Negative coords and coords far beyond grid dims must be silently skipped.
      expect(
        () => OfficeGameState(
          placedCorridors: [
            _narrow('c1', [(col: -1, row: -1), (col: 999, row: 999)]),
            _wide('c2', [(col: -5, row: 0), (col: 100, row: 50)]),
          ],
        ),
        returnsNormally,
      );
    });
  });
}
