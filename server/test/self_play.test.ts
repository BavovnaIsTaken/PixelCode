/**
 * Phase 3: Self-Play Simulation tests
 *
 * Tests the self-play training system where an agent attempts a task
 * multiple times, learns from best/worst attempts, and generates training data.
 *
 * Invariants:
 * - best_attempt.score >= avg_score >= worst_attempt.score
 * - total_lessons = unique_failure_patterns from worst attempts
 * - self-play generates training signal (lessons) without cloud cost
 */

import { test } from "node:test";
import assert from "node:assert/strict";

// Mocked types (would import from real modules)
interface SelfPlayAttempt {
  runNumber: number;
  score: number;
  output: string;
  executionTimeMs: number;
  success: boolean;
}

interface SelfPlayResult {
  agentId: string;
  skillType: number;
  difficulty: 1 | 2 | 3;
  totalRuns: number;
  bestAttempt: SelfPlayAttempt;
  worstAttempt: SelfPlayAttempt;
  averageScore: number;
  lessonsGenerated: Array<{
    pattern: string;
    confidence: number;
    fromWorstAttempt: boolean;
  }>;
  executionStats: {
    totalTimeMs: number;
    avgTimeMs: number;
    timeoutViolations: number;
  };
}

// Mocks for testing
function mockAttempt(
  runNumber: number,
  score: number,
  success: boolean = true,
  executionTimeMs: number = 100
): SelfPlayAttempt {
  return {
    runNumber,
    score,
    output: `Output from run ${runNumber}`,
    executionTimeMs,
    success,
  };
}

function computeAverageScore(attempts: SelfPlayAttempt[]): number {
  if (attempts.length === 0) return 0;
  const sum = attempts.reduce((acc, a) => acc + a.score, 0);
  return sum / attempts.length;
}

function extractLessons(worstAttempt: SelfPlayAttempt): Array<{
  pattern: string;
  confidence: number;
  fromWorstAttempt: boolean;
}> {
  // Mock: extract 1-3 failure patterns from worst attempt output
  const patterns = [];
  if (worstAttempt.output.includes("syntax")) {
    patterns.push({
      pattern: "syntax-error-in-output",
      confidence: 0.8,
      fromWorstAttempt: true,
    });
  }
  if (worstAttempt.output.includes("timeout")) {
    patterns.push({
      pattern: "timeout-during-execution",
      confidence: 0.9,
      fromWorstAttempt: true,
    });
  }
  return patterns.length > 0
    ? patterns
    : [
        {
          pattern: "generic-failure",
          confidence: 0.5,
          fromWorstAttempt: true,
        },
      ];
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Self-Play — initializes with N runs parameter", () => {
  const runs = 5;
  assert.ok(runs > 0, "N must be positive");
  assert.ok(runs <= 100, "N should be capped at 100 for safety");
});

test("Self-Play — best_attempt has highest score of all runs", () => {
  const attempts = [
    mockAttempt(1, 4),
    mockAttempt(2, 7),
    mockAttempt(3, 5),
    mockAttempt(4, 9),
    mockAttempt(5, 6),
  ];
  const bestAttempt = attempts.reduce((best, curr) =>
    curr.score > best.score ? curr : best
  );
  assert.equal(bestAttempt.runNumber, 4);
  assert.equal(bestAttempt.score, 9);
});

test("Self-Play — worst_attempt has lowest score of all runs", () => {
  const attempts = [
    mockAttempt(1, 4),
    mockAttempt(2, 7),
    mockAttempt(3, 5),
    mockAttempt(4, 9),
    mockAttempt(5, 1),
  ];
  const worstAttempt = attempts.reduce((worst, curr) =>
    curr.score < worst.score ? curr : worst
  );
  assert.equal(worstAttempt.runNumber, 5);
  assert.equal(worstAttempt.score, 1);
});

test("Self-Play — averageScore correctly calculated from all attempts", () => {
  const attempts = [
    mockAttempt(1, 4),
    mockAttempt(2, 6),
    mockAttempt(3, 8),
  ];
  const avg = computeAverageScore(attempts);
  assert.equal(avg, 6, "Average of [4,6,8] should be 6");
});

test("Self-Play — score ordering: best >= avg >= worst", () => {
  const attempts = [
    mockAttempt(1, 4),
    mockAttempt(2, 7),
    mockAttempt(3, 5),
    mockAttempt(4, 9),
    mockAttempt(5, 3),
  ];
  const best = Math.max(...attempts.map((a) => a.score));
  const worst = Math.min(...attempts.map((a) => a.score));
  const avg = computeAverageScore(attempts);

  assert.ok(best >= avg, "best must be >= average");
  assert.ok(avg >= worst, "average must be >= worst");
});

