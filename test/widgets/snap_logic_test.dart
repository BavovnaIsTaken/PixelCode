import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/snap_logic.dart';

// workstation: 2×2 tiles — convenient minimal size for all snap tests
PlacedRoom _room(int col, int row) => PlacedRoom(
      id: 'r_${col}_$row',
      type: RoomType.workstation,
      col: col,
      row: row,
    );

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
}
