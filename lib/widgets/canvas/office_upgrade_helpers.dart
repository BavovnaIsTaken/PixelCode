/// Pure helpers extracted from `office_upgrade_dialog.dart` so the next-tier
/// resolver, upgrade-cost computation and number formatting can be unit
/// tested without rendering the dialog.
///
/// The dialog still owns its own `_formatNumber` for backward compatibility;
/// new callers should prefer [formatGrymniShort] and the resolver helpers
/// below.
library;

import '../../models/game_economy.dart';

/// Compact "Kk"-style number formatter used by the upgrade dialog.
///
/// * Values < 1000 are returned as-is.
/// * Round multiples of 1000 are rendered without a fractional part
///   (`1000 → '1K'`, `8000 → '8K'`).
/// * Other values fall back to one fractional digit (`1500 → '1.5K'`).
String formatGrymniShort(int n) {
  if (n >= 1000) {
    final k = n / 1000;
    return k % 1 == 0 ? '${k.toStringAsFixed(0)}K' : '${k.toStringAsFixed(1)}K';
  }
  return n.toString();
}

/// What the upgrade button should look like for the given economy snapshot.
enum UpgradeButtonState {
  /// Player can afford the next tier and it isn't WIP — surface as the
  /// gold "Переїхати" CTA.
  upgradeAffordable,

  /// Next tier exists but the player can't afford it — disabled chip.
  upgradeUnaffordable,

  /// Next tier is gated behind "В розробці" — chip reads "СКОРО".
  comingSoon,

  /// No next tier — the player is on the top tier.
  alreadyMaxed,
}

UpgradeButtonState upgradeButtonStateFor({
  required OfficeLevel current,
  required int grymni,
}) {
  final next = current.nextLevel;
  if (next == null) return UpgradeButtonState.alreadyMaxed;
  if (next.isWipComingSoon) return UpgradeButtonState.comingSoon;
  if (grymni < next.upgradeCost) return UpgradeButtonState.upgradeUnaffordable;
  return UpgradeButtonState.upgradeAffordable;
}

/// Mirror of `GameEconomyNotifier.canUpgradeOffice`, expressed as a pure
/// function so widgets/tests don't need to instantiate the notifier.
bool canUpgradeFromState({required OfficeLevel current, required int grymni}) =>
    upgradeButtonStateFor(current: current, grymni: grymni) ==
    UpgradeButtonState.upgradeAffordable;

/// What the "+ ₲N" expansion chip on the current-tier card should look like.
enum ExpansionButtonState {
  /// Tier still has expansion steps left and the player can afford the next.
  buyAffordable,

  /// Next step exists but the player can't afford it — disabled chip.
  buyUnaffordable,

  /// Tier is fully expanded — no chip rendered.
  fullyExpanded,
}

ExpansionButtonState expansionButtonStateFor({
  required OfficeLevel current,
  required int expansionsBought,
  required int grymni,
}) {
  final steps = current.expansions;
  if (expansionsBought >= steps.length) return ExpansionButtonState.fullyExpanded;
  final cost = steps[expansionsBought].cost;
  return grymni >= cost
      ? ExpansionButtonState.buyAffordable
      : ExpansionButtonState.buyUnaffordable;
}

/// Cost of the next expansion step at [current], or `null` if the tier is
/// already maxed.
int? nextExpansionCost({
  required OfficeLevel current,
  required int expansionsBought,
}) {
  final steps = current.expansions;
  if (expansionsBought >= steps.length) return null;
  return steps[expansionsBought].cost;
}
