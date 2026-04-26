/**
 * Phase 4: Crowdsourced Training Data Pool tests
 *
 * Opt-in gameplay data collection for improving AI agents.
 * Users can consent/revoke, and all personally identifying info is stripped
 * before data enters the training pool.
 *
 * Invariants:
 * - consent is opt-in (false by default)
 * - revocation is permanent and retroactive (for future data only)
 * - anonymization removes all PII (agentId, playerId, etc.)
 * - audit trail is immutable (consent changes are logged with timestamps)
 * - shared data cannot be de-anonymized
 */

import { test } from "node:test";
import assert from "node:assert/strict";

// Mocked types
interface ConsentRecord {
  userId: string;
  consented: boolean; // true = opt-in, false = opt-out
  timestamp: string; // ISO 8601
  reason?: string; // why they consented/revoked
}

interface GameplayDataPoint {
  playerId: string;
  agentId: string;
  taskId: string;
  outcome: "success" | "failure" | "partial";
  skillsUsed: string[];
  timestamp: string;
  metadata: Record<string, unknown>;
}

interface AnonymizedDataPoint {
  // NO playerId, NO agentId — completely stripped
  hashId: string; // random hash (not reversible)
  taskDifficulty: number; // 1-3
  outcome: "success" | "failure" | "partial";
  skillsUsed: string[]; // only skill types
  timestamp: string;
  // Note: actual timestamp is optional (can be rounded to day)
}

interface TrainingDataPool {
  totalDataPoints: number;
  anonymizedCount: number;
  consentingUsers: number;
  poolSizeBytes: number;
}

const PII_FIELDS = ["playerId", "agentId", "userId", "nickname"];

// In-memory consent & anonymization tracker
class MockTrainingDataManager {
  private consentRecords: Map<string, ConsentRecord[]> = new Map(); // userId → consent history
  private userConsent: Map<string, boolean> = new Map(); // userId → current consent
  private dataPoints: Map<string, GameplayDataPoint> = new Map(); // raw gameplay data
  private anonymizedData: Map<string, AnonymizedDataPoint> = new Map(); // anonymized pool
  private auditLog: Array<{
    timestamp: string;
    event: string;
    userId: string;
  }> = [];

  setConsent(userId: string, consented: boolean, reason?: string): void {
    const record: ConsentRecord = {
      userId,
      consented,
      timestamp: new Date().toISOString(),
      reason,
    };

    // Append to consent history
    const history = this.consentRecords.get(userId) || [];
    history.push(record);
    this.consentRecords.set(userId, history);

    // Update current consent
    this.userConsent.set(userId, consented);

    // Log to audit trail
    this.auditLog.push({
      timestamp: record.timestamp,
      event: consented ? "consent_granted" : "consent_revoked",
      userId,
    });
  }

