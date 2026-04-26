/**
 * Phase 4: Marketplace Quality Scoring tests
 *
 * Before an agent can be listed on marketplace, it must pass standardized
 * dungeon challenges and receive a quality score (0-100).
 *
 * Scoring prevents spam, ensures minimum viability, and provides
 * a transparent metric for buyers.
 *
 * Invariants:
 * - quality_score is deterministic (same agent, same challenges → same score)
 * - score is standardized (run on fixed challenges, not user's custom ones)
 * - minimum threshold (e.g., 60/100) required to list
 * - higher-skill agents score higher
 */

import { test } from "node:test";
import assert from "node:assert/strict";

// Mocked types
interface QualityChallenge {
  skillType: number;
  difficulty: 1 | 2 | 3;
  title: string;
}

interface ChallengeResult {
  challenge: QualityChallenge;
  agentScore: number; // 1-10 from judge
  points: number; // (difficulty * agentScore)
}

interface QualityReport {
  agentId: string;
  challengesRun: number;
  totalPoints: number;
  qualityScore: number; // 0-100, normalized
  passedMinimumThreshold: boolean;
  timestampIso: string;
  determinismHash: string; // for rerunning exact same evaluation
}

// Fixed set of challenges for quality evaluation (not user-customizable)
const QUALITY_CHALLENGES: QualityChallenge[] = [
  { skillType: 0, difficulty: 1, title: "String Reversal" },
  { skillType: 0, difficulty: 2, title: "Fibonacci" },
  { skillType: 1, difficulty: 1, title: "Magic Numbers Refactor" },
  { skillType: 1, difficulty: 2, title: "God Function Split" },
  { skillType: 2, difficulty: 1, title: "Basic Unit Test" },
];

const MINIMUM_QUALITY_THRESHOLD = 60;
const MAX_QUALITY_SCORE = 100;

// Helper: simulate agent run on challenges
function scoreAgent(
  agentId: string,
  simulatedScores: number[] // 1-10 for each challenge
): QualityReport {
  const results: ChallengeResult[] = QUALITY_CHALLENGES.map(
    (challenge, idx) => ({
      challenge,
      agentScore: simulatedScores[idx] ?? 5,
      points: challenge.difficulty * (simulatedScores[idx] ?? 5),
    })
  );

  const totalPoints = results.reduce((sum, r) => sum + r.points, 0);
  const maxPoints = QUALITY_CHALLENGES.reduce(
    (sum, c) => sum + c.difficulty * 10,
    0
  ); // max possible
  const qualityScore = Math.round((totalPoints / maxPoints) * MAX_QUALITY_SCORE);

  // Determinism hash: same input → same output (testable)
  const hashInput = JSON.stringify({ agentId, simulatedScores });
  const determinismHash = hashInput
    .split("")
    .reduce((h, c) => h + c.charCodeAt(0), 0)
    .toString(16);

  return {
    agentId,
    challengesRun: QUALITY_CHALLENGES.length,
    totalPoints,
    qualityScore,
    passedMinimumThreshold: qualityScore >= MINIMUM_QUALITY_THRESHOLD,
    timestampIso: new Date().toISOString(),
    determinismHash,
  };
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Quality Scoring — uses fixed standardized challenges", () => {
  assert.ok(QUALITY_CHALLENGES.length > 0);
  assert.ok(QUALITY_CHALLENGES.length <= 10, "reasonable number of challenges");

  for (const challenge of QUALITY_CHALLENGES) {
    assert.ok(challenge.skillType >= 0 && challenge.skillType <= 4);
    assert.ok([1, 2, 3].includes(challenge.difficulty));
  }
});

test("Quality Scoring — minimum threshold is set (e.g., 60/100)", () => {
  assert.equal(MINIMUM_QUALITY_THRESHOLD, 60);
  assert.ok(
    MINIMUM_QUALITY_THRESHOLD < MAX_QUALITY_SCORE,
    "threshold < max"
  );
});

test("Quality Scoring — perfect agent (10/10 on all) reaches 100", () => {
  const perfectScores = Array(QUALITY_CHALLENGES.length).fill(10);
  const report = scoreAgent("perfect-coder", perfectScores);

  assert.equal(report.qualityScore, 100);
  assert.ok(report.passedMinimumThreshold);
});

test("Quality Scoring — poor agent (1-2/10 all) fails threshold", () => {
  const poorScores = [1, 2, 1, 2, 1];
  const report = scoreAgent("poor-coder", poorScores);

  assert.ok(report.qualityScore < MINIMUM_QUALITY_THRESHOLD);
  assert.equal(report.passedMinimumThreshold, false);
});

test("Quality Scoring — average agent (5-6/10) borderline passes", () => {
  const averageScores = [5, 6, 5, 6, 5];
  const report = scoreAgent("average-coder", averageScores);

  // 5-6 range should be around 50-60, borderline or slightly above
  assert.ok(
    Math.abs(report.qualityScore - 55) < 10,
    "average agent should score ~50-60"
  );
});

test("Quality Scoring — deterministic: same agent → same score on rerun", () => {
  const scores = [7, 8, 6, 7, 8];
  const report1 = scoreAgent("coder#1", scores);
  const report2 = scoreAgent("coder#1", scores);

  assert.equal(report1.qualityScore, report2.qualityScore);
  assert.equal(report1.determinismHash, report2.determinismHash);
});

test("Quality Scoring — different agents produce different scores", () => {
  const report1 = scoreAgent("coder#1", [9, 9, 9, 9, 9]);
  const report2 = scoreAgent("coder#2", [3, 3, 3, 3, 3]);

  assert.notEqual(report1.qualityScore, report2.qualityScore);
  assert.ok(report1.qualityScore > report2.qualityScore);
});

test("Quality Scoring — points scale with difficulty (hard tasks worth more)", () => {
  const easyChallenge: QualityChallenge = {
    skillType: 0,
    difficulty: 1,
    title: "Easy",
  };
  const hardChallenge: QualityChallenge = {
    skillType: 0,
    difficulty: 3,
    title: "Hard",
  };
  const score = 8;

  const easyPoints = easyChallenge.difficulty * score;
  const hardPoints = hardChallenge.difficulty * score;

  assert.equal(easyPoints, 8);
  assert.equal(hardPoints, 24);
  assert.ok(hardPoints > easyPoints);
});

test("Quality Scoring — report includes metadata for audit trail", () => {
  const report = scoreAgent("audit-test", [6, 6, 6, 6, 6]);

  assert.ok(report.agentId);
  assert.ok(report.challengesRun > 0);
  assert.ok(report.qualityScore >= 0 && report.qualityScore <= 100);
  assert.ok(report.timestampIso);
  assert.ok(report.determinismHash);
});

test("Quality Scoring — score monotonicity: higher all-scores → higher quality", () => {
  const low = scoreAgent("low", [3, 3, 3, 3, 3]);
  const mid = scoreAgent("mid", [5, 5, 5, 5, 5]);
  const high = scoreAgent("high", [8, 8, 8, 8, 8]);

  assert.ok(low.qualityScore <= mid.qualityScore);
  assert.ok(mid.qualityScore <= high.qualityScore);
});
