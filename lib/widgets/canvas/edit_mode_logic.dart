/// Pure decision logic for the furniture edit mode tap/long-press state
/// machine. Lives separately from `agent_canvas.dart` so it can be unit
/// tested without mounting the canvas.
///
/// The widget owns: pointer→tile coord conversion, provider reads/writes,
/// notifier mutations, painter rebuilds. This module owns: deciding what
/// SHOULD happen for a given input tile + current hand state + game state.
library;

import '../../models/game_economy.dart';

/// Discriminated outcome of a single edit-mode tap. The widget interprets
/// each variant by combining a `FurnitureEditModeCoord` transition and
/// (optionally) a `GameEconomyNotifier` mutation. Keeps the test surface
/// pure: tests assert which variant + payload comes back for a given
/// fixture, no real notifiers needed.
sealed class EditModeTapAction {
  const EditModeTapAction();
}

/// Tap fell outside the floor margin (one-tile wall border on each side)
/// or hit nothing actionable with empty hand. Widget should do nothing.
class TapNoOp extends EditModeTapAction {
  const TapNoOp();
}

/// Player picked up a placed furniture item — start move flow.
class TapPickUp extends EditModeTapAction {
  final int placedIndex;
  const TapPickUp(this.placedIndex);
}

/// Player cancelled the move (tapped the same item that was held).
class TapReleaseHold extends EditModeTapAction {
  const TapReleaseHold();
}

/// Move-in-flight committed: drop the held item at (col, row).
class TapMoveHere extends EditModeTapAction {
  final int placedIndex;
  final int col;
  final int row;
  const TapMoveHere(this.placedIndex, this.col, this.row);
}

/// Inventory placement: drop the selected item id at (col, row).
class TapPlaceFromInventory extends EditModeTapAction {
  final String itemId;
  final int col;
  final int row;
  const TapPlaceFromInventory(this.itemId, this.col, this.row);
}

/// Tap on an empty hand hit a placed room → remove that room.
class TapRemoveRoom extends EditModeTapAction {
  final String roomId;
  const TapRemoveRoom(this.roomId);
}

/// Held index was stale (item removed underneath us, e.g. after a save
/// reload). Widget should clear the hold without mutating game state.
class TapReleaseStaleHold extends EditModeTapAction {
  const TapReleaseStaleHold();
}

/// Snapshot of the inputs the decision function needs. Mirrors the
/// runtime widget reads, but the test can construct it directly.
class EditModeTapInput {
  final int col;
  final int row;
  final int gridCols;
  final int gridRows;
  final Set<String> blockedTiles;
  final List<FurniturePlacement> placedFurniture;
  final List<PlacedRoom> placedRooms;
  final int? heldPlacedIndex;
  final String? selectedFurnitureId;
  final FurnitureItem? Function(String id) lookupItem;

  const EditModeTapInput({
    required this.col,
    required this.row,
    required this.gridCols,
    required this.gridRows,
    required this.blockedTiles,
    required this.placedFurniture,
    required this.placedRooms,
    required this.heldPlacedIndex,
    required this.selectedFurnitureId,
    required this.lookupItem,
  });
}

/// Top-to-bottom hit test: walks placed furniture in reverse so the
/// most recently added item wins overlap. Returns the index into
/// [placedFurniture] or null if no hit.
int? hitTestPlacedFurniture(
  int col,
  int row,
  List<FurniturePlacement> placedFurniture,
  FurnitureItem? Function(String id) lookupItem,
) {
  for (int i = placedFurniture.length - 1; i >= 0; i--) {
    final p = placedFurniture[i];
    final item = lookupItem(p.itemId);
    if (item == null) continue;
    if (col >= p.col &&
        col < p.col + item.widthTiles &&
        row >= p.row &&
        row < p.row + item.heightTiles) {
      return i;
    }
  }
  return null;
}

