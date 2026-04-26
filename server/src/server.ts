/**
 * PixelCode WebSocket Server
 *
 * Bridges Flutter UI ↔ Claude Agent SDK.
 * Runs a Manager session that delegates to team agents.
 */

import { WebSocketServer, WebSocket } from "ws";
import { rmSync, readdirSync, existsSync, readFileSync, mkdirSync, writeFileSync } from "fs";
import { join, extname, dirname } from "path";
import { homedir, hostname, networkInterfaces } from "os";
import { execFile, execFileSync, spawn, ChildProcess } from "child_process";
import { createServer as createHttpServer, IncomingMessage, ServerResponse } from "http";
import { Bonjour } from "bonjour-service";
import {
  query,
  tool,
  createSdkMcpServer,
  type SDKMessage,
  type SDKAssistantMessage,
  type SDKPartialAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage,
  type SDKToolProgressMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import {
  roleCatalog,
  roleTemplateFor,
  roleTypeOf,
  buildOfficePrompt,
  buildDynamicAgents,
  buildHiredAgentInfoList,
  hardwareToModel,
  skillsToModel,
  type GameStateData,
  type HiredAgentInfo,
} from "./agents.js";
import { runDungeon, getChallenge } from "./dungeon.js";
import type { ClientMessage, ServerMessage, TaskCardData, TaskAttachmentData, TaskColumnKey, StickyColorKey, TaskPriorityKey, ConnectedClientInfo } from "./protocol.js";
import {
  loadTraits, saveTraits, recordLesson, removeLesson,
  formatTraitsForPrompt, getAllTraits,
  type TraitStore, type LessonType, type LessonCategory,
} from "./trait_memory.js";
import { TaskQueue, type QueuedTask } from "./task_queue.js";
import { AgentRunner, type SubAgentResult } from "./agent_runner.js";
import { ChatHistory } from "./chat_history.js";
import { AgentContextPreparer } from "./agent_context.js";
import { injectLearnedContext, applyLlmLessons, type LlmLesson } from "./personalization.js";
import { profileCache } from "./profile_cache.js";
import { lessonExtractor } from "./lesson_extractor.js";
import { runAllChecks, runSingleCheck, runFix, type HealthContext } from "./health.js";
import type { HealthItemId } from "./protocol.js";
import { loadConfig, type ServerConfig } from "./config.js";
import { handleAdminRequest, recordLog, type AdminContext } from "./admin.js";

// ─── Config (file → env → CLI flags, highest precedence last) ───────────────

function parseCliFlags(argv: string[]): { flags: Partial<ServerConfig>; configPath?: string } {
  const flags: Partial<ServerConfig> = {};
  let configPath: string | undefined;
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    const eq = arg.indexOf("=");
    const key = eq === -1 ? arg : arg.slice(0, eq);
    const value = eq === -1 ? argv[++i] : arg.slice(eq + 1);
    if (value === undefined) continue;
    switch (key) {
      case "--port": case "-p": {
        const n = parseInt(value, 10);
        if (Number.isFinite(n)) flags.port = n;
        break;
      }
      case "--cwd": case "--project-cwd": flags.projectCwd = value; break;
      case "--ota-hostname": flags.otaHostname = value; break;
      case "--config": configPath = value; break;
    }
  }
  return { flags, configPath };
}

const __cli = parseCliFlags(process.argv);
const __configSource = loadConfig({ configPath: __cli.configPath, flags: __cli.flags });
const PORT = __configSource.effective.port;
let PROJECT_CWD = __configSource.effective.projectCwd;
const __bootedAtMs = Date.now();

// ─── Debug logging ──────────────────────────────────────────────────────────

type DebugLevel = "debug" | "info" | "warn" | "error";

/** Stores log entries produced before any WebSocket client connects. */
const earlyLogBuffer: Array<{ level: DebugLevel; category: string; message: string; timestamp: string }> = [];
let wsClientsReady = false;

function dbg(level: DebugLevel, category: string, message: string, data?: unknown): void {
  const ts = new Date().toISOString().slice(11, 23); // HH:MM:SS.mmm
  const prefix = { debug: "🔍", info: "ℹ️ ", warn: "⚠️ ", error: "❌" }[level];
  const line = `${ts} ${prefix} [${category}] ${message}`;
  if (data !== undefined) {
    console.log(line, typeof data === "string" ? data : JSON.stringify(data, null, 2));
  } else {
    console.log(line);
  }
  const isoTs = new Date().toISOString();
  recordLog({ level, category, message, timestamp: isoTs });
  // Buffer early logs so they can be replayed when the first client connects
  if (!wsClientsReady) {
    earlyLogBuffer.push({ level, category, message, timestamp: isoTs });
  } else {
    for (const client of wss.clients) {
      if ((client as WebSocket).readyState === WebSocket.OPEN) {
        sendDebug(client as WebSocket, level, category, message);
      }
    }
  }
}

/** Forward debug log to the Flutter debug console. */
function sendDebug(ws: WebSocket, level: DebugLevel, category: string, message: string): void {
  send(ws, {
    type: "debug_log",
    timestamp: new Date().toISOString(),
    level,
    category,
    message,
  });
}

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
    case "mcp__dispatch__dispatch":
      return `Dispatching to ${(input.agent as string) ?? "agent"}`;
    case "mcp__dispatch__team_status":
      return `Checking team status`;
    case "mcp__dispatch__cancel_task":
      return `Cancelling task`;
    case "mcp__dispatch__board_create_task":
      return `Adding task: ${((input.title as string) ?? "").slice(0, 40)}`;
    case "mcp__dispatch__board_move_task":
      return `Moving task → ${(input.column as string) ?? ""}`;
    case "mcp__dispatch__board_update_task":
      return `Updating task ${(input.taskId as string) ?? ""}`;
    case "mcp__dispatch__board_assign_agent":
      return `${(input.assign as boolean) ? "Assigning" : "Unassigning"} ${(input.agentId as string) ?? ""}`;
    case "mcp__dispatch__board_list":
      return `Reading task board`;
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

function handleSDKMessage(ws: WebSocket, message: SDKMessage, targetAgentId: string = "manager"): void {
  // Log every SDK message type (except noisy stream_event)
  if (message.type !== "stream_event") {
    dbg("debug", "sdk", `${message.type}${
      message.type === "system" ? `/${(message as SDKSystemMessage).subtype}` :
      message.type === "assistant" ? `${(message as SDKAssistantMessage).parent_tool_use_id ? " (sub-agent)" : " (top-level)"}` :
      ""
    }`);
  }

  try {
  switch (message.type) {
    case "system": {
      const sys = message as SDKSystemMessage;
      sendDebug(ws, "info", "sdk", `system/${sys.subtype} session=${sys.session_id}`);
      if (sys.subtype === "init") {
        send(ws, {
          type: "init",
          sessionId: sys.session_id,
          agents: agentInfoForClient(ws),
          workingDirectory: PROJECT_CWD,
        });
      }
      break;
    }

    case "assistant": {
      const asst = message as SDKAssistantMessage;
      // Skip sub-agent messages (they have parent_tool_use_id)
      if (asst.parent_tool_use_id) {
        // Resolve the parent agent name from the tool_use_id map
        const parentAgent = resolveAgentId(ws, asst.parent_tool_use_id);

        // Parse tool uses for agent status
        for (const block of asst.message.content) {
          if (block.type === "tool_use") {
            const input = block.input as Record<string, unknown>;
            const status = toolStatusText(block.name, input);

            // Check if this is a sub-agent launch (nested delegation)
            if (block.name === "Agent" || block.name === "Task") {
              const agentType = (input.subagent_type as string) ?? "general";
              const taskDesc = (input.description as string) ?? "";

              // Register sub-agent tool_use_id → agent name
              getAgentMap(ws).set(block.id, agentType);

              send(ws, {
                type: "subagent_start",
                parentAgentId: parentAgent,
                agentId: block.id,
                agentType,
                task: taskDesc,
              });

              emitActivity(ws, parentAgent, "delegated", `→ ${agentType}: ${taskDesc}`);
              emitActivity(ws, agentType, "started", taskDesc);

              // Track metrics: task assigned
              const m = getAgentMetrics(ws, agentType);
              const activeTasks = getActiveTasks(ws);
              const prevCount = activeTasks.get(agentType) ?? 0;
              if (prevCount > 0) {
                m.reworkCount++;
                autoLearnLesson(ws, agentType, "weakness", "problem_solving", "task-rework",
                  `Required rework on task — previous attempt was insufficient. Needs more thorough analysis before starting.`);
              }
              m.tasksAssigned++;
              activeTasks.set(agentType, prevCount + 1);
              sendMetrics(ws);
            } else {
              // Non-delegation tool use from a sub-agent
              emitActivity(ws, parentAgent, "tool_use", status);
            }

            send(ws, {
              type: "tool_use",
              agentId: parentAgent,
              toolUseId: block.id,
              toolName: block.name,
              status,
            });
          }
        }
        break;
      }

      // Top-level assistant message — this is the addressed agent talking
      const text = extractText(asst);
      if (text) {
        chatHistory.add({ role: "assistant", text, agentId: targetAgentId, timestamp: new Date().toISOString() });
        chatHistory.save(historyFilePath(PROJECT_CWD));
        broadcastAll({ type: "assistant_message_done", messageId: asst.uuid, text, agentId: targetAgentId });
        clientSentAssistantMessage.set(ws, true);
      }

      // Parse tool uses from addressed agent
      for (const block of asst.message.content) {
        if (block.type === "tool_use") {
          const input = block.input as Record<string, unknown>;
          const status = toolStatusText(block.name, input);

          // Dispatch MCP tools are handled by the MCP server callback — skip delegation tracking here
          if (block.name.startsWith("mcp__dispatch__")) {
            // Just send the tool_use notification for UI status
            send(ws, {
              type: "tool_use",
              agentId: targetAgentId,
              toolUseId: block.id,
              toolName: block.name,
              status,
            });
          } else if (block.name === "Agent" || block.name === "Task") {
            // Legacy Agent tool (shouldn't happen with new prompts, but keep for safety)
            const agentType = (input.subagent_type as string) ?? "general";
            const taskDesc = (input.description as string) ?? "";

            getAgentMap(ws).set(block.id, agentType);

            send(ws, {
              type: "subagent_start",
              parentAgentId: targetAgentId,
              agentId: block.id,
              agentType,
              task: taskDesc,
            });

            emitActivity(ws, targetAgentId, "delegated", `→ ${agentType}: ${taskDesc}`);
            emitActivity(ws, agentType, "started", taskDesc);

            const m = getAgentMetrics(ws, agentType);
            const activeTasks = getActiveTasks(ws);
            const prevCount = activeTasks.get(agentType) ?? 0;
            if (prevCount > 0) {
              m.reworkCount++;
              autoLearnLesson(ws, agentType, "weakness", "problem_solving", "task-rework",
                `Required rework on task — previous attempt was insufficient. Needs more thorough analysis before starting.`);
            }
            m.tasksAssigned++;
            activeTasks.set(agentType, prevCount + 1);
            sendMetrics(ws);

            send(ws, {
              type: "tool_use",
              agentId: targetAgentId,
              toolUseId: block.id,
              toolName: block.name,
              status,
            });
          } else {
            emitActivity(ws, targetAgentId, "tool_use", status);

            send(ws, {
              type: "tool_use",
              agentId: targetAgentId,
              toolUseId: block.id,
              toolName: block.name,
              status,
            });
          }
        }
      }
      break;
    }

    case "stream_event": {
      const partial = message as SDKPartialAssistantMessage;
      // Only forward top-level (Manager) streaming
      if (partial.parent_tool_use_id) break;

      const event = partial.event;
      if (
        event.type === "content_block_delta" &&
        event.delta.type === "text_delta"
      ) {
        broadcastAll({ type: "assistant_text", text: event.delta.text, isPartial: true, agentId: targetAgentId });
      }
      break;
    }

    case "tool_progress": {
      const prog = message as SDKToolProgressMessage;
      const rawId = prog.parent_tool_use_id ?? targetAgentId;
      const agentId = resolveAgentId(ws, rawId);
      const status = `${prog.tool_name} (${Math.round(prog.elapsed_time_seconds)}s)`;
      send(ws, {
        type: "agent_status",
        agentId,
        status: "running",
        tools: [
          {
            toolUseId: prog.tool_use_id,
            toolName: prog.tool_name,
            status,
          },
        ],
      });
      // Emit activity only once per tool_use_id to avoid spamming the log
      const emitted = getEmittedTools(ws);
      if (!emitted.has(prog.tool_use_id)) {
        emitted.add(prog.tool_use_id);
        emitActivity(ws, agentId, "tool_use", status);
      }
      break;
    }

    case "result": {
      const res = message as SDKResultMessage;

      // Mark all active agent tasks as completed + detect clean runs
      const activeTasks = getActiveTasks(ws);
      const metrics = getMetrics(ws);
      for (const [agentId, count] of activeTasks) {
        if (count > 0) {
          const m = getAgentMetrics(ws, agentId);
          m.tasksCompleted += count;
          emitActivity(ws, agentId, "completed", `${count} task(s) done`);

          // Auto-learn: clean execution (completed without rework)
          if (m.reworkCount === 0 && m.tasksCompleted >= 1) {
            autoLearnLesson(ws, agentId, "strength", "problem_solving", "clean-execution",
              `Completes tasks cleanly on first attempt without requiring rework.`);
          }
        }
      }
      activeTasks.clear();
      getEmittedTools(ws).clear();

      const durationSec = Math.round((res.duration_ms ?? 0) / 1000);
      const costUsd = res.total_cost_usd ?? 0;
      emitActivity(ws, targetAgentId, "completed", `Query done in ${durationSec}s ($${costUsd.toFixed(2)})`);

      const resultText = "result" in res ? (res as unknown as Record<string, string>).result ?? "" : "";

      // Fallback: if the agent finished without sending a visible chat message
      // (e.g. the model ended silently after tool use), surface the SDK result text.
      if (resultText && !clientSentAssistantMessage.get(ws)) {
        const fallbackId = `fallback-${Date.now()}`;
        chatHistory.add({ role: "assistant", text: resultText, agentId: targetAgentId, timestamp: new Date().toISOString() });
        chatHistory.save(historyFilePath(PROJECT_CWD));
        broadcastAll({ type: "assistant_message_done", messageId: fallbackId, text: resultText, agentId: targetAgentId });
        dbg("info", "sdk", `Surfaced SDK result as fallback chat message (${resultText.length} chars)`);
      }

      send(ws, {
        type: "result",
        text: resultText,
        costUsd,
        durationMs: res.duration_ms ?? 0,
      });
      // Reset all hired-instance statuses to idle
      for (const agent of agentInfoForClient(ws)) {
        send(ws, {
          type: "agent_status",
          agentId: agent.id,
          status: "idle",
          tools: [],
        });
      }
      sendMetrics(ws);
      sendTraits(ws);
      // Clean up agent map for this query
      getAgentMap(ws).clear();

      // Trigger async post-query reflection (non-blocking)
      reflectOnQuery(ws, targetAgentId).catch((err) => {
        dbg("warn", "traits", `Reflection failed: ${err}`);
      });
      break;
    }
  }
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    dbg("error", "sdk", `handleSDKMessage(${message.type}) crashed: ${errMsg}`);
    sendDebug(ws, "error", "sdk", `Message handler error: ${errMsg}`);
  }
}

// ─── Chat history ────────────────────────────────────────────────────────────

/** Returns the path where chat history is persisted for a given project dir. */
function historyFilePath(projectCwd: string): string {
  const cwdKey = projectCwd.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".claude", "projects", cwdKey, "chat_history.json");
}

const chatHistory = new ChatHistory();
chatHistory.load(historyFilePath(PROJECT_CWD));

