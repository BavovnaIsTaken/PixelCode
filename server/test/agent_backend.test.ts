import { test } from "node:test";
import assert from "node:assert/strict";
import type { AgentBackend, BackendResult } from "../src/agent_backend.js";

// ─── Interface contract tests ──────────────────────────────────────────────

test("BackendResult has correct shape", () => {
  const result: BackendResult = {
    text: "hello",
    durationMs: 100,
    costUsd: 0.5,
  };

  assert.equal(typeof result.text, "string");
  assert.equal(typeof result.durationMs, "number");
  assert.equal(typeof result.costUsd, "number");
});

test("BackendResult durationMs is non-negative", () => {
  const result: BackendResult = {
    text: "output",
    durationMs: 0,
    costUsd: 0,
  };

  assert.ok(result.durationMs >= 0, "durationMs must be >= 0");
});

test("BackendResult costUsd is non-negative", () => {
  const result: BackendResult = {
    text: "output",
    durationMs: 50,
    costUsd: 0,
  };

  assert.ok(result.costUsd >= 0, "costUsd must be >= 0");
});

// ─── Mock backend satisfies interface ───────────────────────────────────────

test("MockBackend implements AgentBackend", async () => {
  const mockBackend: AgentBackend = {
    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      return {
        text: `Executed with model ${model}`,
        durationMs: 42,
        costUsd: 0.01,
      };
    },
  };

  const result = await mockBackend.execute("test prompt", "system", "haiku");

  assert.equal(result.text, "Executed with model haiku");
  assert.equal(result.durationMs, 42);
  assert.equal(result.costUsd, 0.01);
});

// ─── Execute method contract ───────────────────────────────────────────────

test("execute() with empty prompt returns result", async () => {
  const mockBackend: AgentBackend = {
    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      return {
        text: "",
        durationMs: 0,
        costUsd: 0,
      };
    },
  };

  const result = await mockBackend.execute("", "", "haiku");

  assert.equal(result.text, "");
});

test("execute() accepts all three parameters", async () => {
  const mockBackend: AgentBackend = {
    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      assert.equal(typeof prompt, "string");
      assert.equal(typeof systemPrompt, "string");
      assert.equal(typeof model, "string");

      return {
        text: "ok",
        durationMs: 10,
        costUsd: 0,
      };
    },
  };

  await mockBackend.execute("test prompt", "system", "opus");
});

// ─── Error propagation ──────────────────────────────────────────────────────

test("execute() error is propagated to caller", async () => {
  const mockBackend: AgentBackend = {
    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      throw new Error("Backend failed");
    },
  };

  await assert.rejects(
    () => mockBackend.execute("test", "sys", "haiku"),
    /Backend failed/
  );
});

test("execute() rejection is caught as Promise rejection", async () => {
  const mockBackend: AgentBackend = {
    async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
      return Promise.reject(new Error("Network error"));
    },
  };

  await assert.rejects(
    () => mockBackend.execute("test", "sys", "haiku"),
    /Network error/
  );
});
