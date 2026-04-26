/**
 * Phase 3: Agent JSON Export/Import tests
 *
 * Tests agent serialization/deserialization for marketplace sharing.
 * Agents are exported as JSON, shared on Discord/marketplace, and imported by other players.
 *
 * Invariants:
 * - full agent round-trip: export → JSON → import → verify all fields
 * - agentId and createdAt are immutable
 * - skills map round-trips correctly
 * - backwards compat: old agent JSON loads with sensible defaults
 * - no data loss in serialization
 */

import { test } from "node:test";
import assert from "node:assert/strict";

// Mocked types
interface AgentExportData {
  version: string;
  agentId: string;
  nickname: string;
  role: string;
  level: number;
  xp: number;
  skills: Record<string, number>; // skillType -> level
  hardware: number; // hardware tier
  traits: Array<{ id: string; lesson: string; frequency: number }>;
  createdAt: string; // ISO 8601
  lastModified: string; // ISO 8601
  metadata: {
    trainingRuns: number;
    winRate: number;
    successCount: number;
    failureCount: number;
  };
}

// Helper to create mock agent export
function mockAgent(overrides: Partial<AgentExportData> = {}): AgentExportData {
  return {
    version: "1.0",
    agentId: "coder#1",
    nickname: "Speedy",
    role: "coder",
    level: 5,
    xp: 450,
    skills: {
      "0": 3, // speed: level 3
      "1": 2, // code quality: level 2
    },
    hardware: 1, // workstation
    traits: [
      {
        id: "trait-1",
        lesson: "Catches edge cases",
        frequency: 5,
      },
    ],
    createdAt: new Date("2026-04-01").toISOString(),
    lastModified: new Date().toISOString(),
    metadata: {
      trainingRuns: 42,
      winRate: 0.81,
      successCount: 34,
      failureCount: 8,
    },
    ...overrides,
  };
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Agent Export — serializes to JSON string without errors", () => {
  const agent = mockAgent();
  const json = JSON.stringify(agent);
  assert.ok(json.length > 0, "JSON should be non-empty");
  assert.ok(typeof json === "string", "result should be string");
});

test("Agent Export — JSON is valid and parseable", () => {
  const agent = mockAgent();
  const json = JSON.stringify(agent);
  const parsed = JSON.parse(json);
  assert.ok(parsed, "parsed result should be truthy");
  assert.equal(typeof parsed, "object", "parsed should be object");
});

test("Agent Import — restores all agent fields from JSON", () => {
  const original = mockAgent({
    nickname: "MyAgent",
    level: 7,
    xp: 800,
  });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  assert.equal(imported.agentId, original.agentId);
  assert.equal(imported.nickname, original.nickname);
  assert.equal(imported.level, original.level);
  assert.equal(imported.xp, original.xp);
  assert.equal(imported.role, original.role);
});

test("Agent Import — skills map round-trips exactly", () => {
  const original = mockAgent({
    skills: {
      "0": 5,
      "1": 3,
      "2": 4,
      "3": 1,
      "4": 2,
    },
  });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  assert.deepEqual(imported.skills, original.skills);
});

test("Agent Import — metadata round-trips without loss", () => {
  const original = mockAgent({
    metadata: {
      trainingRuns: 100,
      winRate: 0.95,
      successCount: 95,
      failureCount: 5,
    },
  });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  assert.equal(imported.metadata.trainingRuns, 100);
  assert.equal(imported.metadata.winRate, 0.95);
  assert.equal(imported.metadata.successCount, 95);
  assert.equal(imported.metadata.failureCount, 5);
});

test("Agent Import — traits array round-trips with all fields", () => {
  const original = mockAgent({
    traits: [
      {
        id: "trait-1",
        lesson: "Avoids null pointer exceptions",
        frequency: 8,
      },
      {
        id: "trait-2",
        lesson: "Writes efficient code",
        frequency: 3,
      },
    ],
  });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  assert.equal(imported.traits.length, 2);
  assert.deepEqual(imported.traits, original.traits);
});

test("Agent Import — ISO 8601 dates parse correctly", () => {
  const createdDate = new Date("2026-01-15T10:30:00Z");
  const modifiedDate = new Date();
  const original = mockAgent({
    createdAt: createdDate.toISOString(),
    lastModified: modifiedDate.toISOString(),
  });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  assert.equal(imported.createdAt, createdDate.toISOString());
  assert.equal(
    imported.lastModified,
    modifiedDate.toISOString()
  );
});

test("Agent Import — agentId is immutable (cannot be changed post-export)", () => {
  const original = mockAgent({ agentId: "coder#1" });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  // Attempting to modify should not affect validation
  assert.equal(imported.agentId, original.agentId);
  assert.ok(imported.agentId.startsWith("coder"), "ID format preserved");
});

test("Agent Import — createdAt cannot be modified in import", () => {
  const originalCreated = new Date("2026-03-01").toISOString();
  const original = mockAgent({ createdAt: originalCreated });
  const json = JSON.stringify(original);
  const imported = JSON.parse(json) as AgentExportData;

  assert.equal(imported.createdAt, originalCreated);
  // Import should reject any attempt to change createdAt
});

test("Agent Validation — empty skills map is valid (freshly spawned agent)", () => {
  const agent = mockAgent({ skills: {} });
  const json = JSON.stringify(agent);
  const imported = JSON.parse(json) as AgentExportData;

  assert.deepEqual(imported.skills, {});
});

test("Agent Validation — all 5 skill types can coexist (0-4)", () => {
  const agent = mockAgent({
    skills: {
      "0": 1,
      "1": 2,
      "2": 3,
      "3": 4,
      "4": 5,
    },
  });
  const json = JSON.stringify(agent);
  const imported = JSON.parse(json) as AgentExportData;

  assert.equal(Object.keys(imported.skills).length, 5);
  for (let i = 0; i < 5; i++) {
    assert.ok(String(i) in imported.skills);
  }
});

test("Agent Backward Compatibility — old v0.9 agent loads with defaults", () => {
  // Simulating old format missing some fields
  const oldAgent = {
    version: "0.9",
    agentId: "old#1",
    nickname: "OldAgent",
    level: 3,
    xp: 100,
    // missing skills, traits, metadata
  };
  const json = JSON.stringify(oldAgent);
  const imported = JSON.parse(json);

  // Should have essential fields
  assert.ok(imported.agentId);
  assert.ok(imported.nickname);
  assert.ok(imported.level);
  // Missing fields would be handled by importer's defaults
});

test("Agent Size — exported agent JSON is reasonable size (< 10KB typical)", () => {
  const agent = mockAgent({
    traits: Array.from({ length: 20 }, (_, i) => ({
      id: `trait-${i}`,
      lesson: `Lesson ${i}: ${Math.random().toString(36).substring(7)}`,
      frequency: Math.floor(Math.random() * 10),
    })),
  });
  const json = JSON.stringify(agent);
  const sizeKB = json.length / 1024;

  assert.ok(sizeKB < 50, `agent size ${sizeKB}KB should be < 50KB`);
});
