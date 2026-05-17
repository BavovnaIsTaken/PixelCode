/// Monte Carlo simulation proving "grown" (with accumulated context) agents
/// meaningfully outperform "raw" (baseline) agents at the same level/skills.
library;

import 'dart:math';

import 'package:pixelcode/services/task_outcome.dart';

class AgentProfile {
  final int precisionSkill;
  final int creativitySkill;
  final int reliabilitySkill;
  final double lessonBonus;
  final double specializationCritBonus;
  final double projectMemoryBonus;

  const AgentProfile({
    required this.precisionSkill,
    required this.creativitySkill,
    required this.reliabilitySkill,
    this.lessonBonus = 0.0,
    this.specializationCritBonus = 0.0,
    this.projectMemoryBonus = 0.0,
  });

  AgentProfile get asRaw => AgentProfile(
        precisionSkill: precisionSkill,
        creativitySkill: creativitySkill,
        reliabilitySkill: reliabilitySkill,
      );
}

class SimulationResult {
  final int iterations;
  final int cleanCount;
  final int critCount;
  final int bugCount;
  final int incompleteCount;

  const SimulationResult({
    required this.iterations,
    required this.cleanCount,
    required this.critCount,
    required this.bugCount,
    required this.incompleteCount,
  });

  double get completionRate => (cleanCount + critCount) / iterations;
  double get critRate => critCount / iterations;
  double get bugRate => bugCount / iterations;
  double get incompleteRate => incompleteCount / iterations;

  @override
  String toString() =>
      'SimulationResult(n=$iterations, completion=${(completionRate * 100).toStringAsFixed(1)}%, '
      'crit=${(critRate * 100).toStringAsFixed(1)}%, '
      'bug=${(bugRate * 100).toStringAsFixed(1)}%, '
      'incomplete=${(incompleteRate * 100).toStringAsFixed(1)}%)';
}

class GrowthDelta {
  final SimulationResult raw;
  final SimulationResult grown;

  const GrowthDelta({required this.raw, required this.grown});

  double get completionRateDelta => grown.completionRate - raw.completionRate;
  double get critRateDelta => grown.critRate - raw.critRate;
  double get incompleteDelta => raw.incompleteRate - grown.incompleteRate;

  @override
  String toString() =>
      'GrowthDelta(completion+${(completionRateDelta * 100).toStringAsFixed(1)}%, '
      'crit+${(critRateDelta * 100).toStringAsFixed(1)}%, '
      'incomplete-${(incompleteDelta * 100).toStringAsFixed(1)}%)';
}

SimulationResult simulateOutcomes({
  required AgentProfile profile,
  required int iterations,
  required Random rng,
  bool isDivergentTask = false,
  String taskType = '',
}) {
  int clean = 0, crit = 0, bug = 0, incomplete = 0;

  for (var i = 0; i < iterations; i++) {
    final outcome = rollOutcome(
      rng: rng,
      precisionSkill: profile.precisionSkill,
      creativitySkill: profile.creativitySkill,
      reliabilitySkill: profile.reliabilitySkill,
      isDivergentTask: isDivergentTask,
      taskType: taskType,
      lessonBonus: profile.lessonBonus,
      specializationCritBonus: profile.specializationCritBonus,
      projectMemoryBonus: profile.projectMemoryBonus,
    );

    switch (outcome) {
      case TaskOutcome.clean:
        clean++;
      case TaskOutcome.crit:
        crit++;
      case TaskOutcome.bug:
        bug++;
      case TaskOutcome.incomplete:
        incomplete++;
    }
  }

  return SimulationResult(
    iterations: iterations,
    cleanCount: clean,
    critCount: crit,
    bugCount: bug,
    incompleteCount: incomplete,
  );
}

GrowthDelta computeGrowthDelta({
  required AgentProfile grownProfile,
  required int iterations,
  required Random rng,
  bool isDivergentTask = false,
  String taskType = '',
}) {
  final rawResult = simulateOutcomes(
    profile: grownProfile.asRaw,
    iterations: iterations,
    rng: rng,
    isDivergentTask: isDivergentTask,
    taskType: taskType,
  );

  final grownResult = simulateOutcomes(
    profile: grownProfile,
    iterations: iterations,
    rng: rng,
    isDivergentTask: isDivergentTask,
    taskType: taskType,
  );

  return GrowthDelta(raw: rawResult, grown: grownResult);
}
