/// Tests for the pure helpers carved out of `office_upgrade_dialog.dart`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/canvas/office_upgrade_helpers.dart';

void main() {
  group('formatGrymniShort', () {
    test('values < 1000 render as plain integers (edge)', () {
      expect(formatGrymniShort(0), '0');
      expect(formatGrymniShort(7), '7');
      expect(formatGrymniShort(999), '999');
    });

    test('round multiples of 1000 drop the fractional digit', () {
      expect(formatGrymniShort(1000), '1K');
      expect(formatGrymniShort(8000), '8K');
      expect(formatGrymniShort(50000), '50K');
      expect(formatGrymniShort(500000), '500K');
    });

    test('non-round values get one fractional digit', () {
      expect(formatGrymniShort(1500), '1.5K');
      expect(formatGrymniShort(2500), '2.5K');
      expect(formatGrymniShort(1234), '1.2K');
    });
  });

  group('upgradeButtonStateFor', () {
    test('garage → smallOffice with enough gold is affordable', () {
      final state = upgradeButtonStateFor(
        current: OfficeLevel.garage,
        grymni: OfficeLevel.smallOffice.upgradeCost,
      );
      expect(state, UpgradeButtonState.upgradeAffordable);
      expect(
        canUpgradeFromState(
          current: OfficeLevel.garage,
          grymni: OfficeLevel.smallOffice.upgradeCost,
        ),
        isTrue,
      );
    });

    test('one short of upgradeCost → unaffordable (negative + edge)', () {
      final state = upgradeButtonStateFor(
        current: OfficeLevel.garage,
        grymni: OfficeLevel.smallOffice.upgradeCost - 1,
      );
      expect(state, UpgradeButtonState.upgradeUnaffordable);
      expect(
        canUpgradeFromState(
          current: OfficeLevel.garage,
          grymni: OfficeLevel.smallOffice.upgradeCost - 1,
        ),
        isFalse,
      );
    });

    test('techHub → campus is comingSoon regardless of gold', () {
      final state = upgradeButtonStateFor(
        current: OfficeLevel.techHub,
        grymni: 1 << 30,
      );
      expect(state, UpgradeButtonState.comingSoon);
      expect(
        canUpgradeFromState(current: OfficeLevel.techHub, grymni: 1 << 30),
        isFalse,
      );
    });

    test('campus → already maxed (no nextLevel)', () {
      final state = upgradeButtonStateFor(
        current: OfficeLevel.campus,
        grymni: 1 << 30,
      );
      expect(state, UpgradeButtonState.alreadyMaxed);
      expect(
        canUpgradeFromState(current: OfficeLevel.campus, grymni: 1 << 30),
        isFalse,
      );
    });

    test('zero gold + non-WIP next tier → unaffordable (edge)', () {
      final state = upgradeButtonStateFor(
        current: OfficeLevel.garage,
        grymni: 0,
      );
      expect(state, UpgradeButtonState.upgradeUnaffordable);
    });
  });

  group('expansionButtonStateFor + nextExpansionCost', () {
    test('first step is affordable when gold matches exactly (edge)', () {
      final firstCost = OfficeLevel.garage.expansions.first.cost;
      final state = expansionButtonStateFor(
        current: OfficeLevel.garage,
        expansionsBought: 0,
        grymni: firstCost,
      );
      expect(state, ExpansionButtonState.buyAffordable);
      expect(
        nextExpansionCost(
          current: OfficeLevel.garage,
          expansionsBought: 0,
        ),
        firstCost,
      );
    });

    test('zero gold → buyUnaffordable while steps remain (negative)', () {
      final state = expansionButtonStateFor(
        current: OfficeLevel.garage,
        expansionsBought: 0,
        grymni: 0,
      );
      expect(state, ExpansionButtonState.buyUnaffordable);
    });

    test('after every step bought → fullyExpanded, cost is null', () {
      final stepCount = OfficeLevel.garage.expansions.length;
      final state = expansionButtonStateFor(
        current: OfficeLevel.garage,
        expansionsBought: stepCount,
        grymni: 1 << 30,
      );
      expect(state, ExpansionButtonState.fullyExpanded);
      expect(
        nextExpansionCost(
          current: OfficeLevel.garage,
          expansionsBought: stepCount,
        ),
        isNull,
      );
    });

    test('expansionsBought beyond cap is treated as fullyExpanded (edge)', () {
      final state = expansionButtonStateFor(
        current: OfficeLevel.garage,
        expansionsBought: OfficeLevel.garage.expansions.length + 5,
        grymni: 0,
      );
      expect(state, ExpansionButtonState.fullyExpanded);
    });

    test('cost matches catalog at the current step (positive)', () {
      for (var i = 0; i < OfficeLevel.smallOffice.expansions.length; i++) {
        expect(
          nextExpansionCost(
            current: OfficeLevel.smallOffice,
            expansionsBought: i,
          ),
          OfficeLevel.smallOffice.expansions[i].cost,
        );
      }
    });
  });
}
