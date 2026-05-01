import { test } from "node:test";
import assert from "node:assert/strict";
import {
  subAgentMirrorToolUse,
  subAgentMirrorMessage,
  subAgentMirrorDelta,
} from "../src/server.ts";

const MGR = "manager#1";
const THREAD = "dispatch-abc";

// ─── subAgentMirrorToolUse ────────────────────────────────────────────────────

test("subAgentMirrorToolUse — type is tool_use", () => {
  const p = subAgentMirrorToolUse(MGR, "tu_1", "Read", "читаю файл", THREAD);
  assert.equal(p.type, "tool_use");
});

test("subAgentMirrorToolUse — agentId is manager", () => {
  const p = subAgentMirrorToolUse(MGR, "tu_1", "Read", "читаю файл", THREAD);
  assert.equal(p.agentId, MGR);
});

test("subAgentMirrorToolUse — toolUseId gets _m suffix", () => {
  const p = subAgentMirrorToolUse(MGR, "tu_1", "Read", "читаю файл", THREAD);
  assert.equal(p.toolUseId, "tu_1_m");
});

test("subAgentMirrorToolUse — toolName and status preserved", () => {
  const p = subAgentMirrorToolUse(MGR, "tu_1", "Bash", "npm test", THREAD);
  assert.equal(p.toolName, "Bash");
  assert.equal(p.status, "npm test");
});

test("subAgentMirrorToolUse — threadId preserved", () => {
  const p = subAgentMirrorToolUse(MGR, "tu_1", "Read", "читаю", THREAD);
  assert.equal(p.threadId, THREAD);
});

test("subAgentMirrorToolUse — different dispatches get distinct threadIds", () => {
  const p1 = subAgentMirrorToolUse(MGR, "tu_1", "Read", "s", "dispatch-A");
  const p2 = subAgentMirrorToolUse(MGR, "tu_2", "Read", "s", "dispatch-B");
  assert.notEqual(p1.threadId, p2.threadId);
});

// ─── subAgentMirrorMessage ────────────────────────────────────────────────────

test("subAgentMirrorMessage — type is assistant_message_done", () => {
  const p = subAgentMirrorMessage(MGR, "msg_1", "Готово", THREAD);
  assert.equal(p.type, "assistant_message_done");
});

test("subAgentMirrorMessage — agentId is manager", () => {
  const p = subAgentMirrorMessage(MGR, "msg_1", "Готово", THREAD);
  assert.equal(p.agentId, MGR);
});

test("subAgentMirrorMessage — messageId gets _m suffix", () => {
  const p = subAgentMirrorMessage(MGR, "msg_1", "Готово", THREAD);
  assert.equal(p.messageId, "msg_1_m");
});

test("subAgentMirrorMessage — text preserved verbatim", () => {
  const text = "Зробив рефактор у 5 файлах.";
  const p = subAgentMirrorMessage(MGR, "msg_1", text, THREAD);
  assert.equal(p.text, text);
});

test("subAgentMirrorMessage — threadId preserved", () => {
  const p = subAgentMirrorMessage(MGR, "msg_1", "ok", THREAD);
  assert.equal(p.threadId, THREAD);
});

test("subAgentMirrorMessage — mirror ids are unique across dispatches", () => {
  const p1 = subAgentMirrorMessage(MGR, "uuid-A", "t", "dispatch-A");
  const p2 = subAgentMirrorMessage(MGR, "uuid-B", "t", "dispatch-B");
  assert.notEqual(p1.messageId, p2.messageId);
  assert.notEqual(p1.threadId, p2.threadId);
});

// ─── subAgentMirrorDelta ──────────────────────────────────────────────────────

test("subAgentMirrorDelta — type is assistant_text", () => {
  const p = subAgentMirrorDelta(MGR, "chunk", THREAD);
  assert.equal(p.type, "assistant_text");
});

test("subAgentMirrorDelta — isPartial is true", () => {
  const p = subAgentMirrorDelta(MGR, "chunk", THREAD);
  assert.equal(p.isPartial, true);
});

test("subAgentMirrorDelta — agentId is manager", () => {
  const p = subAgentMirrorDelta(MGR, "chunk", THREAD);
  assert.equal(p.agentId, MGR);
});

test("subAgentMirrorDelta — text preserved", () => {
  const p = subAgentMirrorDelta(MGR, "шматочок тексту", THREAD);
  assert.equal(p.text, "шматочок тексту");
});

test("subAgentMirrorDelta — threadId preserved", () => {
  const p = subAgentMirrorDelta(MGR, "d", THREAD);
  assert.equal(p.threadId, THREAD);
});

// ─── Cross-helper consistency ─────────────────────────────────────────────────

test("tool_use and message for same dispatch share threadId", () => {
  const tu = subAgentMirrorToolUse(MGR, "tu_1", "Read", "s", THREAD);
  const msg = subAgentMirrorMessage(MGR, "msg_1", "done", THREAD);
  assert.equal(tu.threadId, msg.threadId);
});

test("delta and message for same dispatch share threadId", () => {
  const delta = subAgentMirrorDelta(MGR, "chunk", THREAD);
  const msg = subAgentMirrorMessage(MGR, "msg_1", "done", THREAD);
  assert.equal(delta.threadId, msg.threadId);
});

test("mirror ids never collide with original ids", () => {
  const originalToolUseId = "toolu_xyz";
  const originalMessageId = "msg_xyz";
  const tu = subAgentMirrorToolUse(MGR, originalToolUseId, "Read", "s", THREAD);
  const msg = subAgentMirrorMessage(MGR, originalMessageId, "t", THREAD);
  assert.notEqual(tu.toolUseId, originalToolUseId);
  assert.notEqual(msg.messageId, originalMessageId);
});
