import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, writeFileSync, mkdtempSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { ChatHistory, type StoredChatMessage } from "../src/chat_history.js";

// ─── Helpers ─────────────────────────────────────────────────────────────────

function makeMsg(
  role: "user" | "assistant",
  text: string,
  agentId = "coder#1",
  timestamp = new Date().toISOString()
): StoredChatMessage {
  return { role, text, agentId, timestamp };
}

function longText(chars: number): string {
  return "x".repeat(chars);
}

const tmpDir = mkdtempSync(join(tmpdir(), "chat-history-test-"));

function tmpFile(name: string): string {
  return join(tmpDir, name);
}

// ─── Basic operations ─────────────────────────────────────────────────────

test("ChatHistory starts empty", () => {
  const history = new ChatHistory();
  assert.ok(history.isEmpty);
});

test("ChatHistory is not empty after add", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "hello"));
  assert.ok(!history.isEmpty);
});

test("ChatHistory.add appends messages in order", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "msg1"));
  history.add(makeMsg("assistant", "msg2"));
  history.add(makeMsg("user", "msg3"));

  const snap = history.snapshot();
  assert.equal(snap.messages.length, 3);
  assert.equal(snap.messages[0].text, "msg1");
  assert.equal(snap.messages[1].text, "msg2");
  assert.equal(snap.messages[2].text, "msg3");
});

test("ChatHistory.add is idempotent on caller-supplied id", () => {
  const history = new ChatHistory();
  const msg: StoredChatMessage = {
    role: "user",
    text: "hello",
    agentId: "coder#1",
    timestamp: "2026-05-09T10:00:00Z",
    id: "client-msg-1",
  };
  history.add(msg);
  history.add(msg); // replay path: same id arrives twice

  const snap = history.snapshot();
  assert.equal(snap.messages.length, 1, "second add with same id must be skipped");
});

test("ChatHistory.add still appends when id differs even if other fields match", () => {
  const history = new ChatHistory();
  history.add({
    role: "user",
    text: "hello",
    agentId: "coder#1",
    timestamp: "2026-05-09T10:00:00Z",
    id: "msg-1",
  });
  history.add({
    role: "user",
    text: "hello",
    agentId: "coder#1",
    timestamp: "2026-05-09T10:00:00Z",
    id: "msg-2",
  });

  assert.equal(history.snapshot().messages.length, 2);
});

test("ChatHistory.add without id always appends (no fingerprint dedup)", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "hello"));
  history.add(makeMsg("user", "hello"));
  // No id supplied → server generates fresh UUIDs → both rows kept.
  assert.equal(history.snapshot().messages.length, 2);
});

test("ChatHistory.clear removes all messages", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "hello"));
  history.add(makeMsg("assistant", "world"));

  history.clear();

  assert.ok(history.isEmpty);
});

test("ChatHistory can add messages after clear", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "before"));
  history.clear();
  history.add(makeMsg("user", "after"));

  const snap = history.snapshot();
  assert.equal(snap.messages.length, 1);
  assert.equal(snap.messages[0].text, "after");
});

// ─── Snapshot ────────────────────────────────────────────────────────────────

test("snapshot type is 'chat_history'", () => {
  const history = new ChatHistory();
  const snap = history.snapshot();
  assert.equal(snap.type, "chat_history");
});

test("snapshot returns copy, not reference (mutating snap does not affect history)", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "original"));

  const snap = history.snapshot();
  (snap.messages as any[]).push({ role: "user", text: "injected" });

  const snap2 = history.snapshot();
  assert.equal(snap2.messages.length, 1, "original history unaffected");
});

test("snapshot of empty history has empty messages array", () => {
  const history = new ChatHistory();
  const snap = history.snapshot();
  assert.deepEqual(snap.messages, []);
});

// ─── Disk persistence ─────────────────────────────────────────────────────

test("save and load round-trips all messages", () => {
  const history = new ChatHistory();
  const ts = "2026-01-01T00:00:00.000Z";
  history.add(makeMsg("user", "hello", "coder#1", ts));
  history.add(makeMsg("assistant", "world", "reviewer#1", ts));

  const path = tmpFile("round-trip.json");
  history.save(path);

  const loaded = new ChatHistory();
  loaded.load(path);

  const snap = loaded.snapshot();
  assert.equal(snap.messages.length, 2);
  assert.equal(snap.messages[0].text, "hello");
  assert.equal(snap.messages[0].role, "user");
  assert.equal(snap.messages[1].text, "world");
});

test("load from non-existent file leaves history empty", () => {
  const history = new ChatHistory();
  history.load("/tmp/this-file-does-not-exist-xyz-123.json");
  assert.ok(history.isEmpty);
});

