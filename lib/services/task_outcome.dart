/// Pure functions that roll a task's final outcome based on agent skills.
///
/// Agents stop being defined by levels alone — the outcome roll is where
/// Precision/Creativity/Reliability skills express themselves as real
/// gameplay consequences (bug bounce, crit gold, incomplete reset).
library;

import 'dart:math';

enum TaskOutcome {
  /// Task moves `testing → done`. Normal reward.
  clean,

  /// Task moves `testing → done` AND awards a gold bonus.
  /// Rolled only on divergent task types (`taskType` in
  /// `{architecture, product-spec, ui-design}`).
  crit,

  /// Task bounces `testing → in-progress` (bug was found). Half XP.
  bug,

  /// Task is reset back to `backlog`. Half XP; agent may pick it up again.
  incomplete,
}

/// `0.4 - 0.03 * precisionSkill`, clamped to `[0, 0.4]`.
/// * Precision 0 → 40% bug chance.
/// * Precision 7 → 19%.
/// * Precision 14+ → 0%.
double bugChance({required int precisionSkill}) =>
    (0.4 - 0.03 * precisionSkill).clamp(0.0, 0.4);

/// `0.02 * creativitySkill`, clamped to `[0, 1]`.
/// Only relevant on divergent task types (gated in [rollOutcome]).
double critChance({required int creativitySkill}) =>
    (0.02 * creativitySkill).clamp(0.0, 1.0);

/// `0.85 + 0.01 * reliabilitySkill`, clamped to `[0, 1]`.
/// * Reliability 0 → 15% chance of incomplete.
/// * Reliability 15+ → 0%.
double completionSuccessChance({required int reliabilitySkill}) =>
    (0.85 + 0.01 * reliabilitySkill).clamp(0.0, 1.0);

/// Task-type identifiers considered divergent (where creativity matters).
const divergentTaskTypes = <String>{
  'architecture',
  'product-spec',
  'ui-design',
};

/// Task types that require a physical workstation (computer). Agents without
/// an assigned desk suffer an incomplete-chance penalty on these.
const workstationTaskTypes = <String>{
  'coding',
  'testing',
  'debugging',
};

/// Penalty applied to [completionSuccessChance] when an agent has no desk
/// and is working on a [workstationTaskTypes] task. −0.25 success rate.
const double kUnassignedIncompletePenalty = 0.25;

/// Hard cap on the aggregate specialization crit bonus applied inside
/// [rollOutcome]. Mirrors `kMaxSpecializationCritBonus` in game_economy.dart;
/// duplicated here because [rollOutcome] is intentionally dependency-free
/// (no model imports). Keep the two values in sync.
const double kMaxSpecializationCritBonusInRoll = 0.30;

/// Rolls the final outcome for a task at the `testing → done` transition.
///
/// Order of checks:
/// 1. Reliability gate (incomplete if we roll above the success threshold).
///    Agents without a workstation on [workstationTaskTypes] suffer a −0.25
///    penalty to their success chance.
/// 2. Bug check (Precision).
/// 3. Crit check (Creativity + specialization, divergent tasks only).
/// 4. Otherwise `clean`.
///
/// [specializationCritBonus] is the additive crit bonus from this agent's
/// unlocked specializations matching the current `taskType`. Caller computes
/// it; this function just clamps it defensively and folds it into the
/// crit chance.
///
/// [rng] is injectable for deterministic tests.
TaskOutcome rollOutcome({
  required Random rng,
  required int precisionSkill,
  required int creativitySkill,
  required int reliabilitySkill,
  bool isDivergentTask = false,
  bool isUnassigned = false,
  String taskType = '',
  double specializationCritBonus = 0.0,
}) {
  final baseSuccess = completionSuccessChance(reliabilitySkill: reliabilitySkill);
  final needsDesk = isUnassigned && workstationTaskTypes.contains(taskType);
  final adjustedSuccess = needsDesk
      ? (baseSuccess - kUnassignedIncompletePenalty).clamp(0.0, 1.0)
      : baseSuccess;

  if (rng.nextDouble() > adjustedSuccess) {
    return TaskOutcome.incomplete;
  }
  if (rng.nextDouble() < bugChance(precisionSkill: precisionSkill)) {
    return TaskOutcome.bug;
  }
  if (isDivergentTask) {
    final base = critChance(creativitySkill: creativitySkill);
    final bonus =
        specializationCritBonus.clamp(0.0, kMaxSpecializationCritBonusInRoll);
    if (rng.nextDouble() < (base + bonus).clamp(0.0, 1.0)) {
      return TaskOutcome.crit;
    }
  }
  return TaskOutcome.clean;
}
