/**
 * PixelCode WebSocket Server
 *
 * Bridges Flutter UI ↔ Claude Agent SDK.
 * Runs a Manager session that delegates to team agents.
 */

import { WebSocketServer, WebSocket } from "ws";
import { rmSync, readdirSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import {
  query,
  type SDKMessage,
  type SDKAssistantMessage,
  type SDKPartialAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage,
  type SDKToolProgressMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { teamAgents, agentInfoList, buildOfficePrompt, buildDynamicAgents, hardwareToModel, type GameStateData } from "./agents.js";
import type { ClientMessage, ServerMessage, TaskCardData, TaskColumnKey, StickyColorKey, TaskPriorityKey } from "./protocol.js";
import {
  loadTraits, saveTraits, recordLesson, removeLesson,
  formatTraitsForPrompt, getAllTraits,
  type TraitStore, type LessonType, type LessonCategory,
} from "./trait_memory.js";

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
        send(ws, {
          type: "assistant_message_done",
          messageId: asst.uuid,
          text,
        });
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

// ─── Per-client shared session ───────────────────────────────────────────────

/** One shared session per WebSocket client. All agents share conversation context. */
const clientSessions = new WeakMap<WebSocket, string>();

/** Per-client project memory text, injected into system prompts. */
const clientProjectContext = new WeakMap<WebSocket, string>();

/** Per-client game economy state (hired agents, hardware, skills). */
const clientGameState = new WeakMap<WebSocket, GameStateData>();

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

async function runQuery(ws: WebSocket, userMessage: string, targetAgentId: string): Promise<void> {
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
      permissionMode: "acceptEdits" as const,
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

    const q = query({
      prompt: prefixedPrompt,
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

// ─── WebSocket server ───────────────────────────────────────────────────────

const wss = new WebSocketServer({ port: PORT });

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

  ws.on("message", async (data) => {
    try {
      const msg = JSON.parse(data.toString()) as ClientMessage;
      dbg("debug", "ws", `← ${msg.type}${msg.type === "send_message" ? `: "${(msg as {content: string}).content.slice(0, 60)}"` : ""}`);

      switch (msg.type) {
        case "send_message": {
          const targetAgent = msg.agentId || "manager";
          sendDebug(ws, "info", "ws", `User → ${targetAgent}: "${msg.content.slice(0, 60)}…"`);
          await runQuery(ws, msg.content, targetAgent);
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
          // Reload trait memory for the new project
          traitStore = loadTraits(PROJECT_CWD);
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
