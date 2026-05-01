import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/growth_telemetry.dart';

void main() {
  group('growth_telemetry — "grown vs raw" delta validation', () {
    // Representative Lv10 coder profile: mid-range skills at Lv10.
    // skillCap(10) = 10 + 2*10 = 30, so [8, 6, 8] is reasonable.
    const baseProfile = AgentProfile(
      precisionSkill: 8,
      creativitySkill: 6,
      reliabilitySkill: 8,
    );

    const grownProfile = AgentProfile(
      precisionSkill: 8,
      creativitySkill: 6,
      reliabilitySkill: 8,
      lessonBonus: 0.10,
      specializationCritBonus: 0.30,
      projectMemoryBonus: 0.15,
    );

    const iterations = 5000;

    test('completion rate: grown > raw on standard task', () {
      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: grownProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: false,
      );

      expect(
        delta.completionRateDelta,
        greaterThanOrEqualTo(0.04),
        reason:
            'Lesson bonus should lift completion rate; delta=${delta.completionRateDelta.toStringAsFixed(3)}',
      );
    });

    test('incomplete rate: grown < raw on standard task', () {
      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: grownProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: false,
      );

      expect(
        delta.incompleteDelta,
        greaterThanOrEqualTo(0.04),
        reason:
            'Lesson bonus reduces incomplete rate; delta=${delta.incompleteDelta.toStringAsFixed(3)}',
      );
    });

    test('crit rate: grown >> raw on architecture divergent task', () {
      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: grownProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: true,
        taskType: 'architecture',
      );

      expect(
        delta.critRateDelta,
        greaterThanOrEqualTo(0.18),
        reason:
            'Spec bonus + memory bonus on architecture should boost crit significantly; '
            'delta=${delta.critRateDelta.toStringAsFixed(3)}',
      );
    });

    test('crit rate: grown >> raw on product-spec divergent task', () {
      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: grownProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: true,
        taskType: 'product-spec',
      );

      expect(
        delta.critRateDelta,
        greaterThanOrEqualTo(0.13),
        reason:
            'Spec bonus on product-spec should boost crit; '
            'delta=${delta.critRateDelta.toStringAsFixed(3)}',
      );
    });

    test('lesson-only bonus: isolated lesson effect on completion', () {
      final lessonOnlyProfile = AgentProfile(
        precisionSkill: 8,
        creativitySkill: 6,
        reliabilitySkill: 8,
        lessonBonus: 0.10,
      );

      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: lessonOnlyProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: false,
      );

      expect(
        delta.completionRateDelta,
        greaterThanOrEqualTo(0.04),
        reason:
            'Lesson bonus alone should improve completion; '
            'delta=${delta.completionRateDelta.toStringAsFixed(3)}',
      );
    });

    test('spec-only bonus: isolated spec effect on divergent crit', () {
      final specOnlyProfile = AgentProfile(
        precisionSkill: 8,
        creativitySkill: 6,
        reliabilitySkill: 8,
        specializationCritBonus: 0.30,
      );

      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: specOnlyProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: true,
        taskType: 'ui-design',
      );

      expect(
        delta.critRateDelta,
        greaterThanOrEqualTo(0.09),
        reason:
            'Spec bonus alone should improve crit on divergent tasks; '
            'delta=${delta.critRateDelta.toStringAsFixed(3)}',
      );
    });

    test('raw profile yields zero delta (sanity check)', () {
      final rng = Random(42);
      final delta = computeGrowthDelta(
        grownProfile: baseProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: false,
      );

      expect(
        delta.completionRateDelta,
        lessThan(0.01),
        reason:
            'No bonuses means delta ≈ 0; delta=${delta.completionRateDelta.toStringAsFixed(3)}',
      );
      expect(
        delta.critRateDelta,
        lessThan(0.01),
        reason: 'No bonuses means delta ≈ 0; delta=${delta.critRateDelta.toStringAsFixed(3)}',
      );
    });

    test('full grown profile achieves high completion rate floor', () {
      final rng = Random(42);
      final result = simulateOutcomes(
        profile: grownProfile,
        iterations: iterations,
        rng: rng,
        isDivergentTask: false,
      );

      // Completion is limited by: (1) not incomplete, (2) not bug.
      // adjustedSuccess = 0.85 + 0.01*8 + 0.10 = 1.0 (clamped) → 100% not incomplete
      // bugChance = 0.4 - 0.03*8 = 0.16 → 84% not bug
      // Combined: ≥83% completion floor.
      expect(
        result.completionRate,
        greaterThanOrEqualTo(0.83),
        reason:
            'Grown profile limited by bugChance; '
            'actual=${result.completionRate.toStringAsFixed(3)}',
      );
    });
  });
}