// Personalization layer (Phase 4.5.1) — extends each query's system prompt
// with the agent's learned-context fragment. Kill-switch via env var.
const agentContextPreparer = new AgentContextPreparer(chatHistory);
const PERSONALIZATION_ENABLED = process.env.PIXELCODE_PERSONALIZATION !== "off";

// ─── Shared SDK session (one per project, all clients) ───────────────────────

/**
 * Single SDK session shared across all WebSocket clients of this project.
 * Persisted to disk so it survives reconnects, app restarts, server restarts,
 * and device switches (e.g. Mac → iPhone). One conversation per project —
 * `chat_history` is already shared the same way.
 */
let currentSessionId: string | null = null;

/** Serializer for query() calls on the shared session — concurrent queries on
 *  the same resumed session ID race on `system/init` and tool event order. */
let sessionInflight: Promise<void> = Promise.resolve();

function sdkSessionFile(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key, "sdk_session.json");
}

function loadPersistedSession(): void {
  const f = sdkSessionFile(PROJECT_CWD);
  if (!existsSync(f)) {
    currentSessionId = null;
    return;
  }
  try {
    const raw = JSON.parse(readFileSync(f, "utf-8")) as { sessionId?: string };
    if (typeof raw.sessionId === "string" && raw.sessionId.length > 0) {
      currentSessionId = raw.sessionId;
      dbg("info", "session", `Loaded persisted SDK session: ${raw.sessionId.slice(0, 12)}…`);
    } else {
      currentSessionId = null;
    }
  } catch (e) {
    dbg("warn", "session", `Failed to load sdk_session: ${e}`);
    currentSessionId = null;
  }
}

function persistSession(): void {
  const f = sdkSessionFile(PROJECT_CWD);
  try {
    if (!currentSessionId) {
      if (existsSync(f)) rmSync(f, { force: true });
      return;
    }
    const dir = dirname(f);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(f, JSON.stringify({ sessionId: currentSessionId, updatedAt: Date.now() }));
  } catch (e) {
    dbg("warn", "session", `Failed to persist sdk_session: ${e}`);
  }
}

/** Serialize a function on the shared SDK session. Sequential per project. */
async function withSessionLock<T>(fn: () => Promise<T>): Promise<T> {
  const prev = sessionInflight;
  let release!: () => void;
  sessionInflight = new Promise<void>((r) => { release = r; });
  try {
    await prev;
    return await fn();
  } finally {
    release();
  }
}

loadPersistedSession();

/** Per-client project memory text, injected into system prompts. */
const clientProjectContext = new WeakMap<WebSocket, string>();

/** Per-client bypass permissions flag. When true, agents skip all permission prompts. */
const clientBypassPermissions = new WeakMap<WebSocket, boolean>();

/** Per-client game economy state (hired agents, hardware, skills). */
const clientGameState = new WeakMap<WebSocket, GameStateData>();

/** Latest full game state for cross-device sync (last-write-wins by timestamp). */
let latestFullGameState: string | null = null;
let latestStateUpdatedAt: number = 0;

/** Path where the authoritative game state is persisted across server restarts. */
function gameStateFile(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key, "game_state.json");
}

function loadPersistedGameState(): void {
  const file = gameStateFile(PROJECT_CWD);
  if (!existsSync(file)) return;
  try {
    const raw = JSON.parse(readFileSync(file, "utf-8")) as { fullState?: string; updatedAt?: number };
    if (typeof raw.fullState === "string" && typeof raw.updatedAt === "number") {
      latestFullGameState = raw.fullState;
      latestStateUpdatedAt = raw.updatedAt;
      dbg("info", "game", `Loaded persisted game state (updatedAt=${raw.updatedAt})`);
    }
  } catch (e) {
    dbg("warn", "game", `Failed to load persisted game state: ${e}`);
  }
}

function persistGameState(): void {
  if (!latestFullGameState) return;
  const file = gameStateFile(PROJECT_CWD);
  const dir = file.substring(0, file.lastIndexOf("/"));
  try {
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(file, JSON.stringify({
      fullState: latestFullGameState,
      updatedAt: latestStateUpdatedAt,
    }));
  } catch (e) {
    dbg("warn", "game", `Failed to persist game state: ${e}`);
  }
}

loadPersistedGameState();

/**
 * Per-client flag: tracks whether an assistant_message_done was sent for the
 * current query. Used as a fallback to surface the SDK result text when the
 * model ends without producing a visible chat message.
 */
const clientSentAssistantMessage = new WeakMap<WebSocket, boolean>();

// ─── Non-blocking orchestration ─────────────────────────────────────────────

/** Global task queue — shared across all clients, tasks carry their own ws ref. */
const taskQueue = new TaskQueue();

/** Global agent runner — manages independent sub-agent query() calls. */
const agentRunner = new AgentRunner();

/** Per-client flag: whether the manager is currently processing a query. */
const managerBusy = new WeakMap<WebSocket, boolean>();

// ─── Connected client tracking ─────────────────────────────────────────────

interface TrackedClient {
  clientId: string;
  deviceName: string;
  platform: string;
  connectedAt: string; // ISO 8601
  remoteAddress: string;
  ws: WebSocket;
}

/** All currently connected clients with their identifying info. */
const connectedClients = new Map<WebSocket, TrackedClient>();

function isLoopback(addr: string): boolean {
  return addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1";
}

/** Build the clients list for the admin HTTP API. */
function buildClientsList(): ConnectedClientInfo[] {
  const list: ConnectedClientInfo[] = [];
  for (const client of connectedClients.values()) {
    list.push({
      clientId: client.clientId,
      deviceName: client.deviceName,
      platform: client.platform,
      connectedAt: client.connectedAt,
      isLocal: isLoopback(client.remoteAddress),
    });
  }
  return list;
}

// ─── Team metrics tracking ──────────────────────────────────────────────────

interface AgentMetrics {
  tasksAssigned: number;
  tasksCompleted: number;
  reworkCount: number;
}

/** Per-client metrics state. */
const clientMetrics = new WeakMap<WebSocket, Map<string, AgentMetrics>>();

function getMetrics(ws: WebSocket): Map<string, AgentMetrics> {
  let metrics = clientMetrics.get(ws);
  if (!metrics) {
    metrics = new Map();
    clientMetrics.set(ws, metrics);
  }
  return metrics;
}

function getAgentMetrics(ws: WebSocket, agentId: string): AgentMetrics {
  const metrics = getMetrics(ws);
  let agent = metrics.get(agentId);
  if (!agent) {
    agent = { tasksAssigned: 0, tasksCompleted: 0, reworkCount: 0 };
    metrics.set(agentId, agent);
  }
  return agent;
}

/** Track which agents have active tasks (to detect rework). */
const activeAgentTasks = new WeakMap<WebSocket, Map<string, number>>();

function getActiveTasks(ws: WebSocket): Map<string, number> {
  let tasks = activeAgentTasks.get(ws);
  if (!tasks) {
    tasks = new Map();
    activeAgentTasks.set(ws, tasks);
  }
  return tasks;
}

function sendMetrics(ws: WebSocket): void {
  const metrics = getMetrics(ws);
  const payload: Record<string, AgentMetrics> = {};
  for (const [id, m] of metrics) {
    payload[id] = { ...m };
  }
  send(ws, { type: "team_metrics", metrics: payload });
}

/** Track tool_use_ids we already emitted activity for (to avoid spam from repeated tool_progress). */
const emittedToolUseIds = new WeakMap<WebSocket, Set<string>>();

function getEmittedTools(ws: WebSocket): Set<string> {
  let set = emittedToolUseIds.get(ws);
  if (!set) {
    set = new Set();
    emittedToolUseIds.set(ws, set);
  }
  return set;
}

/** Map tool_use_id → human-readable agent name (e.g. "coder", "tech-lead"). */
const toolUseIdToAgent = new WeakMap<WebSocket, Map<string, string>>();

function getAgentMap(ws: WebSocket): Map<string, string> {
  let map = toolUseIdToAgent.get(ws);
  if (!map) {
    map = new Map();
    toolUseIdToAgent.set(ws, map);
  }
  return map;
}

/** Resolve a tool_use_id or agent name to an instanceId / roleType.
 *
 * Priority:
 *  1. If the raw string matches a hired instanceId (from any client's game
 *     state), return it unchanged.
 *  2. Fall back to the per-client tool_use_id → agent map (sub-agent launches).
 *  3. Otherwise return the raw string (e.g. a role type like "coder").
 */
function resolveAgentId(ws: WebSocket, raw: string): string {
  const gs = clientGameState.get(ws);
  if (gs?.instances[raw]) return raw;
  const mapped = getAgentMap(ws).get(raw);
  if (mapped) return mapped;
  return raw;
}

/** Resolve the first hired instance of a given roleType (e.g. "manager" → "manager#1").
 *  Falls back to the bare roleType if no hired instance exists yet. */
function resolveRoleInstance(ws: WebSocket, roleType: string): string {
  const gs = clientGameState.get(ws);
  const hired = gs?.instances ?? {};
  for (const id of Object.keys(hired)) {
    if (hired[id].roleType === roleType) return id;
  }
  return roleType;
}

/** AgentInfo list for a client — computed from their game state.
 *
 * Used in init/new_chat/resume_session responses so Flutter can enumerate
 * hired instances. Falls back to an empty list when no game state is set yet;
 * Flutter's own GameState is the primary source of truth either way.
 */
function agentInfoForClient(ws: WebSocket): HiredAgentInfo[] {
  return buildHiredAgentInfoList(clientGameState.get(ws));
}

// ─── Trait memory ──────────────────────────────────────────────────────────

let traitStore: TraitStore = loadTraits(PROJECT_CWD);

function sendTraits(ws: WebSocket): void {
  send(ws, { type: "agent_traits", traits: getAllTraits(traitStore) });
}

/**
 * Record an auto-detected lesson from runtime signals (rework, errors, clean runs).
 * Broadcasts updated traits to the client.
 */
function autoLearnLesson(
  ws: WebSocket,
  agentId: string,
  type: LessonType,
  category: LessonCategory,
  tag: string,
  lesson: string,
): void {
  const result = recordLesson(PROJECT_CWD, traitStore, {
    agentId, type, category, tag, lesson,
  });
  dbg("info", "traits", `${type === "weakness" ? "⚡" : "✦"} [${agentId}] ${tag} (freq=${result.frequency}): ${lesson}`);
  sendDebug(ws, "info", "traits", `Lesson ${type === "weakness" ? "learned" : "confirmed"}: [${agentId}] ${lesson} (×${result.frequency})`);
  sendTraits(ws);
}

// ─── Activity log ───────────────────────────────────────────────────────────

interface ActivityEvent {
  timestamp: string; // ISO 8601
  agentId: string;
  event: "started" | "tool_use" | "completed" | "delegated" | "error";
  detail: string;
}

function emitActivity(
  ws: WebSocket,
  agentId: string,
  event: ActivityEvent["event"],
  detail: string,
): void {
  dbg("debug", "activity", `${event} [${agentId}] ${detail}`);
  send(ws, {
    type: "activity_event",
    timestamp: new Date().toISOString(),
    agentId,
    event,
    detail,
  });
  // Buffer for post-query reflection
  getQueryActivities(ws).push({ agentId, event, detail });
}

// ─── Run query for a client ─────────────────────────────────────────────────

// ─── Inter-agent communication tracking ─────────────────────────────────────

interface CommEvent {
  timestamp: number; // Date.now()
  from: string;
  to: string;
}

const clientCommLog = new WeakMap<WebSocket, CommEvent[]>();

function getCommLog(ws: WebSocket): CommEvent[] {
  let log = clientCommLog.get(ws);
  if (!log) {
    log = [];
    clientCommLog.set(ws, log);
  }
  return log;
}

function trackComm(ws: WebSocket, from: string, to: string): void {
  getCommLog(ws).push({ timestamp: Date.now(), from, to });
}

function sendCommGraph(ws: WebSocket): void {
  const log = getCommLog(ws);
  send(ws, { type: "comm_graph", events: log });
}

// ─── Post-query reflection (lightweight, async) ───────────────────────────

/** Per-client activity buffer — gathered during a query, consumed by reflection. */
const clientQueryActivities = new WeakMap<WebSocket, Array<{ agentId: string; event: string; detail: string }>>();

function getQueryActivities(ws: WebSocket): Array<{ agentId: string; event: string; detail: string }> {
  let buf = clientQueryActivities.get(ws);
  if (!buf) {
    buf = [];
    clientQueryActivities.set(ws, buf);
  }
  return buf;
}

/**
 * Ask haiku for a brief reflection on the completed query.
 * Extracts 0-3 lessons (strengths/weaknesses) from the session activity.
 * Non-blocking — called after result is sent to client.
 */
async function reflectOnQuery(ws: WebSocket, targetAgentId: string): Promise<void> {
  const activities = getQueryActivities(ws);
  if (activities.length === 0) return;

  // Build a compact summary of what happened
  const agentActivities = new Map<string, string[]>();
  let hasErrors = false;
  for (const a of activities) {
    if (!agentActivities.has(a.agentId)) agentActivities.set(a.agentId, []);
    agentActivities.get(a.agentId)!.push(`[${a.event}] ${a.detail}`);
    if (a.event === "error") hasErrors = true;
  }

  // Build activity summary (capped to stay cheap)
  const summaryLines: string[] = [];
  for (const [agentId, events] of agentActivities) {
    summaryLines.push(`## ${agentId}`);
    // Keep max 10 events per agent to limit token usage
    for (const e of events.slice(-10)) {
      summaryLines.push(`  ${e}`);
    }
  }
  const activitySummary = summaryLines.join("\n");

  // Get existing rework stats
  const metrics = getMetrics(ws);
  const reworkAgents: string[] = [];
  for (const [agentId, m] of metrics) {
    if (m.reworkCount > 0) reworkAgents.push(`${agentId}(rework=${m.reworkCount})`);
  }

  const reflectionPrompt = `Analyze this AI agent team work session and extract learning lessons.

Session activity:
${activitySummary}

${hasErrors ? "⚠️ The session had errors." : "No errors during session."}
${reworkAgents.length > 0 ? `⚠️ Agents with rework: ${reworkAgents.join(", ")}` : "No rework needed."}

Team agents: manager, tech-lead, coder, reviewer, tester, security, ui-ux-designer, llm-specialist

Extract 0-3 notable lessons from this session. Each lesson is a pattern that should be remembered for future work.
- A "strength" is something an agent did notably well (thorough analysis, clean code, good delegation, etc.)
- A "weakness" is something an agent struggled with or made a mistake on (missed edge cases, wrong approach, needed rework, etc.)
- Only include genuinely insightful observations, NOT generic platitudes.
- The "tag" must be specific and kebab-case (e.g., "missing-null-checks", "thorough-code-review", "poor-delegation-clarity").

Reply ONLY with a JSON array (no markdown, no explanation):
[{"agentId":"...", "type":"strength|weakness", "category":"code_quality|architecture|testing|security|communication|delegation|problem_solving|tools_usage", "tag":"short-kebab-id", "lesson":"One specific sentence"}]

If nothing notable happened, reply with: []`;

  try {
    dbg("debug", "traits", "Starting post-query reflection…");

    const existingSessionId = currentSessionId;
    const responseText = await withSessionLock(async () => {
      const q = query({
        prompt: reflectionPrompt,
        options: {
          model: "haiku",
          cwd: PROJECT_CWD,
          ...(existingSessionId ? { resume: existingSessionId } : {}),
          continue: false,
          persistSession: false,
          allowedTools: [],
          maxTurns: 1,
        },
      });

      let text = "";
      for await (const message of q) {
        if (message.type === "assistant") {
          const content = (message as SDKAssistantMessage).message?.content;
          if (Array.isArray(content)) {
            for (const block of content) {
              if (block.type === "text") {
                text += block.text;
              }
            }
          }
        }
      }
      return text;
    });

    // Parse the JSON response
    const trimmed = responseText.trim();
    // Extract JSON from potential markdown code blocks
    const jsonMatch = trimmed.match(/\[[\s\S]*\]/);
    if (!jsonMatch) {
      dbg("debug", "traits", "Reflection returned no lessons.");
      return;
    }

    const lessons = JSON.parse(jsonMatch[0]) as Array<{
      agentId: string;
      type: string;
      category: string;
      tag: string;
      lesson: string;
    }>;

    if (!Array.isArray(lessons) || lessons.length === 0) {
      dbg("debug", "traits", "Reflection: no notable patterns.");
      return;
    }

    // Record each lesson
    const validCategories = new Set([
      "code_quality", "architecture", "testing", "security",
      "communication", "delegation", "problem_solving", "tools_usage",
    ]);
    // Valid lesson targets = hired instanceIds (lessons are per-instance).
    const validAgents = new Set(agentInfoForClient(ws).map(a => a.id));

    const profileBatch: LlmLesson[] = [];
    for (const l of lessons.slice(0, 3)) {
      if (!validAgents.has(l.agentId)) continue;
      if (l.type !== "strength" && l.type !== "weakness") continue;
      if (!validCategories.has(l.category)) continue;
      if (!l.tag || !l.lesson) continue;

      autoLearnLesson(
        ws,
        l.agentId,
        l.type as LessonType,
        l.category as LessonCategory,
        l.tag,
        l.lesson,
      );

      profileBatch.push({ agentId: l.agentId, type: l.type, tag: l.tag, lesson: l.lesson });
    }

    // Phase 4.5.2 — also feed validated lessons into the AgentProfile lifecycle.
    // Coexists with TraitStore: both surfaces accumulate independently for now.
    if (PERSONALIZATION_ENABLED) {
      await applyLlmLessons(profileBatch, {
        cache: profileCache,
        extractor: lessonExtractor,
        userId: "default-user", // TODO(auth): real userId once available
        onError: (err) =>
          dbg(
            "warn",
            "personalization",
            `applyLlmLessons failed: ${err instanceof Error ? err.message : String(err)}`
          ),
      });
    }

    dbg("info", "traits", `Reflection complete: ${lessons.length} lesson(s) extracted.`);
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    dbg("warn", "traits", `Reflection error: ${errMsg}`);
  } finally {
    // Clear activity buffer for next query
    activities.length = 0;
  }
}

