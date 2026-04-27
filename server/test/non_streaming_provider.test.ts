import { test } from "node:test";
import assert from "node:assert/strict";
import type { WebSocket } from "ws";
import type { AgentBackend, BackendResult } from "../src/agent_backend.js";
import type { ServerMessage } from "../src/protocol.js";
import {
  runNonStreamingBackend,
  type NonStreamingProviderConfig,
} from "../src/non_streaming_provider.js";

// ─── Test helpers ──────────────────────────────────────────────────────────

function makeBackend(result: Partial<BackendResult> = {}): AgentBackend {
  return {
    async execute(): Promise<BackendResult> {
      return {
        text: "model output",
        durationMs: 42,
        costUsd: 0.001,
        ...result,
      };
    },
  };
}

interface CapturedExecuteCall {
  prompt: string;
  systemPrompt: string;
  model: string;
}

function makeRecordingBackend(
  captured: CapturedExecuteCall[],
): AgentBackend {
  return {
    async execute(prompt, systemPrompt, model): Promise<BackendResult> {
      captured.push({ prompt, systemPrompt, model });
      return { text: "ok", durationMs: 1, costUsd: 0 };
    },
  };
}

interface CapturedSend {
  msg: ServerMessage;
}

function makeSend(captured: CapturedSend[]) {
  return (_ws: WebSocket, msg: ServerMessage) => {
    captured.push({ msg });
  };
}

const fakeWs = {} as WebSocket;

function configWith(
  overrides: Partial<NonStreamingProviderConfig> = {},
): NonStreamingProviderConfig {
  return {
    getKey: () => "sk-test-key",
    createBackend: () => makeBackend(),
    sessionId: "test-provider",
    missingKeyError: "Test key missing",
    ...overrides,
  };
}

async function collect<T>(gen: AsyncGenerator<T>): Promise<T[]> {
  const out: T[] = [];
  for await (const v of gen) out.push(v);
  return out;
}

// ─── Happy-path: yield sequence ────────────────────────────────────────────

test("yields exactly two messages: assistant + result", async () => {
  const sent: CapturedSend[] = [];
  const messages = await collect(
    runNonStreamingBackend({
      config: configWith(),
      ws: fakeWs,
      prompt: "hi",
      systemPrompt: "be helpful",
      model: "haiku",
      agentId: "coder#1",
      send: makeSend(sent),
    }),
  );

  assert.equal(messages.length, 2);
  assert.equal((messages[0] as { type: string }).type, "assistant");
  assert.equal((messages[1] as { type: string }).type, "result");
});

test("first yield carries assistant content + cost/duration from backend", async () => {
  const messages = await collect(
    runNonStreamingBackend({
      config: configWith({
        createBackend: () =>
          makeBackend({ text: "the answer", durationMs: 123, costUsd: 0.5 }),
      }),
      ws: fakeWs,
      prompt: "p",
      systemPrompt: "s",
      model: "sonnet",
      agentId: "a",
      send: makeSend([]),
    }),
  );

  const assistantMsg = messages[0] as {
    message: { content: Array<{ text: string }> };
    duration_ms: number;
    usage: { total_cost_usd: number };
    session_id: string;
  };
  assert.equal(assistantMsg.message.content[0].text, "the answer");
  assert.equal(assistantMsg.duration_ms, 123);
  assert.equal(assistantMsg.usage.total_cost_usd, 0.5);
  assert.equal(assistantMsg.session_id, "test-provider");
});

test("result yield mirrors text/duration/cost from backend", async () => {
  const messages = await collect(
    runNonStreamingBackend({
      config: configWith({
        createBackend: () =>
          makeBackend({ text: "answer", durationMs: 77, costUsd: 0.02 }),
      }),
      ws: fakeWs,
      prompt: "p",
      systemPrompt: "s",
      model: "opus",
      agentId: "a",
      send: makeSend([]),
    }),
  );

  const resultMsg = messages[1] as {
    type: string;
    result: string;
    duration_ms: number;
    total_cost_usd: number;
  };
  assert.equal(resultMsg.result, "answer");
  assert.equal(resultMsg.duration_ms, 77);
  assert.equal(resultMsg.total_cost_usd, 0.02);
});

test("session_id label is taken from the provider config", async () => {
  const messages = await collect(
    runNonStreamingBackend({
      config: configWith({ sessionId: "deepseek" }),
      ws: fakeWs,
      prompt: "p",
      systemPrompt: "s",
      model: "haiku",
      agentId: "a",
      send: makeSend([]),
    }),
  );

  const assistantMsg = messages[0] as { session_id: string };
  assert.equal(assistantMsg.session_id, "deepseek");
});

// ─── send() side-effect ────────────────────────────────────────────────────