  recordGameplay(userId: string, data: GameplayDataPoint): boolean {
    // Only record if user has consented
    const hasConsent = this.userConsent.get(userId) || false;
    if (!hasConsent) {
      return false; // silently drop
    }

    const pointId = `data-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    this.dataPoints.set(pointId, data);

    // Anonymize and add to pool
    const anonymized = this.anonymize(data);
    this.anonymizedData.set(pointId, anonymized);

    return true;
  }

  private anonymize(data: GameplayDataPoint): AnonymizedDataPoint {
    // Remove all PII
    const sanitized = { ...data };
    for (const field of PII_FIELDS) {
      delete (sanitized as Record<string, unknown>)[field];
    }

    // Generate non-reversible hash
    const hashInput = JSON.stringify(data);
    const hashId = this.simpleHash(hashInput);

    return {
      hashId,
      taskDifficulty: this.inferDifficulty(data.taskId),
      outcome: data.outcome,
      skillsUsed: data.skillsUsed,
      timestamp: data.timestamp,
    };
  }

  private simpleHash(input: string): string {
    return `hash-${input
      .split("")
      .reduce((h, c) => h + c.charCodeAt(0), 0)
      .toString(16)}`;
  }

  private inferDifficulty(taskId: string): number {
    // Simple heuristic: extract difficulty from task ID
    const match = taskId.match(/difficulty-(\d)/);
    return match ? parseInt(match[1], 10) : 2; // default medium
  }

  getAnonymizedPool(): AnonymizedDataPoint[] {
    return Array.from(this.anonymizedData.values());
  }

  getConsentHistory(userId: string): ConsentRecord[] {
    return this.consentRecords.get(userId) || [];
  }

  hasUserConsented(userId: string): boolean {
    return this.userConsent.get(userId) || false;
  }

  getStats(): TrainingDataPool {
    const poolStr = JSON.stringify(Array.from(this.anonymizedData.values()));
    return {
      totalDataPoints: this.dataPoints.size,
      anonymizedCount: this.anonymizedData.size,
      consentingUsers: this.userConsent.size,
      poolSizeBytes: poolStr.length,
    };
  }

  getAuditLog(): Array<{ timestamp: string; event: string; userId: string }> {
    return [...this.auditLog];
  }

  verifyNoPersonalData(): boolean {
    const pool = this.getAnonymizedPool();
    for (const point of pool) {
      const str = JSON.stringify(point);
      for (const field of PII_FIELDS) {
        if (str.includes(field)) {
          return false; // found a PII field
        }
      }
    }
    return true;
  }
}

// ─── Test Suite ─────────────────────────────────────────────────────────────

test("Training Data — consent is opt-in (default false)", () => {
  const manager = new MockTrainingDataManager();

  assert.equal(manager.hasUserConsented("user-1"), false);
});

test("Training Data — user can grant consent", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true, "Wants to help improve AI");

  assert.equal(manager.hasUserConsented("user-1"), true);
});

test("Training Data — user can revoke consent", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true, "Opted in");
  manager.setConsent("user-1", false, "Changed mind");

  assert.equal(manager.hasUserConsented("user-1"), false);
});

test("Training Data — records gameplay only if user consented", () => {
  const manager = new MockTrainingDataManager();

  const data: GameplayDataPoint = {
    playerId: "user-1",
    agentId: "coder#1",
    taskId: "difficulty-2-code-review",
    outcome: "success",
    skillsUsed: ["precision", "speed"],
    timestamp: new Date().toISOString(),
    metadata: {},
  };

  // Without consent
  const recordedWithoutConsent = manager.recordGameplay("user-1", data);
  assert.equal(recordedWithoutConsent, false);

  // With consent
  manager.setConsent("user-1", true);
  const recordedWithConsent = manager.recordGameplay("user-1", data);
  assert.equal(recordedWithConsent, true);
});

test("Training Data — anonymized data removes all PII", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true);

  const data: GameplayDataPoint = {
    playerId: "user-1",
    agentId: "coder#42-custom",
    taskId: "difficulty-3-refactor",
    outcome: "partial",
    skillsUsed: ["code-quality"],
    timestamp: new Date().toISOString(),
    metadata: { attempts: 3 },
  };

  manager.recordGameplay("user-1", data);
  const pool = manager.getAnonymizedPool();

  assert.equal(pool.length, 1);
  const anonPoint = pool[0];

  // Verify no PII
  assert.ok(!("playerId" in anonPoint));
  assert.ok(!("agentId" in anonPoint));
  assert.ok(anonPoint.outcome, "outcome preserved");
  assert.deepEqual(anonPoint.skillsUsed, ["code-quality"]);
});

test("Training Data — audit trail logs all consent changes", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true, "Initial opt-in");
  manager.setConsent("user-1", false, "Revoked");
  manager.setConsent("user-1", true, "Re-opted in");

  const auditLog = manager.getAuditLog();
  assert.equal(auditLog.length, 3);
  assert.equal(auditLog[0].event, "consent_granted");
  assert.equal(auditLog[1].event, "consent_revoked");
  assert.equal(auditLog[2].event, "consent_granted");
});

test("Training Data — consent history is immutable append-only log", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true, "First time");
  manager.setConsent("user-1", false, "Revoke");

  const history = manager.getConsentHistory("user-1");
  assert.equal(history.length, 2);
  assert.equal(history[0].consented, true);
  assert.equal(history[1].consented, false);
  // Verify timestamps are in order
  assert.ok(
    new Date(history[0].timestamp) <= new Date(history[1].timestamp)
  );
});

test("Training Data — anonymized pool never contains PII across all records", () => {
  const manager = new MockTrainingDataManager();

  // Add many data points from different users
  manager.setConsent("user-1", true);
  manager.setConsent("user-2", true);
  manager.setConsent("user-3", true);

  for (let i = 0; i < 5; i++) {
    manager.recordGameplay(`user-${(i % 3) + 1}`, {
      playerId: `user-${(i % 3) + 1}`,
      agentId: `agent-${i}`,
      taskId: `task-${i}`,
      outcome: i % 2 === 0 ? "success" : "failure",
      skillsUsed: ["speed"],
      timestamp: new Date().toISOString(),
      metadata: {},
    });
  }

  const hasNoPersonalData = manager.verifyNoPersonalData();
  assert.equal(hasNoPersonalData, true);
});

test("Training Data — tracks pool statistics (size, point count)", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true);

  for (let i = 0; i < 10; i++) {
    manager.recordGameplay("user-1", {
      playerId: "user-1",
      agentId: `agent-${i}`,
      taskId: `task-${i}`,
      outcome: "success",
      skillsUsed: ["speed"],
      timestamp: new Date().toISOString(),
      metadata: {},
    });
  }

  const stats = manager.getStats();
  assert.equal(stats.totalDataPoints, 10);
  assert.equal(stats.anonymizedCount, 10);
  assert.ok(stats.poolSizeBytes > 0);
});

test("Training Data — consent revocation stops future data collection", () => {
  const manager = new MockTrainingDataManager();
  manager.setConsent("user-1", true);

  // Record some data while consented
  manager.recordGameplay("user-1", {
    playerId: "user-1",
    agentId: "agent-1",
    taskId: "task-1",
    outcome: "success",
    skillsUsed: ["speed"],
    timestamp: new Date().toISOString(),
    metadata: {},
  });

  // Revoke consent
  manager.setConsent("user-1", false);

  // Try to record after revocation
  const recorded = manager.recordGameplay("user-1", {
    playerId: "user-1",
    agentId: "agent-2",
    taskId: "task-2",
    outcome: "failure",
    skillsUsed: ["precision"],
    timestamp: new Date().toISOString(),
    metadata: {},
  });

  assert.equal(recorded, false);
  const stats = manager.getStats();
  assert.equal(stats.totalDataPoints, 1, "only first data point recorded");
});

test("Training Data — multiple users can have independent consent", () => {
  const manager = new MockTrainingDataManager();

  manager.setConsent("user-1", true);
  manager.setConsent("user-2", false);
  manager.setConsent("user-3", true);

  assert.equal(manager.hasUserConsented("user-1"), true);
  assert.equal(manager.hasUserConsented("user-2"), false);
  assert.equal(manager.hasUserConsented("user-3"), true);
});
