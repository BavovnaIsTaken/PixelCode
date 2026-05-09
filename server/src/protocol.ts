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
      localId?: string; // client-generated UUID, echoed in chat_history snapshot so client can match optimistic→canonical
      taskDifficulty?: number; // 1-5, optional; if set, server checks agent skill level
      forceSend?: boolean; // bypass skill-gate check
    }
  | { type: "new_chat" }
  | { type: "resume_session"; sessionId: string }
  | { type: "clear_sessions" }
  | { type: "interrupt" }
  | { type: "get_status" }
  // Task board
  | {
      type: "board_get_state";
      /**
       * Last revision the client has already applied. If the current server
       * revision matches, the server replies with `board_state_unchanged`
       * (no payload) instead of a full `board_state`. Lets reconnecting
       * clients avoid re-rendering identical state. Optional for backward
       * compatibility — old clients omit it and always get full state.
       */
      since?: number;
    }
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
  /**
   * Atomically seed multiple board tasks in a single transaction.
   *
   * Used by the facilitator pipeline so a partial-seed failure cannot
   * leave the board half-populated: either every task is committed or
   * none are. Validation (non-empty title, valid column) runs on every
   * task before any state mutates; the first invalid task aborts the
   * whole batch with a `board_seed_batch_result` describing the
   * failure.
   */
  | {
      type: "board_seed_batch";
      /** Optional client-supplied id so the response can be correlated. */
      batchId?: string;
      /** A `source` string the server stamps onto every task. The
       *  facilitator pipeline passes "facilitator" so downstream
       *  auto-dispatch can recognise these. */
      source?: string;
      tasks: Array<{
        title: string;
        description?: string;
        color?: string;
        priority?: string;
        column?: string;
        difficulty?: number;
        allowedRoles?: string[];
        taskType?: string;
        assignedAgents?: string[];
      }>;
    }
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
          provider?: number; // AgentProviderType enum index (0=cloud, 1=local, 3=deepseek, 4=kimi)
          skills: Record<string, number>; // skillType index → level (1-10)
        }
      >;
      fullState?: string; // JSON-encoded full GameState for cross-device sync
      stateUpdatedAt?: number; // epoch ms — last-write-wins guard, server rejects older
      deepseekApiKey?: string; // forwarded from client SharedPreferences, used by DeepSeek backend
      kimiApiKey?: string; // forwarded from client SharedPreferences, used by Kimi backend
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
  | { type: "set_consent"; agentId: string; enabled: boolean }
  | { type: "get_consent" }
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
  | { type: "android_deploy_watch_devices" }
  | { type: "android_deploy_unwatch_devices" }
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
    }
  // Pull request: client asks server for the persisted facilitator output.
  // Server replies with `facilitator_output_sync` if one exists, or nothing.
  | { type: "get_facilitator_output" }
  // Tech-lead pulse: client asks for the recent task-completion digest so it
  // can surface team activity in the UI (e.g. on the Hub). Server replies
  // with `tech_lead_pulse` (always sent, possibly with empty entries).
  | { type: "get_tech_lead_pulse"; limit?: number }
  // Push: client uploads its locally stored facilitator output so the server
  // can serve it to other devices. Sent when client finds output on disk but
  // the server may not have it yet (e.g. after a server restart or first sync).
  | { type: "push_facilitator_output"; outputFormat: string; outputJson: string }
  // Session presence — multi-device coordination
  | { type: "session_claim" }   // viewer requests to become primary
  | { type: "session_release" }; // primary voluntarily yields (or after takeover prompt)

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
      threadId?: string;
    }
  | {
      type: "assistant_message_done";
      messageId: string;
      text: string;
      agentId: string;
      threadId?: string;
      timestamp?: string; // server-canonical ISO8601 timestamp
    }
  | {
      type: "chat_history";
      messages: Array<{
        role: "user" | "assistant";
        text: string;
        agentId: string;
        timestamp: string;
        id?: string; // stable message identifier — allows client-server deduplication across devices
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
      threadId?: string;
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
      /**
       * Monotonically increasing revision, bumped on every server-side
       * mutation. Clients track the last revision they applied; an older
       * broadcast that arrives out of order can be ignored. Optional so
       * older clients keep working — they simply ignore the field.
       */
      revision?: number;
    }
  | {
      /**
       * Sent in response to a `board_get_state` with a `since` matching
       * the current server revision. Lets a reconnecting client know its
       * cached state is current without re-shipping every task.
       */
      type: "board_state_unchanged";
      revision: number;
    }
  /**
   * Acknowledgement for `board_seed_batch`. Always emitted, success or
   * failure. On `ok=true`, every task in the batch was committed and
   * the freshly-created ids are listed; on `ok=false`, no state changed
   * and `errors` describes the first invalid task.
   */
  | {
      type: "board_seed_batch_result";
      batchId?: string;
      ok: boolean;
      committedIds: string[];
      errors: Array<{ index: number; reason: string }>;
    }
  // Project memory
  | {
      type: "summary_result";
      summary: string;
    }
  // Roster — server-side validation rejected the set_game_state payload.
  // Sent only when at least one instance failed validation; the server's
  // internal state is unchanged and the client should surface these to
  // the user (toast / dialog) and roll back the offending mutation.
  | {
      type: "set_game_state_error";
      errors: Array<{
        instanceId: string;
        code: string;
        message: string;
      }>;
    }
  // Roster — emitted right after a successful set_game_state for every
  // instanceId that disappeared from the roster compared to the previous
  // accepted state. Lets the client clean up agent-scoped UI (open chat
  // tabs, busy indicators) without diff'ing two snapshots itself.
  | {
      type: "agent_fired";
      instanceId: string;
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
  | { type: "consent_state"; consent: Record<string, boolean> }
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
  | {
      type: "facilitator_error";
      /** Human-readable message; kept for backward compat. */
      error: string;
      /**
       * Typed failure code so the client can surface a specific UX:
       *   - "timeout"     — LLM call exceeded its time budget; retry
       *   - "parse"       — LLM returned no/invalid JSON; report style
       *   - "rate_limit"  — provider rate-limited; retry later
       *   - "auth"        — API key missing/invalid; settings prompt
       *   - "unknown"     — anything else (default)
       * Optional for forward compatibility with older clients.
       */
      code?: "timeout" | "parse" | "rate_limit" | "auth" | "unknown";
    }
  // Cross-device sync — sent to new clients on connect and broadcast to all
  // other clients when a new facilitator output is seeded. Same payload as
  // `facilitator_seeded` so clients can reuse the same decode path.
  | {
      type: "facilitator_output_sync";
      styleId: string;
      finalScore: ScopeScore;
      outputFormat: OutputFormatKey;
      outputJson: string;
    }
  // Session presence — multi-device coordination
  | {
      type: "session_status";
      /** Whether this client is now in primary or viewer mode. */
      mode: "primary" | "viewer";
      /** Device name of the current primary (present in viewer mode). */
      primaryDevice?: string;
    }
  | {
      type: "session_taken";
      /** Device name of the device that took the session. */
      byDevice: string;
    }
  // Tech-lead pulse — recent task-completion digest, sent in reply to
  // `tech_lead_pulse`. Always sent (entries may be empty) so the client
  // can transition out of a loading state. Newest entry last.
  | {
      type: "tech_lead_pulse";
      entries: Array<{
        taskId: string;
        title: string;
        agentId: string;
        role: string;
        outcome: "done";
        ts: string;
      }>;
    };

/** IDs of all network-diagnostic checks known to the server. `clientConnected` is client-only. */
export type HealthItemId =
  | "tailscaleInstalled"
  | "tailscaleRunning"
  | "funnelActive"
  | "serverListening"
  | "iosSigning"
  | "xcodeTools"
  | "androidSdk"
  | "androidSigning"
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
