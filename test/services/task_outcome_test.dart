import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/task_outcome.dart';

void main() {
  group('bugChance', () {
    test('clamps to [0, 0.4]', () {
      expect(bugChance(precisionSkill: 0), 0.4);
      expect(bugChance(precisionSkill: 14), 0.0);
      expect(bugChance(precisionSkill: 7), closeTo(0.19, 1e-9));
      expect(bugChance(precisionSkill: 100), 0.0);
    });
  });

  group('critChance', () {
    test('is 0.02 * creativity', () {
      expect(critChance(creativitySkill: 0), 0.0);
      expect(critChance(creativitySkill: 10), closeTo(0.2, 1e-9));
    });

    test('clamps at 1.0', () {
      expect(critChance(creativitySkill: 100), 1.0);
    });
  });

  group('completionSuccessChance', () {
    test('starts at 0.85', () {
      expect(completionSuccessChance(reliabilitySkill: 0), 0.85);
    });

    test('caps at 1.0', () {
      expect(completionSuccessChance(reliabilitySkill: 100), 1.0);
    });

    test('reaches 1.0 by reliability 15', () {
      expect(completionSuccessChance(reliabilitySkill: 15), 1.0);
    });
  });

  group('rollOutcome', () {
    test('high-everything agent almost always gets clean', () {
      final rng = Random(1);
      var clean = 0;
      var incomplete = 0;
      for (var i = 0; i < 1000; i++) {
        final r = rollOutcome(
          rng: rng,
          precisionSkill: 10,
          creativitySkill: 0,
          reliabilitySkill: 15,
        );
        if (r == TaskOutcome.clean) clean++;
        if (r == TaskOutcome.incomplete) incomplete++;
      }
      expect(clean, greaterThan(850));
      expect(incomplete, 0);
    });

    test('low-reliability agent often incomplete', () {
      final rng = Random(1);
      var incomplete = 0;
      for (var i = 0; i < 1000; i++) {
        final r = rollOutcome(
          rng: rng,
          precisionSkill: 10,
          creativitySkill: 0,
          reliabilitySkill: 0,
        );
        if (r == TaskOutcome.incomplete) incomplete++;
      }
      // 0.85 success rate → ~15% incomplete
      expect(incomplete, greaterThan(100));
      expect(incomplete, lessThan(200));
    });

    test('low-precision agent often bugs', () {
      final rng = Random(1);
      var bugs = 0;
      for (var i = 0; i < 1000; i++) {
        final r = rollOutcome(
          rng: rng,
          precisionSkill: 0,
          creativitySkill: 0,
          reliabilitySkill: 15,
        );
        if (r == TaskOutcome.bug) bugs++;
      }
      // bug chance 0.4 × success 1.0 → ~40%
      expect(bugs, greaterThan(350));
      expect(bugs, lessThan(450));
    });

    test('crit only fires on divergent tasks', () {
      final rng = Random(1);
      var critsNonDiv = 0;
      for (var i = 0; i < 500; i++) {
        final r = rollOutcome(
          rng: rng,
          precisionSkill: 15,
          creativitySkill: 50,
          reliabilitySkill: 15,
          isDivergentTask: false,
        );
        if (r == TaskOutcome.crit) critsNonDiv++;
      }
      expect(critsNonDiv, 0);

      var critsDiv = 0;
      for (var i = 0; i < 500; i++) {
        final r = rollOutcome(
          rng: rng,
          precisionSkill: 15,
          creativitySkill: 50,
          reliabilitySkill: 15,
          isDivergentTask: true,
        );
        if (r == TaskOutcome.crit) critsDiv++;
      }
      expect(critsDiv, greaterThan(0));
    });

    test('divergentTaskTypes covers expected IDs', () {
      expect(divergentTaskTypes, containsAll({'architecture', 'product-spec', 'ui-design'}));
    });
  });
}