// ─── Dispatch MCP Server ────────────────────────────────────────────────────

/**
 * Creates an in-process MCP server with Dispatch, TeamStatus, and CancelTask tools.
 * The manager uses these instead of the built-in Agent tool.
 * Each tool returns immediately — sub-agents run in the background.
 */
function createDispatchServer(ws: WebSocket) {
  const dispatchTool = tool(
    "dispatch",
    "Dispatch a task to a specific team agent INSTANCE. The agent works independently — you do NOT wait for the result. Continue with other work immediately.",
    {
      agent: z.string().describe("Exact instanceId to dispatch to (e.g. 'coder#1', 'reviewer#2'). Use team_status to see who is available."),
      task: z.string().describe("Detailed task description for the agent. Be specific about what to do and expected output."),
      priority: z.enum(["high", "normal", "low"]).optional().describe("Task priority. Default: normal"),
    },
    async (args) => {
      const agentId = args.agent;
      const taskDesc = args.task;
      const priority = (args.priority ?? "normal") as "high" | "normal" | "low";

      // Validate instanceId against the hired team (excluding the manager role).
      const gsForValidation = clientGameState.get(ws);
      const hired = gsForValidation?.instances ?? {};
      const availableIds = Object.keys(hired).filter(
        (id) => hired[id].roleType !== "manager",
      );
      const validAgents = new Set(availableIds);
      if (!validAgents.has(agentId)) {
        return {
          content: [{ type: "text" as const, text: `Unknown instance "${agentId}". Available: ${availableIds.length > 0 ? availableIds.join(", ") : "(no teammates hired — hire more in the shop)"}.` }],
        };
      }

      // Check if this specific instance is already busy
      if (agentRunner.isAgentBusy(agentId)) {
        return {
          content: [{ type: "text" as const, text: `Instance "${agentId}" is already busy. Use team_status to see workload, or dispatch to another instance.` }],
        };
      }

      // Dispatch the sub-agent
      const projectMemory = clientProjectContext.get(ws);
      const gameState = clientGameState.get(ws);
      const bypassPermissions = clientBypassPermissions.get(ws);

      const dispatchId = agentRunner.dispatch({
        agentId,
        task: taskDesc,
        ws,
        projectCwd: PROJECT_CWD,
        gameState,
        projectMemory,
        traitStore,
        bypassPermissions,
        onMessage: (msg, agId, dId) => handleSubAgentMessage(ws, msg, agId, dId),
        onComplete: (result) => handleSubAgentComplete(ws, result),
        onError: (agId, dId, error) => handleSubAgentError(ws, agId, dId, error),
      });

      // Notify UI of dispatch
      send(ws, {
        type: "task_dispatched",
        dispatchId,
        agentId,
        task: taskDesc,
        priority,
      } as ServerMessage);

      // Set agent status to running
      send(ws, {
        type: "agent_status",
        agentId,
        status: "running",
        tools: [],
      });

      emitActivity(ws, "manager", "delegated", `→ ${agentId}: ${taskDesc}`);
      emitActivity(ws, agentId, "started", taskDesc);

      // Track metrics
      const m = getAgentMetrics(ws, agentId);
      m.tasksAssigned++;
      sendMetrics(ws);

      trackComm(ws, "manager", agentId);
      sendCommGraph(ws);

      sendQueueStatus(ws);

      dbg("info", "dispatch", `Dispatched to ${agentId}: "${taskDesc.slice(0, 80)}" (${dispatchId})`);

      return {
        content: [{ type: "text" as const, text: `Task dispatched to ${agentId} (ID: ${dispatchId}). They are working independently. Continue with other work or respond to the user.` }],
      };
    },
  );

  const teamStatusTool = tool(
    "team_status",
    "Check which agents are currently busy, idle, or queued. Use this before dispatching to balance workload.",
    {},
    async () => {
      const running = agentRunner.getStatus();
      const queuedCount = taskQueue.size;

      const lines: string[] = [];

      for (const agent of agentInfoForClient(ws)) {
        if (agent.roleType === "manager") continue;
        const runEntry = running.find(r => r.agentId === agent.id);
        if (runEntry) {
          const elapsed = Math.round(runEntry.elapsedMs / 1000);
          lines.push(`- **${agent.id}** (${agent.name}, ${agent.role}): BUSY — "${runEntry.task.slice(0, 60)}" (${elapsed}s)`);
        } else {
          lines.push(`- **${agent.id}** (${agent.name}, ${agent.role}): idle`);
        }
      }

      if (queuedCount > 0) {
        lines.push(`\n${queuedCount} task(s) in queue.`);
      }

      return {
        content: [{ type: "text" as const, text: lines.join("\n") }],
      };
    },
  );

  const cancelTaskTool = tool(
    "cancel_task",
    "Cancel a running sub-agent task by its dispatch ID.",
    {
      dispatch_id: z.string().describe("The dispatch ID returned when the task was dispatched"),
    },
    async (args) => {
      const ok = agentRunner.cancel(args.dispatch_id);
      return {
        content: [{ type: "text" as const, text: ok ? `Task ${args.dispatch_id} cancelled.` : `No running task with ID ${args.dispatch_id}.` }],
      };
    },
  );

  // ─── Board tools (for manager/tech-lead) ────────────────────────────────
  const boardCreateTool = tool(
    "board_create_task",
    "Create a new task card on the shared task board. Use this when breaking a user request into parallelizable subtasks. Cards start in the 'backlog' column.",
    {
      title: z.string().describe("Short task title."),
      description: z.string().optional().describe("Detailed description. Include acceptance criteria or pointers if useful."),
      column: z.enum(["backlog", "in_progress", "testing", "done"]).optional().describe("Target column. Default: backlog."),
      priority: z.enum(["low", "normal", "high", "urgent"]).optional(),
      color: z.enum(["yellow", "pink", "blue", "green", "orange", "purple"]).optional(),
      assignedAgents: z.array(z.string()).optional().describe("Optional instanceIds to assign (e.g. ['coder#1'])."),
    },
    async (args) => {
      const id = `task_${++boardTaskCounter}_${Date.now()}`;
      const now = new Date().toISOString();
      const task: TaskCardData = {
        id,
        title: args.title,
        description: args.description ?? "",
        column: (args.column as TaskColumnKey) ?? "backlog",
        priority: (args.priority as TaskPriorityKey) ?? "normal",
        color: (args.color as StickyColorKey) ?? "yellow",
        assignedAgents: args.assignedAgents ?? [],
        createdAt: now,
        updatedAt: now,
      };
      boardTasks.set(id, task);
      dbg("info", "board", `[MCP] Created task: ${task.title} (${id})`);
      broadcastBoardState();
      return { content: [{ type: "text" as const, text: `Created task ${id} in ${task.column}: "${task.title}"` }] };
    },
  );

  const boardMoveTool = tool(
    "board_move_task",
    "Move a task card to another column. Use when task state changes (e.g. start work → in_progress, finished → done).",
    {
      taskId: z.string().describe("The task ID returned from board_create_task or board_list."),
      column: z.enum(["backlog", "in_progress", "testing", "done"]),
    },
    async (args) => {
      const task = boardTasks.get(args.taskId);
      if (!task) return { content: [{ type: "text" as const, text: `Unknown taskId: ${args.taskId}` }] };
      const oldColumn = task.column;
      task.column = args.column as TaskColumnKey;
      task.updatedAt = new Date().toISOString();
      broadcastBoardState();
      dbg("info", "board", `[MCP] Moved ${args.taskId}: ${oldColumn} → ${task.column}`);
      return { content: [{ type: "text" as const, text: `Moved ${args.taskId}: ${oldColumn} → ${task.column}` }] };
    },
  );

  const boardUpdateTool = tool(
    "board_update_task",
    "Update a task card's title, description, priority, or color.",
    {
      taskId: z.string(),
      title: z.string().optional(),
      description: z.string().optional(),
      priority: z.enum(["low", "normal", "high", "urgent"]).optional(),
      color: z.enum(["yellow", "pink", "blue", "green", "orange", "purple"]).optional(),
    },
    async (args) => {
      const task = boardTasks.get(args.taskId);
      if (!task) return { content: [{ type: "text" as const, text: `Unknown taskId: ${args.taskId}` }] };
      if (args.title !== undefined) task.title = args.title;
      if (args.description !== undefined) task.description = args.description;
      if (args.priority !== undefined) task.priority = args.priority as TaskPriorityKey;
      if (args.color !== undefined) task.color = args.color as StickyColorKey;
      task.updatedAt = new Date().toISOString();
      broadcastBoardState();
      return { content: [{ type: "text" as const, text: `Updated ${args.taskId}.` }] };
    },
  );

  const boardAssignTool = tool(
    "board_assign_agent",
    "Assign or unassign an agent instance to a task card.",
    {
      taskId: z.string(),
      agentId: z.string().describe("instanceId, e.g. 'coder#1'"),
      assign: z.boolean().describe("true to assign, false to unassign"),
    },
    async (args) => {
      const task = boardTasks.get(args.taskId);
      if (!task) return { content: [{ type: "text" as const, text: `Unknown taskId: ${args.taskId}` }] };
      if (args.assign) {
        if (!task.assignedAgents.includes(args.agentId)) task.assignedAgents.push(args.agentId);
      } else {
        task.assignedAgents = task.assignedAgents.filter((a) => a !== args.agentId);
      }
      task.updatedAt = new Date().toISOString();
      broadcastBoardState();
      return { content: [{ type: "text" as const, text: `${args.assign ? "Assigned" : "Unassigned"} ${args.agentId} on ${args.taskId}.` }] };
    },
  );

  const boardListTool = tool(
    "board_list",
    "List all task cards on the board with their id, column, title, and assignees. Use before moving/updating to find taskIds.",
    {},
    async () => {
      const lines: string[] = [];
      for (const t of boardTasks.values()) {
        const assignees = t.assignedAgents.length > 0 ? ` [${t.assignedAgents.join(", ")}]` : "";
        lines.push(`- ${t.id} | ${t.column} | ${t.priority} | "${t.title}"${assignees}`);
      }
      return { content: [{ type: "text" as const, text: lines.length > 0 ? lines.join("\n") : "(board is empty)" }] };
    },
  );

  return createSdkMcpServer({
    name: "dispatch",
    tools: [
      dispatchTool,
      teamStatusTool,
      cancelTaskTool,
      boardCreateTool,
      boardMoveTool,
      boardUpdateTool,
      boardAssignTool,
      boardListTool,
    ],
  });
}

// ─── Sub-agent message handling ─────────────────────────────────────────────

/** Handle real-time messages from independently running sub-agents. */
function handleSubAgentMessage(ws: WebSocket, message: SDKMessage, agentId: string, _dispatchId: string): void {
  if (ws.readyState !== WebSocket.OPEN) return;

  try {
    switch (message.type) {
      case "assistant": {
        const asst = message as SDKAssistantMessage;
        // Forward tool uses for status updates
        for (const block of asst.message.content) {
          if (block.type === "tool_use") {
            const input = block.input as Record<string, unknown>;
            const status = toolStatusText(block.name, input);
            send(ws, {
              type: "tool_use",
              agentId,
              toolUseId: block.id,
              toolName: block.name,
              status,
            });
            emitActivity(ws, agentId, "tool_use", status);
          }
        }

        // Forward text as chat messages from this agent
        const text = extractText(asst);
        if (text && !asst.parent_tool_use_id) {
          chatHistory.add({ role: "assistant", text, agentId, timestamp: new Date().toISOString() });
          chatHistory.save(historyFilePath(PROJECT_CWD));
          broadcastAll({ type: "assistant_message_done", messageId: asst.uuid, text, agentId });
        }
        break;
      }

      case "stream_event": {
        const partial = message as SDKPartialAssistantMessage;
        if (partial.parent_tool_use_id) break;
        const event = partial.event;
        if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
          broadcastAll({ type: "assistant_text", text: event.delta.text, isPartial: true, agentId });
        }
        break;
      }

      case "tool_progress": {
        const prog = message as SDKToolProgressMessage;
        const status = `${prog.tool_name} (${Math.round(prog.elapsed_time_seconds)}s)`;
        send(ws, {
          type: "agent_status",
          agentId,
          status: "running",
          tools: [{ toolUseId: prog.tool_use_id, toolName: prog.tool_name, status }],
        });
        break;
      }
    }
  } catch (err) {
    dbg("error", "dispatch", `Sub-agent message handler error: ${err}`);
  }
}

/** Handle sub-agent completion — enqueue result for manager acknowledgement. */
function handleSubAgentComplete(ws: WebSocket, result: SubAgentResult): void {
  dbg("info", "dispatch", `Agent ${result.agentId} completed (${result.dispatchId}): ${result.text.slice(0, 100)}`);

  // Set agent back to idle
  send(ws, {
    type: "agent_status",
    agentId: result.agentId,
    status: "idle",
    tools: [],
  });

  // Track metrics
  const m = getAgentMetrics(ws, result.agentId);
  m.tasksCompleted++;
  sendMetrics(ws);

  emitActivity(ws, result.agentId, "completed", `Done ($${result.costUsd.toFixed(2)}, ${Math.round(result.durationMs / 1000)}s)`);
  trackComm(ws, result.agentId, "user");
  sendCommGraph(ws);

  // Send the sub-agent result directly to the client
  send(ws, {
    type: "subagent_result",
    dispatchId: result.dispatchId,
    agentId: result.agentId,
    result: result.text,
    costUsd: result.costUsd,
    durationMs: result.durationMs,
  } as ServerMessage);

  // Enqueue a notification for the manager to acknowledge
  taskQueue.enqueue({
    id: `result_${result.dispatchId}`,
    priority: "critical",
    type: "subagent_result",
    agentId: result.agentId,
    dispatchId: result.dispatchId,
    result: result.text,
    costUsd: result.costUsd,
    durationMs: result.durationMs,
    enqueuedAt: Date.now(),
    ws,
  });

  sendQueueStatus(ws);

  // Kick the queue — manager may be idle and can process the result
  processQueue(ws);
}

