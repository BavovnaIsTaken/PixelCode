/**
 * Agent Hub WebSocket Server
 *
 * Bridges Flutter UI ↔ Claude Agent SDK.
 * Runs a Tech Lead session that delegates to 6 sub-agents.
 */

import { WebSocketServer, WebSocket } from "ws";
import {
  query,
  type SDKMessage,
  type SDKAssistantMessage,
  type SDKPartialAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage,
  type SDKToolProgressMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { teamAgents, techLeadPrompt, agentInfoList } from "./agents.js";
import type { ClientMessage, ServerMessage } from "./protocol.js";

const PORT = parseInt(process.env.PORT ?? "9720", 10);
const IMUX_CWD = process.env.IMUX_CWD ?? process.cwd();

// ─── Helpers ─────────────────────────────────────────────────────────────────

function send(ws: WebSocket, msg: ServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(msg));
  }
}

function toolStatusText(toolName: string, input: Record<string, unknown>): string {
  switch (toolName) {
    case "Read":
      return `Reading ${(input.file_path as string)?.split("/").pop() ?? "file"}`;
    case "Edit":
      return `Editing ${(input.file_path as string)?.split("/").pop() ?? "file"}`;
    case "Write":
      return `Writing ${(input.file_path as string)?.split("/").pop() ?? "file"}`;
    case "Bash":
      return `Running: ${((input.command as string) ?? "").slice(0, 60)}`;
    case "Grep":
      return `Searching: ${(input.pattern as string) ?? ""}`;
    case "Glob":
      return `Finding: ${(input.pattern as string) ?? ""}`;
    case "Agent":
      return `Delegating to ${(input.description as string) ?? "agent"}`;
    default:
      return `${toolName}`;
  }
}

// ─── Extract text from assistant message ─────────────────────────────────────

function extractText(msg: SDKAssistantMessage): string {
  const blocks = msg.message.content;
  return blocks
    .filter((b: { type: string }): b is { type: "text"; text: string } => b.type === "text")
    .map((b: { type: "text"; text: string }) => b.text)
    .join("");
}

// ─── Process SDK messages ────────────────────────────────────────────────────

function handleSDKMessage(ws: WebSocket, message: SDKMessage): void {
  switch (message.type) {
    case "system": {
      const sys = message as SDKSystemMessage;
      if (sys.subtype === "init") {
        send(ws, {
          type: "init",
          sessionId: sys.session_id,
          agents: agentInfoList,
        });
      }
      break;
    }

    case "assistant": {
      const asst = message as SDKAssistantMessage;
      // Skip sub-agent messages (they have parent_tool_use_id)
      if (asst.parent_tool_use_id) {
        // Parse tool uses for agent status
        for (const block of asst.message.content) {
          if (block.type === "tool_use") {
            const input = block.input as Record<string, unknown>;
            const status = toolStatusText(block.name, input);

            // Check if this is a sub-agent launch
            if (block.name === "Agent" || block.name === "Task") {
              send(ws, {
                type: "subagent_start",
                parentAgentId: "tech-lead",
                agentId: block.id,
                agentType: (input.subagent_type as string) ?? "general",
                task: (input.description as string) ?? "",
              });
            }

            send(ws, {
              type: "tool_use",
              agentId: asst.parent_tool_use_id ?? "tech-lead",
              toolUseId: block.id,
              toolName: block.name,
              status,
            });
          }
        }
        break;
      }

      // Top-level assistant message — this is the Tech Lead talking
      const text = extractText(asst);
      if (text) {
        send(ws, {
          type: "assistant_message_done",
          messageId: asst.uuid,
          text,
        });
      }

      // Parse tool uses from Tech Lead
      for (const block of asst.message.content) {
        if (block.type === "tool_use") {
          const input = block.input as Record<string, unknown>;
          const status = toolStatusText(block.name, input);

          if (block.name === "Agent" || block.name === "Task") {
            send(ws, {
              type: "subagent_start",
              parentAgentId: "tech-lead",
              agentId: block.id,
              agentType: (input.subagent_type as string) ?? "general",
              task: (input.description as string) ?? "",
            });
          }

          send(ws, {
            type: "tool_use",
            agentId: "tech-lead",
            toolUseId: block.id,
            toolName: block.name,
            status,
          });
        }
      }
      break;
    }

    case "stream_event": {
      const partial = message as SDKPartialAssistantMessage;
      // Only forward top-level (Tech Lead) streaming
      if (partial.parent_tool_use_id) break;

      const event = partial.event;
      if (
        event.type === "content_block_delta" &&
        event.delta.type === "text_delta"
      ) {
        send(ws, {
          type: "assistant_text",
          text: event.delta.text,
          isPartial: true,
        });
      }
      break;
    }

    case "tool_progress": {
      const prog = message as SDKToolProgressMessage;
      send(ws, {
        type: "agent_status",
        agentId: prog.parent_tool_use_id ?? "tech-lead",
        status: "running",
        tools: [
          {
            toolUseId: prog.tool_use_id,
            toolName: prog.tool_name,
            status: `${prog.tool_name} (${Math.round(prog.elapsed_time_seconds)}s)`,
          },
        ],
      });
      break;
    }

    case "result": {
      const res = message as SDKResultMessage;
      send(ws, {
        type: "result",
        text: "result" in res ? res.result : "",
        costUsd: res.total_cost_usd,
        durationMs: res.duration_ms,
      });
      // Reset all agent statuses to idle
      for (const agent of agentInfoList) {
        send(ws, {
          type: "agent_status",
          agentId: agent.id,
          status: "idle",
          tools: [],
        });
      }
      break;
    }
  }
}

