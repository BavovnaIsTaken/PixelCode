/// Pure helpers extracted from `build_menu.dart` so the room/template
/// affordability logic can be unit-tested without spinning up the widget tree.
///
/// All functions in this file are **pure** — no Flutter imports, no Riverpod,
/// no global state. They take primitive inputs and return primitives or small
/// value objects. The widgets in `build_menu.dart` re-implement the same
/// branches inline today; future refactors should swap to these helpers
/// directly. For now they exist so the rules that drive enable/disable + cost
/// labels are testable on their own.
library;

import '../../models/game_economy.dart';

/// Hide luxury rooms in the garage tier — they don't fit anyway and seeing
/// them locked is more clutter than aspiration at the smallest grid. Keep
/// every other (room × tier) combination visible.
bool isRoomAvailableForTier(RoomType type, OfficeLevel tier) {
  if (type.isLuxury && tier == OfficeLevel.garage) return false;
  return true;
}

/// How many rooms of [type] are currently placed in the office.
int placedRoomCount(List<PlacedRoom> placed, RoomType type) =>
    placed.where((r) => r.type == type).length;

/// True when the player has already placed [type] up to its [maxPerOffice]
/// limit at the current tier.
bool roomAtCap(List<PlacedRoom> placed, RoomType type) =>
    placedRoomCount(placed, type) >= type.maxPerOffice;

/// Pricing breakdown for a single [RoomType] purchase.
class RoomCardStatus {
  const RoomCardStatus({
    required this.cost,
    required this.canAfford,
    required this.atCap,
  });

  final int cost;
  final bool canAfford;
  final bool atCap;

  /// The card is enabled (tap → start ghost) only when the player can both
  /// afford the room and has room under the per-tier cap.
  bool get available => canAfford && !atCap;
}

RoomCardStatus roomCardStatus({
  required RoomType type,
  required int grymni,
  required List<PlacedRoom> placed,
}) {
  return RoomCardStatus(
    cost: type.cost,
    canAfford: grymni >= type.cost,
    atCap: roomAtCap(placed, type),
  );
}

/// Pricing for a [RoomTemplate] (base room + furniture - bundle discount).
class TemplatePricing {
  const TemplatePricing({
    required this.raw,
    required this.bundle,
    required this.saved,
    required this.canAfford,
    required this.atCap,
  });

  final int raw;
  final int bundle;
  final int saved;
  final bool canAfford;
  final bool atCap;

  bool get available => canAfford && !atCap;
}

TemplatePricing templatePricing({
  required RoomTemplate template,
  required int grymni,
  required List<PlacedRoom> placed,
}) {
  final raw = template.rawCost(furnitureCatalog);
  final bundle = template.bundleCost(furnitureCatalog);
  return TemplatePricing(
    raw: raw,
    bundle: bundle,
    saved: raw - bundle,
    canAfford: grymni >= bundle,
    atCap: roomAtCap(placed, template.baseRoom),
  );
}