/** Handle sub-agent error. */
function handleSubAgentError(ws: WebSocket, agentId: string, dispatchId: string, error: string): void {
  dbg("error", "dispatch", `Agent ${agentId} error (${dispatchId}): ${error}`);

  send(ws, {
    type: "agent_status",
    agentId,
    status: "idle",
    tools: [],
  });

  emitActivity(ws, agentId, "error", error);

  send(ws, { type: "error", message: `[${agentId}] ${error}` });

  sendQueueStatus(ws);

  // Still try to process next queue item
  processQueue(ws);
}

// ─── Queue processor ────────────────────────────────────────────────────────

/**
 * Process the next task in the queue if the manager is not busy.
 * Called after each query finishes and after new tasks are enqueued.
 */
async function processQueue(ws: WebSocket): Promise<void> {
  if (managerBusy.get(ws)) return;
  if (taskQueue.isEmpty) return;

  const task = taskQueue.dequeue();
  if (!task) return;

  managerBusy.set(ws, true);

  try {
    // Serialize on the shared SDK session — concurrent queries on the same
    // resumed sessionId race on `system/init` and tool event order.
    await withSessionLock(async () => {
      switch (task.type) {
        case "chat":
          await runQuery(ws, task.userMessage!, task.targetAgentId!, task.images);
          break;

        case "subagent_result":
          // Feed the result back to the manager for acknowledgement
          await runQuery(
            ws,
            `[System notification] Agent "${task.agentId}" completed their task (dispatch ${task.dispatchId}).\n\nResult summary:\n${(task.result ?? "").slice(0, 2000)}\n\nMove the matching board card to "done" and post ONE short status line to the user per the Communication policy (e.g. "Готово: {X}." — merge with the next-step line if more work is queued, like "Зробили {A}. Працюємо над {B}."). Do not narrate the board move itself.`,
            resolveRoleInstance(ws, "manager"),
          );
          break;

        case "board":
          await runQuery(
            ws,
            `[Board task] "${task.boardTaskTitle}": ${task.boardTaskDescription ?? "no description"}. Plan and dispatch this work, then post ONE short status line to the user per the Communication policy — if you split it, name the pieces (e.g. 'Розбив "${task.boardTaskTitle}" на: {A}, {B}. Беремо {A} першим.'); if you dispatch as-is, just say what you're starting on (e.g. 'Працюємо над ${task.boardTaskTitle}.'). Do not narrate the dispatch mechanics.`,
            resolveRoleInstance(ws, "manager"),
          );
          break;
      }
    });
  } catch (err) {
    dbg("error", "queue", `processQueue error: ${err}`);
  } finally {
    managerBusy.set(ws, false);
    sendQueueStatus(ws);
    // Check if more work is queued
    if (!taskQueue.isEmpty) {
      setImmediate(() => processQueue(ws));
    }
  }
}

/** Send current queue status to the client. */
function sendQueueStatus(ws: WebSocket): void {
  send(ws, {
    type: "queue_status",
    pending: taskQueue.size,
    running: agentRunner.getStatus(),
  } as ServerMessage);
}

// ─── Run query for a client ─────────────────────────────────────────────────

/**
 * Detect image MIME type from base64 data by inspecting magic bytes.
 * Falls back to image/jpeg if detection fails.
 */
function detectImageMimeType(base64: string): "image/jpeg" | "image/png" | "image/gif" | "image/webp" {
  const header = base64.slice(0, 16);
  if (header.startsWith("iVBOR")) return "image/png";
  if (header.startsWith("R0lGOD")) return "image/gif";
  if (header.startsWith("UklGR")) return "image/webp";
  return "image/jpeg";
}

async function runQuery(ws: WebSocket, userMessage: string, targetAgentId: string, images?: string[]): Promise<void> {
  try {
    // Signal target agent is thinking
    send(ws, {
      type: "agent_status",
      agentId: targetAgentId,
      status: "thinking",
      tools: [],
    });

    // Track user → agent communication
    trackComm(ws, "user", targetAgentId);

    dbg("info", "session", `New query → ${targetAgentId}: "${userMessage.slice(0, 80)}"`);
    sendDebug(ws, "info", "session", `Query → ${targetAgentId}`);

    // Clear activity buffer for this query (reflection uses it afterwards)
    getQueryActivities(ws).length = 0;

    // Reset per-query flag so the result fallback can detect a silent finish
    clientSentAssistantMessage.set(ws, false);

    // Build system prompt addressed to the target agent, with project memory + traits + game state
    const projectMemory = clientProjectContext.get(ws);
    const agentTraits = formatTraitsForPrompt(traitStore, targetAgentId);
    const gameState = clientGameState.get(ws);
    const systemPrompt = buildOfficePrompt(targetAgentId, projectMemory, agentTraits, gameState);

    // Append the personalization fragment. Always safe — falls back to vanilla
    // systemPrompt on any failure, controlled by PIXELCODE_PERSONALIZATION env var.
    const finalSystemPrompt = await injectLearnedContext(
      systemPrompt,
      {
        preparer: agentContextPreparer,
        enabled: PERSONALIZATION_ENABLED,
        onError: (err) =>
          dbg(
            "warn",
            "personalization",
            `prepare failed: ${err instanceof Error ? err.message : String(err)}`
          ),
      },
      {
        agentId: targetAgentId,
        userId: "default-user", // TODO(auth): replace with real userId once user identity exists in protocol
        sessionId: currentSessionId ?? "fresh",
        currentProject: PROJECT_CWD,
      }
    );

    // Build dynamic agent definitions (one per hired instance, models from hardware)
    const dynamicAgents = buildDynamicAgents(gameState);
    void dynamicAgents; // currently only used for prompt composition inside buildOfficePrompt

    // Determine model based on target instance's hardware
    const targetInstance = gameState?.instances[targetAgentId];
    const targetHardware = targetInstance?.hardware ?? 0;
    const targetModel = hardwareToModel(targetHardware);

    // Determine tools based on the instance's role template + delegation capability.
    // Fall back to roleTypeOf() so clients can address a bare role type during
    // startup (before the first set_game_state arrives).
    const targetRoleType = roleTypeOf(targetAgentId, gameState);
    const agentDef = roleTemplateFor(targetAgentId, gameState);
    const baseTools = agentDef?.tools ?? ["Read", "Glob", "Grep", "Bash"];
    // Manager and tech-lead can delegate via Dispatch MCP tool (no blocking Agent tool)
    const canDelegate = targetRoleType === "manager" || targetRoleType === "tech-lead";
    const allowedTools = [...baseTools];
    if (canDelegate) {
      allowedTools.push(
        "mcp__dispatch__dispatch",
        "mcp__dispatch__team_status",
        "mcp__dispatch__cancel_task",
        "mcp__dispatch__board_create_task",
        "mcp__dispatch__board_move_task",
        "mcp__dispatch__board_update_task",
        "mcp__dispatch__board_assign_agent",
        "mcp__dispatch__board_list",
      );
    }

    // Resume from existing shared session if available, persist for future resume.
    const existingSessionId = currentSessionId;
    const hasSession = !!existingSessionId;

    // Create Dispatch MCP server for delegating agents
    const mcpServers = canDelegate
      ? { dispatch: createDispatchServer(ws) }
      : undefined;

    const queryOptions = {
      systemPrompt: finalSystemPrompt,
      model: targetModel,
      allowedTools,
      ...(mcpServers ? { mcpServers } : {}),
      cwd: PROJECT_CWD,
      includePartialMessages: true,
      permissionMode: (clientBypassPermissions.get(ws) ? "bypassPermissions" : "acceptEdits") as "bypassPermissions" | "acceptEdits",
      maxTurns: 50,
      persistSession: true,
      continue: false,
      ...(hasSession ? { resume: existingSessionId } : {}),
    };

    dbg("debug", "session", "query() options:", {
      targetAgent: targetAgentId,
      model: queryOptions.model,
      tools: queryOptions.allowedTools.join(", "),
      persistSession: queryOptions.persistSession,
      continue: queryOptions.continue,
    });
    // Log first 500 chars of system prompt so we can verify it's correct
    dbg("info", "prompt", `System prompt (first 500 chars): ${finalSystemPrompt.slice(0, 500)}`);
    sendDebug(ws, "info", "prompt", `SystemPrompt starts: "${finalSystemPrompt.slice(0, 200)}…"`);

    // Prefix the message so the AI knows who it's from and who it's to
    const prefixedPrompt = `[User → ${targetAgentId}]: ${userMessage}`;

    // Build the prompt — use content blocks with images when attached,
    // otherwise fall back to a plain string for simplicity.
    let promptParam: string | AsyncIterable<SDKUserMessage>;
    if (images && images.length > 0) {
      const contentBlocks: Array<
        | { type: "image"; source: { type: "base64"; media_type: string; data: string } }
        | { type: "text"; text: string }
      > = [];
      for (const imgBase64 of images) {
        contentBlocks.push({
          type: "image",
          source: {
            type: "base64",
            media_type: detectImageMimeType(imgBase64),
            data: imgBase64,
          },
        });
      }
      contentBlocks.push({ type: "text", text: prefixedPrompt });

      const sessionId = existingSessionId ?? "";
      async function* imageMessageStream(): AsyncGenerator<SDKUserMessage> {
        yield {
          type: "user" as const,
          message: {
            role: "user" as const,
            content: contentBlocks,
          },
          parent_tool_use_id: null,
          session_id: sessionId,
        };
      }
      promptParam = imageMessageStream();
      dbg("info", "session", `Sending ${images.length} image(s) as vision content blocks`);
    } else {
      promptParam = prefixedPrompt;
    }

    const q = query({
      prompt: promptParam,
      options: queryOptions,
    });

    let messageCount = 0;
    for await (const message of q) {
      messageCount++;

      // Capture session ID — persist + broadcast to all connected clients so
      // every device records the live shared session in its SharedPreferences.
      if (
        message.type === "system" &&
        (message as SDKSystemMessage).subtype === "init"
      ) {
        const sid = (message as SDKSystemMessage).session_id;
        if (currentSessionId !== sid) {
          currentSessionId = sid;
          persistSession();
          for (const c of wss.clients) {
            if (c.readyState !== WebSocket.OPEN) continue;
            send(c as WebSocket, {
              type: "init",
              sessionId: sid,
              agents: agentInfoForClient(c as WebSocket),
              workingDirectory: PROJECT_CWD,
            });
          }
        }
        dbg("info", "session", `Session ID: ${sid}`);
        sendDebug(ws, "info", "session", `Session: ${sid.slice(0, 12)}…`);
      }

      // Track inter-agent communication from delegation
      if (message.type === "assistant") {
        const asst = message as SDKAssistantMessage;
        for (const block of asst.message.content) {
          if (block.type === "tool_use" && (block.name === "Agent" || block.name === "Task")) {
            const input = block.input as Record<string, unknown>;
            const delegateTo = (input.subagent_type as string) ?? "general";
            const delegateFrom = asst.parent_tool_use_id
              ? resolveAgentId(ws, asst.parent_tool_use_id)
              : targetAgentId;
            trackComm(ws, delegateFrom, delegateTo);
          }
        }
      }

      handleSDKMessage(ws, message, targetAgentId);
    }

    // Track agent → user response
    trackComm(ws, targetAgentId, "user");
    sendCommGraph(ws);

    dbg("info", "session", `Query finished. ${messageCount} SDK messages processed.`);
    sendDebug(ws, "info", "session",
      `Query complete (${targetAgentId}). ${messageCount} msgs. Session=${currentSessionId?.slice(0, 12) ?? "?"}…`
    );
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    dbg("error", "session", `Query failed: ${errMsg}`);
    sendDebug(ws, "error", "session", `Query FAILED: ${errMsg}`);
    // If the persisted session is unrecoverable (binary deleted the JSONL,
    // version drift, etc.), drop it so the next query starts fresh. We detect
    // this by message text since the SDK doesn't expose a typed error.
    const looksStale = /session.*not.*found|no such session|cannot.*resume/i.test(errMsg);
    if (looksStale && currentSessionId) {
      dbg("warn", "session", `Dropping stale session ${currentSessionId.slice(0, 12)}…`);
      sendDebug(ws, "warn", "session", "Stale session dropped — next message will start fresh");
      currentSessionId = null;
      persistSession();
    }
    send(ws, {
      type: "error",
      message: errMsg,
    });
  }
}

// ─── Task Board (shared across all clients) ────────────────────────────────

const boardTasks: Map<string, TaskCardData> = new Map();
let boardTaskCounter = 0;

function broadcastBoardState(): void {
  const tasks = Array.from(boardTasks.values());
  const msg: ServerMessage = { type: "board_state", tasks };
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(msg));
    }
  }
}

function sendBoardState(ws: WebSocket): void {
  const tasks = Array.from(boardTasks.values());
  send(ws, { type: "board_state", tasks });
}