// ─── Run query for a client ─────────────────────────────────────────────────

async function runQuery(ws: WebSocket, userMessage: string): Promise<void> {
  try {
    // Signal Tech Lead is thinking
    send(ws, {
      type: "agent_status",
      agentId: "tech-lead",
      status: "thinking",
      tools: [],
    });

    const q = query({
      prompt: userMessage,
      options: {
        systemPrompt: techLeadPrompt,
        model: "opus",
        allowedTools: ["Read", "Glob", "Grep", "Bash", "Agent"],
        agents: teamAgents,
        cwd: IMUX_CWD,
        includePartialMessages: true,
        permissionMode: "acceptEdits",
        maxTurns: 50,
      },
    });

    for await (const message of q) {
      handleSDKMessage(ws, message);
    }
  } catch (err) {
    send(ws, {
      type: "error",
      message: err instanceof Error ? err.message : String(err),
    });
  }
}

// ─── WebSocket server ───────────────────────────────────────────────────────

const wss = new WebSocketServer({ port: PORT });

console.log(`🏗️  Agent Hub server listening on ws://localhost:${PORT}`);
console.log(`   Working directory: ${IMUX_CWD}`);
console.log(`   Agents: ${agentInfoList.map((a) => a.name).join(", ")}`);

wss.on("connection", (ws) => {
  console.log("→ Client connected");

  // Send initial agent list immediately
  send(ws, {
    type: "init",
    sessionId: "pending",
    agents: agentInfoList,
  });

  ws.on("message", async (data) => {
    try {
      const msg = JSON.parse(data.toString()) as ClientMessage;

      switch (msg.type) {
        case "send_message":
          console.log(`← User: ${msg.content.slice(0, 80)}...`);
          await runQuery(ws, msg.content);
          break;

        case "get_status":
          // Return current agent statuses
          for (const agent of agentInfoList) {
            send(ws, {
              type: "agent_status",
              agentId: agent.id,
              status: "idle",
              tools: [],
            });
          }
          break;

        case "interrupt":
          console.log("← Interrupt requested");
          // TODO: store query ref and call q.interrupt()
          break;
      }
    } catch (err) {
      send(ws, {
        type: "error",
        message: `Invalid message: ${err}`,
      });
    }
  });

  ws.on("close", () => {
    console.log("→ Client disconnected");
  });
});
