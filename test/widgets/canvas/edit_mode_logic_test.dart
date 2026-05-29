/// Positive + negative coverage for the furniture edit-mode tap state
/// machine. The widget glue is thin (build inputs, dispatch action) — the
/// real decision logic is here, so this file is the primary regression
/// surface for the pencil-toggle / move / delete flow.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/edit_mode_logic.dart';

/// Minimal two-tile-wide furniture stand-in. Real catalog uses
/// `furnitureById`; the pure logic accepts an injected lookup so tests
/// don't depend on catalog data.
const _coffee = FurnitureItem(
  id: 'coffee',
  type: FurnitureType.coffeeTable,
  name: 'Coffee Table',
  cost: 100,
  description: '',
);

const _bigDesk = FurnitureItem(
  id: 'desk2x2',
  type: FurnitureType.storage,
  name: 'Big Desk',
  cost: 200,
  description: '',
  widthTiles: 2,
  heightTiles: 2,
);

FurnitureItem? _lookup(String id) => switch (id) {
      'coffee' => _coffee,
      'desk2x2' => _bigDesk,
      _ => null,
    };

EditModeTapInput _input({
  required int col,
  required int row,
  int gridCols = 10,
  int gridRows = 10,
  Set<String> blocked = const {},
  List<FurniturePlacement> placedFurniture = const [],
  List<PlacedRoom> placedRooms = const [],
  int? heldPlacedIndex,
  String? selectedFurnitureId,
}) =>
    EditModeTapInput(
      col: col,
      row: row,
      gridCols: gridCols,
      gridRows: gridRows,
      blockedTiles: blocked,
      placedFurniture: placedFurniture,
      placedRooms: placedRooms,
      heldPlacedIndex: heldPlacedIndex,
      selectedFurnitureId: selectedFurnitureId,
      lookupItem: _lookup,
    );

