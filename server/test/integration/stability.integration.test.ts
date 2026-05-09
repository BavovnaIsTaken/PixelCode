/**
 * Stability integration tests — anti-regression harness for the
 * "stupid" bugs that have eaten the most time in this project so far:
 *
 *   1. Chat history desyncs between iPhone ↔ Mac. A device misses a
 *      message, or a reconnecting device doesn't catch up.
 *   2. Mid-conversation, an agent asks "and what project are we in?"
 *      The team apparently forgot the brief moments after running the
 *      facilitator intake.
 *
 * The harness mirrors `server.ts` handlers WITHOUT booting a real WS
 * server: each fake client is just a `received: ServerMessage[]` array,
 * and `broadcastAll` walks the connected list. Connect/disconnect runs
 * the SAME logic the real `wss.on("connection", …)` handler does for
 * the message types we care about (chat_history snapshot replay,
 * team-memory restore, facilitator output sync).
 *
 * For each known bug a test reproduces the failure mode against the
 * harness; the harness exists *to* fail today. The matching server.ts
 * change makes it green and keeps regressions out.
 */

import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  existsSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
  readFileSync,
  mkdirSync,
} from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";

import { ChatHistory } from "../../src/chat_history.ts";
import { buildOfficePrompt, type GameStateData } from "../../src/agents.ts";
import { deriveProjectMemoryFromBrief } from "../../src/conversational_loop.ts";

// ─── Test fixtures ────────────────────────────────────────────────────────

function tmpHome(): { root: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "pixelcode-stability-"));
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

function inst(roleType: string) {
  return {
    roleType,
    nickname: roleType,
    hardware: 2,
    skills: { precision: 5, speed: 5 },
  };
}

const ROSTER: GameStateData = {
  instances: {
    "manager#1": inst("manager"),
    "tech-lead#1": inst("tech-lead"),
    "coder#1": inst("coder"),
  },
};

// ─── Server harness ───────────────────────────────────────────────────────

interface FakeClient {
  id: string;
  received: Array<Record<string, unknown>>;
}

interface FacilitatorOutput {
  styleId: string;
  finalScore: Record<string, number>;
  outputFormat: string;
  outputJson: string;
}

/**
 * Mirrors the chat + project-memory + facilitator handlers from
 * `server.ts` against in-memory fake clients. Reuses the SAME modules
 * (ChatHistory, buildOfficePrompt, deriveProjectMemoryFromBrief) so a
 * drift in production code surfaces here.
 */
class ServerHarness {
  chatHistory: ChatHistory;
  readonly clients: FakeClient[] = [];
  readonly clientProjectContext = new Map<string, string>();
  // Per-ws scratch state — mirrors clientGameState/getCommLog/getMetrics/etc.
  // in server.ts. Modeling it here is what lets us pin "set_project clears
  // peer state too" instead of just the sender's.
  readonly clientScratch = new Map<string, { msgsSeen: number }>();
  latestFacilitatorOutput: FacilitatorOutput | null = null;
  private projectCwd: string;

  constructor(baseDir: string) {
    this.projectCwd = baseDir;
    this.chatHistory = new ChatHistory();
    this.chatHistory.load(this.historyFilePath());
  }

  // ── Storage paths (mirror `server.ts`) ─────────────────────────────────
  private historyFilePath(): string {
    return join(this.projectCwd, "history.json");
  }
  private teamMemoryFilePath(): string {
    return join(this.projectCwd, "team_memory.txt");
  }
  private facilitatorFilePath(): string {
    return join(this.projectCwd, "facilitator_output.json");
  }

  // ── Connect / disconnect ───────────────────────────────────────────────
  connect(id: string): FakeClient {
    const c: FakeClient = { id, received: [] };
    this.clients.push(c);
    this.clientScratch.set(c.id, { msgsSeen: 0 });
    // Mirror wss.on("connection", …): init + chat_history + team-memory
    // restore + facilitator_output_sync if present.
    this.send(c, {
      type: "init",
      sessionId: "test",
      agents: [],
      workingDirectory: this.projectCwd,
    });
    this.send(c, this.chatHistory.snapshot() as unknown as Record<string, unknown>);
    if (existsSync(this.teamMemoryFilePath())) {
      this.clientProjectContext.set(
        c.id,
        readFileSync(this.teamMemoryFilePath(), "utf-8"),
      );
    }
    if (existsSync(this.facilitatorFilePath())) {
      // Reload latestFacilitatorOutput from disk to mirror server boot.
      this.latestFacilitatorOutput = JSON.parse(
        readFileSync(this.facilitatorFilePath(), "utf-8"),
      ) as FacilitatorOutput;
    }
    if (this.latestFacilitatorOutput) {
      this.send(c, {
        type: "facilitator_output_sync",
        ...this.latestFacilitatorOutput,
      });
    }
    return c;
  }

