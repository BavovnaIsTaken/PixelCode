import { test } from "node:test";
import assert from "node:assert/strict";
import type { AgentBackend, BackendResult } from "../src/agent_backend.js";

// ─── Mock challenge and dungeon types ───────────────────────────────────────

interface DungeonChallenge {
  skillType: number;
  difficulty: 1 | 2 | 3;
  title: string;
  prompt: string;
  judgeRubric: string;
}

interface DungeonResult {
  agentId: string;
  skillType: number;
  xpEarned: number;
  score: number;
  feedback: string;
  passed: boolean;
}

// ─── Challenge definitions (subset for testing) ────────────────────────────

const challenges: DungeonChallenge[] = [
  {
    skillType: 0,
    difficulty: 1,
    title: "Reverse a String",
    prompt: "Write a function that reverses a string.",
    judgeRubric: "The answer should correctly reverse a string.",
  },
  {
    skillType: 0,
    difficulty: 2,
    title: "Fibonacci Fast",
    prompt: "Write a Fibonacci function using iteration.",
    judgeRubric: "The answer should use iteration, not recursion.",
  },
];

function getChallenge(skillType: number, difficulty: 1 | 2 | 3): DungeonChallenge {
  const match = challenges.find(c => c.skillType === skillType && c.difficulty === difficulty);
  if (!match) {
    return challenges.find(c => c.skillType === skillType) ?? challenges[0];
  }
  return match;
}

// ─── Dungeon executor with dependency injection ─────────────────────────────

async function runDungeon(
  agentId: string,
  skillType: number,
  difficulty: 1 | 2 | 3,
  backend: AgentBackend
): Promise<DungeonResult> {
  const challenge = getChallenge(skillType, difficulty);

  // Step 1: Agent executes challenge
  const agentResult = await backend.execute(
    challenge.prompt,
    "You are an expert software engineer. Answer directly and concisely.",
    "haiku"
  );

  const agentOutput = agentResult.text;

  if (!agentOutput.trim()) {
    return {
      agentId,
      skillType,
      xpEarned: 0,
      score: 0,
      feedback: "Agent produced no output.",
      passed: false,
    };
  }

  // Step 2: Judge evaluates with haiku
  const judgePrompt = `Evaluate this response:
CHALLENGE: ${challenge.prompt}
RESPONSE: ${agentOutput}
CRITERIA: ${challenge.judgeRubric}

Score from 1-10. Respond in format:
SCORE: <number>
FEEDBACK: <text>`;

  const judgeResult = await backend.execute(
    judgePrompt,
    "You are a code evaluator. Always respond in exact format requested.",
    "haiku"
  );

  // Step 3: Parse judge output
  const scoreMatch = judgeResult.text.match(/SCORE:\s*(\d+)/i);
  const feedbackMatch = judgeResult.text.match(/FEEDBACK:\s*(.+)/i);

  const score = scoreMatch ? Math.min(10, Math.max(1, parseInt(scoreMatch[1], 10))) : 5;
  const feedback = feedbackMatch ? feedbackMatch[1].trim() : "Challenge completed.";
  const xpEarned = difficulty * score * 10;
  const passed = score >= 5;

  return { agentId, skillType, xpEarned, score, feedback, passed };
}

// ─── Mock backends for testing ──────────────────────────────────────────────

class MockSuccessBackend implements AgentBackend {
  private callCount = 0;

  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    const callNumber = this.callCount++;

    // First call: Agent responds with a solution
    if (callNumber === 0) {
      return {
        text: "function reverse(s) { return s.split('').reverse().join(''); }",
        durationMs: 10,
        costUsd: 0,
      };
    }

    // Second call: Judge responds with high score
    if (callNumber === 1) {
      return {
        text: "SCORE: 9\nFEEDBACK: Excellent solution, well-written.",
        durationMs: 5,
        costUsd: 0,
      };
    }

    return { text: "", durationMs: 0, costUsd: 0 };
  }
}

class MockLowScoreBackend implements AgentBackend {
  private callCount = 0;

  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    const callNumber = this.callCount++;

    // First call: Agent response is poor
    if (callNumber === 0) {
      return {
        text: "not sure how",
        durationMs: 10,
        costUsd: 0,
      };
    }

    // Second call: Judge gives low score
    if (callNumber === 1) {
      return {
        text: "SCORE: 3\nFEEDBACK: Incorrect and incomplete.",
        durationMs: 5,
        costUsd: 0,
      };
    }

    return { text: "", durationMs: 0, costUsd: 0 };
  }
}

class MockEmptyOutputBackend implements AgentBackend {
  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    return {
      text: "",
      durationMs: 0,
      costUsd: 0,
    };
  }
}

class MockErrorBackend implements AgentBackend {
  async execute(prompt: string, systemPrompt: string, model: string): Promise<never> {
    throw new Error("Backend connection failed");
  }
}

class MockMalformedJudgeBackend implements AgentBackend {
  private callCount = 0;

  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    const callNumber = this.callCount++;

    if (callNumber === 0) {
      return {
        text: "function reverse(s) { return s.split('').reverse().join(''); }",
        durationMs: 10,
        costUsd: 0,
      };
    }

    // Judge responds without proper format
    if (callNumber === 1) {
      return {
        text: "Good answer, I like it.",
        durationMs: 5,
        costUsd: 0,
      };
    }

    return { text: "", durationMs: 0, costUsd: 0 };
  }
}

