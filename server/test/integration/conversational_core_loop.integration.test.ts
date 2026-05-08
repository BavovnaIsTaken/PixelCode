/**
 * Integration: conversational core loop.
 *
 * This is the user-visible core loop the project lives or dies by:
 *
 *   1. User submits a brief.
 *   2. Facilitator generates a team-reaction scene (≤3 in-character
 *      messages) that lands in chat BEFORE the board fills.
 *   3. Facilitator's seed lands as a board batch and gets auto-dispatched.
 *   4. A task transits to "done" → tech-lead digest records the
 *      completion (in-memory ring + JSONL append).
 *   5. The next tech-lead system prompt contains the digest as a
 *      "Recent team activity" block; non-tech-lead prompts do NOT.
 *   6. A simulated server restart replays the digest from JSONL so the
 *      tech-lead's awareness survives reboots.
 *
 * Each layer has unit tests already; THIS test catches regressions at
 * the seams where unit tests look the other way:
 *   - reactions actually arriving in chatHistory before the seed
 *   - the done-transition hook firing exactly once with the right
 *     agentId/role decoded from `coder#1`-style instance ids
 *   - the prompt-injection gate (only tech-lead role gets the digest)
 *   - JSONL replay producing identical state on a fresh process
 *
 * No real WS server. No real LLM. The assertions exercise the same
 * modules `server.ts` composes when handling `facilitator_start` and
 * `board_move_task`, so changes to those handlers that drift the loop
 * out of sync will trip this test rather than reach prod.
 */

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync, readFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

import { generateTeamReactions } from "../../src/facilitator/team_reactions.ts";
import type { CallerFn } from "../../src/facilitator/llm_generators.ts";
import {
  TechLeadDigest,
  digestFile,
  type DigestEntry,
} from "../../src/tech_lead_digest.ts";
import {
  planSeedBatch,
  type SeedBatchInput,
} from "../../src/board_persistence.ts";
import { buildOfficePrompt, type GameStateData } from "../../src/agents.ts";
import { ChatHistory } from "../../src/chat_history.ts";
import type { TaskCardData } from "../../src/protocol.ts";
import {
  applyReactionsToChat,
  recordTaskCompletion,
} from "../../src/conversational_loop.ts";

// ─── Test scaffolding ─────────────────────────────────────────────────────

const VALID_ROLES = [
  "manager",
  "tech-lead",
  "coder",
  "reviewer",
  "tester",
  "security",
  "ui-ux-designer",
  "llm-specialist",
  "game-designer",
  "strategy-keeper",
];

function tmpHome(): { root: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "pixelcode-loop-int-"));
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

function inst(roleType: string, skill = 5) {
  return {
    roleType,
    nickname: roleType,
    hardware: 2,
    skills: { precision: skill, speed: skill },
  };
}

const ROSTER: GameStateData = {
  instances: {
    "manager#1": inst("manager"),
    "tech-lead#1": inst("tech-lead"),
    "coder#1": inst("coder", 8),
    "tester#1": inst("tester"),
  },
};

const PROJECT_CWD = "/tmp/pixelcode-loop-test";

// Reactions wiring + done-transition wiring are imported above from
// `conversational_loop.ts` — the SAME functions `server.ts` calls when
// handling `facilitator_start` and `board_move_task`. Drift between
// handler and test is impossible by construction.

// ─── The full conversational loop, end-to-end ─────────────────────────────