function handleBoardMessage(ws: WebSocket, msg: ClientMessage): void {
  switch (msg.type) {
    case "board_get_state":
      sendBoardState(ws);
      break;

    case "board_create_task": {
      const id = `task_${++boardTaskCounter}_${Date.now()}`;
      const now = new Date().toISOString();
      const task: TaskCardData = {
        id,
        title: msg.title,
        description: msg.description ?? "",
        column: "backlog",
        priority: (msg.priority as TaskPriorityKey) ?? "normal",
        color: (msg.color as StickyColorKey) ?? "yellow",
        assignedAgents: [],
        createdAt: now,
        updatedAt: now,
        difficulty: msg.difficulty,
        allowedRoles: msg.allowedRoles,
        taskType: msg.taskType,
        attachments: [],
      };
      boardTasks.set(id, task);
      dbg("info", "board", `Created task: ${task.title} (${id})`);
      broadcastBoardState();
      break;
    }

    case "board_move_task": {
      const task = boardTasks.get(msg.taskId);
      if (task) {
        const oldColumn = task.column;
        task.column = msg.column as TaskColumnKey;
        task.updatedAt = new Date().toISOString();
        dbg("info", "board", `Moved task ${msg.taskId}: ${oldColumn} → ${task.column}`);
        broadcastBoardState();

        // Auto-enqueue board tasks moved to in_progress for the manager
        if (task.column === "in_progress") {
          const assignees = task.assignedAgents.length > 0
            ? `Assigned agents: ${task.assignedAgents.join(", ")}.`
            : "No specific agents assigned — decide who should handle this.";
          taskQueue.enqueue({
            id: `board_${task.id}`,
            priority: "normal",
            type: "board",
            boardTaskId: task.id,
            boardTaskTitle: task.title,
            boardTaskDescription: task.description,
            targetAgentId: "manager",
            userMessage: `Board task "${task.title}": ${task.description}. ${assignees} Please dispatch this work.`,
            enqueuedAt: Date.now(),
            ws,
          });
          dbg("info", "board", `Auto-enqueued board task "${task.title}" for manager dispatch`);
          sendQueueStatus(ws);
          processQueue(ws);
        }
      }
      break;
    }

    case "board_update_task": {
      const task = boardTasks.get(msg.taskId);
      if (task) {
        const updates = msg.updates;
        if (updates.title !== undefined) task.title = updates.title;
        if (updates.description !== undefined) task.description = updates.description;
        if (updates.priority !== undefined) task.priority = updates.priority;
        if (updates.color !== undefined) task.color = updates.color;
        if (updates.column !== undefined) task.column = updates.column;
        task.updatedAt = new Date().toISOString();
        dbg("info", "board", `Updated task ${msg.taskId}`);
        broadcastBoardState();
      }
      break;
    }

    case "board_delete_task": {
      if (boardTasks.delete(msg.taskId)) {
        dbg("info", "board", `Deleted task ${msg.taskId}`);
        broadcastBoardState();
      }
      break;
    }

    case "board_assign_agent": {
      const task = boardTasks.get(msg.taskId);
      if (task) {
        if (msg.assign) {
          if (!task.assignedAgents.includes(msg.agentId)) {
            task.assignedAgents.push(msg.agentId);
          }
        } else {
          task.assignedAgents = task.assignedAgents.filter(a => a !== msg.agentId);
        }
        task.updatedAt = new Date().toISOString();
        dbg("info", "board", `${msg.assign ? "Assigned" : "Unassigned"} ${msg.agentId} on task ${msg.taskId}`);
        broadcastBoardState();
      }
      break;
    }

    case "board_add_attachment": {
      const task = boardTasks.get(msg.taskId);
      if (!task) break;
      const MAX = 5 * 1024 * 1024; // mirror client cap
      if (msg.sizeBytes > MAX) {
        dbg("warn", "board", `Rejected attachment ${msg.name} on ${msg.taskId}: ${msg.sizeBytes} > ${MAX}`);
        break;
      }
      const attachment: TaskAttachmentData = {
        id: `att_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        name: msg.name,
        mimeType: msg.mimeType,
        sizeBytes: msg.sizeBytes,
        dataBase64: msg.dataBase64,
        uploadedAt: new Date().toISOString(),
      };
      task.attachments = [...(task.attachments ?? []), attachment];
      task.updatedAt = attachment.uploadedAt;
      dbg("info", "board", `Added attachment "${msg.name}" (${msg.sizeBytes}B) to ${msg.taskId}`);
      broadcastBoardState();
      break;
    }

    case "board_remove_attachment": {
      const task = boardTasks.get(msg.taskId);
      if (!task || !task.attachments) break;
      const before = task.attachments.length;
      task.attachments = task.attachments.filter(a => a.id !== msg.attachmentId);
      if (task.attachments.length !== before) {
        task.updatedAt = new Date().toISOString();
        dbg("info", "board", `Removed attachment ${msg.attachmentId} from ${msg.taskId}`);
        broadcastBoardState();
      }
      break;
    }
  }
}

// ─── Session summary generation ─────────────────────────────────────────────

async function generateSessionSummary(ws: WebSocket): Promise<void> {
  const existingSessionId = currentSessionId;
  if (!existingSessionId) {
    send(ws, { type: "summary_result", summary: "" });
    return;
  }

  dbg("info", "project", `Generating session summary for ${existingSessionId.slice(0, 12)}…`);
  sendDebug(ws, "info", "project", "Generating session summary…");

  try {
    const summaryText = await withSessionLock(async () => {
      const q = query({
        prompt: "Summarize what was accomplished in this conversation in 2-3 concise sentences. Focus on concrete changes made and decisions taken. Be specific about files and features. Reply ONLY with the summary, nothing else.",
        options: {
          model: "haiku",
          cwd: PROJECT_CWD,
          resume: existingSessionId,
          continue: false,
          persistSession: false,
          allowedTools: [],
          maxTurns: 1,
        },
      });

      let text = "";
      for await (const message of q) {
        if (message.type === "assistant") {
          const content = (message as SDKAssistantMessage).message?.content;
          if (Array.isArray(content)) {
            for (const block of content) {
              if (block.type === "text") {
                text += block.text;
              }
            }
          }
        }
      }
      return text;
    });

    dbg("info", "project", `Summary generated: ${summaryText.slice(0, 100)}…`);
    send(ws, { type: "summary_result", summary: summaryText.trim() });
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    dbg("error", "project", `Summary generation failed: ${errMsg}`);
    send(ws, { type: "summary_result", summary: "" });
  }
}

// ─── iOS OTA deploy ────────────────────────────────────────────────────────

const OTA_HOSTNAME = __configSource.effective.otaHostname ?? undefined; // optional local hostname override for LAN fallback

/** Track active build process per client so we can cancel it. */
const activeDeployProcess = new WeakMap<WebSocket, ChildProcess>();

/** Directory where OTA artifacts (IPA, manifest) are stored. */
const otaDir = join(homedir(), ".pixelcode", "ota");
mkdirSync(otaDir, { recursive: true });

function sendDeployLog(ws: WebSocket, message: string): void {
  send(ws, { type: "ios_deploy_status", subtype: "log", message } as any);
}

function sendDeployError(ws: WebSocket, message: string): void {
  send(ws, { type: "ios_deploy_status", subtype: "error", message } as any);
}


/** Get a reachable hostname/IP for the OTA server. */
function getOtaHost(): string {
  if (OTA_HOSTNAME) return OTA_HOSTNAME;
  // Auto-detect local IP
  const nets = networkInterfaces();
  for (const ifaces of Object.values(nets)) {
    for (const iface of ifaces ?? []) {
      if (iface.family === "IPv4" && !iface.internal) return iface.address;
    }
  }
  return "localhost";
}

/** Public Tailscale Funnel URL (set once at startup, null if unavailable). */
let tailscaleUrl: string | null = null;

/** Shared HTTP request handler — serves /admin/* and OTA artifacts (IPA + manifest). */
function makeOtaHandler() {
  return async (req: IncomingMessage, res: ServerResponse) => {
    const url = req.url ?? "/";

    // Admin UI + API takes precedence over OTA. Loopback-only inside the handler.
    if (url.startsWith("/admin")) {
      const result = await handleAdminRequest(adminContext, req, res);
      if (result.handled) return;
    }

    // Discovery metadata: lets LAN-discovered clients learn the public Funnel
    // URL before opening a session, so the SessionProfile is created with the
    // remote-reachable address instead of the LAN IP.
    if (url === "/metadata.json" || url === "/metadata") {
      const localIps: string[] = [];
      for (const ifaces of Object.values(networkInterfaces())) {
        for (const iface of ifaces ?? []) {
          if (iface.family === "IPv4" && !iface.internal) localIps.push(iface.address);
        }
      }
      const body = JSON.stringify({
        hostname: hostname(),
        localIps,
        port: PORT,
        tunnelUrl: tailscaleUrl,
      });
      res.writeHead(200, {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      });
      res.end(body);
      return;
    }

    dbg("debug", "ota", `${req.method} ${url}`);

    const safeName = url.split("/").pop()?.replace(/[^a-zA-Z0-9._-]/g, "");
    if (!safeName) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }

    const filePath = join(otaDir, safeName);
    if (!existsSync(filePath)) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }

    const ext = extname(safeName);
    const contentType: Record<string, string> = {
      ".ipa": "application/octet-stream",
      ".plist": "text/xml",
      ".apk": "application/vnd.android.package-archive",
      ".png": "image/png",
    };

    res.writeHead(200, {
      "Content-Type": contentType[ext] ?? "application/octet-stream",
    });
    res.end(readFileSync(filePath));
  };
}

// ─── Tailscale Funnel ─────────────────────────────────────────────────────────

/** Resolve tailscale binary — check PATH, then common install locations. */
function findTailscale(): string | null {
  try {
    return execFileSync("which", ["tailscale"], { timeout: 3000 }).toString().trim() || null;
  } catch { /* not in PATH */ }
  for (const p of ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/usr/bin/tailscale"]) {
    if (existsSync(p)) return p;
  }
  return null;
}

/** Get the stable MagicDNS hostname from `tailscale status --json`. */
async function getTailscaleHostname(): Promise<string | null> {
  const binary = findTailscale();
  if (!binary) return null;
  return new Promise((resolve) => {
    execFile(binary, ["status", "--json"], { timeout: 5000 }, (err, stdout) => {
      if (err) { resolve(null); return; }
      try {
        const status = JSON.parse(stdout) as { Self?: { DNSName?: string } };
        const dns = status?.Self?.DNSName;
        resolve(dns ? dns.replace(/\.$/, "") : null);
      } catch { resolve(null); }
    });
  });
}

/** Enable Tailscale Funnel for a local port (configures the Tailscale daemon). */
async function enableTailscaleFunnel(localPort: number): Promise<void> {
  const binary = findTailscale();
  if (!binary) return;
  return new Promise((resolve) => {
    execFile(binary, ["funnel", "--bg", String(localPort)], { timeout: 15_000 }, (err) => {
      if (err) dbg("warn", "tailscale", `funnel enable: ${err.message}`);
      resolve();
    });
  });
}

// ─── Startup: enable Tailscale Funnel ────────────────────────────────────────
(async () => {
  const tsHostname = await getTailscaleHostname();

  if (tsHostname) {
    dbg("info", "tailscale", `MagicDNS hostname: ${tsHostname}`);
    await enableTailscaleFunnel(PORT);
    tailscaleUrl = `wss://${tsHostname}`;
    console.log(`🌐 Remote access: ${tailscaleUrl}`);
    dbg("info", "tailscale", `Funnel active: https://${tsHostname}`);
  } else {
    dbg("warn", "tailscale",
      "Tailscale not running — remote access disabled. " +
      "Run: brew install tailscale && tailscale up"
    );
  }

  // Broadcast updated server_info to any already-connected clients
  if (tailscaleUrl) {
    const localIps: string[] = [];
    for (const ifaces of Object.values(networkInterfaces())) {
      for (const iface of ifaces ?? []) {
        if (iface.family === "IPv4" && !iface.internal) localIps.push(iface.address);
      }
    }
    broadcastAll({ type: "server_info", hostname: hostname(), localIps, port: PORT, tunnelUrl: tailscaleUrl } as any);
  }
})();

/** Generate the OTA manifest.plist for iOS installation. */
function generateManifest(ipaUrl: string, bundleId: string, title: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${ipaUrl}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${bundleId}</string>
        <key>bundle-version</key>
        <string>1.0.0</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${title}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>`;
}

/** Read bundle identifier from the Flutter project's iOS config. */
function readBundleId(): string {
  // Try reading from project.pbxproj or Info.plist
  const pbxPath = join(PROJECT_CWD, "ios/Runner.xcodeproj/project.pbxproj");
  if (existsSync(pbxPath)) {
    const content = readFileSync(pbxPath, "utf-8");
    const match = content.match(/PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);/);
    if (match) return match[1].trim();
  }
  return "com.example.app";
}

async function iosDeployCheck(ws: WebSocket): Promise<void> {
  let hasFlutter = false;

  try {
    await new Promise<void>((resolve) => {
      execFile("flutter", ["--version"], { timeout: 10000 }, (err) => {
        hasFlutter = !err;
        resolve();
      });
    });
  } catch { /* not installed */ }

  send(ws, { type: "ios_deploy_status", subtype: "deps_result", hasFlutter } as any);
}

/** Detect paired iOS devices via xcrun devicectl. Returns device name or null. */
async function detectIOSDevice(): Promise<string | null> {
  return new Promise((resolve) => {
    execFile("xcrun", ["devicectl", "list", "devices"], { timeout: 10000 }, (err, stdout) => {
      if (err) { resolve(null); return; }
      // Parse output: look for lines with "available (paired)" and iOS/iPhone/iPad
      for (const line of stdout.split("\n")) {
        if (line.includes("available") && line.includes("paired") &&
            (line.includes("iPhone") || line.includes("iPad"))) {
          // Extract device name (first column)
          const name = line.split(/\s{2,}/)[0]?.trim();
          if (name) { resolve(name); return; }
        }
      }
      resolve(null);
    });
  });
}

/** Try to install .app silently via xcrun devicectl. Returns true on success. */
async function trySilentInstall(ws: WebSocket, appPath: string, deviceName: string): Promise<boolean> {
  sendDeployLog(ws, `Пряме встановлення на "${deviceName}"...`);
  sendDeployLog(ws, `Команда: xcrun devicectl device install app -d "${deviceName}"`);

  return new Promise((resolve) => {
    const proc = spawn("xcrun", [
      "devicectl", "device", "install", "app",
      "-d", deviceName,
      appPath,
    ]);
    activeDeployProcess.set(ws, proc);

    proc.stdout.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        if (line.trim()) sendDeployLog(ws, line.trim());
      }
    });
    proc.stderr.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        if (line.trim()) sendDeployLog(ws, line.trim());
      }
    });

    proc.on("close", (code) => resolve(code === 0));
    proc.on("error", () => resolve(false));
  });
}

async function iosDeployStart(ws: WebSocket): Promise<void> {
  dbg("info", "deploy", "Starting iOS build…");

  // Step 1: Build .app bundle
  sendDeployLog(ws, "Побудова iOS додатку...");
  sendDeployLog(ws, "Команда: flutter build ios --release");

  const buildProcess = spawn("flutter", ["build", "ios", "--release"], {
    cwd: PROJECT_CWD,
  });
  activeDeployProcess.set(ws, buildProcess);

  buildProcess.stdout.on("data", (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (line.trim()) sendDeployLog(ws, line.trim());
    }
  });
  buildProcess.stderr.on("data", (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (line.trim()) sendDeployError(ws, line.trim());
    }
  });

  const buildExitCode = await new Promise<number | null>((resolve) => {
    buildProcess.on("close", resolve);
    buildProcess.on("error", (err) => {
      sendDeployError(ws, `Помилка при побудові: ${err.message}`);
      resolve(1);
    });
  });

  if (buildExitCode !== 0) {
    sendDeployError(ws, `Помилка при побудові. Код виходу: ${buildExitCode}`);
    send(ws, { type: "ios_deploy_status", subtype: "complete", success: false } as any);
    activeDeployProcess.delete(ws);
    return;
  }

  // Find the built .app bundle
  const appCandidates = [
    join(PROJECT_CWD, "build/ios/iphoneos/Runner.app"),
    join(PROJECT_CWD, "build/ios/Release-iphoneos/Runner.app"),
  ];
  const appPath = appCandidates.find((p) => existsSync(p));

  if (!appPath) {
    sendDeployError(ws, ".app бандл не знайдено");
    send(ws, { type: "ios_deploy_status", subtype: "complete", success: false } as any);
    activeDeployProcess.delete(ws);
    return;
  }

  sendDeployLog(ws, `Білк завершено: ${appPath}`);
  sendDeployLog(ws, "");

  // Step 2: Try silent install via devicectl (works when device paired on same WiFi)
  sendDeployLog(ws, "Шукаю підключені iOS пристрої...");
  const deviceName = await detectIOSDevice();

  if (deviceName) {
    sendDeployLog(ws, `Знайдено пристрій: ${deviceName}`);
    const silentOk = await trySilentInstall(ws, appPath, deviceName);

    if (silentOk) {
      sendDeployLog(ws, "");
      sendDeployLog(ws, "===============================================");
      sendDeployLog(ws, "Додаток встановлено на пристрій!");
      sendDeployLog(ws, "===============================================");
      send(ws, { type: "ios_deploy_status", subtype: "complete", success: true } as any);
      activeDeployProcess.delete(ws);
      return;
    }

    sendDeployLog(ws, "Пряме встановлення не вдалося. Перемикаюсь на OTA...");
    sendDeployLog(ws, "");
  } else {
    sendDeployLog(ws, "Пристрій не знайдено локально. Використовую OTA...");
    sendDeployLog(ws, "");
  }

  // Step 3: Fallback — OTA via HTTPS
  sendDeployLog(ws, "Пакую в IPA для OTA встановлення...");

  const ipaPath = join(otaDir, "app.ipa");
  const payloadDir = join(otaDir, "Payload");
  const payloadApp = join(payloadDir, "Runner.app");

  try { rmSync(payloadDir, { recursive: true, force: true }); } catch { /* ok */ }
  try { rmSync(ipaPath, { force: true }); } catch { /* ok */ }

  mkdirSync(payloadDir, { recursive: true });

  const cpProcess = spawn("cp", ["-R", appPath, payloadApp]);
  await new Promise<void>((resolve) => cpProcess.on("close", resolve));

  const zipProcess = spawn("zip", ["-r", ipaPath, "Payload"], { cwd: otaDir });
  const zipExitCode = await new Promise<number | null>((resolve) => {
    zipProcess.on("close", resolve);
    zipProcess.on("error", () => resolve(1));
  });

  try { rmSync(payloadDir, { recursive: true, force: true }); } catch { /* ok */ }

  if (zipExitCode !== 0 || !existsSync(ipaPath)) {
    sendDeployError(ws, "Помилка при створенні IPA");
    send(ws, { type: "ios_deploy_status", subtype: "complete", success: false } as any);
    activeDeployProcess.delete(ws);
    return;
  }

  const ipaFileName = "app.ipa";
  if (!tailscaleUrl) {
    sendDeployError(ws, "Tailscale Funnel не активний — OTA недоступний з іншої мережі.");
    sendDeployError(ws, "Запустіть: tailscale up && tailscale funnel " + PORT);
    send(ws, { type: "ios_deploy_status", subtype: "complete", success: false } as any);
    activeDeployProcess.delete(ws);
    return;
  }
  // tailscaleUrl is wss://... — convert to https:// for OTA base URL
  const baseUrl = tailscaleUrl.replace("wss://", "https://");
  const ipaUrl = `${baseUrl}/${ipaFileName}`;
  const bundleId = readBundleId();

  const manifest = generateManifest(ipaUrl, bundleId, "PixelCode");
  writeFileSync(join(otaDir, "manifest.plist"), manifest);

  const manifestUrl = `${baseUrl}/manifest.plist`;
  const installUrl = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestUrl)}`;

  sendDeployLog(ws, `OTA через Tailscale Funnel (довірений HTTPS)`);

  sendDeployLog(ws, "");
  sendDeployLog(ws, "===============================================");
  sendDeployLog(ws, "IPA готовий до OTA встановлення");
  sendDeployLog(ws, "===============================================");
  sendDeployLog(ws, "");

  send(ws, { type: "ios_deploy_status", subtype: "install_ready", installUrl } as any);
  activeDeployProcess.delete(ws);
}

function iosDeployCancel(ws: WebSocket): void {
  const proc = activeDeployProcess.get(ws);
  if (proc) {
    proc.kill("SIGTERM");
    activeDeployProcess.delete(ws);
    sendDeployLog(ws, "Операцію скасовано.");
    send(ws, { type: "ios_deploy_status", subtype: "complete", success: false } as any);
  }
}

// ─── Android deploy ────────────────────────────────────────────────────────

/** Track active Android build process per client so we can cancel it. */
const activeAndroidDeployProcess = new WeakMap<WebSocket, ChildProcess>();

function sendAndroidDeployLog(ws: WebSocket, message: string): void {
  send(ws, { type: "android_deploy_status", subtype: "log", message } as any);
}

function sendAndroidDeployError(ws: WebSocket, message: string): void {
  send(ws, { type: "android_deploy_status", subtype: "error", message } as any);
}

/** Resolve the Android SDK root from env vars or common default locations. */
function findAndroidSdk(): string | null {
  const envPath = process.env.ANDROID_HOME ?? process.env.ANDROID_SDK_ROOT;
  if (envPath && existsSync(envPath)) return envPath;
  const candidates = [
    join(homedir(), "Library/Android/sdk"),
    join(homedir(), "Android/Sdk"),
    "/usr/local/lib/android/sdk",
    "/opt/android-sdk",
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }
  return null;
}

/** Resolve adb binary — prefer Android SDK's platform-tools, fall back to PATH. */
function findAdb(): string | null {
  const sdk = findAndroidSdk();
  if (sdk) {
    const adbPath = join(sdk, "platform-tools/adb");
    if (existsSync(adbPath)) return adbPath;
  }
  try {
    const p = execFileSync("which", ["adb"], { timeout: 3000 }).toString().trim();
    if (p) return p;
  } catch { /* not in PATH */ }
  return null;
}

async function androidDeployCheck(ws: WebSocket): Promise<void> {
  let hasFlutter = false;

  try {
    await new Promise<void>((resolve) => {
      execFile("flutter", ["--version"], { timeout: 10000 }, (err) => {
        hasFlutter = !err;
        resolve();
      });
    });
  } catch { /* not installed */ }

  // Also require Android SDK to be present.
  const hasAndroidSdk = findAndroidSdk() !== null;
  const ok = hasFlutter && hasAndroidSdk;

  send(ws, { type: "android_deploy_status", subtype: "deps_result", hasFlutter: ok } as any);
}

/** Detect first connected Android device via adb. Returns device serial or null. */
async function detectAndroidDevice(adbPath: string): Promise<string | null> {
  return new Promise((resolve) => {
    execFile(adbPath, ["devices"], { timeout: 10000 }, (err, stdout) => {
      if (err) { resolve(null); return; }
      // Parse output: lines after "List of devices attached" with "\t device"
      for (const line of stdout.split("\n").slice(1)) {
        const match = line.match(/^(\S+)\s+device$/);
        if (match) { resolve(match[1]); return; }
      }
      resolve(null);
    });
  });
}

/** List every device reported by `adb devices -l` (any state). */
async function listAndroidDevices(adbPath: string): Promise<Array<{ serial: string; model: string; state: string }>> {
  return new Promise((resolve) => {
    execFile(adbPath, ["devices", "-l"], { timeout: 10000 }, (err, stdout) => {
      if (err) { resolve([]); return; }
      const out: Array<{ serial: string; model: string; state: string }> = [];
      for (const line of stdout.split("\n").slice(1)) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        // Example: "emulator-5554  device product:sdk_gphone ... model:sdk_gphone64_x86_64 ..."
        const parts = trimmed.split(/\s+/);
        if (parts.length < 2) continue;
        const serial = parts[0];
        const state = parts[1];
        const modelMatch = trimmed.match(/\bmodel:(\S+)/);
        const model = modelMatch ? modelMatch[1].replace(/_/g, " ") : serial;
        out.push({ serial, model, state });
      }
      resolve(out);
    });
  });
}

