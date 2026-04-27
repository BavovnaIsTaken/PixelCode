import { spawn } from "child_process";
import { dbg } from "./server.js";
import {
  LocalGeminiError,
  classifyGeminiError,
  tryParseGeminiJson,
} from "./gemini_errors.js";

export {
  LocalGeminiError,
  classifyGeminiError,
  tryParseGeminiJson,
} from "./gemini_errors.js";
export type { LocalGeminiErrorKind } from "./gemini_errors.js";

/**
 * Result of a local execution, mimicking parts of the Claude SDK result.
 */
export interface LocalExecutionResult {
  result: string;
  duration_ms: number;
  total_cost_usd: number; // Always 0 for local
}

/**
 * Bridge to the Gemini CLI.
 * Mimics the core 'query' behavior of the Claude Agent SDK but runs locally.
 */
export class LocalGeminiRunner {
  /**
   * Executes a task using the local Gemini CLI.
   * Currently uses a simplified 'one-shot' call.
   * Future versions will support persistent sessions and tool use.
   */
  async query(params: {
    agentId: string;
    systemPrompt: string;
    userMessage: string;
    projectContext?: string;
    onText: (text: string) => void;
  }): Promise<LocalExecutionResult> {
    const start = Date.now();
    dbg("info", "local-gemini", `Starting local query for ${params.agentId}...`);

    return new Promise((resolve, reject) => {
      const fullPrompt = `${params.systemPrompt}\n\nContext:\n${params.projectContext ?? ""}\n\nTask: ${params.userMessage}`;

      const proc = spawn("gemini", ["-p", fullPrompt, "--output-format", "json"]);

      let stdout = "";
      let stderr = "";

      proc.stdout.on("data", (data) => {
        const chunk = data.toString();
        stdout += chunk;
        params.onText(chunk);
      });

      proc.stderr.on("data", (data) => {
        stderr += data.toString();
      });

      proc.on("close", (code) => {
        const duration_ms = Date.now() - start;

        const parsed = tryParseGeminiJson(stdout);
        if (parsed?.error) {
          const err = classifyGeminiError(parsed.error, stderr);
          dbg("error", "local-gemini", `${err.kind}: ${err.message}`);
          reject(err);
          return;
        }

        if (code === 0) {
          dbg("info", "local-gemini", `Local query for ${params.agentId} finished in ${duration_ms}ms`);
          resolve({
            result: parsed?.response ?? stdout,
            duration_ms,
            total_cost_usd: 0,
          });
        } else {
          const err = classifyGeminiError({ message: stderr || `exit ${code}` }, stderr);
          dbg("error", "local-gemini", `${err.kind}: ${err.message}`);
          reject(err);
        }
      });

      proc.on("error", (err) => {
        const code = (err as NodeJS.ErrnoException).code;
        if (code === "ENOENT") {
          reject(new LocalGeminiError(
            "binary_missing",
            "gemini CLI not found on PATH. Install: npm i -g @google/gemini-cli",
          ));
          return;
        }
        dbg("error", "local-gemini", `Failed to start Gemini CLI: ${err.message}`);
        reject(new LocalGeminiError("process_error", err.message));
      });
    });
  }
}
