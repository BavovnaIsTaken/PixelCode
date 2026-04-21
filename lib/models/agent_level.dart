/// Pure level/XP/skill-cap functions for agents.
library;

import 'dart:math';

/// Maximum level an agent can reach. Beyond this, XP is no-op and the
/// skill cap does not grow.
const int maxAgentLevel = 20;

/// XP required to advance from [level] to [level + 1].
/// Formula: `50 * level^1.6`. Floored to int.
///
/// Examples (actual values):
/// * Lv 1 → 50
/// * Lv 2 → 151
/// * Lv 10 → 1991
/// * Lv 20 → 6062
int xpToNextLevel(int level) {
  final n = level.clamp(1, maxAgentLevel).toDouble();
  return (50 * pow(n, 1.6)).floor();
}

/// Maximum value each skill can be upgraded to at [level].
/// Formula: `10 + 2 * level`.
/// Lv 1 → 12; Lv 5 → 20; Lv 20 → 50.
int skillCap(int level) => 10 + 2 * level.clamp(1, maxAgentLevel);

/// XP awarded for completing a task.
///
/// Formula: `difficulty^2 * quality * diminishing * failureBonus`
///
/// * [difficulty] is clamped to 1-5.
/// * [quality] is typically 0.5 (bug), 1.0 (normal), 1.5 (clean).
/// * Diminishing returns: if the task is far below the agent's level
///   (difficulty + 3 < agentLevel), XP is multiplied by 0.25. This
///   discourages grinding trivial tasks on high-level agents.
/// * [recoveredFromFailure]: +20% XP for recovering from a prior incomplete.
int xpForTask({
  required int difficulty,
  required double quality,
  required int agentLevel,
  bool recoveredFromFailure = false,
}) {
  double xp = pow(difficulty.clamp(1, 5), 2).toDouble() * quality;
  if (difficulty + 3 < agentLevel) xp *= 0.25;
  if (recoveredFromFailure) xp *= 1.2;
  return xp.floor();
}