async function androidDeployListDevices(ws: WebSocket): Promise<void> {
  const adbPath = findAdb();
  const devices = adbPath ? await listAndroidDevices(adbPath) : [];
  send(ws, { type: "android_deploy_status", subtype: "devices_list", devices } as any);
}

/** Try to install APK silently via adb. Returns true on success. */
async function tryAdbInstall(ws: WebSocket, adbPath: string, apkPath: string, serial: string): Promise<boolean> {
  sendAndroidDeployLog(ws, `Встановлення на "${serial}"...`);
  sendAndroidDeployLog(ws, `Команда: adb -s ${serial} install -r ${apkPath}`);

  return new Promise((resolve) => {
    const proc = spawn(adbPath, ["-s", serial, "install", "-r", apkPath]);
    activeAndroidDeployProcess.set(ws, proc);

    proc.stdout.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        if (line.trim()) sendAndroidDeployLog(ws, line.trim());
      }
    });
    proc.stderr.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        if (line.trim()) sendAndroidDeployLog(ws, line.trim());
      }
    });

    proc.on("close", (code) => resolve(code === 0));
    proc.on("error", () => resolve(false));
  });
}

const ANDROID_PACKAGE = "com.danylooliinyk.pixelcode";

/** Launch the installed app via adb monkey (uses LAUNCHER intent). Returns true on success. */
async function tryAdbLaunch(ws: WebSocket, adbPath: string, serial: string): Promise<boolean> {
  sendAndroidDeployLog(ws, `Запуск додатку на "${serial}"...`);
  sendAndroidDeployLog(
    ws,
    `Команда: adb -s ${serial} shell monkey -p ${ANDROID_PACKAGE} -c android.intent.category.LAUNCHER 1`,
  );

  return new Promise((resolve) => {
    const proc = spawn(adbPath, [
      "-s",
      serial,
      "shell",
      "monkey",
      "-p",
      ANDROID_PACKAGE,
      "-c",
      "android.intent.category.LAUNCHER",
      "1",
    ]);
    activeAndroidDeployProcess.set(ws, proc);

    let stdout = "";
    proc.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
      for (const line of chunk.toString().split("\n")) {
        if (line.trim()) sendAndroidDeployLog(ws, line.trim());
      }
    });
    proc.stderr.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        if (line.trim()) sendAndroidDeployLog(ws, line.trim());
      }
    });

    proc.on("close", (code) => {
      // monkey can exit 0 even if it fails to find the package, so also check stdout.
      const ok = code === 0 && !/No activities found/i.test(stdout) && !/Error/i.test(stdout);
      resolve(ok);
    });
    proc.on("error", () => resolve(false));
  });
}

async function androidDeployStart(ws: WebSocket, requestedSerial?: string): Promise<void> {
  dbg("info", "deploy", `Starting Android build…${requestedSerial ? ` (target: ${requestedSerial})` : ""}`);

  sendAndroidDeployLog(ws, "Побудова Android APK...");
  sendAndroidDeployLog(ws, "Команда: flutter build apk --release");

  const buildProcess = spawn("flutter", ["build", "apk", "--release"], {
    cwd: PROJECT_CWD,
  });
  activeAndroidDeployProcess.set(ws, buildProcess);

  buildProcess.stdout.on("data", (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (line.trim()) sendAndroidDeployLog(ws, line.trim());
    }
  });
  buildProcess.stderr.on("data", (chunk: Buffer) => {
    for (const line of chunk.toString().split("\n")) {
      if (line.trim()) sendAndroidDeployError(ws, line.trim());
    }
  });

  const buildExitCode = await new Promise<number | null>((resolve) => {
    buildProcess.on("close", resolve);
    buildProcess.on("error", (err) => {
      sendAndroidDeployError(ws, `Помилка при побудові: ${err.message}`);
      resolve(1);
    });
  });

  if (buildExitCode !== 0) {
    sendAndroidDeployError(ws, `Помилка при побудові. Код виходу: ${buildExitCode}`);
    send(ws, { type: "android_deploy_status", subtype: "complete", success: false } as any);
    activeAndroidDeployProcess.delete(ws);
    return;
  }

  const apkCandidates = [
    join(PROJECT_CWD, "build/app/outputs/flutter-apk/app-release.apk"),
    join(PROJECT_CWD, "build/app/outputs/apk/release/app-release.apk"),
  ];
  const apkPath = apkCandidates.find((p) => existsSync(p));

  if (!apkPath) {
    sendAndroidDeployError(ws, "APK не знайдено після побудови");
    send(ws, { type: "android_deploy_status", subtype: "complete", success: false } as any);
    activeAndroidDeployProcess.delete(ws);
    return;
  }

  sendAndroidDeployLog(ws, `Білд завершено: ${apkPath}`);
  sendAndroidDeployLog(ws, "");

  // Try direct install via adb if a device is connected.
  const adbPath = findAdb();
  if (adbPath) {
    let serial: string | null = null;
    if (requestedSerial) {
      // Verify the requested device is still connected & in "device" state.
      const all = await listAndroidDevices(adbPath);
      const match = all.find((d) => d.serial === requestedSerial && d.state === "device");
      if (match) {
        serial = match.serial;
        sendAndroidDeployLog(ws, `Обрано пристрій: ${match.model} (${match.serial})`);
      } else {
        sendAndroidDeployLog(ws, `Пристрій "${requestedSerial}" не доступний. Шукаю інші...`);
      }
    }
    if (!serial) {
      sendAndroidDeployLog(ws, "Шукаю підключені Android пристрої...");
      serial = await detectAndroidDevice(adbPath);
    }

    if (serial) {
      sendAndroidDeployLog(ws, `Знайдено пристрій: ${serial}`);
      const ok = await tryAdbInstall(ws, adbPath, apkPath, serial);

      if (ok) {
        sendAndroidDeployLog(ws, "");
        sendAndroidDeployLog(ws, "===============================================");
        sendAndroidDeployLog(ws, "APK встановлено на пристрій!");
        sendAndroidDeployLog(ws, "===============================================");
        sendAndroidDeployLog(ws, "");

        const launched = await tryAdbLaunch(ws, adbPath, serial);
        if (launched) {
          sendAndroidDeployLog(ws, "Додаток запущено.");
        } else {
          sendAndroidDeployLog(ws, "Не вдалося автоматично запустити додаток. Запустіть вручну.");
        }

        send(ws, { type: "android_deploy_status", subtype: "complete", success: true } as any);
        activeAndroidDeployProcess.delete(ws);
        return;
      }

      sendAndroidDeployLog(ws, "Пряме встановлення не вдалося. Перемикаюсь на завантаження...");
      sendAndroidDeployLog(ws, "");
    } else {
      sendAndroidDeployLog(ws, "Пристрій не знайдено. Використовую завантаження...");
      sendAndroidDeployLog(ws, "");
    }
  } else {
    sendAndroidDeployLog(ws, "adb не знайдено. Використовую завантаження...");
    sendAndroidDeployLog(ws, "");
  }

  // Fallback: serve APK for download.
  const apkFileName = "app-release.apk";
  const servedApkPath = join(otaDir, apkFileName);
  try { rmSync(servedApkPath, { force: true }); } catch { /* ok */ }

  const cpProcess = spawn("cp", [apkPath, servedApkPath]);
  const cpExitCode = await new Promise<number | null>((resolve) => {
    cpProcess.on("close", resolve);
    cpProcess.on("error", () => resolve(1));
  });

  if (cpExitCode !== 0 || !existsSync(servedApkPath)) {
    sendAndroidDeployError(ws, "Не вдалося підготувати APK до роздачі");
    send(ws, { type: "android_deploy_status", subtype: "complete", success: false } as any);
    activeAndroidDeployProcess.delete(ws);
    return;
  }

  // Prefer Tailscale Funnel (HTTPS) if available, else fall back to LAN IP.
  const baseUrl = tailscaleUrl
    ? tailscaleUrl.replace("wss://", "https://")
    : `http://${getOtaHost()}:${PORT}`;
  const installUrl = `${baseUrl}/${apkFileName}`;

  sendAndroidDeployLog(ws, `APK готовий: ${installUrl}`);
  sendAndroidDeployLog(ws, "");
  sendAndroidDeployLog(ws, "===============================================");
  sendAndroidDeployLog(ws, "Відкрийте посилання на пристрої та встановіть APK");
  sendAndroidDeployLog(ws, "===============================================");

  send(ws, { type: "android_deploy_status", subtype: "install_ready", installUrl } as any);
  activeAndroidDeployProcess.delete(ws);
}

function androidDeployCancel(ws: WebSocket): void {
  const proc = activeAndroidDeployProcess.get(ws);
  if (proc) {
    proc.kill("SIGTERM");
    activeAndroidDeployProcess.delete(ws);
    sendAndroidDeployLog(ws, "Операцію скасовано.");
    send(ws, { type: "android_deploy_status", subtype: "complete", success: false } as any);
  }
}

// ─── Device screenshot ──────────────────────────────────────────────────────

function sendScreenshotError(ws: WebSocket, platform: string, message: string): void {
  send(ws, { type: "screenshot_status", subtype: "error", platform, message } as any);
}

function sendScreenshotReady(ws: WebSocket, platform: string, url: string): void {
  send(ws, { type: "screenshot_status", subtype: "ready", platform, url } as any);
}

/** Public URL for a file served via the OTA HTTP endpoint. */
function otaFileUrl(fileName: string): string {
  const baseUrl = tailscaleUrl
    ? tailscaleUrl.replace("wss://", "https://")
    : `http://${getOtaHost()}:${PORT}`;
  return `${baseUrl}/${fileName}`;
}

