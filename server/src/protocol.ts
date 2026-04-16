/**
 * WebSocket protocol between Flutter client and Node.js agent server.
 *
 * Client → Server: commands
 * Server → Client: events
 */

// ─── Client → Server ────────────────────────────────────────────────────────

export type ClientMessage =
  | { type: "send_message"; content: string; agentId: string; images?: string[] }
  | { type: "new_chat" }
  | { type: "resume_session"; sessionId: string }
  | { type: "clear_sessions" }
  | { type: "interrupt" }
  | { type: "get_status" }
  // Task board
  | { type: "board_get_state" }
  | { type: "board_create_task"; title: string; description?: string; color?: string; priority?: string }
  | { type: "board_move_task"; taskId: string; column: string }
  | { type: "board_update_task"; taskId: string; updates: Partial<TaskCardData> }
  | { type: "board_delete_task"; taskId: string }
  | { type: "board_assign_agent"; taskId: string; agentId: string; assign: boolean }
  // Project management
  | { type: "set_project"; path: string }
  | { type: "set_project_context"; memories: string }
  | { type: "generate_summary" }
  // Game economy
  | {
      type: "set_game_state";
      hiredAgents: string[];
      agentHardware: Record<string, number>; // HardwareTier enum index
      agentSkills: Record<string, Record<string, number>>; // skillType → level (1-10)
      fullState?: string; // JSON-encoded full GameState for cross-device sync
    }
  // Agent traits
  | { type: "get_traits" }
  | {
      type: "record_lesson";
      agentId: string;
      lessonType: "strength" | "weakness";
      category: string;
      tag: string;
      lesson: string;
    }
  | { type: "remove_lesson"; lessonId: string }
  // Live input sync
  | { type: "input_text"; text: string }
  | { type: "input_images"; images: string[] }
  // Character position sync
  | { type: "sync_positions"; positions: Record<string, { col: number; row: number; state: string; dir: string }> }
  // Permissions bypass toggle
  | { type: "set_bypass_permissions"; enabled: boolean }
  // iOS OTA deploy
  | { type: "ios_deploy_check" }
  | { type: "ios_deploy_start" }
  | { type: "ios_deploy_cancel" };

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

// ─── Task Board Types ──────────────────────────────────────────────────────

export type TaskColumnKey = "backlog" | "in_progress" | "testing" | "done";
export type TaskPriorityKey = "low" | "normal" | "high" | "urgent";
export type StickyColorKey = "yellow" | "pink" | "blue" | "green" | "orange" | "purple";

export interface TaskCardData {
  id: string;
  title: string;
  description: string;
  column: TaskColumnKey;
  priority: TaskPriorityKey;
  color: StickyColorKey;
  assignedAgents: string[];
  createdAt: string; // ISO 8601
  updatedAt: string;
}

// ─── Server → Client ────────────────────────────────────────────────────────

export type ServerMessage =
  | {
      type: "init";
      sessionId: string;
      agents: AgentInfo[];
      workingDirectory: string;
    }
  | {
      type: "assistant_text";
      text: string;
      isPartial: boolean;
      agentId: string;
    }
  | {
      type: "assistant_message_done";
      messageId: string;
      text: string;
      agentId: string;
    }
  | {
      type: "chat_history";
      messages: Array<{
        role: "user" | "assistant";
        text: string;
        agentId: string;
        timestamp: string;
        images?: string[];
      }>;
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
      type: "team_metrics";
      metrics: Record<string, { tasksAssigned: number; tasksCompleted: number; reworkCount: number }>;
    }
  | {
      type: "activity_event";
      timestamp: string;
      agentId: string;
      event: "started" | "tool_use" | "completed" | "delegated" | "error";
      detail: string;
    }
  | {
      type: "comm_graph";
      events: Array<{ timestamp: number; from: string; to: string }>;
    }
  | {
      type: "debug_log";
      timestamp: string;
      level: "debug" | "info" | "warn" | "error";
      category: string;
      message: string;
    }
  | {
      type: "error";
      message: string;
    }
  // Task board
  | {
      type: "board_state";
      tasks: TaskCardData[];
    }
  // Project memory
  | {
      type: "summary_result";
      summary: string;
    }
  // Live input sync
  | { type: "input_text"; text: string }
  | { type: "input_images"; images: string[] }
  // iOS OTA deploy
  | {
      type: "ios_deploy_status";
      subtype: "deps_result";
      hasFlutter: boolean;
    }
  | {
      type: "ios_deploy_status";
      subtype: "log";
      message: string;
    }
  | {
      type: "ios_deploy_status";
      subtype: "error";
      message: string;
    }
  | {
      type: "ios_deploy_status";
      subtype: "install_ready";
      installUrl: string;
    }
  | {
      type: "ios_deploy_status";
      subtype: "complete";
      success: boolean;
    }
  // Game state sync (cross-device)
  | {
      type: "game_state_sync";
      fullState: string; // JSON-encoded full GameState
    }
  // Character position sync (cross-device)
  | {
      type: "positions_sync";
      positions: Record<string, { col: number; row: number; state: string; dir: string }>;
    }
  // Agent traits
  | {
      type: "agent_traits";
      traits: Array<{
        id: string;
        agentId: string;
        type: "strength" | "weakness";
        category: string;
        tag: string;
        lesson: string;
        frequency: number;
        firstSeen: string;
        lastSeen: string;
      }>;
    };
