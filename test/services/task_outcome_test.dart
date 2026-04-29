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

    test('workstationTaskTypes covers coding/testing/debugging', () {
      expect(workstationTaskTypes, containsAll({'coding', 'testing', 'debugging'}));
    });

    test('unassigned agent on coding task has higher incomplete rate', () {
      final rng = Random(42);
      var incompleteAssigned = 0;
      var incompleteUnassigned = 0;
      const n = 2000;
      for (var i = 0; i < n; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
              taskType: 'coding',
              isUnassigned: false,
            ) ==
            TaskOutcome.incomplete) {
          incompleteAssigned++;
        }
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
              taskType: 'coding',
              isUnassigned: true,
            ) ==
            TaskOutcome.incomplete) {
          incompleteUnassigned++;
        }
      }
      // Unassigned penalty (−0.25 success) must produce more incompletes.
      expect(incompleteUnassigned, greaterThan(incompleteAssigned));
    });

    test('unassigned penalty does NOT apply on non-workstation tasks', () {
      // For a task like "architecture", isUnassigned should have no extra effect.
      final rng = Random(7);
      var incompleteAssigned = 0;
      var incompleteUnassigned = 0;
      const n = 2000;
      for (var i = 0; i < n; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
              taskType: 'architecture',
              isUnassigned: false,
            ) ==
            TaskOutcome.incomplete) {
          incompleteAssigned++;
        }
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
              taskType: 'architecture',
              isUnassigned: true,
            ) ==
            TaskOutcome.incomplete) {
          incompleteUnassigned++;
        }
      }
      // Without the penalty the two distributions should be within normal
      // statistical noise (~5% tolerance on 2000 samples).
      final diff = (incompleteUnassigned - incompleteAssigned).abs();
      expect(diff, lessThan(n * 0.05));
    });

    test('high-reliability unassigned agent on coding task still completes', () {
      // reliabilitySkill 15 → success 1.0; penalty −0.25 → 0.75 still > 0.
      final rng = Random(99);
      var incomplete = 0;
      for (var i = 0; i < 1000; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 15,
              taskType: 'coding',
              isUnassigned: true,
            ) ==
            TaskOutcome.incomplete) {
          incomplete++;
        }
      }
      // ~25% incomplete expected, not 0 and not all.
      expect(incomplete, greaterThan(180));
      expect(incomplete, lessThan(320));
    });

    test('specialization bonus raises crit rate on divergent tasks', () {
      final rng = Random(11);
      var crits = 0;
      var critsBaseline = 0;
      const n = 4000;
      for (var i = 0; i < n; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 15,
              creativitySkill: 5,
              reliabilitySkill: 15,
              isDivergentTask: true,
              specializationCritBonus: 0.15,
            ) ==
            TaskOutcome.crit) {
          crits++;
        }
        if (rollOutcome(
              rng: rng,
              precisionSkill: 15,
              creativitySkill: 5,
              reliabilitySkill: 15,
              isDivergentTask: true,
            ) ==
            TaskOutcome.crit) {
          critsBaseline++;
        }
      }
      // base critChance(5) = 0.10; with +0.15 bonus → 0.25.
      // Bonus run must be meaningfully higher (delta well above noise).
      expect(crits - critsBaseline, greaterThan(n * 0.08));
    });

    test('specialization bonus does NOT fire on non-divergent tasks', () {
      final rng = Random(13);
      var crits = 0;
      for (var i = 0; i < 1000; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 15,
              creativitySkill: 50,
              reliabilitySkill: 15,
              isDivergentTask: false,
              specializationCritBonus: 0.30,
            ) ==
            TaskOutcome.crit) {
          crits++;
        }
      }
      expect(crits, 0);
    });

    test('specialization bonus is capped at kMaxSpecializationCritBonusInRoll',
        () {
      // Pass an absurd bonus; effective contribution must equal the cap.
      // base critChance(0) = 0; with cap = 0.30 → ~30% crit on divergent.
      final rng = Random(17);
      var crits = 0;
      const n = 4000;
      for (var i = 0; i < n; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 15,
              creativitySkill: 0,
              reliabilitySkill: 15,
              isDivergentTask: true,
              specializationCritBonus: 5.0, // wildly above the cap
            ) ==
            TaskOutcome.crit) {
          crits++;
        }
      }
      // Should sit around 30% (the cap), never near 100%.
      expect(crits, greaterThan(n * 0.22));
      expect(crits, lessThan(n * 0.38));
    });
  });

  group('lessonSuccessBonus', () {
    test('zero lessons yields no bonus', () {
      expect(lessonSuccessBonus(lessonCount: 0), 0.0);
    });

    test('scales at 0.005 per lesson', () {
      expect(lessonSuccessBonus(lessonCount: 10), closeTo(0.05, 1e-9));
      expect(lessonSuccessBonus(lessonCount: 20), closeTo(0.10, 1e-9));
    });

    test('caps at kMaxLessonSuccessBonusInRoll', () {
      expect(lessonSuccessBonus(lessonCount: 100), kMaxLessonSuccessBonusInRoll);
    });
  });

  group('rollOutcome — lesson bonus', () {
    test('lesson bonus reduces incomplete rate', () {
      final rng = Random(23);
      var incompleteNoLessons = 0;
      var incompleteMaxLessons = 0;
      const n = 4000;
      for (var i = 0; i < n; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
            ) ==
            TaskOutcome.incomplete) {
          incompleteNoLessons++;
        }
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
              lessonBonus: kMaxLessonSuccessBonusInRoll,
            ) ==
            TaskOutcome.incomplete) {
          incompleteMaxLessons++;
        }
      }
      // With max lesson bonus the agent should have meaningfully fewer incompletes.
      expect(incompleteNoLessons, greaterThan(incompleteMaxLessons));
      expect(incompleteNoLessons - incompleteMaxLessons, greaterThan(n * 0.04));
    });

    test('lesson bonus is capped at kMaxLessonSuccessBonusInRoll', () {
      // reliability=0 → base 0.85; cap adds at most +0.10 → 0.95 success.
      // Incomplete rate ~5%, never near 0% (uncapped) or 15% (no bonus).
      final rng = Random(29);
      var incomplete = 0;
      const n = 4000;
      for (var i = 0; i < n; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 10,
              creativitySkill: 0,
              reliabilitySkill: 0,
              lessonBonus: 99.0,
            ) ==
            TaskOutcome.incomplete) {
          incomplete++;
        }
      }
      expect(incomplete, greaterThan(n * 0.02));
      expect(incomplete, lessThan(n * 0.10));
    });

    test('lesson bonus does NOT produce crits on non-divergent tasks', () {
      final rng = Random(37);
      var crits = 0;
      for (var i = 0; i < 1000; i++) {
        if (rollOutcome(
              rng: rng,
              precisionSkill: 0,
              creativitySkill: 50,
              reliabilitySkill: 15,
              isDivergentTask: false,
              lessonBonus: kMaxLessonSuccessBonusInRoll,
            ) ==
            TaskOutcome.crit) {
          crits++;
        }
      }
      expect(crits, 0);
    });
  });
}