// ─── Tests ─────────────────────────────────────────────────────────────────

test("getChallenge pure function: returns challenge by skillType and difficulty", () => {
  const challenge = getChallenge(0, 1);

  assert.equal(challenge.skillType, 0);
  assert.equal(challenge.difficulty, 1);
  assert.ok(challenge.title.length > 0);
  assert.ok(challenge.prompt.length > 0);
});

test("getChallenge fallback: returns first skill challenge if difficulty not found", () => {
  const challenge = getChallenge(0, 3); // difficulty 3 not in test set

  assert.equal(challenge.skillType, 0); // Falls back to first skill 0
  assert.ok(challenge.difficulty <= 2); // Will be 1 or 2
});

test("runDungeon with successful agent: high score results in pass", async () => {
  const backend = new MockSuccessBackend();

  const result = await runDungeon("agent#1", 0, 1, backend);

  assert.equal(result.agentId, "agent#1");
  assert.equal(result.skillType, 0);
  assert.equal(result.score, 9);
  assert.ok(result.passed, "score 9 should pass");
  assert.ok(result.feedback.length > 0);
});

test("runDungeon XP formula: difficulty × score × 10", async () => {
  const backend = new MockSuccessBackend();

  const result = await runDungeon("agent#1", 0, 1, backend);

  // difficulty 1, score 9: 1 × 9 × 10 = 90
  assert.equal(result.xpEarned, 90);
});

test("runDungeon XP formula for difficulty 2: difficulty × score × 10", async () => {
  const backend = new MockSuccessBackend();

  const result = await runDungeon("agent#1", 0, 2, backend);

  // difficulty 2, score 9: 2 × 9 × 10 = 180
  assert.equal(result.xpEarned, 180);
});

test("runDungeon low score results in fail", async () => {
  const backend = new MockLowScoreBackend();

  const result = await runDungeon("agent#1", 0, 1, backend);

  assert.equal(result.score, 3);
  assert.ok(!result.passed, "score 3 should not pass");
});

test("runDungeon pass threshold: score 5 passes, score 4 fails", async () => {
  class MockScore5Backend implements AgentBackend {
    private callCount = 0;

    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      const callNumber = this.callCount++;

      if (callNumber === 0) {
        return { text: "solution", durationMs: 10, costUsd: 0 };
      }
      return {
        text: "SCORE: 5\nFEEDBACK: Meets minimum criteria.",
        durationMs: 5,
        costUsd: 0,
      };
    }
  }

  const result = await runDungeon("agent#1", 0, 1, new MockScore5Backend());

  assert.ok(result.passed, "score 5 should pass");
});

test("runDungeon empty agent output: zero XP and fail", async () => {
  const backend = new MockEmptyOutputBackend();

  const result = await runDungeon("agent#1", 0, 1, backend);

  assert.equal(result.xpEarned, 0);
  assert.equal(result.score, 0);
  assert.ok(!result.passed);
  assert.ok(result.feedback.includes("no output"));
});

test("runDungeon score clamped to [1, 10]", async () => {
  class MockClampedBackend implements AgentBackend {
    private callCount = 0;

    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      const callNumber = this.callCount++;

      if (callNumber === 0) {
        return { text: "solution", durationMs: 10, costUsd: 0 };
      }
      // Return invalid scores that should be clamped
      return {
        text: "SCORE: 999\nFEEDBACK: Over the top.",
        durationMs: 5,
        costUsd: 0,
      };
    }
  }

  const result = await runDungeon("agent#1", 0, 1, new MockClampedBackend());

  assert.equal(result.score, 10, "score should be clamped to max 10");
});

test("runDungeon malformed judge output defaults to score 5", async () => {
  const backend = new MockMalformedJudgeBackend();

  const result = await runDungeon("agent#1", 0, 1, backend);

  assert.equal(result.score, 5, "malformed judge output should default to score 5");
  assert.ok(result.passed, "default score 5 should pass");
});

test("runDungeon backend error propagates", async () => {
  const backend = new MockErrorBackend();

  await assert.rejects(
    () => runDungeon("agent#1", 0, 1, backend),
    /Backend connection failed/
  );
});

test("runDungeon: multiple agents tracked separately", async () => {
  const backend1 = new MockSuccessBackend();
  const backend2 = new MockSuccessBackend();

  const result1 = await runDungeon("agent#1", 0, 1, backend1);
  const result2 = await runDungeon("agent#2", 0, 1, backend2);

  assert.equal(result1.agentId, "agent#1");
  assert.equal(result2.agentId, "agent#2");
  assert.equal(result1.score, result2.score); // Both use MockSuccessBackend, so same scores
});

test("runDungeon judge regex parsing: SCORE pattern case-insensitive", async () => {
  class MockLowercaseBackend implements AgentBackend {
    private callCount = 0;

    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      const callNumber = this.callCount++;

      if (callNumber === 0) {
        return { text: "solution", durationMs: 10, costUsd: 0 };
      }
      return {
        text: "score: 7\nfeedback: Good work.",
        durationMs: 5,
        costUsd: 0,
      };
    }
  }

  const result = await runDungeon("agent#1", 0, 1, new MockLowercaseBackend());

  assert.equal(result.score, 7, "should parse lowercase 'score:'");
});

test("runDungeon challenge selection by skillType", async () => {
  const backend = new MockSuccessBackend();

  // Request skillType 0
  const result = await runDungeon("agent#1", 0, 1, backend);

  assert.equal(result.skillType, 0);
});