void main() {
  group('hitTestPlacedFurniture', () {
    test('returns null on empty grid', () {
      expect(hitTestPlacedFurniture(5, 5, const [], _lookup), isNull);
    });

    test('hits 1×1 furniture exact tile', () {
      final placed = [
        const FurniturePlacement(itemId: 'coffee', col: 3, row: 4),
      ];
      expect(hitTestPlacedFurniture(3, 4, placed, _lookup), 0);
    });

    test('misses 1×1 furniture by one tile in any direction', () {
      final placed = [
        const FurniturePlacement(itemId: 'coffee', col: 3, row: 4),
      ];
      expect(hitTestPlacedFurniture(2, 4, placed, _lookup), isNull);
      expect(hitTestPlacedFurniture(4, 4, placed, _lookup), isNull);
      expect(hitTestPlacedFurniture(3, 3, placed, _lookup), isNull);
      expect(hitTestPlacedFurniture(3, 5, placed, _lookup), isNull);
    });

    test('hits any of the 4 tiles a 2×2 footprint occupies', () {
      final placed = [
        const FurniturePlacement(itemId: 'desk2x2', col: 3, row: 4),
      ];
      for (final tile in const [(3, 4), (4, 4), (3, 5), (4, 5)]) {
        expect(
          hitTestPlacedFurniture(tile.$1, tile.$2, placed, _lookup),
          0,
          reason: 'tile (${tile.$1},${tile.$2}) should hit 2×2 desk',
        );
      }
      // Just outside the right/bottom edge — should miss.
      expect(hitTestPlacedFurniture(5, 4, placed, _lookup), isNull);
      expect(hitTestPlacedFurniture(3, 6, placed, _lookup), isNull);
    });

    test('top-most (latest added) wins on overlap', () {
      final placed = [
        const FurniturePlacement(itemId: 'coffee', col: 3, row: 4),
        const FurniturePlacement(itemId: 'coffee', col: 3, row: 4),
      ];
      expect(hitTestPlacedFurniture(3, 4, placed, _lookup), 1);
    });

    test('ignores entries whose itemId the catalog cannot resolve', () {
      final placed = [
        const FurniturePlacement(itemId: 'unknown-id', col: 3, row: 4),
      ];
      expect(hitTestPlacedFurniture(3, 4, placed, _lookup), isNull);
    });
  });

  group('canPlaceFurnitureAt', () {
    test('inside-bounds, unblocked tile → true', () {
      expect(
        canPlaceFurnitureAt(
          col: 3,
          row: 3,
          item: _coffee,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {},
          placedFurniture: const [],
          lookupItem: _lookup,
        ),
        isTrue,
      );
    });

    test('rejects placement on wall margin', () {
      // col=0 / row=0 is wall.
      expect(
        canPlaceFurnitureAt(
          col: 0,
          row: 3,
          item: _coffee,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {},
          placedFurniture: const [],
          lookupItem: _lookup,
        ),
        isFalse,
      );
      // Right-most playable col is gridCols-2 == 8 for 1×1; col=9 is wall.
      expect(
        canPlaceFurnitureAt(
          col: 9,
          row: 3,
          item: _coffee,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {},
          placedFurniture: const [],
          lookupItem: _lookup,
        ),
        isFalse,
      );
    });

    test('2×2 footprint refused when it spills into wall', () {
      // col=8 + width=2 → reaches col=9 (wall). Should refuse.
      expect(
        canPlaceFurnitureAt(
          col: 8,
          row: 3,
          item: _bigDesk,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {},
          placedFurniture: const [],
          lookupItem: _lookup,
        ),
        isFalse,
      );
      // col=7 + width=2 → reaches col=8 (last floor tile). OK.
      expect(
        canPlaceFurnitureAt(
          col: 7,
          row: 3,
          item: _bigDesk,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {},
          placedFurniture: const [],
          lookupItem: _lookup,
        ),
        isTrue,
      );
    });

    test('rejects tile that any footprint cell intersects blockedTiles', () {
      // 2×2 at (3,3) covers (3,3) (4,3) (3,4) (4,4); block one of them.
      expect(
        canPlaceFurnitureAt(
          col: 3,
          row: 3,
          item: _bigDesk,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {'4,4'},
          placedFurniture: const [],
          lookupItem: _lookup,
        ),
        isFalse,
      );
    });

    test('move flow: excluding the held item makes its old tiles passable', () {
      // The desk sits at (3,3) covering 4 tiles. blockedTiles mirrors that
      // (canvas builds blockedTiles from placedFurniture). With no
      // exclusion, moving it 1 tile right (overlapping itself partially)
      // should be rejected.
      final placed = [
        const FurniturePlacement(itemId: 'desk2x2', col: 3, row: 3),
      ];
      final blocked = {'3,3', '4,3', '3,4', '4,4'};

      expect(
        canPlaceFurnitureAt(
          col: 4,
          row: 3,
          item: _bigDesk,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: blocked,
          placedFurniture: placed,
          lookupItem: _lookup,
        ),
        isFalse,
        reason: 'without exclusion the desk self-collides',
      );

      expect(
        canPlaceFurnitureAt(
          col: 4,
          row: 3,
          item: _bigDesk,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: blocked,
          placedFurniture: placed,
          lookupItem: _lookup,
          excludePlacedIndex: 0,
        ),
        isTrue,
        reason: "exclusion lets the desk shift one tile without colliding "
            'with its own old footprint',
      );
    });

    test('excludePlacedIndex out of range is silently ignored', () {
      // Should not crash; should behave as if no exclusion.
      expect(
        canPlaceFurnitureAt(
          col: 3,
          row: 3,
          item: _coffee,
          gridCols: 10,
          gridRows: 10,
          blockedTiles: const {},
          placedFurniture: const [],
          lookupItem: _lookup,
          excludePlacedIndex: 99,
        ),
        isTrue,
      );
    });
  });

  group('decideEditModeTap — out of bounds', () {
    test('tap on wall margin → no-op (any hand state)', () {
      for (final col in const [0, 9]) {
        expect(decideEditModeTap(_input(col: col, row: 3)), isA<TapNoOp>());
      }
      for (final row in const [0, 9]) {
        expect(decideEditModeTap(_input(col: 3, row: row)), isA<TapNoOp>());
      }
    });
  });

  group('decideEditModeTap — empty hand', () {
    test('tap on placed furniture → pick up', () {
      final action = decideEditModeTap(_input(
        col: 3,
        row: 3,
        placedFurniture: const [
          FurniturePlacement(itemId: 'coffee', col: 3, row: 3),
        ],
      ));
      expect(action, isA<TapPickUp>());
      expect((action as TapPickUp).placedIndex, 0);
    });

    test('tap on placed room (no furniture overlap) → remove room', () {
      final action = decideEditModeTap(_input(
        col: 4,
        row: 4,
        placedRooms: const [
          PlacedRoom(
              id: 'room-1', type: RoomType.workstation, col: 3, row: 3),
        ],
      ));
      expect(action, isA<TapRemoveRoom>());
      expect((action as TapRemoveRoom).roomId, 'room-1');
    });

    test('tap on empty floor (no room, no furniture) → no-op', () {
      expect(
        decideEditModeTap(_input(col: 3, row: 3)),
        isA<TapNoOp>(),
      );
    });

    test('placed furniture takes priority over a room at the same tile', () {
      final action = decideEditModeTap(_input(
        col: 3,
        row: 3,
        placedFurniture: const [
          FurniturePlacement(itemId: 'coffee', col: 3, row: 3),
        ],
        placedRooms: const [
          PlacedRoom(
              id: 'room-1', type: RoomType.workstation, col: 3, row: 3),
        ],
      ));
      expect(action, isA<TapPickUp>(),
          reason: 'with empty hand a furniture hit becomes pickup, not '
              'room removal — otherwise the player loses the room while '
              'trying to grab the chair on top of it');
    });
  });

  group('decideEditModeTap — held placed furniture (move flow)', () {
    final coffee = const FurniturePlacement(itemId: 'coffee', col: 3, row: 3);

    test('tap on same held → release hold (cancel)', () {
      expect(
        decideEditModeTap(_input(
          col: 3,
          row: 3,
          placedFurniture: [coffee],
          blocked: const {'3,3'},
          heldPlacedIndex: 0,
        )),
        isA<TapReleaseHold>(),
      );
    });

    test('tap on free tile → TapMoveHere with held idx', () {
      final action = decideEditModeTap(_input(
        col: 5,
        row: 5,
        placedFurniture: [coffee],
        blocked: const {'3,3'},
        heldPlacedIndex: 0,
      ));
      expect(action, isA<TapMoveHere>());
      final move = action as TapMoveHere;
      expect(move.placedIndex, 0);
      expect(move.col, 5);
      expect(move.row, 5);
    });

    test('tap on another placed → swap pickup', () {
      final other = const FurniturePlacement(itemId: 'coffee', col: 6, row: 6);
      final action = decideEditModeTap(_input(
        col: 6,
        row: 6,
        placedFurniture: [coffee, other],
        blocked: const {'3,3', '6,6'},
        heldPlacedIndex: 0,
      ));
      expect(action, isA<TapPickUp>());
      expect((action as TapPickUp).placedIndex, 1);
    });

    test('tap on free tile blocked by other furniture → no-op', () {
      final action = decideEditModeTap(_input(
        col: 6,
        row: 6,
        placedFurniture: [coffee],
        // Pretend (6,6) is blocked by something not in placedFurniture
        // (e.g. desk station / coffee machine).
        blocked: const {'3,3', '6,6'},
        heldPlacedIndex: 0,
      ));
      expect(action, isA<TapNoOp>());
    });

    test('tap inside held 2×2 footprint → release hold (not move)', () {
      // Hit-test catches taps inside the held item's current tiles before
      // the move branch — that's the cancel gesture. Without this guard,
      // tapping any of the 4 footprint tiles would try to set new
      // top-left there, which is partly meaningless for a 2×2.
      final desk =
          const FurniturePlacement(itemId: 'desk2x2', col: 3, row: 3);
      final blocked = {'3,3', '4,3', '3,4', '4,4'};
      for (final cell in const [(3, 3), (4, 3), (3, 4), (4, 4)]) {
        expect(
          decideEditModeTap(_input(
            col: cell.$1,
            row: cell.$2,
            placedFurniture: [desk],
            blocked: blocked,
            heldPlacedIndex: 0,
          )),
          isA<TapReleaseHold>(),
          reason: 'tap on held footprint tile (${cell.$1},${cell.$2}) '
              'should cancel, not start a partial-overlap move',
        );
      }
    });

    test('overlap-shift of 2×2 desk needs self-exclusion to succeed', () {
      // Desk at (3,3) covers (3,3),(4,3),(3,4),(4,4). Tapping (2,3)
      // means new top-left = (2,3) → new footprint covers
      // (2,3),(3,3),(2,4),(3,4) — overlaps old at (3,3) and (3,4). The
      // exclusion logic must drop those tiles from the blocked check or
      // the desk can never shift by less than its own width.
      final desk =
          const FurniturePlacement(itemId: 'desk2x2', col: 3, row: 3);
      final blocked = {'3,3', '4,3', '3,4', '4,4'};
      final action = decideEditModeTap(_input(
        col: 2,
        row: 3,
        placedFurniture: [desk],
        blocked: blocked,
        heldPlacedIndex: 0,
      ));
      expect(action, isA<TapMoveHere>());
      final move = action as TapMoveHere;
      expect(move.placedIndex, 0);
      expect(move.col, 2);
      expect(move.row, 3);
    });

    test('overlap-shift refused if a non-held cell is also blocked', () {
      // Same desk + same blocked tiles, but pretend (2,3) is also blocked
      // by a desk station / wall etc. that's NOT in placedFurniture and
      // hence not excluded. Move should refuse.
      final desk =
          const FurniturePlacement(itemId: 'desk2x2', col: 3, row: 3);
      final blocked = {'3,3', '4,3', '3,4', '4,4', '2,3'};
      expect(
        decideEditModeTap(_input(
          col: 2,
          row: 3,
          placedFurniture: [desk],
          blocked: blocked,
          heldPlacedIndex: 0,
        )),
        isA<TapNoOp>(),
      );
    });

    test('held index out of range → release stale (no mutation)', () {
      expect(
        decideEditModeTap(_input(
          col: 5,
          row: 5,
          placedFurniture: const [],
          heldPlacedIndex: 99,
        )),
        isA<TapReleaseStaleHold>(),
      );
    });

    test("held points to placement whose itemId can't be resolved → "
        'release stale', () {
      expect(
        decideEditModeTap(_input(
          col: 5,
          row: 5,
          placedFurniture: const [
            FurniturePlacement(itemId: 'unknown', col: 3, row: 3),
          ],
          heldPlacedIndex: 0,
        )),
        isA<TapReleaseStaleHold>(),
      );
    });

    test('held-hand tap on wall margin → no-op (does not release)', () {
      expect(
        decideEditModeTap(_input(
          col: 0,
          row: 3,
          placedFurniture: const [
            FurniturePlacement(itemId: 'coffee', col: 3, row: 3),
          ],
          heldPlacedIndex: 0,
        )),
        isA<TapNoOp>(),
      );
    });

    test('held-hand tap on placed room → swap pickup wins over remove-room',
        () {
      // Important: removing a room while holding furniture would silently
      // drop the hand and confuse the player. Empty-hand path is the only
      // way to remove a room.
      final coffee =
          const FurniturePlacement(itemId: 'coffee', col: 5, row: 5);
      final action = decideEditModeTap(_input(
        col: 5,
        row: 5,
        placedFurniture: [coffee],
        placedRooms: const [
          PlacedRoom(
              id: 'room-1', type: RoomType.workstation, col: 3, row: 3),
        ],
        heldPlacedIndex: 0,
        blocked: const {'5,5'},
      ));
      expect(action, isA<TapReleaseHold>(),
          reason: 'tapping back on the held item cancels — does not remove '
              'the room');
    });
  });

  group('decideEditModeTap — selected inventory item (placement flow)', () {
    test('tap on free tile → TapPlaceFromInventory', () {
      final action = decideEditModeTap(_input(
        col: 3,
        row: 3,
        selectedFurnitureId: 'coffee',
      ));
      expect(action, isA<TapPlaceFromInventory>());
      final place = action as TapPlaceFromInventory;
      expect(place.itemId, 'coffee');
      expect(place.col, 3);
      expect(place.row, 3);
    });

    test('tap on blocked tile → no-op', () {
      expect(
        decideEditModeTap(_input(
          col: 3,
          row: 3,
          blocked: const {'3,3'},
          selectedFurnitureId: 'coffee',
        )),
        isA<TapNoOp>(),
      );
    });

    test('tap on existing placed furniture → swap to pick-up of that item',
        () {
      final action = decideEditModeTap(_input(
        col: 4,
        row: 4,
        placedFurniture: const [
          FurniturePlacement(itemId: 'coffee', col: 4, row: 4),
        ],
        selectedFurnitureId: 'coffee',
      ));
      expect(action, isA<TapPickUp>());
      expect((action as TapPickUp).placedIndex, 0);
    });

    test('unknown selected itemId → no-op', () {
      expect(
        decideEditModeTap(_input(
          col: 3,
          row: 3,
          selectedFurnitureId: 'no-such-item',
        )),
        isA<TapNoOp>(),
      );
    });

    test('2×2 selected item refused when it would spill past floor', () {
      expect(
        decideEditModeTap(_input(
          col: 8,
          row: 3,
          selectedFurnitureId: 'desk2x2',
        )),
        isA<TapNoOp>(),
        reason: 'col=8 + width=2 reaches col=9 (wall) → refuse',
      );
    });
  });

  group('decideEditModeTap — hand-state precedence', () {
    test('both held and selected set → held wins (defensive — coord '
        'helpers enforce mutual-exclusion but the pure logic should not '
        'rely on that invariant)', () {
      final coffee = const FurniturePlacement(itemId: 'coffee', col: 5, row: 5);
      final action = decideEditModeTap(_input(
        col: 7,
        row: 7,
        placedFurniture: [coffee],
        blocked: const {'5,5'},
        heldPlacedIndex: 0,
        selectedFurnitureId: 'coffee',
      ));
      expect(action, isA<TapMoveHere>(),
          reason: 'with both states set we follow the move flow, not '
              'placement — otherwise the selected ghost would silently '
              'override a real held-item move and the player loses the '
              'piece they were dragging');
    });
  });

  // ── Regression: "tap deletes furniture" must NEVER happen ────────────────
  //
  // History: twice the build-mode tap path collapsed pickup into delete —
  // once via the legacy `_handleFurnitureTap` (tap = remove), once via
  // `onLongPressStart` firing on borderline clicks. These tests pin the
  // invariant at the pure-logic layer: across every reachable hand-state ×
  // grid-state combination, *no* action that the widget can route a tap to
  // ever results in "remove a placed furniture item". The only remove
  // variant in `EditModeTapAction` is `TapRemoveRoom`, and it requires an
  // empty hand + a placed room beneath the tile, never a furniture hit.
  group('decideEditModeTap — regression: tap NEVER deletes placed furniture',
      () {
    final placedFurnitureFixture = [
      const FurniturePlacement(itemId: 'coffee', col: 3, row: 3),
      const FurniturePlacement(itemId: 'desk2x2', col: 6, row: 6),
    ];

    test('empty hand + tap on 1×1 furniture → pick up (not delete)', () {
      final action = decideEditModeTap(_input(
        col: 3,
        row: 3,
        placedFurniture: placedFurnitureFixture,
      ));
      expect(action, isA<TapPickUp>());
      expect((action as TapPickUp).placedIndex, 0);
    });

    test('empty hand + tap on any tile of 2×2 furniture footprint → pick up',
        () {
      for (final tile in const [(6, 6), (7, 6), (6, 7), (7, 7)]) {
        final action = decideEditModeTap(_input(
          col: tile.$1,
          row: tile.$2,
          placedFurniture: placedFurnitureFixture,
        ));
        expect(action, isA<TapPickUp>(),
            reason: 'tile (${tile.$1},${tile.$2}) — every tile of the '
                'footprint must pick up, never delete');
        expect((action as TapPickUp).placedIndex, 1);
      }
    });

    test('held + tap on different placed furniture → pick up that one '
        '(swap, NOT delete the previously held)', () {
      final action = decideEditModeTap(_input(
        col: 3,
        row: 3,
        placedFurniture: placedFurnitureFixture,
        heldPlacedIndex: 1,
      ));
      expect(action, isA<TapPickUp>());
      expect((action as TapPickUp).placedIndex, 0,
          reason: 'tap rebinds the hand to the tapped item — neither item '
              'is removed');
    });

    test('held + tap on same placed furniture → release hold (cancel '
        'move, NOT delete)', () {
      final action = decideEditModeTap(_input(
        col: 3,
        row: 3,
        placedFurniture: placedFurnitureFixture,
        heldPlacedIndex: 0,
      ));
      expect(action, isA<TapReleaseHold>());
    });

    test('selected inventory + tap on placed furniture → pick up that '
        'placed item (swap to move flow, NOT delete)', () {
      final action = decideEditModeTap(_input(
        col: 6,
        row: 7,
        placedFurniture: placedFurnitureFixture,
        selectedFurnitureId: 'coffee',
      ));
      expect(action, isA<TapPickUp>());
      expect((action as TapPickUp).placedIndex, 1);
    });

    test('every reachable variant of EditModeTapAction is non-destructive '
        'for placed furniture (sealed type has no TapRemoveFurniture)', () {
      // Exhaustive enumeration of the sealed type — if anyone adds a
      // "TapRemoveFurniture" variant in the future, this switch will fail
      // to compile, forcing them to revisit the regression invariant.
      const allActions = <EditModeTapAction>[
        TapNoOp(),
        TapPickUp(0),
        TapReleaseHold(),
        TapMoveHere(0, 1, 1),
        TapPlaceFromInventory('coffee', 1, 1),
        TapRemoveRoom('room-1'),
        TapReleaseStaleHold(),
      ];
      for (final a in allActions) {
        final removesFurniture = switch (a) {
          TapNoOp() => false,
          TapPickUp() => false,
          TapReleaseHold() => false,
          TapMoveHere() => false,
          TapPlaceFromInventory() => false,
          TapRemoveRoom() => false,
          TapReleaseStaleHold() => false,
        };
        expect(removesFurniture, isFalse,
            reason: 'No tap-driven action may remove a placed furniture '
                'item by design — delete lives behind an explicit button.');
      }
    });
  });
}