test("sends one assistant_text WS message before yielding", async () => {
  const sent: CapturedSend[] = [];
  await collect(
    runNonStreamingBackend({
      config: configWith({
        createBackend: () => makeBackend({ text: "streamed text" }),
      }),
      ws: fakeWs,
      prompt: "p",
      systemPrompt: "s",
      model: "haiku",
      agentId: "reviewer#2",
      send: makeSend(sent),
    }),
  );

  assert.equal(sent.length, 1);
  const msg = sent[0].msg as {
    type: string;
    text: string;
    isPartial: boolean;
    agentId: string;
  };
  assert.equal(msg.type, "assistant_text");
  assert.equal(msg.text, "streamed text");
  assert.equal(msg.isPartial, false);
  assert.equal(msg.agentId, "reviewer#2");
});

// ─── Backend invocation contract ───────────────────────────────────────────

test("backend.execute() receives prompt + systemPrompt + model verbatim", async () => {
  const captured: CapturedExecuteCall[] = [];
  await collect(
    runNonStreamingBackend({
      config: configWith({ createBackend: () => makeRecordingBackend(captured) }),
      ws: fakeWs,
      prompt: "user prompt",
      systemPrompt: "you are X",
      model: "sonnet",
      agentId: "a",
      send: makeSend([]),
    }),
  );

  assert.equal(captured.length, 1);
  assert.deepEqual(captured[0], {
    prompt: "user prompt",
    systemPrompt: "you are X",
    model: "sonnet",
  });
});

test("createBackend is called with the resolved API key", async () => {
  let receivedKey: string | undefined;
  await collect(
    runNonStreamingBackend({
      config: configWith({
        getKey: () => "sk-live-1234",
        createBackend: (key) => {
          receivedKey = key;
          return makeBackend();
        },
      }),
      ws: fakeWs,
      prompt: "p",
      systemPrompt: "s",
      model: "haiku",
      agentId: "a",
      send: makeSend([]),
    }),
  );

  assert.equal(receivedKey, "sk-live-1234");
});

// ─── Missing-key error path ────────────────────────────────────────────────

test("throws missingKeyError when getKey returns undefined", async () => {
  const gen = runNonStreamingBackend({
    config: configWith({
      getKey: () => undefined,
      missingKeyError: "Custom: key not set",
    }),
    ws: fakeWs,
    prompt: "p",
    systemPrompt: "s",
    model: "haiku",
    agentId: "a",
    send: makeSend([]),
  });

  await assert.rejects(() => gen.next(), /Custom: key not set/);
});

test("does not call createBackend when key is missing", async () => {
  let createdCount = 0;
  const gen = runNonStreamingBackend({
    config: configWith({
      getKey: () => undefined,
      createBackend: () => {
        createdCount++;
        return makeBackend();
      },
    }),
    ws: fakeWs,
    prompt: "p",
    systemPrompt: "s",
    model: "haiku",
    agentId: "a",
    send: makeSend([]),
  });

  await assert.rejects(() => gen.next());
  assert.equal(createdCount, 0);
});

test("does not send any WS message when key is missing", async () => {
  const sent: CapturedSend[] = [];
  const gen = runNonStreamingBackend({
    config: configWith({ getKey: () => undefined }),
    ws: fakeWs,
    prompt: "p",
    systemPrompt: "s",
    model: "haiku",
    agentId: "a",
    send: makeSend(sent),
  });

  await assert.rejects(() => gen.next());
  assert.equal(sent.length, 0);
});

// ─── Backend error propagation ─────────────────────────────────────────────

test("backend.execute() rejection surfaces from the generator", async () => {
  const erroringBackend: AgentBackend = {
    async execute() {
      throw new Error("upstream 503");
    },
  };

  const gen = runNonStreamingBackend({
    config: configWith({ createBackend: () => erroringBackend }),
    ws: fakeWs,
    prompt: "p",
    systemPrompt: "s",
    model: "haiku",
    agentId: "a",
    send: makeSend([]),
  });

  await assert.rejects(() => collect(gen), /upstream 503/);
});

test("send() runs before backend errors are even possible (key check first)", async () => {
  // If getKey fails, backend should never be created; assertion above already
  // covers it. This test pairs: when getKey succeeds + backend rejects, the
  // assistant_text send should NOT have happened, because send is after execute.
  const sent: CapturedSend[] = [];
  const erroringBackend: AgentBackend = {
    async execute() {
      throw new Error("net err");
    },
  };

  const gen = runNonStreamingBackend({
    config: configWith({ createBackend: () => erroringBackend }),
    ws: fakeWs,
    prompt: "p",
    systemPrompt: "s",
    model: "haiku",
    agentId: "a",
    send: makeSend(sent),
  });

  await assert.rejects(() => collect(gen), /net err/);
  assert.equal(
    sent.length,
    0,
    "no WS messages should leak when execute() rejects",
  );
});