async function captureAndroidScreenshot(ws: WebSocket, requestedSerial?: string): Promise<void> {
  const adbPath = findAdb();
  if (!adbPath) {
    sendScreenshotError(ws, "android", "adb не знайдено");
    return;
  }

  let serial = requestedSerial;
  if (!serial) {
    const devices = await listAndroidDevices(adbPath);
    const ready = devices.find((d) => d.state === "device");
    serial = ready?.serial;
  }
  if (!serial) {
    sendScreenshotError(ws, "android", "Пристрій не знайдено");
    return;
  }

  const fileName = `screenshot-android-${Date.now()}.png`;
  const filePath = join(otaDir, fileName);
  try { mkdirSync(otaDir, { recursive: true }); } catch { /* ok */ }

  const ok = await new Promise<boolean>((resolve) => {
    const proc = spawn(adbPath, ["-s", serial!, "exec-out", "screencap", "-p"]);
    const chunks: Buffer[] = [];
    let stderr = "";
    proc.stdout.on("data", (c: Buffer) => chunks.push(c));
    proc.stderr.on("data", (c: Buffer) => { stderr += c.toString(); });
    proc.on("error", () => resolve(false));
    proc.on("close", (code) => {
      if (code !== 0) {
        dbg("warn", "screenshot", `adb screencap exit ${code}: ${stderr}`);
        resolve(false);
        return;
      }
      try {
        writeFileSync(filePath, Buffer.concat(chunks));
        resolve(true);
      } catch (e) {
        dbg("warn", "screenshot", `write failed: ${(e as Error).message}`);
        resolve(false);
      }
    });
  });

  if (!ok) {
    sendScreenshotError(ws, "android", "Не вдалося зробити скріншот");
    return;
  }
  sendScreenshotReady(ws, "android", otaFileUrl(fileName));
}

/** Resolve idevicescreenshot binary (libimobiledevice) — PATH, then brew locations. */
function findIdeviceScreenshot(): string | null {
  try {
    return execFileSync("which", ["idevicescreenshot"], { timeout: 3000 }).toString().trim() || null;
  } catch { /* not in PATH */ }
  for (const p of ["/opt/homebrew/bin/idevicescreenshot", "/usr/local/bin/idevicescreenshot"]) {
    if (existsSync(p)) return p;
  }
  return null;
}

type IosCaptureResult = "ok" | "not_installed" | "no_device" | "failed";

/** Try capturing from a physical iPhone via libimobiledevice. */
async function tryPhysicalIosScreenshot(filePath: string): Promise<IosCaptureResult> {
  const binary = findIdeviceScreenshot();
  if (!binary) return "not_installed";

  return new Promise((resolve) => {
    const proc = spawn(binary, [filePath]);
    let stderr = "";
    proc.stderr.on("data", (c: Buffer) => { stderr += c.toString(); });
    proc.on("error", () => resolve("failed"));
    proc.on("close", (code) => {
      if (code !== 0) {
        dbg("warn", "screenshot", `idevicescreenshot exit ${code}: ${stderr}`);
        const noDevice = /No device found|ERROR: Could not connect/i.test(stderr);
        resolve(noDevice ? "no_device" : "failed");
        return;
      }
      resolve(existsSync(filePath) ? "ok" : "failed");
    });
  });
}

/** Try capturing from a booted iOS simulator. */
async function trySimulatorScreenshot(filePath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const proc = spawn("xcrun", ["simctl", "io", "booted", "screenshot", filePath]);
    let stderr = "";
    proc.stderr.on("data", (c: Buffer) => { stderr += c.toString(); });
    proc.on("error", () => resolve(false));
    proc.on("close", (code) => {
      if (code !== 0) {
        dbg("warn", "screenshot", `simctl screenshot exit ${code}: ${stderr}`);
      }
      resolve(code === 0 && existsSync(filePath));
    });
  });
}

async function captureIosScreenshot(ws: WebSocket): Promise<void> {
  const fileName = `screenshot-ios-${Date.now()}.png`;
  const filePath = join(otaDir, fileName);
  try { mkdirSync(otaDir, { recursive: true }); } catch { /* ok */ }

  // 1) Physical iPhone via libimobiledevice.
  const physical = await tryPhysicalIosScreenshot(filePath);
  if (physical === "ok") {
    sendScreenshotReady(ws, "ios", otaFileUrl(fileName));
    return;
  }

  // 2) Fallback: booted simulator.
  if (await trySimulatorScreenshot(filePath)) {
    sendScreenshotReady(ws, "ios", otaFileUrl(fileName));
    return;
  }

  if (physical === "not_installed") {
    sendScreenshotError(ws, "ios",
      "Для фізичного iPhone потрібен libimobiledevice: `brew install libimobiledevice`. " +
      "Або запустіть iOS Simulator.");
  } else if (physical === "no_device") {
    sendScreenshotError(ws, "ios",
      "iPhone не знайдено. Підключіть розблокований iPhone (Trust This Computer) " +
      "або запустіть Simulator.");
  } else {
    sendScreenshotError(ws, "ios",
      "Скріншот не вдався. Перевірте, що iPhone підключений і розблокований, або запустіть Simulator.");
  }
}

// ─── HTTP + WebSocket server (single port for WS and OTA file serving) ───────

// Forward-declared so makeOtaHandler's closure can find it; populated below.
let adminContext: AdminContext;

const httpServer = createHttpServer(makeOtaHandler());
const wss = new WebSocketServer({ server: httpServer });
httpServer.listen(PORT);

// ─── mDNS advertisement ──────────────────────────────────────────────────────
// Advertise this server on the local network so PixelCode clients can
// discover it automatically without manual IP entry.
const bonjour = new Bonjour();
let mdnsActive = false;
let mdnsService: ReturnType<Bonjour["publish"]>;

function publishMdns(): void {
  mdnsService = bonjour.publish({
    name: `PixelCode @ ${hostname()}`,
    type: "pixelcode",
    protocol: "tcp",
    port: PORT,
    // Explicit TXT record — required for iOS NWBrowser.bonjourWithTXTRecord
    // (used by the `bonsoir` package) to surface the service. Without a TXT
    // record, iOS silently filters the service out, even though Android
    // (NsdManager) and raw mDNS tools still see it.
    txt: { version: "1" },
  });
  mdnsService.on("up", () => {
    mdnsActive = true;
    dbg("info", "mDNS", `Advertised _pixelcode._tcp on port ${PORT} as "${mdnsService.name}"`);
  });
}

publishMdns();

async function restartMdns(): Promise<boolean> {
  mdnsActive = false;
  return new Promise((resolve) => {
    bonjour.unpublishAll(() => {
      publishMdns();
      // Give Bonjour a moment to re-advertise and fire the "up" event.
      setTimeout(() => resolve(mdnsActive), 1500);
    });
  });
}

function buildHealthContext(): HealthContext {
  return {
    serverPort: PORT,
    serverListening: httpServer.listening,
    mdnsActive,
    restartMdns,
  };
}

/** Unpublish mDNS, give "goodbye" packets a moment to fly, then exit with `code`. */
function gracefulExit(code: number, reason: string): void {
  dbg("info", "shutdown", `${reason} (exit=${code}) — unpublishing mDNS…`);
  let exited = false;
  const doExit = () => { if (!exited) { exited = true; process.exit(code); } };
  bonjour.unpublishAll(() => {
    try { bonjour.destroy(); } catch { /* already destroyed */ }
    doExit();
  });
  setTimeout(doExit, 1500);
}

function shutdownMdns(signal: string): void {
  gracefulExit(0, `signal=${signal}`);
}

process.on("SIGINT", () => shutdownMdns("SIGINT"));
process.on("SIGTERM", () => shutdownMdns("SIGTERM"));

// ─── Admin context (status / config / restart / stop / logs) ────────────────

adminContext = {
  configPath: __configSource.filePath,
  bootedAtMs: __bootedAtMs,
  getEffectiveConfig: () => ({
    port: PORT,
    projectCwd: PROJECT_CWD,
    otaHostname: OTA_HOSTNAME ?? null,
    launcherPort: __configSource.effective.launcherPort,
  }),
  getConfigSources: () => ({
    envOverrides: Object.keys(__configSource.envOverrides) as Array<keyof ServerConfig>,
    flagOverrides: Object.keys(__configSource.flagOverrides) as Array<keyof ServerConfig>,
  }),
  getClientCount: () => connectedClients.size,
  getConnectedClients: () => buildClientsList(),
  getMdnsActive: () => mdnsActive,
  getTailscaleUrl: () => tailscaleUrl,
  scheduleExit: (code, reason) => {
    // Defer slightly so the HTTP response flushes before we tear down.
    setTimeout(() => gracefulExit(code, reason), 100);
  },
};
process.on("exit", () => {
  bonjour.unpublishAll();
  bonjour.destroy();
});

/** Broadcast a message to every connected client. */
function broadcastAll(msg: ServerMessage): void {
  const data = JSON.stringify(msg);
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) client.send(data);
  }
}

/** Broadcast to every client except the sender. */
function broadcastExcept(sender: WebSocket, msg: ServerMessage): void {
  const data = JSON.stringify(msg);
  for (const client of wss.clients) {
    if (client !== sender && client.readyState === WebSocket.OPEN) client.send(data);
  }
}

/** Send the full chat history snapshot to a single client (e.g. on connect).
 *  Always sent — even when empty — so the client can transition out of the
 *  `syncing` state on resumed sessions with no prior messages. */
function sendChatHistory(ws: WebSocket): void {
  send(ws, chatHistory.snapshot());
}

console.log(`🏗️  PixelCode server listening on ws://localhost:${PORT}`);
console.log(`   Working directory: ${PROJECT_CWD}`);
console.log(`   Admin UI:        http://localhost:${PORT}/admin/  (loopback only)`);
console.log(`   Config file:     ${__configSource.filePath}`);
console.log(`   Roles available: ${Object.keys(roleCatalog).join(", ")}`);
console.log(`   Trait memory:    ${getAllTraits(traitStore).length} lessons loaded`);

