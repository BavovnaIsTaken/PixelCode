import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/snap_logic.dart';

// workstation: 2×2 tiles — convenient minimal size for all snap tests
PlacedRoom _room(int col, int row, {int rotation = 0, RoomType type = RoomType.workstation}) =>
    PlacedRoom(
      id: 'r_${col}_${row}_${type.index}_$rotation',
      type: type,
      col: col,
      row: row,
      rotation: rotation,
    );

PlacedCorridor _corridor(List<({int col, int row})> tiles, {bool wide = false}) =>
    PlacedCorridor(id: 'c_${tiles.first.col}_${tiles.first.row}', tiles: tiles, wide: wide);

void main() {
  // ── snapGhostCol ─────────────────────────────────────────────────────────

  group('snapGhostCol', () {
    test('snap right: ghost.right within radius of room.left → snaps flush left of room', () {
      // ghost 2×2 at col=6 → ghostRight=8; room at col=9 → gap=1 ≤ 2
      // y-ranges overlap: both at row=0..2
      final result = snapGhostCol(6, 0, 2, 2, [_room(9, 0)]);
      // snapCol = roomLeft(9) − ghostCols(2) = 7
      expect(result, 7);
    });

    test('snap left: ghost.left within radius of room.right → snaps flush right of room', () {
      // ghost 2×2 at col=9; room at col=5 → roomRight=7; gap=|7−9|=2 ≤ 2
      // y-ranges overlap: both at row=0..2
      final result = snapGhostCol(9, 0, 2, 2, [_room(5, 0)]);
      // snapCol = roomRight(7)
      expect(result, 7);
    });

    test('no snap: gap > kSnapRadius=2 → returns original col', () {
      // ghost at col=0 → ghostRight=2; room at col=6 → gap=4 > 2
      final result = snapGhostCol(0, 0, 2, 2, [_room(6, 0)]);
      expect(result, 0);
    });

    test('no snap: gap ≤ kSnapRadius but no y-overlap → returns original col', () {
      // ghost at col=6 row=0 (y: 0..2); room at col=9 row=5 (y: 5..7)
      // gapRight = 9−8 = 1 ≤ 2  BUT  yOverlap = 0
      final result = snapGhostCol(6, 0, 2, 2, [_room(9, 5)]);
      expect(result, 6);
    });
  });

  // ── snapGhostRow ─────────────────────────────────────────────────────────

  group('snapGhostRow', () {
    test('snap below: ghost.bottom within radius of room.top → snaps flush above room', () {
      // ghost 2×2 at row=5 → ghostBottom=7; room at row=8 → gap=1 ≤ 2
      // x-ranges overlap: both at col=0..2
      final result = snapGhostRow(0, 5, 2, 2, [_room(0, 8)]);
      // snapRow = roomTop(8) − ghostRows(2) = 6
      expect(result, 6);
    });

    test('snap above: ghost.top within radius of room.bottom → snaps flush below room', () {
      // ghost 2×2 at row=9; room at row=5 → roomBottom=7; gap=|7−9|=2 ≤ 2
      // x-ranges overlap: both at col=0..2
      final result = snapGhostRow(0, 9, 2, 2, [_room(0, 5)]);
      // snapRow = roomBottom(7)
      expect(result, 7);
    });

    test('no snap: gap ≤ kSnapRadius but no x-overlap → returns original row', () {
      // ghost at col=0 row=5 (x: 0..2); room at col=5 row=8 (x: 5..7)
      // gapBottom = 8−7 = 1 ≤ 2  BUT  xOverlap = 0
      final result = snapGhostRow(0, 5, 2, 2, [_room(5, 8)]);
      expect(result, 5);
    });
  });

  // ── Rotation-aware snap (Stage 3a fix) ──────────────────────────────────
  // meetingRoom is 3×2 unrotated → 2×3 when rotated 90°. Previously snap used
  // raw type.widthTiles, ignoring rotation; rotated targets failed to snap.

  group('snapGhostCol: rotation-aware target', () {
    test('snap right against rotated meetingRoom: uses footprintWidth (2 cols, not 3)', () {
      // meetingRoom rotated 90° at col=9 row=0 → footprint 2×3 (cols 9..11, rows 0..3)
      // ghost 2×2 at col=6 → ghostRight=8; gap to rotated room.left(9) = 1 ≤ 2
      // y-overlap exists (rooms span 0..3, ghost 0..2)
      final result = snapGhostCol(
          6, 0, 2, 2, [_room(9, 0, type: RoomType.meetingRoom, rotation: 90)]);
      expect(result, 7);
    });

    test('snap left against rotated meetingRoom: uses footprintWidth for right edge', () {
      // meetingRoom rotated 90° at col=5 row=0 → footprint 2×3 → roomRight = 5+2 = 7
      // ghost 2×2 at col=9 → gap = |7−9| = 2 ≤ 2
      final result = snapGhostCol(
          9, 0, 2, 2, [_room(5, 0, type: RoomType.meetingRoom, rotation: 90)]);
      // snapCol = roomRight(7)
      expect(result, 7);
    });
  });

  // ── Corridor snap (Stage 3a) ────────────────────────────────────────────

  group('corridor snap', () {
    test('ghost snaps flush right of a corridor tile when within radius', () {
      // Corridor at (5, 0); ghost 2×2 at col=2 → ghostRight=4; gap = 5−4 = 1 ≤ 2
      // y-overlap: corridor row=0 ∈ ghost rows [0, 2)
      final result = snapGhostCol(
        2, 0, 2, 2, [],
        placedCorridors: [_corridor([(col: 5, row: 0)])],
      );
      // snapCol = tile.col(5) − ghostCols(2) = 3
      expect(result, 3);
    });

    test('ghost snaps flush below a corridor tile', () {
      // Corridor at (0, 5); ghost 2×2 at row=2 → ghostBottom=4; gap = 5−4 = 1 ≤ 2
      // x-overlap: corridor col=0 ∈ ghost cols [0, 2)
      final result = snapGhostRow(
        0, 2, 2, 2, [],
        placedCorridors: [_corridor([(col: 0, row: 5)])],
      );
      // snapRow = tile.row(5) − ghostRows(2) = 3
      expect(result, 3);
    });

    test('room snap wins over corridor snap at equal distance', () {
      // Both a room (at col=9, equal row) and a corridor tile (at col=9, same row)
      // would trigger snap. Room must win → ghost lands flush against room, not
      // gets the corridor-penalty inflated distance.
      final result = snapGhostCol(
        6, 0, 2, 2,
        [_room(9, 0)],
        placedCorridors: [_corridor([(col: 9, row: 0)])],
      );
      expect(result, 7);
    });

    test('no snap when corridor tile lies outside ghost y-overlap', () {
      // Corridor at (5, 5); ghost rows [0, 2) — no y-overlap
      final result = snapGhostCol(
        2, 0, 2, 2, [],
        placedCorridors: [_corridor([(col: 5, row: 5)])],
      );
      expect(result, 2);
    });
  });
}