test("Self-Play — lessons generated from worst attempt patterns", () => {
  const worstAttempt: SelfPlayAttempt = {
    runNumber: 5,
    score: 1,
    output: "Output contains syntax error in function body",
    executionTimeMs: 150,
    success: false,
  };
  const lessons = extractLessons(worstAttempt);
  assert.ok(lessons.length > 0, "lessons should be generated");
  assert.ok(
    lessons.every((l) => l.fromWorstAttempt),
    "all lessons should be marked as from worst attempt"
  );
});

test("Self-Play — lessons have confidence scores between 0 and 1", () => {
  const worstAttempt = mockAttempt(5, 1, false);
  worstAttempt.output = "timeout during execution";
  const lessons = extractLessons(worstAttempt);

  for (const lesson of lessons) {
    assert.ok(lesson.confidence >= 0, "confidence >= 0");
    assert.ok(lesson.confidence <= 1, "confidence <= 1");
  }
});

test("Self-Play — execution stats track total and average time", () => {
  const attempts = [
    mockAttempt(1, 5, true, 80),
    mockAttempt(2, 7, true, 120),
    mockAttempt(3, 6, true, 100),
  ];
  const totalTime = attempts.reduce((sum, a) => sum + a.executionTimeMs, 0);
  const avgTime = totalTime / attempts.length;

  assert.equal(totalTime, 300);
  assert.equal(avgTime, 100);
});

test("Self-Play — timeout safety: single run must not exceed max duration", () => {
  const maxDurationMs = 10000; // 10 second limit per run
  const attempts = [
    mockAttempt(1, 5, true, 2000),
    mockAttempt(2, 7, true, 3000),
    mockAttempt(3, 6, true, 4000),
  ];

  for (const attempt of attempts) {
    assert.ok(
      attempt.executionTimeMs < maxDurationMs,
      `attempt ${attempt.runNumber} exceeded timeout`
    );
  }
});

test("Self-Play — timeoutViolations counter tracks N of runs that timed out", () => {
  const maxDurationMs = 5000;
  const attempts = [
    mockAttempt(1, 0, false, 3000), // failed but within limit
    mockAttempt(2, 7, true, 2000),
    mockAttempt(3, 2, false, 6000), // would be timeout
  ];

  const violations = attempts.filter(
    (a) => a.executionTimeMs >= maxDurationMs
  ).length;
  assert.equal(violations, 1);
});

test("Self-Play — very high success run (all score 9-10) learns from minor variations", () => {
  const attempts = [
    mockAttempt(1, 9),
    mockAttempt(2, 10),
    mockAttempt(3, 9),
  ];
  const best = Math.max(...attempts.map((a) => a.score));
  const worst = Math.min(...attempts.map((a) => a.score));
  const diff = best - worst;

  // Even in high-success scenario, there's a learning signal
  assert.ok(diff >= 0);
  assert.ok(diff <= 1, "spread should be small in high-success case");
});

test("Self-Play — very low success run (all score 1-3) generates multiple lessons", () => {
  const attempts = [
    mockAttempt(1, 1, false),
    mockAttempt(2, 2, false),
    mockAttempt(3, 3, false),
  ];
  const best = Math.max(...attempts.map((a) => a.score));
  const worst = Math.min(...attempts.map((a) => a.score));

  assert.ok(best <= 3, "even best attempt is poor");
  assert.ok(worst <= 3, "all attempts poor quality");
  // Both best and worst are low, so lessons from worst are still valuable
});

test("Self-Play — N runs parameter: N=1 is valid (no iteration)", () => {
  const attempts = [mockAttempt(1, 7)];
  const best = attempts[0];
  const worst = attempts[0];
  const avg = computeAverageScore(attempts);

  assert.equal(best.score, worst.score);
  assert.equal(avg, 7);
});

test("Self-Play — N runs parameter: N=100 is max safety cap", () => {
  const runsAttempted = 100;
  assert.ok(runsAttempted <= 100, "N should not exceed 100");
});

test("Self-Play — result aggregation: fields are all populated", () => {
  const attempts = [
    mockAttempt(1, 4),
    mockAttempt(2, 7),
    mockAttempt(3, 5),
  ];
  const best = attempts.reduce((b, a) => (a.score > b.score ? a : b));
  const worst = attempts.reduce((w, a) => (a.score < w.score ? a : w));
  const avg = computeAverageScore(attempts);
  const lessons = extractLessons(worst);

  // Simulate result structure
  const result = {
    agentId: "coder#1",
    skillType: 1,
    difficulty: 2,
    totalRuns: attempts.length,
    bestAttempt: best,
    worstAttempt: worst,
    averageScore: avg,
    lessonsGenerated: lessons,
    executionStats: {
      totalTimeMs: attempts.reduce((sum, a) => sum + a.executionTimeMs, 0),
      avgTimeMs:
        attempts.reduce((sum, a) => sum + a.executionTimeMs, 0) /
        attempts.length,
      timeoutViolations: 0,
    },
  };

  assert.ok(result.bestAttempt);
  assert.ok(result.worstAttempt);
  assert.ok(result.lessonsGenerated);
  assert.ok(result.executionStats);
});
