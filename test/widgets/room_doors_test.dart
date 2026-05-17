import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/room_doors.dart';

PlacedRoom _room(String id, int col, int row,
        {RoomType type = RoomType.workstation, int rotation = 0}) =>
    PlacedRoom(
      id: id,
      type: type,
      col: col,
      row: row,
      rotation: rotation,
    );

PlacedCorridor _corridor(String id, List<({int col, int row})> tiles,
        {bool wide = false}) =>
    PlacedCorridor(id: id, tiles: tiles, wide: wide);

void main() {
  group('computeRoomDoors', () {
    test('isolated room has no doors', () {
      final room = _room('A', 5, 5);
      final doors = computeRoomDoors(room, [room], []);
      expect(doors.isEmpty, isTrue);
    });

    test('room flush to the right of another room → left edge has doors', () {
      // A: 2×2 at (5,0), B: 2×2 at (7,0); A.right == B.left == 7
      final a = _room('A', 5, 0);
      final b = _room('B', 7, 0);
      final doorsB = computeRoomDoors(b, [a, b], []);
      // B's left edge tiles are rows [0, 1]; both share with A → both doors
      expect(doorsB.left, {0, 1});
      expect(doorsB.top, isEmpty);
      expect(doorsB.right, isEmpty);
      expect(doorsB.bottom, isEmpty);

      // Reciprocal: A's right edge tiles open at rows [0, 1]
      final doorsA = computeRoomDoors(a, [a, b], []);
      expect(doorsA.right, {0, 1});
    });

    test('room flush below another → top edge has doors only along overlap', () {
      // A: 2×2 at (5,0), B: 2×2 at (5,2); A.bottom == B.top == 2
      final a = _room('A', 5, 0);
      final b = _room('B', 5, 2);
      final doorsB = computeRoomDoors(b, [a, b], []);
      // B's top cols [5, 6] share with A → both doors
      expect(doorsB.top, {5, 6});
      expect(doorsB.left, isEmpty);
    });

    test('partial overlap on shared edge → only overlapping cols are doors', () {
      // A: 2×2 at (5,0) cols [5,6]; B: 2×2 at (6,2) cols [6,7]
      // Shared edge along y=2: col 6 only (col 7 in B has nothing above, col 5 in A has nothing below)
      final a = _room('A', 5, 0);
      final b = _room('B', 6, 2);
      final doorsB = computeRoomDoors(b, [a, b], []);
      expect(doorsB.top, {6});
    });

    test('rotated room: doors computed from footprint, not raw type dims', () {
      // meetingRoom: 3×2 unrotated; rotated 90° → 2×3
      // A rotated at (5,0) → cols [5,6], rows [0..2]
      // B workstation 2×2 at (5,3) → top row 3 shared with A.bottom 3
      final a = _room('A', 5, 0, type: RoomType.meetingRoom, rotation: 90);
      final b = _room('B', 5, 3);
      final doorsB = computeRoomDoors(b, [a, b], []);
      // B's top cols [5,6] both share with rotated A (cols 5..6)
      expect(doorsB.top, {5, 6});
    });

    test('room touches a corridor tile → that edge tile is a door', () {
      // Workstation at (5,0); corridor tile at (7,0) → A.right meets corridor at row=0
      final a = _room('A', 5, 0);
      final cor = _corridor('cor', [(col: 7, row: 0)]);
      final doors = computeRoomDoors(a, [a], [cor]);
      expect(doors.right, {0});
    });

    test('wide corridor covers two cols → both adjacent edge cells open', () {
      // Workstation at (5,2); wide corridor tiles at (5,1) and (6,1) (auto +1 col)
      // → A.top tiles at cols 5 and 6 both share with corridor row=1
      final a = _room('A', 5, 2);
      final cor = _corridor('cor', [(col: 5, row: 1)], wide: true);
      final doors = computeRoomDoors(a, [a], [cor]);
      expect(doors.top, {5, 6});
    });

    test('room not adjacent to anything reachable → no doors', () {
      final a = _room('A', 5, 5);
      final b = _room('B', 10, 10);
      final doors = computeRoomDoors(a, [a, b], []);
      expect(doors.isEmpty, isTrue);
    });

    test('player-closed door is filtered out of the result', () {
      // A: 2×2 at (5,0); B: 2×2 at (7,0). Auto-doors on A.right at rows {0,1}.
      // Close one of A's right-edge doors at the (col=6, row=0) interior tile.
      final a = PlacedRoom(
        id: 'A',
        type: RoomType.workstation,
        col: 5,
        row: 0,
        closedDoors: const {(col: 6, row: 0)},
      );
      final b = _room('B', 7, 0);
      final doors = computeRoomDoors(a, [a, b], []);
      // Only row=1 remains open; row=0 was sealed.
      expect(doors.right, {1});
    });

    test('closing every door removes the entire edge', () {
      final a = PlacedRoom(
        id: 'A',
        type: RoomType.workstation,
        col: 5,
        row: 0,
        closedDoors: const {(col: 6, row: 0), (col: 6, row: 1)},
      );
      final b = _room('B', 7, 0);
      final doors = computeRoomDoors(a, [a, b], []);
      expect(doors.right, isEmpty);
    });
  });
}
