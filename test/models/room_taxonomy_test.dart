import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('RoomCategory split', () {
    test('rooms (enclosed units) report category.room', () {
      const expected = {
        RoomType.workstation,
        RoomType.breakRoom,
        RoomType.meetingRoom,
        RoomType.serverRoom,
        RoomType.openSpace,
      };
      for (final rt in expected) {
        expect(rt.category, RoomCategory.room, reason: '$rt should be a Room');
      }
    });

    test('zones (open feature areas) report category.zone', () {
      const expected = {
        RoomType.lounge,
        RoomType.gym,
        RoomType.cinema,
        RoomType.pool,
        RoomType.miniGolf,
      };
      for (final rt in expected) {
        expect(rt.category, RoomCategory.zone, reason: '$rt should be a Zone');
      }
    });

    test('every RoomType has a category — switch exhaustiveness', () {
      for (final rt in RoomType.values) {
        // Should not throw.
        expect(rt.category, anyOf(RoomCategory.room, RoomCategory.zone));
      }
    });
  });

  group('Naming polish (Stage 3b)', () {
    test('Ukrainian names match the agreed-upon taxonomy', () {
      expect(RoomType.workstation.nameUk, 'Воркстейшн');
      expect(RoomType.breakRoom.nameUk, 'Кімната відпочинку');
      expect(RoomType.meetingRoom.nameUk, 'Переговорна');
      expect(RoomType.serverRoom.nameUk, 'Серверна');
      expect(RoomType.openSpace.nameUk, 'Опен-спейс');
      expect(RoomType.lounge.nameUk, 'Рекреація');
    });

    test('every nameUk is non-empty', () {
      for (final rt in RoomType.values) {
        expect(rt.nameUk, isNotEmpty);
      }
    });

    test('every description is non-empty', () {
      for (final rt in RoomType.values) {
        expect(rt.description, isNotEmpty);
      }
    });
  });

  group('openSpace economy', () {
    test('openSpace is a Room with 5×4 footprint and reasonable cost', () {
      expect(RoomType.openSpace.category, RoomCategory.room);
      expect(RoomType.openSpace.widthTiles, 5);
      expect(RoomType.openSpace.heightTiles, 4);
      expect(RoomType.openSpace.cost, greaterThan(0));
      expect(RoomType.openSpace.maxPerOffice, greaterThanOrEqualTo(1));
    });

    test('openSpace bundle is cheaper than 6 individual workstations', () {
      // Stage 3b polish: openSpace 5×4 holds 6 desks. Bundle must save money
      // vs hand-placing 6 workstations or the discount intent is gone.
      final bundle = RoomType.openSpace.cost;
      final individual = RoomType.workstation.cost * 6;
      expect(bundle, lessThan(individual),
          reason:
              'openSpace ($bundle) should be cheaper than 6 × workstation ($individual)');
    });
  });

  group('teamFloor economy (Stage 3b polish round)', () {
    test('teamFloor is a Room with 7×5 footprint', () {
      expect(RoomType.teamFloor.category, RoomCategory.room);
      expect(RoomType.teamFloor.widthTiles, 7);
      expect(RoomType.teamFloor.heightTiles, 5);
    });

    test('teamFloor bundle is cheaper than 12 individual workstations', () {
      // Stage 3b polish: teamFloor 7×5 holds 12 desks. Bundle discount
      // makes "buy a floor" the right call over hand-placing.
      final bundle = RoomType.teamFloor.cost;
      final individual = RoomType.workstation.cost * 12;
      expect(bundle, lessThan(individual),
          reason:
              'teamFloor ($bundle) should be cheaper than 12 × workstation ($individual)');
    });

    test('teamFloor capped to a low maxPerOffice (signature piece)', () {
      // A teamFloor occupies 35 inner tiles — placing many would lock out
      // every other room. Cap is intentionally tight.
      expect(RoomType.teamFloor.maxPerOffice, lessThanOrEqualTo(3));
    });

    test('teamFloor counts as a desk hub for adjacency', () {
      // workstation adjacent to teamFloor must earn +5% (hub pair).
      final teamFloor = PlacedRoom(
        id: 'tf',
        type: RoomType.teamFloor,
        col: 7,
        row: 0,
      );
      final bonus = computeAdjacencyBonusPercent(
        RoomType.workstation,
        5,
        0,
        0,
        [teamFloor],
      );
      expect(bonus, 5);
    });

    test('serverRoom adjacent to teamFloor → +5 (teamFloor counts as hub)', () {
      final teamFloor = PlacedRoom(
        id: 'tf',
        type: RoomType.teamFloor,
        col: 2,
        row: 0,
      );
      // serverRoom 2×2 placed flush to the right of teamFloor (cols 9..10
      // align with teamFloor's right edge col 9).
      final bonus = computeAdjacencyBonusPercent(
        RoomType.serverRoom,
        9,
        0,
        0,
        [teamFloor],
      );
      expect(bonus, 5);
    });

    test('openSpace adjacent to teamFloor → +5 (hub ↔ hub)', () {
      final teamFloor = PlacedRoom(
        id: 'tf',
        type: RoomType.teamFloor,
        col: 0,
        row: 0,
      );
      // openSpace 5×4 flush to the right of teamFloor (right=7 → col 7).
      final bonus = computeAdjacencyBonusPercent(
        RoomType.openSpace,
        7,
        0,
        0,
        [teamFloor],
      );
      expect(bonus, 5);
    });

    test('two adjacent teamFloors do NOT reinforce themselves', () {
      // Hub pair only fires when types DIFFER. Two teamFloors side by side
      // shouldn't double-dip.
      final tf1 = PlacedRoom(
        id: 'tf1',
        type: RoomType.teamFloor,
        col: 0,
        row: 0,
      );
      final bonus = computeAdjacencyBonusPercent(
        RoomType.teamFloor,
        7,
        0,
        0,
        [tf1],
      );
      expect(bonus, isNull);
    });
  });

  group('JSON stability (PlacedRoom)', () {
    test('PlacedRoom roundtrips closedDoors', () {
      final original = PlacedRoom(
        id: 'r1',
        type: RoomType.workstation,
        col: 5,
        row: 5,
        closedDoors: const {(col: 5, row: 6), (col: 6, row: 5)},
      );
      final reread = PlacedRoom.fromJson(original.toJson());
      expect(reread.closedDoors, original.closedDoors);
    });

    test('legacy PlacedRoom JSON without closedDoors decodes to empty set', () {
      final legacy = {
        'id': 'r1',
        'type': RoomType.workstation.index,
        'col': 1,
        'row': 1,
      };
      final room = PlacedRoom.fromJson(legacy);
      expect(room.closedDoors, isEmpty);
    });

    test('toJson omits closedDoors when empty (forward-compat with old readers)',
        () {
      const room = PlacedRoom(
        id: 'r1',
        type: RoomType.workstation,
        col: 1,
        row: 1,
      );
      expect(room.toJson().containsKey('closedDoors'), isFalse);
    });
  });

  group('Adjacency engine (Stage 3b rewire)', () {
    PlacedRoom room(RoomType t, int col, int row) =>
        PlacedRoom(id: '${t.index}_${col}_$row', type: t, col: col, row: row);

    test('workstation adjacent to serverRoom → +5%', () {
      // ws at (5,0) 2×2 → right=7; sv at (7,0) 2×2
      final bonus = computeAdjacencyBonusPercent(
        RoomType.workstation,
        5,
        0,
        0,
        [room(RoomType.serverRoom, 7, 0)],
      );
      expect(bonus, 5);
    });

    test('openSpace adjacent to meetingRoom → +5%', () {
      // openSpace 5×4 at (5,0) → rows 0..3, cols 5..9. meetingRoom 3×2 below.
      final bonus = computeAdjacencyBonusPercent(
        RoomType.openSpace,
        5,
        0,
        0,
        [room(RoomType.meetingRoom, 5, 4)],
      );
      expect(bonus, 5);
    });

    test('openSpace adjacent to BOTH workstation and serverRoom stacks bonus',
        () {
      // openSpace 5×4 at (5,0) → cols 5..9 rows 0..3.
      // ws 2×2 at (3,0) cols 3..4 (touches left edge),
      // sv 2×2 at (10,0) cols 10..11 (touches right edge).
      final bonus = computeAdjacencyBonusPercent(
        RoomType.openSpace,
        5,
        0,
        0,
        [
          room(RoomType.workstation, 3, 0),
          room(RoomType.serverRoom, 10, 0),
        ],
      );
      // ws → +5, sv → +5
      expect(bonus, 10);
    });

    test('Zone does NOT initiate adjacency pair (lounge next to itself)', () {
      // Two lounges side by side — Zones must not give each other bonuses.
      final bonus = computeAdjacencyBonusPercent(
        RoomType.lounge,
        5,
        0,
        0,
        [room(RoomType.lounge, 8, 0)],
      );
      expect(bonus, isNull);
    });

    test('Zone receives bonus from a Room (one-way)', () {
      // Placing a lounge adjacent to a breakRoom → +5% morale (one-way receive).
      final bonus = computeAdjacencyBonusPercent(
        RoomType.lounge,
        5,
        0,
        0,
        [room(RoomType.breakRoom, 8, 0)],
      );
      expect(bonus, 5);
    });

    test('breakRoom initiates pair with gym → +5%', () {
      // breakRoom at (5,0) 2×2; gym at (5,2) 4×3 (touches bottom edge)
      final bonus = computeAdjacencyBonusPercent(
        RoomType.breakRoom,
        5,
        0,
        0,
        [room(RoomType.gym, 5, 2)],
      );
      expect(bonus, 5);
    });

    test('serverRoom far from every workstation/openSpace → −5 penalty', () {
      // serverRoom at (5,5), workstation at (15,15) → distance > 8
      final bonus = computeAdjacencyBonusPercent(
        RoomType.serverRoom,
        5,
        5,
        0,
        [room(RoomType.workstation, 15, 15)],
      );
      expect(bonus, -5);
    });

    test('serverRoom adjacent to an openSpace → +5 (and no isolation penalty)',
        () {
      // serverRoom 2×2 at (5,5) right=7; openSpace 4×3 at (7,5) left=7 → touching.
      // y-overlap: server rows 5..6, openSpace rows 5..7 → overlap 5..6.
      final bonus = computeAdjacencyBonusPercent(
        RoomType.serverRoom,
        5,
        5,
        0,
        [room(RoomType.openSpace, 7, 5)],
      );
      expect(bonus, 5);
    });

    test('serverRoom near (≤8 tiles) an openSpace but not adjacent → no penalty',
        () {
      // serverRoom 2×2 at (5,5), openSpace 4×3 at (9,5) — distance≈4 ≤ 8, not touching.
      final bonus = computeAdjacencyBonusPercent(
        RoomType.serverRoom,
        5,
        5,
        0,
        [room(RoomType.openSpace, 9, 5)],
      );
      // No adjacency → no +5. No far penalty since openSpace counts as a
      // workstation-hub neighbour. Net effect: null.
      expect(bonus, isNull);
    });
  });

  group('fixed-tier lots (Stage 4)', () {
    test('each linear tier hands out a strictly bigger lot', () {
      // No more per-tile expansion — the office grid is a fixed size per tier.
      expect(OfficeLevel.garage.playableTiles,
          lessThan(OfficeLevel.smallOffice.playableTiles));
      expect(OfficeLevel.smallOffice.playableTiles,
          lessThan(OfficeLevel.modernOffice.playableTiles));
      expect(OfficeLevel.modernOffice.playableTiles,
          lessThan(OfficeLevel.techHub.playableTiles));
    });

    test('playableTiles equals the inner area of the fixed lot', () {
      for (final level in OfficeLevel.values) {
        expect(level.playableTiles,
            (level.gridCols - 2) * (level.gridRows - 2));
      }
    });
  });
}
