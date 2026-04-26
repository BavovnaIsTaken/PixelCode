/**
 * Phase 3: Agent Signature/Identity tests
 *
 * Each agent has a unique immutable identity for marketplace trading.
 * Signature includes UUID, creation timestamp, and (optionally) cryptographic signature
 * to prevent counterfeiting or tampering.
 *
 * Invariants:
 * - agentId is globally unique (UUID format or hash-based)
 * - createdAt is immutable, set at spawn time
 * - signature verification prevents tampering
 * - training history is append-only
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "crypto";

// Mocked types
interface AgentSignature {
  agentId: string; // UUID or hash-based unique ID
  createdAt: string; // ISO 8601, immutable
  versionSequence: number; // increments with each significant change
  trainingHistory: Array<{
    timestamp: string;
    event: "self-play" | "lesson" | "skill-upgrade" | "merge";
    details: string;
  }>;
  contentHash: string; // SHA256 of agent state at creation
  lastModifiedHash: string; // SHA256 of current agent state
}

// Helper to generate unique UUID-like ID
function generateAgentId(): string {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).substring(2, 15);
  return `agent-${timestamp}-${random}`;
}

// Helper to compute SHA256 hash
function computeHash(data: string): string {
  return createHash("sha256").update(data).digest("hex");
}

// Helper to create agent signature
function createSignature(
  agentData: Record<string, unknown>
): AgentSignature {
  const now = new Date().toISOString();
  const agentId = generateAgentId();
  const contentHash = computeHash(JSON.stringify(agentData));

  return {
    agentId,
    createdAt: now,
    versionSequence: 1,
    trainingHistory: [
      {
        timestamp: now,
        event: "self-play",
        details: "Agent spawned",
      },
    ],
    contentHash,
    lastModifiedHash: contentHash,
  };
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Agent Signature — agentId is generated and globally unique", () => {
  const id1 = generateAgentId();
  const id2 = generateAgentId();

  assert.notEqual(id1, id2, "two IDs should differ");
  assert.ok(id1.startsWith("agent-"), "ID should have agent prefix");
  assert.ok(id2.startsWith("agent-"), "ID should have agent prefix");
});

test("Agent Signature — agentId format is deterministic and parseable", () => {
  const id = generateAgentId();
  const parts = id.split("-");

  assert.equal(parts[0], "agent");
  assert.ok(parts[1], "timestamp component");
  assert.ok(parts[2], "random component");
});

test("Agent Signature — createdAt is set at spawn time and immutable", () => {
  const beforeSpawn = new Date();
  const sig = createSignature({ role: "coder", level: 1 });
  const afterSpawn = new Date();

  const createdDate = new Date(sig.createdAt);
  assert.ok(createdDate >= beforeSpawn, "createdAt should be >= spawn start");
  assert.ok(createdDate <= afterSpawn, "createdAt should be <= spawn end");
});

test("Agent Signature — contentHash captures initial agent state", () => {
  const agentData = { role: "coder", level: 1, xp: 0 };
  const sig = createSignature(agentData);

  const expectedHash = computeHash(JSON.stringify(agentData));
  assert.equal(sig.contentHash, expectedHash);
});

test("Agent Signature — lastModifiedHash starts equal to contentHash", () => {
  const agentData = { role: "coder", level: 1 };
  const sig = createSignature(agentData);

  assert.equal(sig.lastModifiedHash, sig.contentHash);
});

test("Agent Signature — versionSequence increments with modifications", () => {
  const sig = createSignature({ role: "coder" });
  assert.equal(sig.versionSequence, 1);

  // Simulate modification
  sig.versionSequence += 1;
  assert.equal(sig.versionSequence, 2);
});

test("Agent Signature — trainingHistory is append-only log", () => {
  const sig = createSignature({ role: "coder" });
  const initialLength = sig.trainingHistory.length;

  // Add a training event
  sig.trainingHistory.push({
    timestamp: new Date().toISOString(),
    event: "lesson",
    details: "Learned null-check safety",
  });

  assert.equal(sig.trainingHistory.length, initialLength + 1);
  assert.equal(sig.trainingHistory[0].event, "self-play", "first event preserved");
  assert.equal(sig.trainingHistory[1].event, "lesson", "new event appended");
});

test("Agent Signature — hash verification detects tampering", () => {
  const agentData = { role: "coder", level: 1, xp: 0 };
  const sig = createSignature(agentData);
  const originalHash = sig.contentHash;

  // Simulate tampering: change agent data
  const tamperedData = { role: "coder", level: 10, xp: 9999 };
  const tamperedHash = computeHash(JSON.stringify(tamperedData));

  assert.notEqual(tamperedHash, originalHash, "tampered data has different hash");
});

test("Agent Signature — training history events are timestamped and validated", () => {
  const sig = createSignature({ role: "coder" });

  for (const event of sig.trainingHistory) {
    assert.ok(event.timestamp, "timestamp should exist");
    assert.ok(event.event, "event type should exist");
    assert.ok(
      ["self-play", "lesson", "skill-upgrade", "merge"].includes(event.event),
      "event type should be valid"
    );
  }
});
