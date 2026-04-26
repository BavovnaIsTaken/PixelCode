/**
 * WebSocket protocol between Flutter client and Node.js agent server.
 *
 * Client → Server: commands
 * Server → Client: events
 */

import type {
  FacilitatorStyle,
  IntakeAnswers,
  OutputFormatKey,
} from "./facilitator/types.js";
import type { ScopeScore } from "./quest/scope_scorer.js";

// ─── Client → Server ────────────────────────────────────────────────────────

export type ClientMessage =
  | {
      type: "send_message";
      content: string;
      agentId: string;
      images?: string[];
      taskDifficulty?: number; // 1-5, optional; if set, server checks agent skill level
      forceSend?: boolean; // bypass skill-gate check
    }
  | { type: "new_chat" }
  | { type: "resume_session"; sessionId: string }
  | { type: "clear_sessions" }
  | { type: "interrupt" }
  | { type: "get_status" }
  // Task board
  | { type: "board_get_state" }
  | {
      type: "board_create_task";
      title: string;
      description?: string;
      color?: string;
      priority?: string;
      difficulty?: number;
      allowedRoles?: string[];
      taskType?: string;
    }
  | { type: "board_move_task"; taskId: string; column: string }
  | { type: "board_update_task"; taskId: string; updates: Partial<TaskCardData> }
  | { type: "board_delete_task"; taskId: string }
  | { type: "board_assign_agent"; taskId: string; agentId: string; assign: boolean }
  | {
      type: "board_add_attachment";
      taskId: string;
      name: string;
      mimeType: string;
      sizeBytes: number;
      dataBase64: string;
    }
  | { type: "board_remove_attachment"; taskId: string; attachmentId: string }
  // Project management
  | { type: "set_project"; path: string }
  | { type: "set_project_context"; memories: string }
  | { type: "generate_summary" }
  // Game economy
  | {
      type: "set_game_state";
      /**
       * Hired agent instances keyed by instanceId (e.g. "coder#1").
       * Each entry carries the role type, nickname, hardware tier, and skills.
       */
      instances: Record<
        string,
        {
          roleType: string; // "coder", "reviewer", "manager", etc.
          nickname: string;
          hardware: number; // HardwareTier enum index (0..5)
          provider?: number; // AgentProviderType enum index (0=cloud, 1=local)
          skills: Record<string, number>; // skillType index → level (1-10)
        }
      >;
      fullState?: string; // JSON-encoded full GameState for cross-device sync
      stateUpdatedAt?: number; // epoch ms — last-write-wins guard, server rejects older
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
  | { type: "ios_deploy_cancel" }
  // Android deploy
  | { type: "android_deploy_check" }
  | { type: "android_deploy_list_devices" }
  | { type: "android_deploy_start"; deviceSerial?: string }
  | { type: "android_deploy_cancel" }
  // Device screenshot (Android via adb, iOS via simctl)
  | { type: "screenshot_capture"; platform: "android" | "ios"; deviceSerial?: string }
  // Tailscale setup
  | { type: "tailscale_connect" }
  // Network diagnostics
  | { type: "health_check_request" }
  | { type: "health_fix_request"; id: HealthItemId }
  // Client identification (sent on connect)
  | { type: "client_info"; clientId: string; deviceName: string; platform: string }
  // Dungeon training
  | { type: "start_dungeon"; agentId: string; skillType: number; difficulty: 1 | 2 | 3 }
  // Facilitator System — seed a project with a chosen facilitator style.
  // Client owns the FacilitatorStyle JSON (loaded from assets/facilitators/
  // or, later, marketplace) so the server stays neutral about presets.
  | {
      type: "facilitator_start";
      style: FacilitatorStyle;
      projectDescription: string;
      answers: IntakeAnswers;
    };

// ─── Server → Client ────────────────────────────────────────────────────────

/** Agent identity — refers to either a hired instance (preferred) or a role template. */
export interface AgentInfo {
  /** instanceId (e.g. "coder#1") when describing a hired instance; roleType (e.g. "coder") when describing a template. */
  id: string;
  /** Display nickname for instances, or role label for templates. */
  name: string;
  /** Ukrainian role label. */
  role: string;
  /** Effective Claude model. */
  model: string;
  /** Underlying role type — absent for legacy server responses, present for instances. */
  roleType?: string;
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

export interface TaskAttachmentData {
  id: string;
  name: string;
  mimeType: string;
  sizeBytes: number;
  dataBase64: string;
  uploadedAt: string;
}

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
  difficulty?: number; // 1-5 (1=trivial, 2=easy, 3=medium, 4=hard, 5=expert), default 2
  /** Role types eligible to take this task. Default `['coder']`. v5+. */
  allowedRoles?: string[];
  /** Task-type identifier (e.g. `'coding'`, `'review'`, `'testing'`). v5+. */
  taskType?: string;
  /** Inline file attachments. Server keeps base64 in memory; clients enforce size cap. */
  attachments?: TaskAttachmentData[];
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
  // Android deploy
  | {
      type: "android_deploy_status";
      subtype: "deps_result";
      hasFlutter: boolean;
    }
  | {
      type: "android_deploy_status";
      subtype: "log";
      message: string;
    }
  | {
      type: "android_deploy_status";
      subtype: "error";
      message: string;
    }
  | {
      type: "android_deploy_status";
      subtype: "install_ready";
      installUrl: string;
    }
  | {
      type: "android_deploy_status";
      subtype: "complete";
      success: boolean;
    }
  | {
      type: "android_deploy_status";
      subtype: "devices_list";
      devices: AndroidDeviceInfo[];
    }
  // Device screenshot
  | {
      type: "screenshot_status";
      subtype: "ready";
      platform: "android" | "ios";
      url: string;
    }
  | {
      type: "screenshot_status";
      subtype: "error";
      platform: "android" | "ios";
      message: string;
    }
  // Game state sync (cross-device)
  | {
      type: "game_state_sync";
      fullState: string; // JSON-encoded full GameState
      stateUpdatedAt: number; // epoch ms — clients reject older than their local state
    }
  // Character position sync (cross-device)
  | {
      type: "positions_sync";
      positions: Record<
        string,
        { col: number; row: number; state: string; dir: string; onSkateboard?: boolean }
      >;
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
    }
  // Server connection info (sent on connect + when tunnel becomes available)
  | {
      type: "server_info";
      hostname: string;
      localIps: string[];
      port: number;
      tunnelUrl: string | null; // wss://<machine>.<tailnet>.ts.net (Tailscale Funnel)
    }
  // Tailscale setup log line
  | { type: "tailscale_log"; message: string }
  // Network diagnostics
  | { type: "health_check_result"; items: HealthItem[] }
  | { type: "health_item_update"; item: HealthItem }
  // Task dispatch (non-blocking agent coordination)
  | {
      type: "task_dispatched";
      dispatchId: string;
      agentId: string;
      task: string;
      priority: string;
    }
  | {
      type: "subagent_result";
      dispatchId: string;
      agentId: string;
      result: string;
      costUsd: number;
      durationMs: number;
    }
  | {
      type: "queue_status";
      pending: number;
      running: Array<{ dispatchId: string; agentId: string; task: string; elapsedMs: number }>;
    }
  // Task difficulty gate
  | {
      type: "task_too_hard";
      agentId: string;
      required: number; // minimum avg skill level needed
      current: number; // agent's current avg skill level
    }
  // Dungeon training
  | {
      type: "dungeon_started";
      agentId: string;
      skillType: number;
      difficulty: number;
      challenge: string; // challenge description shown in UI
    }
  | {
      type: "dungeon_complete";
      agentId: string;
      skillType: number;
      xpEarned: number;
      score: number; // 1-10
      feedback: string;
      passed: boolean;
    }
  | { type: "dungeon_error"; agentId: string; error: string }
  // Facilitator System — seed result for a successful `facilitator_start`.
  // `outputJson` is the serialized `FacilitatorOutput` (with `format`
  // discriminator embedded); the client routes it through its registry.
  | {
      type: "facilitator_seeded";
      styleId: string;
      finalScore: ScopeScore;
      outputFormat: OutputFormatKey;
      outputJson: string;
    }
  | { type: "facilitator_error"; error: string };

/** IDs of all network-diagnostic checks known to the server. `clientConnected` is client-only. */
export type HealthItemId =
  | "tailscaleInstalled"
  | "tailscaleRunning"
  | "funnelActive"
  | "serverListening"
  | "iosSigning"
  | "xcodeTools"
  | "androidSdk"
  | "mdnsActive";

/** Status of a single health check item. */
export interface HealthItem {
  id: HealthItemId;
  status: "ok" | "fail" | "checking";
  detail?: string;
  fixable: boolean;
  instruction?: string;
}

/** Info about a connected Android device reported by `adb devices`. */
export interface AndroidDeviceInfo {
  serial: string;
  model: string; // human-readable model (e.g. "Pixel_6") — falls back to serial
  state: string; // "device" | "unauthorized" | "offline" | etc.
}

/** Info about a connected client device. Surfaced via the admin HTTP API
 *  (GET /admin/api/clients) and consumed by PixelDock — main clients no
 *  longer see the connected-devices list. */
export interface ConnectedClientInfo {
  clientId: string;
  deviceName: string; // OS hostname, sanitized
  platform: string; // "macos" | "ios" | "android" | "web" | "unknown"
  connectedAt: string; // ISO 8601
  isLocal: boolean; // true if client connects via loopback — shares machine with the server
}
