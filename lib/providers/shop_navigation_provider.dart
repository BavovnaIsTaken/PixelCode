/// Lightweight deep-link provider for navigating to a specific shop tab,
/// plus shared state for the in-canvas placement/edit flow.
///
/// Placement model has three orthogonal states, intentionally kept as
/// separate `StateProvider`s so write-sites coordinate them explicitly:
///   * [furnitureEditModeProvider] — пенцил-toggle. Truthy whenever the user
///     is in "manipulate placed objects" mode (delete + move + place picked).
///     Independent of selection so the pencil button can toggle delete-only
///     mode without forcing the player to pick an inventory item first.
///   * [selectedFurnitureIdProvider] — an inventory item is "in hand",
///     waiting to be placed on the grid.
///   * [heldPlacedFurnitureIndexProvider] — an already-placed furniture
///     item is "picked up" from the grid, waiting to be re-dropped at a
///     new tile (the move flow).
///
/// Invariants enforced at write-sites:
///   * setting [selectedFurnitureIdProvider] non-null clears
///     [heldPlacedFurnitureIndexProvider] and forces edit mode on.
///   * setting [heldPlacedFurnitureIndexProvider] non-null clears
///     [selectedFurnitureIdProvider] and forces edit mode on.
///   * turning [furnitureEditModeProvider] off clears both above so we never
///     "leak" a picked-up item into a hidden mode.
///
/// Use [FurnitureEditModeCoord] to perform the coordinated transitions —
/// it works with both `WidgetRef` and `Ref` (and `ProviderContainer` in
/// tests) via the shared `Refable` shim.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab indices in ShopPanel. Furniture tab was migrated to BuildMenu's
/// Decor section in Stage 2 of the Build System rework — its index is gone.
/// "Печатка" (premium send-button stamps) sits at index 4, before Donation.
const shopTabOffice = 2;
const shopTabStamp = 4;
const shopTabDonation = 5;

/// When non-null, consumers should navigate to the given shop tab index
/// and then reset this back to null.
final shopDeepLinkProvider = StateProvider<int?>((ref) => null);

/// The furniture item ID currently selected for placement from inventory
/// (null = none).
final selectedFurnitureIdProvider = StateProvider<String?>((ref) => null);

/// Index into `GameState.placedFurniture` of an item the player picked up
/// from the grid to move (null = none).
final heldPlacedFurnitureIndexProvider = StateProvider<int?>((ref) => null);

/// True whenever the player is in placement/manipulation mode. Independent
/// from selection so the pencil button can flip it without forcing an
/// inventory pick first. See [FurnitureEditModeCoord] for the coordinated
/// transitions.
final furnitureEditModeProvider = StateProvider<bool>((ref) => false);

/// Coordinated transitions for the placement/edit triple. Static methods
/// (no instances) — semantic grouping only.
class FurnitureEditModeCoord {
  FurnitureEditModeCoord._();

  /// Activate an inventory item for placement, coordinated with edit mode
  /// and the move-hold so the three providers stay coherent.
  static void enterPlacement(WidgetRef ref, String itemId) {
    ref.read(selectedFurnitureIdProvider.notifier).state = itemId;
    ref.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
    ref.read(furnitureEditModeProvider.notifier).state = true;
  }

  /// Pick up an already-placed furniture item to move it elsewhere.
  static void enterMove(WidgetRef ref, int placedIndex) {
    ref.read(heldPlacedFurnitureIndexProvider.notifier).state = placedIndex;
    ref.read(selectedFurnitureIdProvider.notifier).state = null;
    ref.read(furnitureEditModeProvider.notifier).state = true;
  }

  /// Enter edit mode without any item in hand — pencil-button entry point.
  /// Lets the player tap to delete / pick-up without first selecting from
  /// the Декор list.
  static void enterEmpty(WidgetRef ref) {
    ref.read(selectedFurnitureIdProvider.notifier).state = null;
    ref.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
    ref.read(furnitureEditModeProvider.notifier).state = true;
  }

  /// Leave edit mode and drop everything in hand. Single canonical exit so
  /// callers don't have to remember the three resets.
  static void exit(WidgetRef ref) {
    ref.read(selectedFurnitureIdProvider.notifier).state = null;
    ref.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
    ref.read(furnitureEditModeProvider.notifier).state = false;
  }

  /// Drop just the "in-hand" item without leaving edit mode. Used by the
  /// canvas to cancel a pick-up via tapping the same tile.
  static void releaseHold(WidgetRef ref) {
    ref.read(selectedFurnitureIdProvider.notifier).state = null;
    ref.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
  }
}

/// Test-only mirror of [FurnitureEditModeCoord] that operates on a
/// [ProviderContainer]. The widget paths use the WidgetRef methods above
/// and never enter these — but ProviderContainer tests should call these
/// to exercise the exact same coordination invariants.
class FurnitureEditModeCoordContainer {
  FurnitureEditModeCoordContainer._();

  static void enterPlacement(ProviderContainer c, String itemId) {
    c.read(selectedFurnitureIdProvider.notifier).state = itemId;
    c.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
    c.read(furnitureEditModeProvider.notifier).state = true;
  }

  static void enterMove(ProviderContainer c, int placedIndex) {
    c.read(heldPlacedFurnitureIndexProvider.notifier).state = placedIndex;
    c.read(selectedFurnitureIdProvider.notifier).state = null;
    c.read(furnitureEditModeProvider.notifier).state = true;
  }

  static void enterEmpty(ProviderContainer c) {
    c.read(selectedFurnitureIdProvider.notifier).state = null;
    c.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
    c.read(furnitureEditModeProvider.notifier).state = true;
  }

  static void exit(ProviderContainer c) {
    c.read(selectedFurnitureIdProvider.notifier).state = null;
    c.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
    c.read(furnitureEditModeProvider.notifier).state = false;
  }

  static void releaseHold(ProviderContainer c) {
    c.read(selectedFurnitureIdProvider.notifier).state = null;
    c.read(heldPlacedFurnitureIndexProvider.notifier).state = null;
  }
}