describe("conversational core loop", () => {
  test(
    "e2e: brief → reactions → seed → done → digest → tech-lead prompt → restart",
    async () => {
      const { root, cleanup } = tmpHome();
      try {
        const chatHistory = new ChatHistory();

        // ── 1. User submits a brief ─────────────────────────────────────
        const brief = "Build a quick photo gallery with auth.";

        // ── 2. Facilitator team-reaction scene ──────────────────────────
        // Fake LLM caller returns a known schema. The brief drops →
        // manager + tech-lead + tester respond, all valid role ids.
        const fakeCaller: CallerFn = async () =>
          JSON.stringify({
            reactions: [
              { role: "manager", text: "Беру brief, дроблю на 4 кроки." },
              { role: "tech-lead", text: "Auth — найбільший ризик. Перевіримо session storage." },
              { role: "tester", text: "Тести на edge cases для логіну впишу одразу." },
            ],
          });

        const reactions = await generateTeamReactions(
          {
            projectDescription: brief,
            validRoles: VALID_ROLES,
            projectPath: PROJECT_CWD,
          },
          { caller: fakeCaller },
        );

        const reactionsTs = "2026-05-08T10:00:00Z";
        applyReactionsToChat(chatHistory, reactions, reactionsTs);

        assert.equal(reactions.length, 3, "expected 3 in-character reactions");
        const chatBefore = chatHistory.snapshot();
        assert.equal(chatBefore.type, "chat_history");
        const messagesBefore = (chatBefore as { messages: Array<{ agentId: string; text: string }> }).messages;
        assert.equal(messagesBefore.length, 3, "reactions must land as chat messages");
        assert.deepEqual(
          messagesBefore.map((m) => m.agentId),
          ["manager", "tech-lead", "tester"],
        );
        assert.match(messagesBefore[1].text, /Auth/);

        // ── 3. Facilitator seeds the board ──────────────────────────────
        const facilitatorBatch: SeedBatchInput[] = [
          { title: "Wire auth", allowedRoles: ["coder"], difficulty: 2 },
          { title: "Photo grid screen", allowedRoles: ["coder"], difficulty: 1 },
          { title: "Auth integration tests", allowedRoles: ["tester"], difficulty: 1 },
        ];
        const plan = planSeedBatch(facilitatorBatch, {
          counter: 0,
          now: () => new Date(reactionsTs),
          idToken: () => 1234,
          sourceTag: "facilitator",
        });
        assert.ok(plan.ok, "facilitator batch must commit cleanly");
        assert.equal(plan.tasks.length, 3);

        // Manually assign first task to coder#1 (mimics auto-dispatcher
        // outcome — we already test the dispatcher elsewhere).
        const wireAuth = plan.tasks[0];
        wireAuth.assignedAgents = ["coder#1"];
        wireAuth.column = "in_progress";

        // ── 4. Task transits to done → digest fires ─────────────────────
        const digestPath = digestFile(PROJECT_CWD, root);
        const digest = new TechLeadDigest(digestPath);
        // Pre-condition: clean slate, no entries yet.
        assert.equal(digest.recent().length, 0);
        assert.equal(existsSync(digestPath), false);

        wireAuth.column = "done";
        const recorded = recordTaskCompletion(digest, wireAuth);

        assert.equal(recorded.taskId, wireAuth.id);
        assert.equal(recorded.title, "Wire auth");
        assert.equal(recorded.agentId, "coder#1");
        assert.equal(
          recorded.role, "coder",
          "role MUST be derived from the `coder#1` instance id (drop `#N`)",
        );
        assert.equal(recorded.outcome, "done");
        assert.equal(digest.recent().length, 1, "ring buffer must have 1 entry");

        // JSONL must exist on disk and contain exactly one line.
        assert.ok(existsSync(digestPath), "digest file must be written");
        const persisted = readFileSync(digestPath, "utf8");
        const lines = persisted.split("\n").filter((l) => l.length > 0);
        assert.equal(lines.length, 1);
        assert.equal((JSON.parse(lines[0]) as DigestEntry).taskId, wireAuth.id);

        // ── 5. Prompt injection: tech-lead sees digest, others don't ────
        const digestBlock = digest.renderForPrompt(15);
        assert.match(digestBlock, /^## Recent team activity/);
        assert.match(digestBlock, /Wire auth/);

        const techLeadPrompt = buildOfficePrompt(
          "tech-lead#1",
          undefined,
          undefined,
          ROSTER,
          digestBlock,
        );
        assert.match(
          techLeadPrompt,
          /## Recent team activity/,
          "tech-lead prompt MUST contain the digest block",
        );
        assert.match(
          techLeadPrompt,
          /Wire auth/,
          "tech-lead prompt MUST mention the recent task title",
        );
        assert.match(
          techLeadPrompt,
          /ground architectural reactions in actual finished work/,
          "tech-lead prompt MUST contain the use-the-digest instruction",
        );

        const coderPrompt = buildOfficePrompt(
          "coder#1",
          undefined,
          undefined,
          ROSTER,
          digestBlock,
        );
        assert.equal(
          /## Recent team activity/.test(coderPrompt),
          false,
          "non-tech-lead prompts MUST NOT contain the digest block",
        );

        // ── 6. Restart: a fresh process replays JSONL into the ring ─────
        // Record one more completion before "restarting" to make replay
        // less trivially mockable.
        const photoGrid = plan.tasks[1];
        photoGrid.assignedAgents = ["coder#1"];
        photoGrid.column = "done";
        recordTaskCompletion(digest, photoGrid);
        assert.equal(digest.recent().length, 2);

        const restarted = new TechLeadDigest(digestPath);
        // Pre-loadFromDisk: empty (proves replay actually does work).
        assert.equal(restarted.recent().length, 0);

        restarted.loadFromDisk();
        const replayed = restarted.recent();
        assert.equal(replayed.length, 2, "both completions survive restart");
        assert.deepEqual(
          replayed.map((e) => e.taskId),
          [wireAuth.id, photoGrid.id],
          "replay order must match append order (oldest → newest)",
        );

        // The restarted prompt must still mention the older completion.
        const techLeadPromptAfterRestart = buildOfficePrompt(
          "tech-lead#1",
          undefined,
          undefined,
          ROSTER,
          restarted.renderForPrompt(15),
        );
        assert.match(techLeadPromptAfterRestart, /Wire auth/);
        assert.match(techLeadPromptAfterRestart, /Photo grid screen/);
      } finally {
        cleanup();
      }
    },
  );

  test(
    "reaction LLM failure does NOT poison the chat or block the seed",
    async () => {
      const { root, cleanup } = tmpHome();
      try {
        const chatHistory = new ChatHistory();
        const blowingCaller: CallerFn = async () => {
          throw new Error("rate_limit hit");
        };
        const reactions = await generateTeamReactions(
          {
            projectDescription: "anything",
            validRoles: VALID_ROLES,
            projectPath: PROJECT_CWD,
          },
          { caller: blowingCaller, runOptions: { retries: 0 } },
        );
        assert.deepEqual(reactions, [], "reactions must be empty on failure");
        applyReactionsToChat(chatHistory, reactions, "2026-05-08T10:00:00Z");
        assert.equal(chatHistory.isEmpty, true, "chat must stay empty");

        // The seed pipeline still works the same way: a digest call on a
        // completion records correctly even though no reactions ran.
        const digest = new TechLeadDigest(digestFile(PROJECT_CWD, root));
        const task: TaskCardData = {
          id: "task_1_x",
          title: "Standalone task",
          description: "",
          color: "yellow",
          priority: "normal",
          column: "done",
          createdAt: "2026-05-08T10:00:00Z",
          updatedAt: "2026-05-08T10:01:00Z",
          assignedAgents: ["coder#1"],
          difficulty: 1,
          allowedRoles: ["coder"],
          taskType: "manual",
          attachments: [],
        };
        recordTaskCompletion(digest, task);
        assert.equal(digest.recent().length, 1);
      } finally {
        cleanup();
      }
    },
  );

  test(
    "an unassigned task that lands in done still records (with role=unassigned)",
    () => {
      const { root, cleanup } = tmpHome();
      try {
        const digest = new TechLeadDigest(digestFile(PROJECT_CWD, root));
        const task: TaskCardData = {
          id: "task_99_x",
          title: "Manually moved by user",
          description: "",
          color: "yellow",
          priority: "normal",
          column: "done",
          createdAt: "2026-05-08T10:00:00Z",
          updatedAt: "2026-05-08T10:01:00Z",
          assignedAgents: [],
          difficulty: 1,
          allowedRoles: [],
          taskType: "manual",
          attachments: [],
        };
        const entry = recordTaskCompletion(digest, task);
        assert.equal(entry.agentId, "unassigned");
        assert.equal(entry.role, "unassigned");
        assert.equal(digest.recent().length, 1);
      } finally {
        cleanup();
      }
    },
  );
});
