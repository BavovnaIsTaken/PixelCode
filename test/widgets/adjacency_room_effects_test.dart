import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/office_game_state.dart';

/// Builds a minimal [OfficeGameState] with [rooms] already placed.
OfficeGameState _stateWith(List<PlacedRoom> rooms) => OfficeGameState(
      level: OfficeLevel.smallOffice,
      placedRooms: rooms,
    );

PlacedRoom _room(
  RoomType type, {
  int col = 0,
  int row = 0,
  int rotation = 0,
  String? id,
}) =>
    PlacedRoom(
      id: id ?? '${type.name}_${col}_$row',
      type: type,
      col: col,
      row: row,
      rotation: rotation,
    );

void main() {
  group('OfficeGameState room effects — global', () {
    test('no rooms → speed 1.0, seatRest 1.0', () {
      final s = _stateWith([]);
      expect(s.speedBonus, 1.0);
      expect(s.seatRestMultiplier, 1.0);
    });

    test('serverRoom alone → speed 1.1 (no nearby workstation penalty)', () {
      // No workstations exist → penalty applies: 1.1 − 0.05 = 1.05
      final s = _stateWith([_room(RoomType.serverRoom, col: 2, row: 2)]);
      expect(s.speedBonus, closeTo(1.05, 0.001));
    });

    test('breakRoom alone → seatRest 1.5', () {
      final s = _stateWith([_room(RoomType.breakRoom, col: 1, row: 1)]);
      expect(s.seatRestMultiplier, closeTo(1.5, 0.001));
    });
  });

  group('OfficeGameState room effects — adjacency bonuses', () {
    test('workstation adjacent to serverRoom → speed 1.15 (1.1 + 0.05)', () {
      // workstation 2×2 at (0,1), serverRoom 3×2 at (2,1) → adjacent at x=2
      final rooms = [
        _room(RoomType.workstation, col: 0, row: 1),
        _room(RoomType.serverRoom, col: 2, row: 1),
      ];
      final s = _stateWith(rooms);
      // serverRoom has a nearby workstation → no penalty; adjacent → +0.05
      expect(s.speedBonus, closeTo(1.15, 0.001));
    });

    test('serverRoom NOT adjacent but within 8 tiles → no penalty, no adj bonus', () {
      // workstation at (0,1), serverRoom at (4,1) → gap of 2 tiles, dist ~4
      final rooms = [
        _room(RoomType.workstation, col: 0, row: 1),
        _room(RoomType.serverRoom, col: 4, row: 1),
      ];
      final s = _stateWith(rooms);
      // No adjacency pair → no +5%; workstation nearby → no penalty; global = 1.1
      expect(s.speedBonus, closeTo(1.1, 0.001));
    });

    test('serverRoom far from workstation → penalty: 1.1 − 0.05 = 1.05', () {
      // workstation at (20,1) far from serverRoom at (1,1)
      final rooms = [
        _room(RoomType.workstation, col: 20, row: 1),
        _room(RoomType.serverRoom, col: 1, row: 1),
      ];
      final s = _stateWith(rooms);
      expect(s.speedBonus, closeTo(1.05, 0.001));
    });

    test('breakRoom adjacent to lounge → seatRest doubles to 3.0', () {
      // breakRoom is 2×2 → right=2; lounge at col=2 touches it
      final rooms = [
        _room(RoomType.breakRoom, col: 0, row: 1),
        _room(RoomType.lounge, col: 2, row: 1),
      ];
      final s = _stateWith(rooms);
      // 1.5 × 2.0 = 3.0
      expect(s.seatRestMultiplier, closeTo(3.0, 0.001));
    });

    test('breakRoom NOT adjacent to lounge → seatRest stays 1.5', () {
      final rooms = [
        _room(RoomType.breakRoom, col: 0, row: 1),
        _room(RoomType.lounge, col: 10, row: 1),
      ];
      final s = _stateWith(rooms);
      expect(s.seatRestMultiplier, closeTo(1.5, 0.001));
    });
  });
}
