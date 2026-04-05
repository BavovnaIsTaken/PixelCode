/**
 * WebSocket protocol between Flutter client and Node.js agent server.
 *
 * Client → Server: commands
 * Server → Client: events
 */

// ─── Client → Server ────────────────────────────────────────────────────────

export type ClientMessage =
  | { type: "send_message"; content: string }
  | { type: "interrupt" }
  | { type: "get_status" };

// ─── Server → Client ────────────────────────────────────────────────────────

/** Agent identity */
export interface AgentInfo {
  id: string;
  name: string;
  role: string;
  model: string;
}

/** Agent activity status */
export type AgentStatus = "idle" | "thinking" | "typing" | "reading" | "running" | "waiting";

/** Tool activity within an agent */
export interface ToolActivity {
  toolUseId: string;
  toolName: string;
  status: string; // human-readable, e.g. "Reading main.dart"
}

export type ServerMessage =
  | {
      type: "init";
      sessionId: string;
      agents: AgentInfo[];
    }
  | {
      type: "assistant_text";
      text: string;
      isPartial: boolean;
    }
  | {
      type: "assistant_message_done";
      messageId: string;
      text: string;
    }
  | {
      type: "agent_status";
      agentId: string;
      status: AgentStatus;
      tools: ToolActivity[];
    }
  | {
      type: "subagent_start";
      parentAgentId: string;
      agentId: string;
      agentType: string;
      task: string;
    }
  | {
      type: "subagent_stop";
      agentId: string;
    }
  | {
      type: "tool_use";
      agentId: string;
      toolUseId: string;
      toolName: string;
      status: string;
    }
  | {
      type: "tool_done";
      agentId: string;
      toolUseId: string;
    }
  | {
      type: "result";
      text: string;
      costUsd: number;
      durationMs: number;
    }
  | {
      type: "error";
      message: string;
    };