wss.on("connection", (ws, request) => {
  wsClientsReady = true;
  const remoteAddress = request.socket.remoteAddress ?? "unknown";
  dbg("info", "ws", `Client connected from ${remoteAddress}`);

  // Register with placeholder info until client_info arrives
  connectedClients.set(ws, {
    clientId: `anon-${Date.now()}`,
    deviceName: "",
    platform: "unknown",
    connectedAt: new Date().toISOString(),
    remoteAddress,
    ws,
  });

  // Send initial agent list immediately. Real shared sessionId is propagated
  // when known so reconnecting clients can resume context transparently.
  send(ws, {
    type: "init",
    sessionId: currentSessionId ?? "pending",
    agents: agentInfoForClient(ws),
    workingDirectory: PROJECT_CWD,
  });
  // Send server connection info so clients can share/display it
  const localIps: string[] = [];
  for (const ifaces of Object.values(networkInterfaces())) {
    for (const iface of ifaces ?? []) {
      if (iface.family === "IPv4" && !iface.internal) localIps.push(iface.address);
    }
  }
  send(ws, {
    type: "server_info",
    hostname: hostname(),
    localIps,
    port: PORT,
    tunnelUrl: tailscaleUrl,
  } as any);
  sendDebug(ws, "info", "ws", "Connected to PixelCode server");
  // Replay logs that were produced before this client connected (e.g. Tailscale startup)
  for (const entry of earlyLogBuffer) {
    send(ws, { type: "debug_log", timestamp: entry.timestamp, level: entry.level, category: entry.category, message: entry.message });
  }
  sendBoardState(ws);
  sendTraits(ws);
  // Send existing chat history so new clients are in sync
  sendChatHistory(ws);
  // Send stored game state for cross-device sync
  if (latestFullGameState) {
    send(ws, {
      type: "game_state_sync",
      fullState: latestFullGameState,
      stateUpdatedAt: latestStateUpdatedAt,
    } as any);
    dbg("info", "game", `Sent stored game state to new client (updatedAt=${latestStateUpdatedAt})`);
  }
  ws.on("message", async (data) => {
    try {
      const msg = JSON.parse(data.toString()) as ClientMessage;
      if (msg.type !== "sync_positions") {
        dbg("debug", "ws", `← ${msg.type}${msg.type === "send_message" ? `: "${(msg as {content: string}).content.slice(0, 60)}"` : ""}`);
      }

      switch (msg.type) {
        case "send_message": {
          const targetAgent = msg.agentId || "manager";
          const images = msg.images;
          sendDebug(ws, "info", "ws", `User → ${targetAgent}: "${msg.content.slice(0, 60)}…"${images?.length ? ` [+${images.length} image(s)]` : ""}`);

          // ── Task difficulty gate ───────────────────────────────────────
          if (msg.taskDifficulty && !msg.forceSend) {
            const gs = clientGameState.get(ws);
            const agentSkills = gs?.instances[targetAgent]?.skills;
            if (agentSkills) {
              const levels = Object.values(agentSkills);
              const avgSkill = levels.length > 0
                ? levels.reduce((a, b) => a + b, 0) / levels.length
                : 1;
              // Required avg skill: difficulty maps to thresholds 1/3/5/7/9
              const required = [0, 1, 3, 5, 7, 9][Math.min(msg.taskDifficulty, 5)] ?? 1;
              if (avgSkill < required) {
                send(ws, {
                  type: "task_too_hard",
                  agentId: targetAgent,
                  required,
                  current: Math.round(avgSkill * 10) / 10,
                } as any);
                sendDebug(ws, "warn", "game", `Task difficulty ${msg.taskDifficulty} rejected for ${targetAgent}: avg skill ${avgSkill.toFixed(1)} < required ${required}`);
                break;
              }
            }
          }

          // If forceSend with a difficult task, add a note to the prompt
          const contentWithNote = (msg.taskDifficulty && msg.forceSend)
            ? `${msg.content}\n\n[System note: This task may exceed your current skill level. If you cannot complete it confidently, say so explicitly and describe what skill level would be needed.]`
            : msg.content;

          // Store user message and broadcast snapshot to all other clients.
          // (Sender already added the message optimistically in the UI.)
          chatHistory.add({ role: "user", text: msg.content, agentId: targetAgent, timestamp: new Date().toISOString(), ...(images?.length ? { images } : {}) });
          chatHistory.save(historyFilePath(PROJECT_CWD));
          broadcastExcept(ws, chatHistory.snapshot());

          // Enqueue instead of blocking — manager stays available for new messages
          taskQueue.enqueue({
            id: `chat_${Date.now()}`,
            priority: "high",
            type: "chat",
            userMessage: contentWithNote,
            targetAgentId: targetAgent,
            images: images ?? undefined,
            enqueuedAt: Date.now(),
            ws,
          });
          sendQueueStatus(ws);
          processQueue(ws); // non-blocking kick
          break;
        }

        case "get_status":
          for (const agent of agentInfoForClient(ws)) {
            send(ws, {
              type: "agent_status",
              agentId: agent.id,
              status: "idle",
              tools: [],
            });
          }
          break;

        case "new_chat": {
          const oldSession = currentSessionId;
          dbg("info", "ws", `New chat requested. Old session: ${oldSession ?? "none"}`);
          sendDebug(ws, "warn", "session", `New chat. Dropped session=${oldSession?.slice(0, 12) ?? "none"}`);
          currentSessionId = null;
          persistSession();
          chatHistory.clear();
          chatHistory.save(historyFilePath(PROJECT_CWD));
          // Broadcast cleared init to all clients so every device resets.
          for (const c of wss.clients) {
            if (c.readyState !== WebSocket.OPEN) continue;
            send(c as WebSocket, {
              type: "init",
              sessionId: "pending",
              agents: agentInfoForClient(c as WebSocket),
              workingDirectory: PROJECT_CWD,
            });
          }
          break;
        }

        case "clear_sessions": {
          dbg("info", "ws", "Clear sessions requested");
          sendDebug(ws, "warn", "session", "Clearing all SDK sessions from disk...");
          try {
            // Derive the Claude project dir from the actual working directory
            const cwdKey = PROJECT_CWD.replace(/\//g, "-").replace(/^-/, "");
            const projectDir = join(homedir(), ".claude", "projects", cwdKey);

            let cleared = 0;
            for (const dir of [projectDir]) {
              try {
                const entries = readdirSync(dir);
                for (const entry of entries) {
                  if (entry === "memory") continue; // preserve memory
                  const fullPath = join(dir, entry);
                  rmSync(fullPath, { recursive: true, force: true });
                  cleared++;
                }
              } catch {
                // dir doesn't exist, skip
              }
            }

            currentSessionId = null;
            persistSession();
            dbg("info", "ws", `Cleared ${cleared} session entries`);
            sendDebug(ws, "info", "session", `Cleared ${cleared} session entries from disk`);
            for (const c of wss.clients) {
              if (c.readyState !== WebSocket.OPEN) continue;
              send(c as WebSocket, {
                type: "init",
                sessionId: "pending",
                agents: agentInfoForClient(c as WebSocket),
                workingDirectory: PROJECT_CWD,
              });
            }
          } catch (err) {
            const errMsg = err instanceof Error ? err.message : String(err);
            dbg("error", "ws", `Failed to clear sessions: ${errMsg}`);
            sendDebug(ws, "error", "session", `Clear failed: ${errMsg}`);
          }
          break;
        }

        case "interrupt":
          dbg("info", "ws", "Interrupt requested");
          sendDebug(ws, "warn", "ws", "Interrupt requested (not yet implemented)");
          break;

        // ─── Project management ──────────────────────────────────────────

        case "set_project": {
          const newPath = msg.path;
          dbg("info", "project", `Switching project to: ${newPath}`);
          PROJECT_CWD = newPath;
          // Reload trait memory and chat history for the new project
          traitStore = loadTraits(PROJECT_CWD);
          chatHistory.load(historyFilePath(PROJECT_CWD));
          dbg("info", "traits", `Traits loaded for ${newPath}: ${getAllTraits(traitStore).length} lessons`);
          // Load shared SDK session for the new project (per-project file).
          loadPersistedSession();
          // Clear per-client UI/state
          clientProjectContext.delete(ws);
          clientGameState.delete(ws);
          getCommLog(ws).length = 0;
          getMetrics(ws).clear();
          getActiveTasks(ws).clear();
          getAgentMap(ws).clear();
          getEmittedTools(ws).clear();
          // Send fresh init with the resolved session for this project
          send(ws, {
            type: "init",
            sessionId: currentSessionId ?? "pending",
            agents: agentInfoForClient(ws),
            workingDirectory: PROJECT_CWD,
          });
          sendDebug(ws, "info", "project", `Switched to: ${newPath}`);
          sendTraits(ws);
          break;
        }

        case "set_project_context": {
          const memories = (msg as { type: "set_project_context"; memories: string }).memories;
          clientProjectContext.set(ws, memories);
          dbg("info", "project", `Project memory set (${memories.length} chars)`);
          sendDebug(ws, "info", "project", `Team memory loaded (${memories.length} chars)`);
          break;
        }

        // ─── Game economy ──────────────────────────────────────────────────

        case "set_game_state": {
          const gs: GameStateData = { instances: msg.instances };
          clientGameState.set(ws, gs);
          const instanceIds = Object.keys(gs.instances);
          const teamSummary = instanceIds
            .map((id) => `${id} (${gs.instances[id].nickname}, hw=${gs.instances[id].hardware})`)
            .join(", ");
          dbg("info", "game", `Game state updated: ${instanceIds.length} instance(s) hired`);
          sendDebug(ws, "info", "game", `Team: ${teamSummary || "(empty)"}`);

          // Cross-device sync: last-write-wins by timestamp. Older writes are
          // rejected and the authoritative state is pushed back so the stale
          // client converges instead of clobbering everyone.
          //
          // A fresh client signals itself with incomingTs == 0 (never-persisted
          // state). We only accept such a payload when the server has nothing
          // at all — otherwise a newly installed device could wipe another
          // device's accumulated progress just by connecting.
          if (msg.fullState) {
            const incomingTs = msg.stateUpdatedAt ?? 0;
            const isSeed = latestFullGameState === null;
            const isFreshClient = incomingTs === 0;
            // Seed path: empty server accepts whatever the first client sends.
            // Steady-state: reject fresh clients entirely; otherwise require a
            // strictly newer timestamp than the authoritative one.
            const accept =
              isSeed || (!isFreshClient && incomingTs > latestStateUpdatedAt);
            if (accept) {
              latestFullGameState = msg.fullState;
              latestStateUpdatedAt = incomingTs;
              persistGameState();
              broadcastExcept(ws, {
                type: "game_state_sync",
                fullState: msg.fullState,
                stateUpdatedAt: incomingTs,
              } as any);
              dbg("info", "game", `Game state accepted (ts=${incomingTs}), synced to ${wss.clients.size - 1} other client(s)`);
            } else if (latestFullGameState) {
              send(ws, {
                type: "game_state_sync",
                fullState: latestFullGameState,
                stateUpdatedAt: latestStateUpdatedAt,
              } as any);
              dbg("info", "game", `Game state rejected (ts=${incomingTs} <= ${latestStateUpdatedAt}); pushed authoritative state back`);
            }
          }
          break;
        }

        case "generate_summary": {
          await generateSessionSummary(ws);
          break;
        }

        // ─── Dungeon training ─────────────────────────────────────────────

        case "start_dungeon": {
          const { agentId: dungeonAgentId, skillType, difficulty } = msg;
          const gs = clientGameState.get(ws);

          if (!gs?.instances[dungeonAgentId]) {
            send(ws, { type: "dungeon_error", agentId: dungeonAgentId, error: "Agent is not hired." } as any);
            break;
          }

          const challenge = getChallenge(skillType, difficulty);
          sendDebug(ws, "info", "dungeon", `Dungeon started for ${dungeonAgentId}: skill=${skillType}, diff=${difficulty}, challenge="${challenge.title}"`);

          // Notify client: show what the agent will work on
          send(ws, {
            type: "dungeon_started",
            agentId: dungeonAgentId,
            skillType,
            difficulty,
            challenge: challenge.title,
          } as any);

          // Run dungeon asynchronously
          runDungeon(dungeonAgentId, skillType, difficulty, gs, PROJECT_CWD)
            .then((result) => {
              sendDebug(ws, "info", "dungeon", `Dungeon complete for ${dungeonAgentId}: score=${result.score}, xp=${result.xpEarned}, passed=${result.passed}`);
              send(ws, {
                type: "dungeon_complete",
                agentId: result.agentId,
                skillType: result.skillType,
                xpEarned: result.xpEarned,
                score: result.score,
                feedback: result.feedback,
                passed: result.passed,
              } as any);
            })
            .catch((err) => {
              const errMsg = err instanceof Error ? err.message : String(err);
              sendDebug(ws, "error", "dungeon", `Dungeon error for ${dungeonAgentId}: ${errMsg}`);
              send(ws, { type: "dungeon_error", agentId: dungeonAgentId, error: errMsg } as any);
            });

          break;
        }

        // ─── Task board messages ──────────────────────────────────────────

        case "board_get_state":
        case "board_create_task":
        case "board_move_task":
        case "board_update_task":
        case "board_delete_task":
        case "board_assign_agent":
          handleBoardMessage(ws, msg);
          break;

        // ─── Agent traits ─────────────────────────────────────────────────

        case "get_traits":
          sendTraits(ws);
          break;

        case "record_lesson": {
          const validCategories = new Set([
            "code_quality", "architecture", "testing", "security",
            "communication", "delegation", "problem_solving", "tools_usage",
          ]);
          if (!validCategories.has(msg.category)) {
            send(ws, { type: "error", message: `Invalid lesson category: ${msg.category}` });
            break;
          }
          const lesson = recordLesson(PROJECT_CWD, traitStore, {
            agentId: msg.agentId,
            type: msg.lessonType as LessonType,
            category: msg.category as LessonCategory,
            tag: msg.tag,
            lesson: msg.lesson,
          });
          dbg("info", "traits", `Manual lesson recorded: [${msg.agentId}] ${msg.tag} (freq=${lesson.frequency})`);
          sendDebug(ws, "info", "traits", `Lesson recorded for ${msg.agentId}: ${msg.lesson}`);
          sendTraits(ws);
          break;
        }

        case "remove_lesson": {
          const removed = removeLesson(PROJECT_CWD, traitStore, msg.lessonId);
          if (removed) {
            dbg("info", "traits", `Lesson removed: ${msg.lessonId}`);
            sendDebug(ws, "info", "traits", `Lesson removed: ${msg.lessonId}`);
          }
          sendTraits(ws);
          break;
        }

        // ─── Permissions bypass ───────────────────────────────────────────
        case "set_bypass_permissions": {
          const enabled = (msg as { type: "set_bypass_permissions"; enabled: boolean }).enabled;
          clientBypassPermissions.set(ws, enabled);
          dbg("info", "ws", `Bypass permissions: ${enabled ? "ON" : "OFF"}`);
          sendDebug(ws, "info", "ws", `Bypass permissions: ${enabled ? "ENABLED — agents will not ask for permission" : "DISABLED — agents will ask for permission"}`);
          break;
        }

        // ─── iOS OTA deploy ──────────────────────────────────────────────
        case "ios_deploy_check":
          iosDeployCheck(ws).catch((err) => {
            sendDeployError(ws, `Check failed: ${err}`);
          });
          break;

        case "ios_deploy_start":
          iosDeployStart(ws).catch((err) => {
            sendDeployError(ws, `Deploy failed: ${err}`);
            send(ws, { type: "ios_deploy_status", subtype: "complete", success: false } as any);
          });
          break;

        case "ios_deploy_cancel":
          iosDeployCancel(ws);
          break;

        // ─── Android deploy ──────────────────────────────────────────────
        case "android_deploy_check":
          androidDeployCheck(ws).catch((err) => {
            sendAndroidDeployError(ws, `Check failed: ${err}`);
          });
          break;

        case "android_deploy_list_devices":
          androidDeployListDevices(ws).catch((err) => {
            sendAndroidDeployError(ws, `List devices failed: ${err}`);
          });
          break;

        case "android_deploy_start": {
          const serial = (msg as { type: "android_deploy_start"; deviceSerial?: string }).deviceSerial;
          androidDeployStart(ws, serial).catch((err) => {
            sendAndroidDeployError(ws, `Deploy failed: ${err}`);
            send(ws, { type: "android_deploy_status", subtype: "complete", success: false } as any);
          });
          break;
        }

        case "android_deploy_cancel":
          androidDeployCancel(ws);
          break;

        // ─── Device screenshot ────────────────────────────────────────────
        case "screenshot_capture": {
          const payload = msg as {
            type: "screenshot_capture";
            platform: "android" | "ios";
            deviceSerial?: string;
          };
          if (payload.platform === "android") {
            captureAndroidScreenshot(ws, payload.deviceSerial).catch((err) => {
              sendScreenshotError(ws, "android", `Screenshot failed: ${err}`);
            });
          } else {
            captureIosScreenshot(ws).catch((err) => {
              sendScreenshotError(ws, "ios", `Screenshot failed: ${err}`);
            });
          }
          break;
        }

        // ─── Tailscale setup ──────────────────────────────────────────
        case "tailscale_connect": {
          const binary = findTailscale();
          const tsLog = (msg: string) =>
            send(ws, { type: "tailscale_log", message: msg } as any);

          if (!binary) {
            tsLog("❌ tailscale не знайдено. Встановіть: brew install tailscale");
            break;
          }

          tsLog("Запускаю tailscale up…");
          const proc = spawn(binary, ["up"], { stdio: ["ignore", "pipe", "pipe"] });

          const onOutput = (chunk: Buffer) => {
            const text = chunk.toString();
            for (const line of text.split("\n")) {
              const trimmed = line.trim();
              if (!trimmed) continue;
              tsLog(trimmed);
              // Auto-open auth URL in Mac's default browser
              const urlMatch = trimmed.match(/https:\/\/login\.tailscale\.com\/[^\s]+/);
              if (urlMatch) {
                spawn("open", [urlMatch[0]], { stdio: "ignore" });
                tsLog("🌐 Відкриваю браузер для авторизації…");
              }
            }
          };
          proc.stdout?.on("data", onOutput);
          proc.stderr?.on("data", onOutput);

          proc.on("close", async (code) => {
            if (code === 0) {
              tsLog("✓ Tailscale підключено!");
              await enableTailscaleFunnel(PORT);
              const tsHostname = await getTailscaleHostname();
              if (tsHostname) {
                tailscaleUrl = `wss://${tsHostname}`;
                tsLog(`🚀 Tunnel активний: ${tailscaleUrl}`);
                const localIps: string[] = [];
                for (const ifaces of Object.values(networkInterfaces())) {
                  for (const iface of ifaces ?? []) {
                    if (iface.family === "IPv4" && !iface.internal) localIps.push(iface.address);
                  }
                }
                broadcastAll({ type: "server_info", hostname: hostname(), localIps, port: PORT, tunnelUrl: tailscaleUrl } as any);
              } else {
                tsLog("⚠️ Tailscale запущено, але hostname не знайдено");
              }
            } else {
              tsLog(`tailscale up завершився з кодом ${code}`);
            }
          });
          break;
        }

        // ─── Network diagnostics ─────────────────────────────────────────
        case "health_check_request": {
          const items = await runAllChecks(buildHealthContext());
          send(ws, { type: "health_check_result", items } as any);
          break;
        }

        case "health_fix_request": {
          const payload = msg as { type: "health_fix_request"; id: HealthItemId };
          const ctx = buildHealthContext();
          await runFix(payload.id, ctx);
          const updated = await runSingleCheck(payload.id, ctx);
          if (updated) send(ws, { type: "health_item_update", item: updated } as any);
          break;
        }

        // ─── Client identification ──────────────────────────────────────
        case "client_info": {
          const info = msg as { type: "client_info"; clientId: string; deviceName: string; platform: string };
          const existing = connectedClients.get(ws);
          connectedClients.set(ws, {
            clientId: info.clientId,
            deviceName: info.deviceName,
            platform: info.platform,
            connectedAt: existing?.connectedAt ?? new Date().toISOString(),
            remoteAddress: existing?.remoteAddress ?? "unknown",
            ws,
          });
          const label = info.deviceName || "unknown";
          dbg("info", "clients", `Client identified: ${label} (${info.platform}) [${info.clientId.slice(0, 8)}]`);
          break;
        }

        // ─── Character position sync ──────────────────────────────────────
        case "sync_positions": {
          broadcastExcept(ws, { type: "positions_sync", positions: msg.positions } as any);
          break;
        }

        // ─── Live input sync ──────────────────────────────────────────────
        case "input_text": {
          const broadcast: ServerMessage = { type: "input_text", text: msg.text };
          for (const client of wss.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(JSON.stringify(broadcast));
            }
          }
          break;
        }

        case "input_images": {
          const broadcast: ServerMessage = { type: "input_images", images: msg.images };
          for (const client of wss.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(JSON.stringify(broadcast));
            }
          }
          break;
        }
      }
    } catch (err) {
      const errMsg = `Invalid message: ${err}`;
      dbg("error", "ws", errMsg);
      sendDebug(ws, "error", "ws", errMsg);
      send(ws, { type: "error", message: errMsg });
    }
  });

  ws.on("close", () => {
    const clientInfo = connectedClients.get(ws);
    const disconnectLabel = clientInfo?.deviceName || "unknown";
    dbg("info", "ws", `Client disconnected: ${disconnectLabel} (${clientInfo?.platform ?? "?"}). Shared session: ${currentSessionId ?? "none"}`);
    // Clean up task queue and running agents for this client
    const removed = taskQueue.removeForClient(ws);
    if (removed > 0) dbg("info", "queue", `Removed ${removed} queued tasks for disconnected client`);
    agentRunner.cancelAll(ws);
    connectedClients.delete(ws);
  });
});