  /**
   * Mirrors `case "set_project"` in server.ts: switch global PROJECT_CWD,
   * reload chat history + team memory for the new project, and re-init
   * EVERY connected client (not just the sender) so peer devices don't
   * keep operating on stale state. The bug pinned by the regression test
   * is: previously per-ws scratch + clientProjectContext was cleared only
   * for the sender, leaving peer devices in an inconsistent state.
   */
  setProject(c: FakeClient, newBaseDir: string): void {
    this.projectCwd = newBaseDir;
    this.chatHistory = new ChatHistory();
    this.chatHistory.load(this.historyFilePath());
    const newMemory = existsSync(this.teamMemoryFilePath())
      ? readFileSync(this.teamMemoryFilePath(), "utf-8")
      : null;
    this.latestFacilitatorOutput = existsSync(this.facilitatorFilePath())
      ? (JSON.parse(readFileSync(this.facilitatorFilePath(), "utf-8")) as FacilitatorOutput)
      : null;
    // Reset every connected client's per-ws state, not just the sender.
    for (const peer of this.clients) {
      this.clientScratch.set(peer.id, { msgsSeen: 0 });
      if (newMemory) this.clientProjectContext.set(peer.id, newMemory);
      else this.clientProjectContext.delete(peer.id);
      // Broadcast `init` with new workingDirectory so every device's UI
      // re-syncs to the new project.
      this.send(peer, {
        type: "init",
        sessionId: "test",
        agents: [],
        workingDirectory: this.projectCwd,
      });
      this.send(
        peer,
        this.chatHistory.snapshot() as unknown as Record<string, unknown>,
      );
      if (this.latestFacilitatorOutput) {
        this.send(peer, {
          type: "facilitator_output_sync",
          ...this.latestFacilitatorOutput,
        });
      }
    }
  }

  /** Mirrors per-ws bookkeeping done on user-message receive. */
  private bumpScratch(c: FakeClient): void {
    const s = this.clientScratch.get(c.id);
    if (s) s.msgsSeen += 1;
  }

  disconnect(c: FakeClient): void {
    const i = this.clients.indexOf(c);
    if (i >= 0) this.clients.splice(i, 1);
    // WeakMap-style binding in real server.ts ties context to ws lifetime,
    // but team_memory.txt persists. Mirror that: clear in-memory entry,
    // disk stays.
    this.clientProjectContext.delete(c.id);
  }

  // ── Chat handler (mirrors `case "chat_message"` in server.ts) ──────────
  sendUserMessage(c: FakeClient, content: string, ts: string): void {
    this.bumpScratch(c);
    this.chatHistory.add({
      role: "user",
      text: content,
      agentId: "manager",
      timestamp: ts,
      id: `local-${c.id}-${ts}`,
    });
    this.chatHistory.save(this.historyFilePath());
    this.broadcastAll(this.chatHistory.snapshot() as unknown as Record<string, unknown>);
  }

  /**
   * Mirrors the part of `case "facilitator_start"` that runs after the
   * seed succeeds: persist the output AND distil project memory so the
   * next agent prompt has grounding. The latter is what was missing.
   */
  facilitatorSeed(c: FakeClient, brief: string, now: Date): void {
    const output: FacilitatorOutput = {
      styleId: "test-style",
      finalScore: {},
      outputFormat: "quest_line",
      outputJson: JSON.stringify({ id: "out-1", projectBrief: brief }),
    };
    this.latestFacilitatorOutput = output;
    mkdirSync(dirname(this.facilitatorFilePath()), { recursive: true });
    writeFileSync(this.facilitatorFilePath(), JSON.stringify(output));

    // The fix: derive a project-memory hint and persist it so every
    // agent prompt has grounding even after a reconnect or another
    // device joining.
    const memory = deriveProjectMemoryFromBrief(brief, now);
    mkdirSync(dirname(this.teamMemoryFilePath()), { recursive: true });
    writeFileSync(this.teamMemoryFilePath(), memory);
    // Mirror server.ts: set on every currently-connected client, not just
    // the sender. Otherwise peer devices keep stale/empty memory until
    // they reconnect.
    for (const peer of this.clients) this.clientProjectContext.set(peer.id, memory);

    this.broadcastAll({
      type: "facilitator_seeded",
      styleId: output.styleId,
      finalScore: output.finalScore,
      outputFormat: output.outputFormat,
      outputJson: output.outputJson,
    });
  }