test("load from corrupt file leaves history empty", () => {
  const path = tmpFile("corrupt.json");
  writeFileSync(path, "{ not valid json }", "utf8");

  const history = new ChatHistory();
  history.load(path);
  assert.ok(history.isEmpty);
});

test("load clears existing history before loading", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "before-load"));

  const fresh = new ChatHistory();
  fresh.add(makeMsg("assistant", "disk-msg"));
  const path = tmpFile("replace.json");
  fresh.save(path);

  history.load(path);

  const snap = history.snapshot();
  assert.equal(snap.messages.length, 1);
  assert.equal(snap.messages[0].text, "disk-msg");
});

test("save creates parent directories if needed", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "test"));

  const path = join(tmpDir, "nested", "deep", "history.json");
  history.save(path);

  assert.ok(existsSync(path));
});

// ─── getContextMessages (token budget) ───────────────────────────────────────

test("getContextMessages returns all messages if under budget", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "a")); // 1 token
  history.add(makeMsg("assistant", "b")); // 1 token

  const msgs = history.getContextMessages("session", 100);
  assert.equal(msgs.length, 2);
});

test("getContextMessages returns empty array when history empty", () => {
  const history = new ChatHistory();
  const msgs = history.getContextMessages("session");
  assert.deepEqual(msgs, []);
});

test("getContextMessages respects token budget (drops oldest)", () => {
  const history = new ChatHistory();
  // Each "xxxx...x" (400 chars) = 100 tokens
  history.add(makeMsg("user", longText(400))); // 100 tokens — oldest
  history.add(makeMsg("assistant", longText(400))); // 100 tokens
  history.add(makeMsg("user", "short")); // 2 tokens — newest

  // Budget 150: can fit newest (2) + second (100) = 102, but not first
  const msgs = history.getContextMessages("session", 150);
  assert.equal(msgs.length, 2);
  assert.equal(msgs[msgs.length - 1].text, "short"); // Newest at end
});

test("getContextMessages returns messages in chronological order (oldest first)", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "first"));
  history.add(makeMsg("assistant", "second"));
  history.add(makeMsg("user", "third"));

  const msgs = history.getContextMessages("session");
  assert.equal(msgs[0].text, "first");
  assert.equal(msgs[1].text, "second");
  assert.equal(msgs[2].text, "third");
});

test("getContextMessages messages have generated IDs", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "hello"));

  const msgs = history.getContextMessages("session");
  assert.ok(msgs[0].id, "message should have an id");
  assert.ok(msgs[0].id!.startsWith("msg_"));
});

test("getContextMessages token estimation: text.length / 4 rounded up", () => {
  const history = new ChatHistory();
  // 5 chars = ceil(5/4) = 2 tokens
  history.add(makeMsg("user", "hello")); // 2 tokens
  history.add(makeMsg("user", "hi")); // 1 token

  // Budget of 2: should only fit "hi" (newest = 1 token)
  const msgs = history.getContextMessages("session", 2);
  assert.equal(msgs.length, 1);
  assert.equal(msgs[0].text, "hi");
});

// ─── markForCache ────────────────────────────────────────────────────────────

test("markForCache marks messages as cached", () => {
  const history = new ChatHistory();
  const ts = "2026-01-01T00:00:00.000Z";
  history.add(makeMsg("user", "hello", "coder#1", ts));

  // Get the message ID
  const msgs = history.getContextMessages("session");
  const msgId = msgs[0].id!;

  history.markForCache("session", [msgId]);

  const markedMsgs = history.getContextMessages("session");
  assert.equal(markedMsgs[0].metadata?.cachedForPrompt, true);
});

test("markForCache does not affect non-targeted messages", () => {
  const history = new ChatHistory();
  const ts1 = "2026-01-01T00:00:00.000Z";
  const ts2 = "2026-01-02T00:00:00.000Z";
  history.add(makeMsg("user", "msg1", "coder#1", ts1));
  history.add(makeMsg("assistant", "msg2", "coder#1", ts2));

  const msgs = history.getContextMessages("session");
  const firstId = msgs[0].id!;

  history.markForCache("session", [firstId]); // Only mark first

  const refreshed = history.getContextMessages("session");
  assert.equal(refreshed[0].metadata?.cachedForPrompt, true);
  assert.ok(!refreshed[1].metadata?.cachedForPrompt);
});

test("markForCache with empty id list has no effect", () => {
  const history = new ChatHistory();
  history.add(makeMsg("user", "hello"));

  history.markForCache("session", []); // No IDs

  const msgs = history.getContextMessages("session");
  assert.ok(!msgs[0].metadata?.cachedForPrompt);
});
