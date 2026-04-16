/**
 * PixelCode WebSocket Server
 *
 * Bridges Flutter UI ↔ Claude Agent SDK.
 * Runs a Manager session that delegates to team agents.
 */

import { WebSocketServer, WebSocket } from "ws";
import { rmSync, readdirSync, existsSync, readFileSync, mkdirSync, writeFileSync } from "fs";
import { join, extname } from "path";
import { homedir, hostname, networkInterfaces } from "os";
import { execFile, spawn, ChildProcess } from "child_process";
import { createServer as createHttpsServer } from "https";
import { createServer as createHttpServer, IncomingMessage, ServerResponse } from "http";
import { Bonjour } from "bonjour-service";
import selfsigned from "selfsigned";
import {
  query,
  type SDKMessage,
  type SDKAssistantMessage,
  type SDKPartialAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage,
  type SDKToolProgressMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { teamAgents, agentInfoList, buildOfficePrompt, buildDynamicAgents, hardwareToModel, type GameStateData } from "./agents.js";
import type { ClientMessage, ServerMessage, TaskCardData, TaskColumnKey, StickyColorKey, TaskPriorityKey } from "./protocol.js";
import {
  loadTraits, saveTraits, recordLesson, removeLesson,
  formatTraitsForPrompt, getAllTraits,
  type TraitStore, type LessonType, type LessonCategory,
} from "./trait_memory.js";
import { ChatHistory } from "./chat_history.js";

const PORT = parseInt(process.env.PORT ?? "9720", 10);
let PROJECT_CWD = process.env.PROJECT_CWD ?? process.cwd();

// ─── Debug logging ──────────────────────────────────────────────────────────

type DebugLevel = "debug" | "info" | "warn" | "error";

function dbg(level: DebugLevel, category: string, message: string, data?: unknown): void {
  const ts = new Date().toISOString().slice(11, 23); // HH:MM:SS.mmm
  const prefix = { debug: "🔍", info: "ℹ️ ", warn: "⚠️ ", error: "❌" }[level];
  const line = `${ts} ${prefix} [${category}] ${message}`;
  if (data !== undefined) {
    console.log(line, typeof data === "string" ? data : JSON.stringify(data, null, 2));
  } else {
    console.log(line);
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
          agents: agentInfoList,
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
      }

      // Parse tool uses from addressed agent
      for (const block of asst.message.content) {
        if (block.type === "tool_use") {
          const input = block.input as Record<string, unknown>;
          const status = toolStatusText(block.name, input);

          if (block.name === "Agent" || block.name === "Task") {
            const agentType = (input.subagent_type as string) ?? "general";
            const taskDesc = (input.description as string) ?? "";

            // Register sub-agent tool_use_id → agent name
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
            emitActivity(ws, targetAgentId, "tool_use", status);
          }

          send(ws, {
            type: "tool_use",
            agentId: targetAgentId,
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

      send(ws, {
        type: "result",
        text: "result" in res ? (res as unknown as Record<string, string>).result : "",
        costUsd,
        durationMs: res.duration_ms ?? 0,
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

// ─── Per-client shared session ───────────────────────────────────────────────

/** One shared session per WebSocket client. All agents share conversation context. */
const clientSessions = new WeakMap<WebSocket, string>();

/** Per-client project memory text, injected into system prompts. */
const clientProjectContext = new WeakMap<WebSocket, string>();

/** Per-client bypass permissions flag. When true, agents skip all permission prompts. */
const clientBypassPermissions = new WeakMap<WebSocket, boolean>();

/** Per-client game economy state (hired agents, hardware, skills). */
const clientGameState = new WeakMap<WebSocket, GameStateData>();

/** Latest full game state for cross-device sync (last-write-wins). */
let latestFullGameState: string | null = null;

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

/** Pre-computed set of known agent IDs for fast lookup. */
const knownAgentIds = new Set(agentInfoList.map(a => a.id));

/** Resolve a tool_use_id or agent name to a human-readable agent name. */
function resolveAgentId(ws: WebSocket, raw: string): string {
  if (knownAgentIds.has(raw)) return raw;
  return getAgentMap(ws).get(raw) ?? raw;
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

Team agents: manager, tech-lead, coder, reviewer, tester, security, ui-ux-designer

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

    const existingSessionId = clientSessions.get(ws);
    const q = query({
      prompt: reflectionPrompt,
      options: {
        model: "haiku",
        cwd: PROJECT_CWD,
        ...(existingSessionId && existingSessionId !== "pending" ? { resume: existingSessionId } : {}),
        continue: false,
        persistSession: false,
        allowedTools: [],
        maxTurns: 1,
      },
    });

    let responseText = "";
    for await (const message of q) {
      if (message.type === "assistant") {
        const content = (message as SDKAssistantMessage).message?.content;
        if (Array.isArray(content)) {
          for (const block of content) {
            if (block.type === "text") {
              responseText += block.text;
            }
          }
        }
      }
    }

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
    const validAgents = new Set(agentInfoList.map(a => a.id));

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

    // Build system prompt addressed to the target agent, with project memory + traits + game state
    const projectMemory = clientProjectContext.get(ws);
    const agentTraits = formatTraitsForPrompt(traitStore, targetAgentId);
    const gameState = clientGameState.get(ws);
    const systemPrompt = buildOfficePrompt(targetAgentId, projectMemory, agentTraits, gameState);

    // Build dynamic agent definitions (filtered by hired, models from hardware)
    const dynamicAgents = buildDynamicAgents(gameState);

    // Determine model based on target agent's hardware
    const targetHardware = gameState?.agentHardware[targetAgentId] ?? 0;
    const targetModel = hardwareToModel(targetHardware);

    // Determine tools based on target agent's definition + delegation capability
    const agentDef = teamAgents[targetAgentId];
    const baseTools = agentDef?.tools ?? ["Read", "Glob", "Grep", "Bash"];
    // Manager and tech-lead can delegate to other agents
    const canDelegate = targetAgentId === "manager" || targetAgentId === "tech-lead";
    const allowedTools = canDelegate
      ? [...new Set([...baseTools, "Agent"])]
      : [...baseTools];

    // Resume from existing session if available, persist for future resume.
    const existingSessionId = clientSessions.get(ws);
    const hasSession = existingSessionId && existingSessionId !== "pending";

    const queryOptions = {
      systemPrompt,
      model: targetModel,
      allowedTools,
      agents: dynamicAgents,
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
    dbg("info", "prompt", `System prompt (first 500 chars): ${systemPrompt.slice(0, 500)}`);
    sendDebug(ws, "info", "prompt", `SystemPrompt starts: "${systemPrompt.slice(0, 200)}…"`);

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

      const sessionId = existingSessionId && existingSessionId !== "pending" ? existingSessionId : "";
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

      // Capture session ID for logging
      if (
        message.type === "system" &&
        (message as SDKSystemMessage).subtype === "init"
      ) {
        const sid = (message as SDKSystemMessage).session_id;
        clientSessions.set(ws, sid);
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
      `Query complete (${targetAgentId}). ${messageCount} msgs. Session=${clientSessions.get(ws)?.slice(0, 12) ?? "?"}…`
    );
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    dbg("error", "session", `Query failed: ${errMsg}`);
    sendDebug(ws, "error", "session", `Query FAILED: ${errMsg}`);
    // Clear the broken session so the next message starts fresh instead of
    // repeatedly trying to resume a session that the binary can't recover.
    clientSessions.delete(ws);
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
  }
}

// ─── Session summary generation ─────────────────────────────────────────────

async function generateSessionSummary(ws: WebSocket): Promise<void> {
  const existingSessionId = clientSessions.get(ws);
  if (!existingSessionId || existingSessionId === "pending") {
    send(ws, { type: "summary_result", summary: "" });
    return;
  }

  dbg("info", "project", `Generating session summary for ${existingSessionId.slice(0, 12)}…`);
  sendDebug(ws, "info", "project", "Generating session summary…");

  try {
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

    let summaryText = "";
    for await (const message of q) {
      if (message.type === "assistant") {
        const content = (message as SDKAssistantMessage).message?.content;
        if (Array.isArray(content)) {
          for (const block of content) {
            if (block.type === "text") {
              summaryText += block.text;
            }
          }
        }
      }
    }

    dbg("info", "project", `Summary generated: ${summaryText.slice(0, 100)}…`);
    send(ws, { type: "summary_result", summary: summaryText.trim() });
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    dbg("error", "project", `Summary generation failed: ${errMsg}`);
    send(ws, { type: "summary_result", summary: "" });
  }
}

// ─── iOS OTA deploy ────────────────────────────────────────────────────────

const OTA_PORT = parseInt(process.env.OTA_PORT ?? "9721", 10);
const OTA_HTTP_PORT = parseInt(process.env.OTA_HTTP_PORT ?? "9722", 10);
const OTA_HOSTNAME = process.env.OTA_HOSTNAME; // e.g. "my-mac.tail12345.ts.net"
const TLS_CERT_PATH = process.env.TLS_CERT_PATH;
const TLS_KEY_PATH = process.env.TLS_KEY_PATH;

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

/** Get or generate TLS certificates for the OTA HTTPS server. */
async function getOtaTlsOptions(): Promise<{ cert: string; key: string }> {
  // 1. User-provided certs
  if (TLS_CERT_PATH && TLS_KEY_PATH) {
    dbg("info", "ota", `Using user-provided TLS certs: ${TLS_CERT_PATH}`);
    return {
      cert: readFileSync(TLS_CERT_PATH, "utf-8"),
      key: readFileSync(TLS_KEY_PATH, "utf-8"),
    };
  }

  // 2. Fallback: self-signed cert
  const certFile = join(otaDir, "server.crt");
  const keyFile = join(otaDir, "server.key");

  if (existsSync(certFile) && existsSync(keyFile)) {
    return {
      cert: readFileSync(certFile, "utf-8"),
      key: readFileSync(keyFile, "utf-8"),
    };
  }

  dbg("info", "ota", "Generating self-signed TLS certificate…");
  const host = getOtaHost();
  const altNames: Array<{ type: 2; value: string } | { type: 7; ip: string }> = [
    { type: 2 as const, value: host },
  ];
  if (host.match(/^\d/)) {
    altNames.push({ type: 7 as const, ip: host });
  }

  const notAfterDate = new Date();
  notAfterDate.setFullYear(notAfterDate.getFullYear() + 1);

  const pems = await selfsigned.generate(
    [{ name: "commonName", value: host }],
    {
      notAfterDate,
      keySize: 2048,
      extensions: [
        { name: "subjectAltName", altNames },
      ],
    },
  );

  writeFileSync(certFile, pems.cert);
  writeFileSync(keyFile, pems.private);
  dbg("info", "ota", `Self-signed cert saved to ${otaDir}`);

  return { cert: pems.cert, key: pems.private };
}

/** Public Cloudflare Tunnel URL (set once at startup, null if unavailable). */
let cloudflaredUrl: string | null = null;

/** Shared request handler for both HTTPS and HTTP OTA servers. */
function makeOtaHandler() {
  return (req: IncomingMessage, res: ServerResponse) => {
    const url = req.url ?? "/";
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
    };

    res.writeHead(200, {
      "Content-Type": contentType[ext] ?? "application/octet-stream",
    });
    res.end(readFileSync(filePath));
  };
}

/** Start plain HTTP server for cloudflared to tunnel through. */
function startOtaHttpServer(): void {
  const server = createHttpServer(makeOtaHandler());
  server.listen(OTA_HTTP_PORT, "127.0.0.1", () => {
    dbg("info", "ota", `OTA HTTP server on http://localhost:${OTA_HTTP_PORT} (cloudflared target)`);
  });
}

/** Start cloudflared quick tunnel. Returns the public HTTPS URL, or null. */
function startCloudflaredTunnel(): Promise<string | null> {
  return new Promise((resolve) => {
    let resolved = false;

    const done = (url: string | null) => {
      if (!resolved) { resolved = true; resolve(url); }
    };

    let proc: ReturnType<typeof spawn>;
    try {
      proc = spawn("cloudflared", ["tunnel", "--url", `http://localhost:${OTA_HTTP_PORT}`], {
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch {
      dbg("warn", "ota", "cloudflared not found");
      return resolve(null);
    }

    const onData = (chunk: Buffer) => {
      const text = chunk.toString();
      const match = text.match(/https:\/\/(?!api\.)[a-z0-9-]+\.trycloudflare\.com/);
      if (match) {
        dbg("info", "ota", `Cloudflare tunnel ready: ${match[0]}`);
        done(match[0]);
      }
    };

    proc.stdout?.on("data", onData);
    proc.stderr?.on("data", onData);
    proc.on("error", () => { dbg("warn", "ota", "cloudflared error"); done(null); });
    proc.on("close", () => done(null));

    setTimeout(() => {
      dbg("warn", "ota", "cloudflared tunnel timeout (15s)");
      done(null);
    }, 15_000);
  });
}

/** Start the HTTPS server that serves IPA + manifest for OTA install. */
async function startOtaServer(): Promise<void> {
  const tls = await getOtaTlsOptions();
  const server = createHttpsServer(tls, makeOtaHandler());
  server.listen(OTA_PORT, () => {
    dbg("info", "ota", `OTA HTTPS server on https://${getOtaHost()}:${OTA_PORT}`);
  });
}

// Start OTA servers + try cloudflared tunnel
(async () => {
  await startOtaServer();       // HTTPS fallback
  startOtaHttpServer();         // HTTP target for cloudflared
  cloudflaredUrl = await startCloudflaredTunnel();
  if (cloudflaredUrl) {
    dbg("info", "ota", `OTA mode: Cloudflare tunnel → ${cloudflaredUrl}`);
  } else {
    dbg("info", "ota", "OTA mode: HTTPS fallback (cloudflared unavailable)");
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
  const baseUrl = cloudflaredUrl ?? `https://${getOtaHost()}:${OTA_PORT}`;
  const ipaUrl = `${baseUrl}/${ipaFileName}`;
  const bundleId = readBundleId();

  const manifest = generateManifest(ipaUrl, bundleId, "PixelCode");
  writeFileSync(join(otaDir, "manifest.plist"), manifest);

  const manifestUrl = `${baseUrl}/manifest.plist`;
  const installUrl = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestUrl)}`;

  if (cloudflaredUrl) {
    sendDeployLog(ws, `OTA через Cloudflare tunnel (довірений HTTPS)`);
  } else {
    const certPath = join(otaDir, "server.crt");
    sendDeployLog(ws, `OTA через локальний HTTPS (${getOtaHost()}:${OTA_PORT})`);
    sendDeployLog(ws, `⚠️  Самопідписаний сертифікат — потрібно встановити на iPhone`);
    sendDeployLog(ws, `Файл: ${certPath}`);
    sendDeployLog(ws, `Команда: open ${otaDir}`);
  }

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

// ─── WebSocket server ───────────────────────────────────────────────────────

const wss = new WebSocketServer({ port: PORT });

// ─── mDNS advertisement ──────────────────────────────────────────────────────
// Advertise this server on the local network so PixelCode clients can
// discover it automatically without manual IP entry.
const bonjour = new Bonjour();
const mdnsService = bonjour.publish({
  name: `PixelCode @ ${hostname()}`,
  type: "pixelcode",
  protocol: "tcp",
  port: PORT,
});
mdnsService.on("up", () => {
  dbg("info", "mDNS", `Advertised _pixelcode._tcp on port ${PORT} as "${mdnsService.name}"`);
});

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

/** Send the full chat history snapshot to a single client (e.g. on connect). */
function sendChatHistory(ws: WebSocket): void {
  if (!chatHistory.isEmpty) send(ws, chatHistory.snapshot());
}

console.log(`🏗️  PixelCode server listening on ws://localhost:${PORT}`);
console.log(`   Working directory: ${PROJECT_CWD}`);
console.log(`   Agents: ${agentInfoList.map((a) => a.name).join(", ")}`);
console.log(`   Trait memory: ${getAllTraits(traitStore).length} lessons loaded`);

wss.on("connection", (ws) => {
  dbg("info", "ws", "Client connected");

  // Send initial agent list immediately
  send(ws, {
    type: "init",
    sessionId: "pending",
    agents: agentInfoList,
    workingDirectory: PROJECT_CWD,
  });
  sendDebug(ws, "info", "ws", "Connected to PixelCode server");
  sendBoardState(ws);
  sendTraits(ws);
  // Send existing chat history so new clients are in sync
  sendChatHistory(ws);
  // Send stored game state for cross-device sync
  if (latestFullGameState) {
    send(ws, { type: "game_state_sync", fullState: latestFullGameState } as any);
    dbg("info", "game", "Sent stored game state to new client");
  }

  ws.on("message", async (data) => {
    try {
      const msg = JSON.parse(data.toString()) as ClientMessage;
      dbg("debug", "ws", `← ${msg.type}${msg.type === "send_message" ? `: "${(msg as {content: string}).content.slice(0, 60)}"` : ""}`);

      switch (msg.type) {
        case "send_message": {
          const targetAgent = msg.agentId || "manager";
          const images = msg.images;
          sendDebug(ws, "info", "ws", `User → ${targetAgent}: "${msg.content.slice(0, 60)}…"${images?.length ? ` [+${images.length} image(s)]` : ""}`);
          // Store user message and broadcast snapshot to all other clients.
          // (Sender already added the message optimistically in the UI.)
          chatHistory.add({ role: "user", text: msg.content, agentId: targetAgent, timestamp: new Date().toISOString(), ...(images?.length ? { images } : {}) });
          chatHistory.save(historyFilePath(PROJECT_CWD));
          broadcastExcept(ws, chatHistory.snapshot());
          await runQuery(ws, msg.content, targetAgent, images);
          break;
        }

        case "get_status":
          for (const agent of agentInfoList) {
            send(ws, {
              type: "agent_status",
              agentId: agent.id,
              status: "idle",
              tools: [],
            });
          }
          break;

        case "new_chat": {
          const oldSession = clientSessions.get(ws);
          dbg("info", "ws", `New chat requested. Old session: ${oldSession ?? "none"}`);
          sendDebug(ws, "warn", "session", `New chat. Dropped session=${oldSession?.slice(0, 12) ?? "none"}`);
          clientSessions.delete(ws);
          chatHistory.clear();
          chatHistory.save(historyFilePath(PROJECT_CWD));
          send(ws, {
            type: "init",
            sessionId: "pending",
            agents: agentInfoList,
            workingDirectory: PROJECT_CWD,
          });
          break;
        }

        case "resume_session": {
          const requestedId = msg.sessionId as string;
          dbg("info", "ws", `Resume session requested: ${requestedId}`);
          clientSessions.set(ws, requestedId);
          sendDebug(ws, "info", "session", `Resumed session: ${requestedId.slice(0, 12)}…`);
          send(ws, {
            type: "init",
            sessionId: requestedId,
            agents: agentInfoList,
            workingDirectory: PROJECT_CWD,
          });
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

            clientSessions.delete(ws);
            dbg("info", "ws", `Cleared ${cleared} session entries`);
            sendDebug(ws, "info", "session", `Cleared ${cleared} session entries from disk`);
            send(ws, {
              type: "init",
              sessionId: "pending",
              agents: agentInfoList,
              workingDirectory: PROJECT_CWD,
            });
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
          // Clear all per-client state
          clientSessions.delete(ws);
          clientProjectContext.delete(ws);
          clientGameState.delete(ws);
          getCommLog(ws).length = 0;
          getMetrics(ws).clear();
          getActiveTasks(ws).clear();
          getAgentMap(ws).clear();
          getEmittedTools(ws).clear();
          // Send fresh init
          send(ws, {
            type: "init",
            sessionId: "pending",
            agents: agentInfoList,
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
          const gs: GameStateData = {
            hiredAgents: msg.hiredAgents,
            agentHardware: msg.agentHardware,
            agentSkills: msg.agentSkills,
          };
          clientGameState.set(ws, gs);
          dbg("info", "game", `Game state updated: ${gs.hiredAgents.length} hired, hardware=${JSON.stringify(gs.agentHardware)}`);
          sendDebug(ws, "info", "game", `Team: ${gs.hiredAgents.join(", ")} | HW: ${Object.entries(gs.agentHardware).map(([k,v]) => `${k}=${v}`).join(", ")}`);

          // Cross-device sync: broadcast full game state to other clients
          if (msg.fullState) {
            latestFullGameState = msg.fullState;
            broadcastExcept(ws, { type: "game_state_sync", fullState: msg.fullState } as any);
            dbg("info", "game", `Game state synced to ${wss.clients.size - 1} other client(s)`);
          }
          break;
        }

        case "generate_summary": {
          await generateSessionSummary(ws);
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
    const session = clientSessions.get(ws);
    dbg("info", "ws", `Client disconnected. Session was: ${session ?? "none"}`);
  });
});
