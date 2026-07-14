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
}
