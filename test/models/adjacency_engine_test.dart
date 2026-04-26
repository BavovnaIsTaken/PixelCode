import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';

PlacedRoom _room(
  RoomType type, {
  int col = 0,
  int row = 0,
  int rotation = 0,
}) =>
    PlacedRoom(
      id: '${type.name}_${col}_$row',
      type: type,
      col: col,
      row: row,
      rotation: rotation,
    );

void main() {
  // ─── areRoomsAdjacent ────────────────────────────────────────────────────

  group('areRoomsAdjacent', () {
    test('horizontal neighbours share a wall', () {
      // workstation 2×2 at (0,0), serverRoom 3×2 at (2,0) → touch at x=2
      final ws = _room(RoomType.workstation, col: 0, row: 0);
      final srv = _room(RoomType.serverRoom, col: 2, row: 0);
      expect(areRoomsAdjacent(ws, srv), isTrue);
    });

    test('vertical neighbours share a wall', () {
      // breakRoom 3×2 at (0,0), lounge 4×3 at (0,2) → touch at y=2
      final br = _room(RoomType.breakRoom, col: 0, row: 0);
      final ln = _room(RoomType.lounge, col: 0, row: 2);
      expect(areRoomsAdjacent(br, ln), isTrue);
    });

    test('rooms with a gap are NOT adjacent', () {
      final a = _room(RoomType.workstation, col: 0, row: 0);
      final b = _room(RoomType.serverRoom, col: 3, row: 0); // gap of 1 tile
      expect(areRoomsAdjacent(a, b), isFalse);
    });

    test('overlapping rooms are NOT adjacent', () {
      final a = _room(RoomType.workstation, col: 0, row: 0);
      final b = _room(RoomType.workstation, col: 1, row: 0);
      expect(areRoomsAdjacent(a, b), isFalse);
    });

    test('corner-only touch (no shared wall segment) is NOT adjacent', () {
      // ws at (0,0) 2×2 → right=2, bottom=2
      // serverRoom at (2,2) → touch only at corner (2,2)
      final ws = _room(RoomType.workstation, col: 0, row: 0);
      final srv = _room(RoomType.serverRoom, col: 2, row: 2);
      expect(areRoomsAdjacent(ws, srv), isFalse);
    });

    test('symmetry: adjacent(a,b) == adjacent(b,a)', () {
      final ws = _room(RoomType.workstation, col: 0, row: 0);
      final srv = _room(RoomType.serverRoom, col: 2, row: 0);
      expect(areRoomsAdjacent(ws, srv), areRoomsAdjacent(srv, ws));
    });
  });

  // ─── computeAdjacencyBonusPercent ────────────────────────────────────────

  group('computeAdjacencyBonusPercent', () {
    test('workstation adjacent to serverRoom → +5', () {
      final srv = _room(RoomType.serverRoom, col: 2, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.workstation, 0, 0, 0, [srv]);
      expect(pct, 5);
    });

    test('serverRoom adjacent to workstation → +5', () {
      final ws = _room(RoomType.workstation, col: 0, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.serverRoom, 2, 0, 0, [ws]);
      // workstation is within 8 tiles AND adjacent → no penalty, +5 bonus
      expect(pct, 5);
    });

    test('breakRoom adjacent to lounge → +5', () {
      // breakRoom is 2×2 → right=2; lounge must be at col=2 to touch
      final ln = _room(RoomType.lounge, col: 2, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.breakRoom, 0, 0, 0, [ln]);
      expect(pct, 5);
    });

    test('meetingRoom adjacent to workstation → +5', () {
      // meetingRoom is 3×2 → right=3; workstation must be at col=3 to touch
      final ws = _room(RoomType.workstation, col: 3, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.meetingRoom, 0, 0, 0, [ws]);
      expect(pct, 5);
    });

    test('serverRoom placed far (>8 tiles) from every workstation → −5', () {
      // workstation at (20,0), serverRoom ghost at (0,0) → dist > 8
      final ws = _room(RoomType.workstation, col: 20, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.serverRoom, 0, 0, 0, [ws]);
      expect(pct, -5);
    });

    test('serverRoom placed within 8 tiles but NOT adjacent → 0 (null)', () {
      // workstation at (5,0), serverRoom ghost at (0,0) → dist=5+1=6, no adj
      final ws = _room(RoomType.workstation, col: 5, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.serverRoom, 0, 0, 0, [ws]);
      // No adjacency pair bonus, workstation is nearby → no penalty either
      expect(pct, isNull);
    });

    test('no existing rooms → null (serverRoom in empty office)', () {
      // serverRoom with no existing rooms → existingRooms.isEmpty → no penalty
      final pct = computeAdjacencyBonusPercent(
          RoomType.serverRoom, 0, 0, 0, []);
      expect(pct, isNull);
    });

    test('unrelated room pair (workstation next to lounge) → null', () {
      final ln = _room(RoomType.lounge, col: 2, row: 0);
      final pct = computeAdjacencyBonusPercent(
          RoomType.workstation, 0, 0, 0, [ln]);
      expect(pct, isNull);
    });

    test('bonus accumulates from multiple adjacent pairs', () {
      // workstation at (0,0) adjacent to both serverRoom AND meetingRoom
      final srv = _room(RoomType.serverRoom, col: 2, row: 0);
      final mt = _room(RoomType.meetingRoom, col: 0, row: 2);
      final pct = computeAdjacencyBonusPercent(
          RoomType.workstation, 0, 0, 0, [srv, mt]);
      expect(pct, 10); // +5 from server + +5 from meeting
    });
  });
}
