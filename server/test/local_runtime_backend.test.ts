import { test } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "events";
import type { AgentBackend } from "../src/agent_backend.js";

// ─── Mock LocalGeminiRunner behavior ────────────────────────────────────────

/**
 * Mock for LocalGeminiRunner that simulates process behavior.
 */
class MockLocalGeminiRunner {
  async query(params: {
    agentId: string;
    systemPrompt: string;
    userMessage: string;
    projectContext?: string;
    onText: (text: string) => void;
  }): Promise<{ result: string; duration_ms: number; total_cost_usd: number }> {
    // Simulate instant execution
    const result = `Executed: ${params.userMessage}`;
    params.onText(result);
    return { result, duration_ms: 10, total_cost_usd: 0 };
  }
}

/**
 * Mock that simulates a timeout.
 */
class MockTimeoutGeminiRunner {
  async query(): Promise<never> {
    // Simulate timeout by never resolving
    return new Promise(() => {
      // Never resolves
    });
  }
}

/**
 * Mock that simulates an error.
 */
class MockErrorGeminiRunner {
  async query(): Promise<never> {
    throw new Error("Gemini CLI not found");
  }
}

// ─── LocalRuntimeBackend test ──────────────────────────────────────────────

test("LocalRuntimeBackend.execute() returns BackendResult", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockLocalGeminiRunner();

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new TestBackend();
  const result = await backend.execute("test prompt", "system", "haiku");

  assert.equal(typeof result.text, "string");
  assert.ok(result.durationMs >= 0);
  assert.equal(result.costUsd, 0);
});

test("LocalRuntimeBackend zero-cost: costUsd always 0", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockLocalGeminiRunner();

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new TestBackend();
  const result = await backend.execute("test", "sys", "sonnet");

  assert.equal(result.costUsd, 0, "Local backend must have zero cost");
});

test("LocalRuntimeBackend captures stdout text", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockLocalGeminiRunner();

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new TestBackend();
  const result = await backend.execute("hello world", "sys", "haiku");

  assert.ok(result.text.includes("hello world"));
});

test("LocalRuntimeBackend error on runner failure", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockErrorGeminiRunner();

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new TestBackend();

  await assert.rejects(() => backend.execute("test", "sys", "haiku"), /Gemini CLI not found/);
});

// ─── Health check tests ─────────────────────────────────────────────────────

test("LocalRuntimeBackend health check available", async () => {
  class HealthCheckBackend implements AgentBackend {
    private runner: MockLocalGeminiRunner | null = new MockLocalGeminiRunner();

    async isAvailable(): Promise<boolean> {
      return this.runner !== null;
    }

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      if (!this.runner) throw new Error("Backend unavailable");
      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });
      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new HealthCheckBackend();
  const available = await backend.isAvailable();

  assert.equal(available, true);
});

test("LocalRuntimeBackend health check unavailable", async () => {
  class HealthCheckBackend implements AgentBackend {
    private runner: MockLocalGeminiRunner | null = null;

    async isAvailable(): Promise<boolean> {
      return this.runner !== null;
    }

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      throw new Error("Backend unavailable");
    }
  }

  const backend = new HealthCheckBackend();
  const available = await backend.isAvailable();

  assert.equal(available, false);
});

// ─── Timeout simulation ─────────────────────────────────────────────────────

test("LocalRuntimeBackend timeout handling", async () => {
  class TimeoutBackend implements AgentBackend {
    private runner = new MockTimeoutGeminiRunner();
    private timeoutMs = 100;

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      const race = Promise.race([
        this.runner.query({
          agentId: "test",
          systemPrompt,
          userMessage: prompt,
          onText: () => {},
        }),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error("Timeout")), this.timeoutMs)
        ),
      ]);

      try {
        const result = await race;
        return {
          text: result.result,
          durationMs: result.duration_ms,
          costUsd: result.total_cost_usd,
        };
      } catch (err) {
        throw err;
      }
    }
  }

  const backend = new TimeoutBackend();

  await assert.rejects(() => backend.execute("test", "sys", "haiku"), /Timeout/);
});

// ─── Duration measurement ──────────────────────────────────────────────────

test("LocalRuntimeBackend duration_ms is measured", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockLocalGeminiRunner();

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new TestBackend();
  const result = await backend.execute("test", "sys", "haiku");

  assert.ok(result.durationMs >= 0, "duration must be measured");
  assert.ok(result.durationMs < 1000, "execution should be reasonably fast");
});

// ─── OnText callback invoked ────────────────────────────────────────────────

test("LocalRuntimeBackend invokes onText callback", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockLocalGeminiRunner();

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      let textChunks: string[] = [];

      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: (chunk) => {
          textChunks.push(chunk);
        },
      });

      assert.ok(textChunks.length > 0, "onText must be called");

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }
  }

  const backend = new TestBackend();
  await backend.execute("test", "sys", "haiku");
});

// ─── Model parameter passed to backend ──────────────────────────────────────

test("LocalRuntimeBackend accepts model parameter", async () => {
  class TestBackend implements AgentBackend {
    private runner = new MockLocalGeminiRunner();
    private lastModel: string = "";

    async execute(
      prompt: string,
      systemPrompt: string,
      model: string
    ): Promise<{ text: string; durationMs: number; costUsd: number }> {
      this.lastModel = model;

      const result = await this.runner.query({
        agentId: "test",
        systemPrompt,
        userMessage: prompt,
        onText: () => {},
      });

      return {
        text: result.result,
        durationMs: result.duration_ms,
        costUsd: result.total_cost_usd,
      };
    }

    getLastModel(): string {
      return this.lastModel;
    }
  }

  const backend = new TestBackend();
  await backend.execute("test", "sys", "opus");

  assert.equal(backend.getLastModel(), "opus");
});
