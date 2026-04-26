import { spawn } from "child_process";
import { dbg } from "./server.js";

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
      // For the prototype, we wrap the message with the system prompt and context.
      // This is a naive implementation; the Gemini CLI might need a specific flag
      // for system prompts or structured input in the future.
      const fullPrompt = `${params.systemPrompt}\n\nContext:\n${params.projectContext ?? ""}\n\nTask: ${params.userMessage}`;
      
      const proc = spawn("gemini", [fullPrompt]);

      let fullText = "";

      proc.stdout.on("data", (data) => {
        const chunk = data.toString();
        fullText += chunk;
        params.onText(chunk);
      });

      proc.on("close", (code) => {
        const duration_ms = Date.now() - start;
        if (code === 0) {
          dbg("info", "local-gemini", `Local query for ${params.agentId} finished in ${duration_ms}ms`);
          resolve({ 
            result: fullText, 
            duration_ms,
            total_cost_usd: 0 
          });
        } else {
          const errorMsg = `Gemini CLI exited with code ${code}`;
          dbg("error", "local-gemini", errorMsg);
          reject(new Error(errorMsg));
        }
      });

      proc.on("error", (err) => {
        dbg("error", "local-gemini", `Failed to start Gemini CLI: ${err.message}`);
        reject(err);
      });
    });
  }
}