/// Validates that all tiles of an item's footprint at (col,row) fit
/// inside the floor and aren't blocked. When [excludePlacedIndex] is
/// given, that placed item's tiles are exempt from blocking — needed for
/// small moves where source/target footprints overlap by one tile.
bool canPlaceFurnitureAt({
  required int col,
  required int row,
  required FurnitureItem item,
  required int gridCols,
  required int gridRows,
  required Set<String> blockedTiles,
  required List<FurniturePlacement> placedFurniture,
  required FurnitureItem? Function(String id) lookupItem,
  int? excludePlacedIndex,
}) {
  if (col < 1 ||
      row < 1 ||
      col + item.widthTiles > gridCols - 1 ||
      row + item.heightTiles > gridRows - 1) {
    return false;
  }

  Set<String> excluded = const {};
  if (excludePlacedIndex != null &&
      excludePlacedIndex >= 0 &&
      excludePlacedIndex < placedFurniture.length) {
    final p = placedFurniture[excludePlacedIndex];
    final pItem = lookupItem(p.itemId);
    if (pItem != null) {
      excluded = {
        for (int dc = 0; dc < pItem.widthTiles; dc++)
          for (int dr = 0; dr < pItem.heightTiles; dr++)
            '${p.col + dc},${p.row + dr}',
      };
    }
  }

  for (int dc = 0; dc < item.widthTiles; dc++) {
    for (int dr = 0; dr < item.heightTiles; dr++) {
      final key = '${col + dc},${row + dr}';
      if (excluded.contains(key)) continue;
      if (blockedTiles.contains(key)) return false;
    }
  }
  return true;
}

/// Resolves the action for a single tap in edit mode. Pure — only reads
/// from [input], no provider side effects.
///
/// Branch order matches the widget:
///   * Out-of-bounds → no-op
///   * Held → release-on-same / swap-on-other / move-on-free
///   * Selected → swap-on-other / place-on-free
///   * Empty hand → pick-up-furniture / remove-room / no-op
EditModeTapAction decideEditModeTap(EditModeTapInput input) {
  final col = input.col;
  final row = input.row;

  // Floor margin guard — outermost ring is wall.
  if (col < 1 ||
      col >= input.gridCols - 1 ||
      row < 1 ||
      row >= input.gridRows - 1) {
    return const TapNoOp();
  }

  final placedHit =
      hitTestPlacedFurniture(col, row, input.placedFurniture, input.lookupItem);

  // ── Held placed furniture (move flow) ──────────────────────────────────
  if (input.heldPlacedIndex != null) {
    final heldIdx = input.heldPlacedIndex!;
    if (placedHit == heldIdx) {
      return const TapReleaseHold();
    }
    if (placedHit != null) {
      return TapPickUp(placedHit);
    }
    // Stale hold (item gone) — widget releases without mutating.
    if (heldIdx < 0 || heldIdx >= input.placedFurniture.length) {
      return const TapReleaseStaleHold();
    }
    final old = input.placedFurniture[heldIdx];
    final item = input.lookupItem(old.itemId);
    if (item == null) return const TapReleaseStaleHold();
    final ok = canPlaceFurnitureAt(
      col: col,
      row: row,
      item: item,
      gridCols: input.gridCols,
      gridRows: input.gridRows,
      blockedTiles: input.blockedTiles,
      placedFurniture: input.placedFurniture,
      lookupItem: input.lookupItem,
      excludePlacedIndex: heldIdx,
    );
    if (!ok) return const TapNoOp();
    return TapMoveHere(heldIdx, col, row);
  }

  // ── Selected inventory item (placement flow) ───────────────────────────
  if (input.selectedFurnitureId != null) {
    if (placedHit != null) {
      return TapPickUp(placedHit);
    }
    final item = input.lookupItem(input.selectedFurnitureId!);
    if (item == null) return const TapNoOp();
    final ok = canPlaceFurnitureAt(
      col: col,
      row: row,
      item: item,
      gridCols: input.gridCols,
      gridRows: input.gridRows,
      blockedTiles: input.blockedTiles,
      placedFurniture: input.placedFurniture,
      lookupItem: input.lookupItem,
    );
    if (!ok) return const TapNoOp();
    return TapPlaceFromInventory(input.selectedFurnitureId!, col, row);
  }

  // ── Empty hand: pick up furniture, or delete room ──────────────────────
  if (placedHit != null) {
    return TapPickUp(placedHit);
  }

  for (final room in input.placedRooms) {
    if (col >= room.col &&
        col < room.col + room.type.widthTiles &&
        row >= room.row &&
        row < room.row + room.type.heightTiles) {
      return TapRemoveRoom(room.id);
    }
  }

  return const TapNoOp();
}