  /**
   * Build the system prompt the SAME way agent dispatch builds it for a
   * given client. Uses `clientProjectContext` keyed by client.
   */
  promptFor(c: FakeClient, agentId: string): string {
    const projectMemory = this.clientProjectContext.get(c.id);
    return buildOfficePrompt(
      agentId,
      projectMemory,
      undefined,
      ROSTER,
      undefined,
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────
  private send(c: FakeClient, msg: Record<string, unknown>): void {
    c.received.push(msg);
  }
  private broadcastAll(msg: Record<string, unknown>): void {
    for (const c of this.clients) this.send(c, msg);
  }
}

function lastChatHistory(c: FakeClient): Array<{ role: string; text: string }> {
  for (let i = c.received.length - 1; i >= 0; i--) {
    const m = c.received[i];
    if (m.type === "chat_history") {
      return m.messages as Array<{ role: string; text: string }>;
    }
  }
  return [];
}

// ─── Bug 1: chat history desync between devices ───────────────────────────

describe("chat sync across connected clients", () => {
  test("when A sends, B receives the new snapshot via broadcast", () => {
    const { root, cleanup } = tmpHome();
    try {
      const h = new ServerHarness(root);
      const iPhone = h.connect("iphone");
      const mac = h.connect("mac");
      h.sendUserMessage(iPhone, "Hello team — let's start.", "2026-05-08T10:00:00Z");

      const macHistory = lastChatHistory(mac);
      assert.equal(macHistory.length, 1, "Mac must see the iPhone message");
      assert.equal(macHistory[0].text, "Hello team — let's start.");
      assert.equal(macHistory[0].role, "user");
    } finally {
      cleanup();
    }
  });

  test("a reconnecting client catches up to messages it missed", () => {
    const { root, cleanup } = tmpHome();
    try {
      const h = new ServerHarness(root);
      const iPhone = h.connect("iphone");
      const mac = h.connect("mac");

      // Mac drops off the network mid-session.
      h.disconnect(mac);

      // iPhone sends two messages while Mac is gone — these only land
      // in chatHistory + on iPhone, not on the offline Mac.
      h.sendUserMessage(iPhone, "First message", "2026-05-08T10:01:00Z");
      h.sendUserMessage(iPhone, "Second message", "2026-05-08T10:02:00Z");

      // Mac comes back. Connect handler must replay the FULL current
      // history, not just messages broadcast after the reconnect.
      const macAgain = h.connect("mac");
      const replayed = lastChatHistory(macAgain);
      assert.equal(replayed.length, 2, "reconnecting Mac must catch up to 2 missed messages");
      assert.deepEqual(
        replayed.map((m) => m.text),
        ["First message", "Second message"],
      );
    } finally {
      cleanup();
    }
  });

  test("history persists to disk; a fresh server boot still has the messages", () => {
    const { root, cleanup } = tmpHome();
    try {
      // First "boot": one client sends a message, then everyone leaves.
      {
        const h = new ServerHarness(root);
        const iPhone = h.connect("iphone");
        h.sendUserMessage(iPhone, "Pre-restart message", "2026-05-08T10:00:00Z");
        h.disconnect(iPhone);
      }
      // Second "boot": fresh harness, same baseDir → must replay history.
      const h2 = new ServerHarness(root);
      const mac = h2.connect("mac");
      const replayed = lastChatHistory(mac);
      assert.equal(replayed.length, 1);
      assert.equal(replayed[0].text, "Pre-restart message");
    } finally {
      cleanup();
    }
  });
});

// ─── Bug 2: facilitator forgets project context ───────────────────────────

describe("facilitator project memory survives", () => {
  test(
    "after facilitator_start, agent prompt MUST mention the brief",
    () => {
      const { root, cleanup } = tmpHome();
      try {
        const h = new ServerHarness(root);
        const iPhone = h.connect("iphone");
        h.facilitatorSeed(
          iPhone,
          "Build a photo gallery with auth and offline mode.",
          new Date("2026-05-08T10:00:00Z"),
        );
        const prompt = h.promptFor(iPhone, "manager#1");
        assert.match(
          prompt,
          /Project Memory/,
          "prompt must include the Project Memory section once a brief is seeded",
        );
        assert.match(
          prompt,
          /photo gallery/,
          "prompt must reference the actual brief content, not be empty",
        );
        assert.match(
          prompt,
          /If asked which project you're working on, ground answers in this brief/,
          "prompt must instruct the agent NOT to ask 'what project'",
        );
      } finally {
        cleanup();
      }
    },
  );

  test(
    "a device ALREADY connected when seed lands also gets project context",
    () => {
      // Regression: previously `clientProjectContext.set(ws, …)` ran only
      // on the sending ws. A peer device that was already connected when
      // facilitator_start fired kept its old (or empty) context until it
      // reconnected — so its agent dispatches asked "what project are we in?"
      // even though the brief was already on disk.
      const { root, cleanup } = tmpHome();
      try {
        const h = new ServerHarness(root);
        const mac = h.connect("mac");
        const iPhone = h.connect("iphone");
        // iPhone runs facilitator_start AFTER both clients are already
        // connected. Mac must still see the brief in its prompt.
        h.facilitatorSeed(
          iPhone,
          "Ship a Slack bot for stand-ups.",
          new Date("2026-05-09T10:00:00Z"),
        );
        const macPrompt = h.promptFor(mac, "tech-lead#1");
        assert.match(
          macPrompt,
          /Slack bot/,
          "Mac was connected at seed time → must inherit the brief without reconnect",
        );
      } finally {
        cleanup();
      }
    },
  );

  test(
    "a second device that joins after the seed sees the same project context",
    () => {
      const { root, cleanup } = tmpHome();
      try {
        const h = new ServerHarness(root);
        const iPhone = h.connect("iphone");
        h.facilitatorSeed(
          iPhone,
          "Build a photo gallery with auth and offline mode.",
          new Date("2026-05-08T10:00:00Z"),
        );
        // Mac connects later — it must inherit the project memory via
        // team_memory.txt restore (mirrors server.ts:loadTeamMemory).
        const mac = h.connect("mac");
        const macPrompt = h.promptFor(mac, "tech-lead#1");
        assert.match(macPrompt, /photo gallery/, "Mac's prompt must reference brief from team memory");
      } finally {
        cleanup();
      }
    },
  );

  test(
    "after a reconnect (new ws), the agent prompt still has the brief",
    () => {
      const { root, cleanup } = tmpHome();
      try {
        const h = new ServerHarness(root);
        const iPhone = h.connect("iphone");
        h.facilitatorSeed(
          iPhone,
          "Build an iOS habit tracker with widgets.",
          new Date("2026-05-08T10:00:00Z"),
        );
        h.disconnect(iPhone);
        // Fresh ws session — no in-memory state. Reconnect MUST restore
        // the brief into the new client's project context.
        const iPhoneAgain = h.connect("iphone");
        const promptAfter = h.promptFor(iPhoneAgain, "manager#1");
        assert.match(
          promptAfter,
          /habit tracker/,
          "reconnecting iPhone must still see the brief, not lose project context",
        );
      } finally {
        cleanup();
      }
    },
  );

  test(
    "a fresh server boot replays facilitator output to new clients",
    () => {
      const { root, cleanup } = tmpHome();
      try {
        // Boot 1: seed a brief, then everyone leaves.
        {
          const h = new ServerHarness(root);
          const iPhone = h.connect("iphone");
          h.facilitatorSeed(
            iPhone,
            "Wire DeepSeek as a third backend.",
            new Date("2026-05-08T10:00:00Z"),
          );
          h.disconnect(iPhone);
        }
        // Boot 2: server restarts. The brief must survive — every new
        // device that joins gets the project context from team_memory.txt.
        const h2 = new ServerHarness(root);
        const mac = h2.connect("mac");
        const prompt = h2.promptFor(mac, "tech-lead#1");
        assert.match(
          prompt,
          /DeepSeek/,
          "post-restart prompt must still ground in the brief from disk",
        );
      } finally {
        cleanup();
      }
    },
  );
});

// ─── Bug 3: set_project leaves peer devices on the OLD project ───────────

describe("set_project sync across connected clients", () => {
  test(
    "switching project re-inits all connected clients, not just sender",
    () => {
      const { root: projectA, cleanup: cleanA } = tmpHome();
      const { root: projectB, cleanup: cleanB } = tmpHome();
      try {
        // Pre-seed projectB with a different brief on disk so we can
        // assert peers actually reload it.
        mkdirSync(projectB, { recursive: true });
        writeFileSync(
          join(projectB, "team_memory.txt"),
          "Project B: ship Slack integration.",
        );

        const h = new ServerHarness(projectA);
        const mac = h.connect("mac");
        const iPhone = h.connect("iphone");
        h.sendUserMessage(mac, "msg in project A", "2026-05-09T10:00:00Z");
        // Sanity: both clients see the projectA message.
        assert.equal(lastChatHistory(iPhone).length, 1);

        // Mac switches to project B. iPhone is still connected.
        h.setProject(mac, projectB);

        // iPhone (peer) MUST be re-inited to project B without reconnect.
        const iPhoneInits = iPhone.received.filter(
          (m) => m.type === "init",
        ) as Array<{ workingDirectory: string }>;
        assert.equal(
          iPhoneInits[iPhoneInits.length - 1].workingDirectory,
          projectB,
          "peer iPhone should receive an init pointing at the new project",
        );
        // iPhone's chat view must reflect projectB's empty history, not
        // projectA's stale snapshot.
        assert.equal(
          lastChatHistory(iPhone).length,
          0,
          "peer iPhone's chat must reset to projectB's history",
        );
        // iPhone's project memory must reload to projectB's brief.
        assert.match(
          h.clientProjectContext.get(iPhone.id) ?? "",
          /Slack integration/,
          "peer iPhone's project memory must reflect projectB's brief",
        );
      } finally {
        cleanA();
        cleanB();
      }
    },
  );

  test(
    "switching project clears peer scratch state, not just sender's",
    () => {
      const { root: projectA, cleanup: cleanA } = tmpHome();
      const { root: projectB, cleanup: cleanB } = tmpHome();
      try {
        const h = new ServerHarness(projectA);
        const mac = h.connect("mac");
        const iPhone = h.connect("iphone");
        h.sendUserMessage(iPhone, "first", "2026-05-09T10:00:00Z");
        h.sendUserMessage(iPhone, "second", "2026-05-09T10:01:00Z");
        assert.equal(h.clientScratch.get(iPhone.id)?.msgsSeen, 2);

        // Mac switches projects. iPhone's scratch should reset too —
        // otherwise stale per-ws state from project A bleeds into B.
        h.setProject(mac, projectB);
        assert.equal(
          h.clientScratch.get(iPhone.id)?.msgsSeen,
          0,
          "peer iPhone's scratch must be cleared when project switches",
        );
      } finally {
        cleanA();
        cleanB();
      }
    },
  );
});

// ─── deriveProjectMemoryFromBrief unit-level guarantees ───────────────────

describe("deriveProjectMemoryFromBrief", () => {
  test("includes the brief verbatim when short", () => {
    const out = deriveProjectMemoryFromBrief(
      "Photo gallery with auth.",
      new Date("2026-05-08T10:00:00Z"),
    );
    assert.match(out, /Photo gallery with auth\./);
    assert.match(out, /seeded 2026-05-08/);
  });

  test("caps long briefs at ~280 chars + ellipsis", () => {
    const long = "a".repeat(500);
    const out = deriveProjectMemoryFromBrief(long, new Date("2026-05-08T00:00:00Z"));
    assert.ok(out.includes("…"), "long brief must end with an ellipsis");
    // The summary line itself shouldn't blow past ~290 chars.
    const summaryLine = out.split("\n")[1];
    assert.ok(summaryLine.length <= 290, `summary line was ${summaryLine.length} chars`);
  });

  test("normalizes whitespace so multi-line briefs render cleanly", () => {
    const messy = "Build a thing\n\n   that does\tstuff   ";
    const out = deriveProjectMemoryFromBrief(messy, new Date("2026-05-08T00:00:00Z"));
    assert.match(out, /Build a thing that does stuff/);
    assert.ok(!out.match(/\n\n\n/), "no triple newlines");
  });
});
