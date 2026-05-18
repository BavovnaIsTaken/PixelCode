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
import { BoardWriter, isValidBoardColumn, loadBoard, planSeedBatch } from "./board_persistence.js";
import { MAX_AGENT_LOAD, pickAssignee, shouldAutoDispatch } from "./auto_dispatcher.js";
import { advanceOnDispatchSuccess, findOrphanActiveCards } from "./board_transitions.js";
import { classifyPersistedGameState, firedInstanceIds, validateGameState } from "./roster_validation.js";
import { LocalGeminiRunner } from "./local_gemini_runner.js";
import { DeepSeekBackend } from "./deepseek_backend.js";
import { KimiBackend } from "./kimi_backend.js";
import {
  runNonStreamingBackend,
  type NonStreamingProviderConfig,
} from "./non_streaming_provider.js";

const localGemini = new LocalGeminiRunner();
import { runDungeon, getChallenge } from "./dungeon.js";
import { FacilitatorRunner } from "./facilitator/runner.js";
import { GeneratorRegistry } from "./facilitator/output_generator.js";
import {
  ClaudeQuestLineGenerator,
  ClaudeMissionBriefingGenerator,
  ClaudeMilestoneTreeGenerator,
  callClaude,
} from "./facilitator/llm_generators.js";
import {
  parseStartRequest as parseFacilitatorStart,
  handleStartRequest as handleFacilitatorStart,
} from "./facilitator/ws_handler.js";
import { generateTeamReactions } from "./facilitator/team_reactions.js";
import { TechLeadDigest, digestFile } from "./tech_lead_digest.js";
import { UsageLogger, usageLogFile, newRunId } from "./usage_log.js";
import { analyze as analyzeUsageBaselines } from "./usage_baseline.js";
import { IncidentLogger, incidentLogFile, newIncidentId } from "./incident_log.js";
import { detectPrematureComplete, stripPrematureCompleteClaim } from "./premature_complete_detector.js";
import { classifySubAgentFailure } from "./subagent_failure_classifier.js";
import { AgentRunStore, agentRunsFile } from "./agent_run.js";
import {
  applyReactionsToChat,
  deriveProjectMemoryFromBrief,
  recordTaskCompletion,
} from "./conversational_loop.js";
import type { ClientMessage, ServerMessage, TaskCardData, TaskAttachmentData, TaskColumnKey, StickyColorKey, TaskPriorityKey, ConnectedClientInfo } from "./protocol.js";
import {
  loadTraits, saveTraits, recordLesson, removeLesson,
  formatTraitsForPrompt, getAllTraits, getLessonsForAgent,
  isConsentEnabled, setConsent, getAllConsent,
  loadCandidates, recordLessonCandidate, getAllCandidates,
  type TraitStore, type CandidateStore, type LessonType, type LessonCategory,
} from "./trait_memory.js";
import {
  buildReflectionPrompt,
  appendReflectionTelemetry,
  detectForbiddenAvailabilityClaims,
  buildReflectionKpiMessage,
  type ActivityEntry,
} from "./reflection_prompt.js";
import { isValidTag } from "./reflection_taxonomy.js";
import { TaskQueue, type QueuedTask } from "./task_queue.js";
import { AgentRunner, type SubAgentResult } from "./agent_runner.js";
import { DISPATCH_TOOL_DESCRIPTION, buildDispatchReturnString, extractDispatchIdFromToolResult } from "./dispatch_prompts.js";
import { ChatQueryRegistry } from "./chat_query_registry.js";
import { CircuitBreaker } from "./circuit_breaker.js";
import { HeartbeatMonitor } from "./heartbeat.js";
import { ChatHistory } from "./chat_history.js";
import { AgentContextPreparer } from "./agent_context.js";
import { injectLearnedContext, applyLlmLessons, type LlmLesson } from "./personalization.js";
import { profileCache } from "./profile_cache.js";
import { lessonExtractor } from "./lesson_extractor.js";
import { runAllChecks, runSingleCheck, runFix, type HealthContext } from "./health.js";
import type { HealthItemId } from "./protocol.js";
import { loadConfig, type ServerConfig } from "./config.js";
import { handleAdminRequest, recordLog, type AdminContext } from "./admin.js";
import { runBuildDoctor, publishBuildFix } from "./build_doctor.js";

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

export function dbg(level: DebugLevel, category: string, message: string, data?: unknown): void {
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

function handleSDKMessage(
  ws: WebSocket,
  message: SDKMessage,
  targetAgentId: string = "manager",
  /**
   * C.2.6 — chat runId, threaded through so the post-query reflection
   * gate scopes "session" to one chat query (independent units of
   * observation) rather than the SDK persistent session id.
   * Optional for backward compatibility with non-chat call sites.
   */
  reflectionRunId?: string,
): void {
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
        const timestamp = new Date().toISOString();
        chatHistory.add({ role: "assistant", text, agentId: targetAgentId, timestamp, id: asst.uuid });
        chatHistory.save(historyFilePath(PROJECT_CWD));
        broadcastAll({ type: "assistant_message_done", messageId: asst.uuid, text, agentId: targetAgentId, timestamp });
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
        const timestamp = new Date().toISOString();
        const fallbackId = `fallback-${Date.now()}`;
        chatHistory.add({ role: "assistant", text: resultText, agentId: targetAgentId, timestamp, id: fallbackId });
        chatHistory.save(historyFilePath(PROJECT_CWD));
        broadcastAll({ type: "assistant_message_done", messageId: fallbackId, text: resultText, agentId: targetAgentId, timestamp });
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
      reflectOnQuery(ws, targetAgentId, reflectionRunId).catch((err) => {
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

/** Returns the path where shared team memory is persisted for a given project dir. */
function teamMemoryFile(projectCwd: string): string {
  const cwdKey = projectCwd.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".claude", "projects", cwdKey, "team_memory.txt");
}

function loadTeamMemory(projectCwd: string): string | null {
  try {
    const f = teamMemoryFile(projectCwd);
    return existsSync(f) ? readFileSync(f, "utf-8") : null;
  } catch {
    return null;
  }
}

function saveTeamMemory(projectCwd: string, memories: string): void {
  try {
    const f = teamMemoryFile(projectCwd);
    mkdirSync(dirname(f), { recursive: true });
    writeFileSync(f, memories, "utf-8");
  } catch (e) {
    dbg("warn", "project", `Failed to save team memory: ${e}`);
  }
}

const chatHistory = new ChatHistory();
chatHistory.load(historyFilePath(PROJECT_CWD));

// Tech-lead digest — append-only log of board completions. Replays from
// disk on boot so the tech-lead agent has continuous awareness across
// server restarts. Best-effort: any IO failure is swallowed by the module.
const techLeadDigest = new TechLeadDigest(digestFile(PROJECT_CWD));
techLeadDigest.loadFromDisk();

// C.2 — Per-role usage log. Records {runId, role, taskType, agentId,
// tokens, cost, duration, numTurns, numToolCalls, startedAt, completedAt}
// per SDK query. Append-only JSONL, no in-memory aggregation; a future
// analyzer reads the file to compute empirical baselines (median / p95
// per `{role, taskType}`) for outlier detection in the facilitator UI.
const usageLogger = new UsageLogger(usageLogFile(PROJECT_CWD));

// C.2.5 — Dispatch-lifecycle anomaly log. Records premature-complete
// claims (manager said "Готово" before subagent_result arrived) and
// no-op runs (subagent finished with zero tool calls). Pure-rate signal
// for the daily-control surface — NOT used to block any runtime path.
const incidentLogger = new IncidentLogger(incidentLogFile(PROJECT_CWD));

// C.2 — Persistent AgentRun entity. Records lifecycle of every SDK query
// (status: running → completed / failed / interrupted / cancelled) so the
// UI can answer "what happened while I was offline" and "did my task
// actually run" after a server respawn. Replayed on boot; any leftover
// `running` rows from a prior process are promoted to `interrupted` and
// the affected agents are surfaced through the standard active-agents
// broadcast (see boot sweep below).
const agentRunStore = new AgentRunStore(agentRunsFile(PROJECT_CWD));
agentRunStore.load();
{
  const orphaned = agentRunStore.markRunningAsInterrupted("server-respawn");
  if (orphaned.length > 0) {
    dbg("warn", "session",
      `Boot sweep: ${orphaned.length} run(s) orphaned by previous process — marked interrupted`);
    // Surface the partial text of each orphan into chatHistory so the
    // chat flow itself shows what the agent had typed before the crash,
    // not just the banner. Idempotent on re-boot via chatHistory.add's
    // id dedupe (key = runId).
    for (const r of orphaned) {
      if (r.partialOutput && r.partialOutput.length > 0) {
        chatHistory.add({
          role: "assistant",
          text: r.partialOutput,
          agentId: r.agentId,
          timestamp: r.completedAt ?? new Date().toISOString(),
          id: r.runId,
        });
      }
    }
    // Persist once after the loop — avoids N writes for N orphans.
    if (orphaned.length > 0) chatHistory.save(historyFilePath(PROJECT_CWD));
  }
}

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

/** Per-client DeepSeek API key, forwarded from client SharedPreferences. */
const clientDeepSeekKey = new WeakMap<WebSocket, string>();
/** Per-client Kimi API key, forwarded from client SharedPreferences. */
const clientKimiKey = new WeakMap<WebSocket, string>();
/**
 * Most-recent provider key seen on any ws. The server is single-tenant
 * (no auth boundary), so a key the user typed on Mac is the same user's
 * key everywhere. Late-joining devices inherit from these on connect, so
 * iPhone that never typed the key can still dispatch to a DeepSeek agent
 * that Mac hired. Local-typed keys on a peer always win — see
 * `set_game_state` propagation. Cleared on `set_project` (different
 * project may use a different account).
 */
let lastSeenDeepSeekKey: string | undefined;
let lastSeenKimiKey: string | undefined;

/**
 * Registry of non-streaming providers keyed by `AgentProviderType` enum index.
 * Adding a 6th non-streaming provider = one entry here + an enum value on the
 * client side. The streaming Claude SDK path and Local Gemini path stay out of
 * this registry — they have different lifecycles and tool-use semantics.
 */
const nonStreamingProviders = new Map<number, NonStreamingProviderConfig>([
  [
    3, // deepseek
    {
      getKey: (ws) => clientDeepSeekKey.get(ws),
      createBackend: (apiKey) => new DeepSeekBackend(apiKey),
      sessionId: "deepseek",
      missingKeyError: "DeepSeek API key not set — link account in Settings",
    },
  ],
  [
    4, // kimi
    {
      getKey: (ws) => clientKimiKey.get(ws),
      createBackend: (apiKey) => new KimiBackend(apiKey),
      sessionId: "kimi",
      missingKeyError: "Kimi API key not set — link account in Settings",
    },
  ],
]);

/**
 * Singleton runner with LLM-backed generators wired in at boot.
 * Tests continue to use GeneratorRegistry with stubs via RunnerDeps injection.
 */
const _facilitatorGenerators = new GeneratorRegistry();
_facilitatorGenerators.setGenerator("quest_line", new ClaudeQuestLineGenerator(PROJECT_CWD));
_facilitatorGenerators.setGenerator("mission_briefing", new ClaudeMissionBriefingGenerator(PROJECT_CWD));
_facilitatorGenerators.setGenerator("milestone_tree", new ClaudeMilestoneTreeGenerator(PROJECT_CWD));
const facilitatorRunner = new FacilitatorRunner({ generators: _facilitatorGenerators });

/** Latest full game state for cross-device sync (last-write-wins by timestamp). */
let latestFullGameState: string | null = null;
let latestStateUpdatedAt: number = 0;

/** Latest facilitator output for cross-device sync. */
let latestFacilitatorOutput: { styleId: string; finalScore: unknown; outputFormat: string; outputJson: string } | null = null;

/** Path where the authoritative game state is persisted across server restarts. */
function gameStateFile(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key, "game_state.json");
}

function loadPersistedGameState(): void {
  const file = gameStateFile(PROJECT_CWD);
  if (!existsSync(file)) return;
  let rawText: string;
  try {
    rawText = readFileSync(file, "utf-8");
  } catch (e) {
    dbg("warn", "game", `Failed to read persisted game state: ${e}`);
    return;
  }

  const result = classifyPersistedGameState(rawText);
  switch (result.kind) {
    case "loaded":
      latestFullGameState = result.envelope.fullState;
      latestStateUpdatedAt = result.envelope.updatedAt;
      dbg("info", "game", `Loaded persisted game state (updatedAt=${result.envelope.updatedAt})`);
      return;
    case "shape_mismatch":
      dbg("warn", "game", `Persisted game state has wrong shape; ignoring (${result.reason})`);
      return;
    case "quarantine_outer":
    case "quarantine_inner": {
      const target = `${file}.broken-${Date.now()}`;
      try { writeFileSync(target, rawText); } catch { /* best effort */ }
      try { rmSync(file); } catch { /* best effort */ }
      dbg(
        "warn",
        "game",
        `Game state quarantined to ${target} (${result.kind === "quarantine_outer" ? "outer" : "inner"} parse: ${result.reason})`,
      );
      return;
    }
    case "fresh":
      return;
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

function facilitatorOutputFile(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key, "facilitator_output.json");
}

function loadPersistedFacilitatorOutput(): void {
  const file = facilitatorOutputFile(PROJECT_CWD);
  if (!existsSync(file)) return;
  try {
    const raw = JSON.parse(readFileSync(file, "utf-8"));
    if (raw && typeof raw.outputJson === "string") {
      latestFacilitatorOutput = raw;
      dbg("info", "facilitator", "Loaded persisted facilitator output");
    }
  } catch (e) {
    dbg("warn", "facilitator", `Failed to load persisted facilitator output: ${e}`);
  }
}

function persistFacilitatorOutput(): void {
  if (!latestFacilitatorOutput) return;
  const file = facilitatorOutputFile(PROJECT_CWD);
  const dir = file.substring(0, file.lastIndexOf("/"));
  try {
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(file, JSON.stringify(latestFacilitatorOutput));
  } catch (e) {
    dbg("warn", "facilitator", `Failed to persist facilitator output: ${e}`);
  }
}

loadPersistedFacilitatorOutput();

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

/** Global chat query registry — tracks main manager queries so the UI
 *  can list/cancel them. Disconnect cleanup goes through cancelForWs. */
const chatQueryRegistry = new ChatQueryRegistry();

// ─── Heartbeat ──────────────────────────────────────────────────────────────
//
// Server-driven WS ping cycle. TCP keep-alive isn't enough on mobile networks:
// a Wi-Fi↔LTE handoff or NAT timeout can leave a half-open socket where neither
// side notices the peer is gone. The monitor pings every HEARTBEAT_INTERVAL_MS,
// and any client that misses MAX_MISSED_PINGS in a row gets terminated — fast
// enough that "Active agents" UI doesn't lie about a long-dead peer, slow
// enough to survive the occasional dropped packet.
const HEARTBEAT_INTERVAL_MS = 20_000;
const heartbeatMonitor = new HeartbeatMonitor<WebSocket>({ maxMissedPings: 3 });
const heartbeatTimer = setInterval(() => {
  const { terminate, ping } = heartbeatMonitor.tick();
  for (const ws of terminate) {
    const info = connectedClients.get(ws);
    dbg("warn", "ws", `Heartbeat timeout — terminating ${info?.deviceName ?? "unknown"} (${info?.platform ?? "?"})`);
    try { ws.terminate(); } catch { /* socket already dead */ }
  }
  for (const ws of ping) {
    try { ws.ping(); } catch { /* will be picked up on next tick */ }
  }
}, HEARTBEAT_INTERVAL_MS);
heartbeatTimer.unref?.();

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

// ─── Session presence ─────────────────────────────────────────────────────────

interface ActiveSession {
  clientId: string;
  deviceName: string;
  ws: WebSocket;
}

/** The device currently holding the primary session (write authority). */
let activeSession: ActiveSession | null = null;

/** True if the given WebSocket is the current primary. */
function isPrimary(ws: WebSocket): boolean {
  return activeSession !== null && activeSession.ws === ws;
}

/** Claim the session for the given client (must already be in connectedClients). */
function claimSession(ws: WebSocket): void {
  const client = connectedClients.get(ws);
  if (!client) return;
  activeSession = { clientId: client.clientId, deviceName: client.deviceName, ws };
  dbg("info", "session", `Primary → ${client.deviceName} [${client.clientId.slice(0, 8)}]`);
}

/** Notify all connected clients of their current session mode. */
function broadcastSessionStatus(): void {
  for (const [clientWs, client] of connectedClients.entries()) {
    if (clientWs.readyState !== WebSocket.OPEN) continue;
    const mode = activeSession?.ws === clientWs ? "primary" : "viewer";
    send(clientWs, {
      type: "session_status",
      mode,
      ...(mode === "viewer" && activeSession ? { primaryDevice: activeSession.deviceName } : {}),
    } as any);
  }
}

/** Transfer the session to a new client: update active, notify all. */
function transferSession(newPrimaryWs: WebSocket): void {
  const oldPrimaryWs = activeSession?.ws ?? null;
  claimSession(newPrimaryWs);
  // Notify old primary that the session was taken
  if (oldPrimaryWs && oldPrimaryWs !== newPrimaryWs && oldPrimaryWs.readyState === WebSocket.OPEN) {
    const taker = connectedClients.get(newPrimaryWs);
    send(oldPrimaryWs, { type: "session_taken", byDevice: taker?.deviceName ?? "another device" } as any);
  }
  broadcastSessionStatus();
}

/** Called on disconnect: if primary left, auto-promote first available viewer. */
function handlePrimaryDisconnect(): void {
  activeSession = null;
  // Promote the first still-connected client
  for (const [clientWs] of connectedClients.entries()) {
    if (clientWs.readyState === WebSocket.OPEN) {
      claimSession(clientWs);
      broadcastSessionStatus();
      return;
    }
  }
}

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
let candidateStore: CandidateStore = loadCandidates(PROJECT_CWD);

function sendTraits(ws: WebSocket): void {
  send(ws, { type: "agent_traits", traits: getAllTraits(traitStore) });
}

/** Broadcast updated traits to every connected client after a write. */
function broadcastTraits(): void {
  const msg: ServerMessage = { type: "agent_traits", traits: getAllTraits(traitStore) };
  for (const c of wss.clients) {
    if (c.readyState === WebSocket.OPEN) send(c, msg);
  }
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
  if (!isConsentEnabled(traitStore, agentId)) return;

  const result = recordLesson(PROJECT_CWD, traitStore, {
    agentId, type, category, tag, lesson, source: "hook",
  });
  dbg("info", "traits", `${type === "weakness" ? "⚡" : "✦"} [${agentId}] ${tag} (freq=${result.frequency}): ${lesson}`);
  sendDebug(ws, "info", "traits", `Lesson ${type === "weakness" ? "learned" : "confirmed"}: [${agentId}] ${lesson} (×${result.frequency})`);
  broadcastTraits();
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

/**
 * Dispatch-MCP tools added at query-time for delegating roles. Kept in sync
 * with the push at allowedTools (search "allowedTools.push" in this file).
 */
const DISPATCH_TOOL_NAMES = [
  "mcp__dispatch__dispatch",
  "mcp__dispatch__team_status",
  "mcp__dispatch__cancel_task",
  "mcp__dispatch__board_create_task",
  "mcp__dispatch__board_move_task",
  "mcp__dispatch__board_update_task",
  "mcp__dispatch__board_assign_agent",
  "mcp__dispatch__board_list",
] as const;

/**
 * Deterministically reconstruct the toolset an agent had during the session,
 * mirroring the logic in the chat query path (canDelegate adds dispatch tools
 * for manager/tech-lead). Used to give reflection ground-truth instead of
 * letting Haiku invent tool-availability claims.
 */
function allowedToolsForAgent(agentId: string, gameState: GameStateData | undefined): string[] {
  const roleType = roleTypeOf(agentId, gameState);
  const def = roleTemplateFor(agentId, gameState);
  const base = def?.tools ?? ["Read", "Glob", "Grep", "Bash"];
  if (roleType === "manager" || roleType === "tech-lead") {
    return [...base, ...DISPATCH_TOOL_NAMES];
  }
  return [...base];
}

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
async function reflectOnQuery(
  ws: WebSocket,
  targetAgentId: string,
  /**
   * Stable id for the reflection "session" used by the candidate gate to
   * decide whether two same-tag observations count as independent. C.2.6:
   * pass the chat-runId (one per user query) so each query is its own
   * session. Falls back to the SDK persistent sessionId only when no
   * runId is available (legacy callers / non-chat paths) — the SDK id
   * persists across queries, which is exactly the bug C.2.6 fixes.
   */
  reflectionRunId?: string,
): Promise<void> {
  if (!isConsentEnabled(traitStore, targetAgentId)) return;

  const activities = getQueryActivities(ws);
  if (activities.length === 0) {
    appendReflectionTelemetry(PROJECT_CWD, { kind: "reflection_skipped", reason: "no_activity" });
    return;
  }

  const hasErrors = activities.some((a) => a.event === "error");

  // Per-agent rework stats — kept here because they come from a different
  // map (getMetrics) and are mutated outside the activity buffer.
  const metrics = getMetrics(ws);
  const reworkAgents: string[] = [];
  for (const [agentId, m] of metrics) {
    if (m.reworkCount > 0) reworkAgents.push(`${agentId}(rework=${m.reworkCount})`);
  }

  // Ground-truth: which tools were actually wired into each agent during the
  // session. Reflection must not invent "tool not available" claims when a
  // tool is listed here. Cheap to derive — pure function over gameState + role.
  const gameStateForReflection = clientGameState.get(ws);
  const involvedAgents = Array.from(new Set(activities.map((a) => a.agentId)));
  const allowedToolsByAgent: Record<string, string[]> = {};
  for (const agentId of involvedAgents) {
    allowedToolsByAgent[agentId] = allowedToolsForAgent(agentId, gameStateForReflection);
  }

  const reflectionPrompt = buildReflectionPrompt({
    activities: activities as ActivityEntry[],
    allowedToolsByAgent,
    reworkAgents,
    hasErrors,
  });

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

    // LLM-extracted lessons may confabulate (see docs/AGENT_PERSONALIZATION_SYSTEM.md
    // §confabulation-gate). Route them through the candidate pool: a tag must be
    // observed in ≥threshold distinct sessions (asymmetric: weakness=3, strength=2)
    // before it lands in the real TraitStore. Hook-based learners (task-rework,
    // clean-execution at lines 293/365/450) bypass this gate because their signal
    // is structural, not LLM-judged.
    //
    // C.2.6 — gate "session" = one chat-runId, NOT the SDK persistent session.
    // The SDK session id stays stable for hours via prompt-cache reuse, so
    // candidate.sessionCount could never advance within a productive working
    // session — promotion rate sat at 0% over 30 days / 15 candidates.
    // runId per chat query is the natural unit of independence; MIN_PROMOTION
    // _GAP_MS (2h burst-defense) still prevents back-to-back rapid promotions.
    //
    // Fallback order:
    //   1. reflectionRunId (passed in by chat-path callers post-C.2.6)
    //   2. SDK session (legacy: pre-C.2.6 behaviour, kept so non-chat callers
    //      that haven't been migrated still get some accumulation, however slow)
    //   3. per-client + day bucket (cold start before SDK session exists)
    const trackedClient = connectedClients.get(ws);
    const wsBucket = trackedClient?.clientId ?? "anon";
    const dayBucket = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    const reflectionSessionId =
      reflectionRunId ?? existingSessionId ?? `transient-${wsBucket}-${dayBucket}`;
    const profileBatch: LlmLesson[] = [];
    for (const l of lessons.slice(0, 3)) {
      if (!validAgents.has(l.agentId)) continue;
      if (l.type !== "strength" && l.type !== "weakness") continue;
      if (!validCategories.has(l.category)) continue;
      if (!l.tag || !l.lesson) continue;
      if (!isConsentEnabled(traitStore, l.agentId)) continue;

      // C.2.6 — closed-taxonomy hard validation. The reflection prompt
      // enumerates the canonical tag set in <canonical_tags>; Haiku-4.5
      // follows it ~92-96% of the time. The remaining 4-8% would silently
      // pollute the candidate pool with aliased tags (the failure mode that
      // sat at 0% promotion / 15 candidates for 30 days pre-fix). Reject
      // here, record as telemetry so the rejection rate is observable, and
      // skip the submission entirely.
      if (!isValidTag(l.tag, l.type as LessonType)) {
        appendReflectionTelemetry(PROJECT_CWD, {
          kind: "invalid_tag",
          agentId: l.agentId,
          tag: l.tag,
          type: l.type,
          category: l.category,
          lesson: l.lesson,
        });
        dbg("debug", "traits",
          `Rejected candidate with non-canonical tag "${l.tag}" (${l.type}) for ${l.agentId}`);
        continue;
      }

      const outcome = recordLessonCandidate(
        PROJECT_CWD,
        traitStore,
        candidateStore,
        {
          agentId: l.agentId,
          type: l.type as LessonType,
          category: l.category as LessonCategory,
          tag: l.tag,
          lesson: l.lesson,
        },
        reflectionSessionId,
      );

      // Telemetry — every submission, every status, for KPI tracking
      // (promotion_rate, bypass_rate, etc — see reflection_prompt.ts).
      appendReflectionTelemetry(PROJECT_CWD, {
        kind: "candidate_submitted",
        agentId: l.agentId,
        tag: l.tag,
        type: l.type,
        category: l.category,
        status: outcome.status,
        ...(outcome.status === "promoted" ? { via: outcome.via } : {}),
        ...(outcome.status === "too-soon" ? { gapMs: outcome.gapMs } : {}),
        ...(outcome.status === "pending" ? { sessionCount: outcome.candidate.sessionCount } : {}),
      });

      // Cheap sanity check — flag visible hard-constraint violations.
      const forbidden = detectForbiddenAvailabilityClaims(l.lesson);
      if (forbidden.length > 0) {
        appendReflectionTelemetry(PROJECT_CWD, {
          kind: "constraint_violation",
          agentId: l.agentId,
          tag: l.tag,
          phrases: forbidden,
          lesson: l.lesson,
        });
        dbg("warn", "traits", `Reflection constraint violated [${l.agentId}] ${l.tag}: ${forbidden.join(", ")}`);
      }

      if (outcome.status === "promoted") {
        dbg("info", "traits", `Lesson promoted from candidate: [${l.agentId}] ${l.tag} via=${outcome.via} (freq=${outcome.lesson.frequency})`);
        sendDebug(ws, "info", "traits", `Lesson confirmed: [${l.agentId}] ${l.lesson}`);
        broadcastTraits();
      } else if (outcome.status === "pending") {
        const threshold = l.type === "weakness" ? 3 : 2;
        dbg("debug", "traits", `Candidate held: [${l.agentId}] ${l.tag} (sessions=${outcome.candidate.sessionCount}/${threshold})`);
      } else if (outcome.status === "too-soon") {
        dbg("debug", "traits", `Candidate burst-deferred: [${l.agentId}] ${l.tag} (gap=${Math.round(outcome.gapMs/1000)}s)`);
      }

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
    DISPATCH_TOOL_DESCRIPTION,
    {
      agent: z.string().describe("Exact instanceId to dispatch to (e.g. 'coder#1', 'reviewer#2'). Use team_status to see who is available."),
      task: z.string().describe("Detailed task description for the agent. Be specific about what to do and expected output."),
      priority: z.enum(["high", "normal", "low"]).optional().describe("Task priority. Default: normal"),
      boardTaskId: z.string().optional().describe("If this dispatch fulfills a board card (taskType !== 'facilitator' or you got the task via a [Board task] queue item), pass that card's id (e.g. 'task_42_1700000000') so the server can advance the column on finish. Omit for ad-hoc dispatches."),
    },
    async (args) => {
      const agentId = args.agent;
      const taskDesc = args.task;
      const priority = (args.priority ?? "normal") as "high" | "normal" | "low";
      const boardTaskId = args.boardTaskId;

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
      const bypassPermissions = clientBypassPermissions.get(ws) ?? true;

      const dispatchId = agentRunner.dispatch({
        agentId,
        task: taskDesc,
        ws,
        projectCwd: PROJECT_CWD,
        gameState,
        projectMemory,
        traitStore,
        bypassPermissions,
        techLeadDigest: techLeadDigest.renderForPrompt(15),
        usageLogger,
        incidentLogger,
        agentRunStore,
        role: roleTypeOf(agentId, gameState),
        boardTaskId,
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
      broadcastActiveAgents(ws);

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
        content: [{ type: "text" as const, text: buildDispatchReturnString(agentId, dispatchId) }],
      };
    },
  );

  const teamStatusTool = tool(
    "team_status",
    `Check which agents are currently busy, idle, or at capacity. Use this before dispatching to balance workload. Each agent has a board card limit of ${MAX_AGENT_LOAD} concurrent in-progress tasks — do NOT dispatch to agents marked AT CAPACITY.`,
    {},
    async () => {
      const running = agentRunner.getStatus();
      const queuedCount = taskQueue.size;

      // Count in-progress board cards per agent.
      const cardLoad = new Map<string, number>();
      for (const task of boardTasks.values()) {
        if (task.column === "in_progress" || task.column === "testing") {
          for (const aid of task.assignedAgents) {
            cardLoad.set(aid, (cardLoad.get(aid) ?? 0) + 1);
          }
        }
      }

      const lines: string[] = [];

      for (const agent of agentInfoForClient(ws)) {
        if (agent.roleType === "manager") continue;
        const runEntry = running.find(r => r.agentId === agent.id);
        const load = cardLoad.get(agent.id) ?? 0;
        const atCap = load >= MAX_AGENT_LOAD;
        const taskStatus = runEntry
          ? `BUSY — "${runEntry.task.slice(0, 60)}" (${Math.round(runEntry.elapsedMs / 1000)}s)`
          : "idle";
        const loadStatus = atCap
          ? `board: ${load}/${MAX_AGENT_LOAD} — ⛔ AT CAPACITY`
          : `board: ${load}/${MAX_AGENT_LOAD}`;
        lines.push(`- **${agent.id}** (${agent.name}, ${agent.role}): ${taskStatus} | ${loadStatus}`);
      }

      if (queuedCount > 0) {
        lines.push(`\n${queuedCount} task(s) in queue.`);
      }

      lines.push(`\nRule: never assign to an agent with ${MAX_AGENT_LOAD}/${MAX_AGENT_LOAD} board cards.`);

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
      // C.2.6 — snapshot agentId BEFORE cancel; agent_runner's explicit-cancel
      // branch returns early without calling onError, so handleSubAgentError
      // (which would emit agent_status: idle) is bypassed. Mirror the WS
      // cancel_dispatch_agent handler so manager-LLM-initiated cancels leave
      // the chat-header indicator and active-agents UI in a consistent state.
      const targetAgentId = agentRunner
        .getRunning()
        .find((r) => r.dispatchId === args.dispatch_id)?.agentId;
      const ok = agentRunner.cancel(args.dispatch_id);
      if (ok) {
        broadcastActiveAgents(ws);
        if (targetAgentId) {
          send(ws, {
            type: "agent_status",
            agentId: targetAgentId,
            status: "idle",
            tools: [],
          });
        }
      }
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
      let warning = "";
      if (args.assign) {
        if (!task.assignedAgents.includes(args.agentId)) {
          const currentLoad = [...boardTasks.values()].filter(
            t => (t.column === "in_progress" || t.column === "testing") && t.assignedAgents.includes(args.agentId)
          ).length;
          if (currentLoad >= MAX_AGENT_LOAD) {
            warning = ` ⚠️ WARNING: ${args.agentId} already has ${currentLoad}/${MAX_AGENT_LOAD} in-progress cards — they are AT CAPACITY. Assign to a free agent instead.`;
          }
          task.assignedAgents.push(args.agentId);
        }
      } else {
        task.assignedAgents = task.assignedAgents.filter((a) => a !== args.agentId);
      }
      task.updatedAt = new Date().toISOString();
      broadcastBoardState();
      return { content: [{ type: "text" as const, text: `${args.assign ? "Assigned" : "Unassigned"} ${args.agentId} on ${args.taskId}.${warning}` }] };
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

// ─── Sub-agent mirror helpers (pure, exported for tests) ─────────────────────

/** Payload sent to the manager's chat to surface a sub-agent tool-use in a thread. */
export function subAgentMirrorToolUse(
  managerAgentId: string,
  toolUseId: string,
  toolName: string,
  status: string,
  threadId: string,
) {
  return {
    type: "subagent_thread_event" as const,
    agentId: managerAgentId,
    toolUseId: toolUseId + "_m",
    toolName,
    status,
    threadId,
  };
}

/** Payload sent to the manager's chat to surface a sub-agent final message in a thread. */
export function subAgentMirrorMessage(
  managerAgentId: string,
  messageId: string,
  text: string,
  threadId: string,
) {
  return { type: "assistant_message_done" as const, messageId: messageId + "_m", text, agentId: managerAgentId, threadId };
}

/** Payload sent to the manager's chat to surface a sub-agent streaming delta in a thread. */
export function subAgentMirrorDelta(
  managerAgentId: string,
  text: string,
  threadId: string,
) {
  return { type: "assistant_text" as const, text, isPartial: true as const, agentId: managerAgentId, threadId };
}

// ─── Sub-agent message handling ─────────────────────────────────────────────

/** Handle real-time messages from independently running sub-agents. */
function handleSubAgentMessage(ws: WebSocket, message: SDKMessage, agentId: string, dispatchId: string): void {
  // Do NOT gate on ws.readyState: a sub-agent dispatch survives client
  // disconnect (C.2.1), but its final assistant message must still land in
  // chatHistory and reach any other connected device via broadcastAll().
  // Direct send(ws, ...) calls below are already individually no-ops when
  // the owning ws is closed (see send() at the top of this file).
  const managerAgentId = resolveRoleInstance(ws, "manager");

  try {
    switch (message.type) {
      case "assistant": {
        const asst = message as SDKAssistantMessage;
        // Forward tool uses for status updates and thread status entries
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
              threadId: dispatchId,
            });
            // Mirror to manager's chat so the captain sees sub-agent activity as a thread
            broadcastAll(subAgentMirrorToolUse(managerAgentId, block.id, block.name, status, dispatchId));
            emitActivity(ws, agentId, "tool_use", status);
          }
        }

        // Forward text as chat messages from this agent
        const text = extractText(asst);
        if (text && !asst.parent_tool_use_id) {
          const timestamp = new Date().toISOString();
          chatHistory.add({ role: "assistant", text, agentId, timestamp, id: asst.uuid });
          chatHistory.save(historyFilePath(PROJECT_CWD));
          broadcastAll({ type: "assistant_message_done", messageId: asst.uuid, text, agentId, threadId: dispatchId, timestamp });
          // Mirror result to manager's thread
          broadcastAll(subAgentMirrorMessage(managerAgentId, asst.uuid, text, dispatchId));
        }
        break;
      }

      case "stream_event": {
        const partial = message as SDKPartialAssistantMessage;
        if (partial.parent_tool_use_id) break;
        const event = partial.event;
        if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
          broadcastAll({ type: "assistant_text", text: event.delta.text, isPartial: true, agentId, threadId: dispatchId });
          // Mirror streaming to manager's thread
          broadcastAll(subAgentMirrorDelta(managerAgentId, event.delta.text, dispatchId));
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

  // Refresh "Active agents" UI — dispatch has left the runner.
  broadcastActiveAgents(ws);

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

  // C.2 — server as single writer for board transitions. If this dispatch
  // served a specific board card, advance its column / roll outcome here so
  // the source of truth lives on the server, not on a client-side timer.
  // Idempotent: the helper no-ops on `backlog` / `done`, so a manager-LLM
  // that already moved the card via its `board_move_task` MCP tool won't
  // double-advance. Breaker / timeout / cancel paths reach handleSubAgentError
  // instead and intentionally do NOT trigger a transition.
  if (result.boardTaskId) {
    advanceBoardTaskAfterDispatch(ws, result.boardTaskId, result.agentId);
  }

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

/**
 * Server-as-single-writer board transition triggered when a sub-agent
 * dispatch finishes successfully (C.2). Mutates the in-memory board map
 * directly, persists, broadcasts, and runs the `recordTaskCompletionToDigest`
 * side-effect on `→ done` transitions just like the manager-driven path.
 *
 * Pure decision logic lives in `board_transitions.ts`; this function is
 * the integration glue (snapshot lookups, mutation, broadcast). Kept here
 * — not in board_transitions — to keep that module free of WS/server deps.
 */
function advanceBoardTaskAfterDispatch(
  ws: WebSocket,
  boardTaskId: string,
  agentId: string,
): void {
  const task = boardTasks.get(boardTaskId);
  if (!task) {
    dbg("warn", "board", `advanceBoardTaskAfterDispatch: unknown boardTaskId=${boardTaskId}`);
    return;
  }

  const gameState = clientGameState.get(ws);
  const agent = gameState?.instances[agentId];
  const lessonCount = getLessonsForAgent(traitStore, agentId).length;

  const decision = advanceOnDispatchSuccess({
    task,
    agent,
    lessonCount,
    rng: Math.random,
  });
  if (!decision.changed) return;

  const oldColumn = task.column;
  task.column = decision.nextColumn;
  if (decision.outcome) task.outcome = decision.outcome;
  task.updatedAt = new Date().toISOString();
  dbg(
    "info",
    "board",
    `C.2 advance ${boardTaskId}: ${oldColumn} → ${task.column}${
      decision.outcome ? ` (outcome=${decision.outcome})` : ""
    }`,
  );
  commitBoardChange();
  if (task.column === "done") {
    boardWriter.flush(); // same archive-safety as manual board_move_task
    if (oldColumn !== "done") recordTaskCompletionToDigest(task);
  }
  broadcastBoardState();
}

/** Handle sub-agent error. */
function handleSubAgentError(ws: WebSocket, agentId: string, dispatchId: string, error: string): void {
  dbg("error", "dispatch", `Agent ${agentId} error (${dispatchId}): ${error}`);

  // Refresh "Active agents" UI — dispatch has left the runner.
  broadcastActiveAgents(ws);

  send(ws, {
    type: "agent_status",
    agentId,
    status: "idle",
    tools: [],
  });

  // C.2.5 — discriminated failure event. Lets the client distinguish
  // timeout (retry-friendly) from breaker (cost-budget) from generic
  // error, and clear any stale partial tool-progress state ("Reading
  // char_0.png…" displayed indefinitely was the 2026-05-18 incident UX).
  const cls = classifySubAgentFailure(error);
  send(ws, {
    type: "subagent_failed",
    dispatchId,
    agentId,
    reason: cls.reason,
    message: cls.message,
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
            `[Board task id=${task.boardTaskId ?? "unknown"}] "${task.boardTaskTitle}": ${task.boardTaskDescription ?? "no description"}. Plan and dispatch this work — when you call \`dispatch\`, pass boardTaskId="${task.boardTaskId ?? ""}" so the server can advance the column on finish. Then post ONE short status line to the user per the Communication policy — if you split it, name the pieces (e.g. 'Розбив "${task.boardTaskTitle}" на: {A}, {B}. Беремо {A} першим.'); if you dispatch as-is, just say what you're starting on (e.g. 'Працюємо над ${task.boardTaskTitle}.'). Do not narrate the dispatch mechanics.`,
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

/** Build the active_agents payload for a single ws — union of sub-agent
 *  dispatches and main chat queries owned by this socket. */
function buildActiveAgentsMessage(ws: WebSocket): ServerMessage {
  const entries: Array<{
    kind: "dispatch" | "chat";
    id: string;
    agentId: string;
    task: string;
    elapsedMs: number;
  }> = [];
  for (const r of agentRunner.getStatus()) {
    entries.push({ kind: "dispatch", id: r.dispatchId, agentId: r.agentId, task: r.task, elapsedMs: r.elapsedMs });
  }
  for (const q of chatQueryRegistry.list({ ws })) {
    entries.push({ kind: "chat", id: q.queryId, agentId: q.agentId, task: q.userMessage, elapsedMs: q.elapsedMs });
  }
  return { type: "active_agents", entries };
}

function broadcastActiveAgents(ws: WebSocket): void {
  send(ws, buildActiveAgentsMessage(ws));
}

/**
 * C.2 — persist a run's partial assistant text into `chatHistory` so it
 * shows up in the chat flow itself (not just the interrupted-banner)
 * on reconnect. Keyed by runId — idempotent if called twice for the
 * same run (boot sweep + runtime catch can both fire). No-op for empty
 * partials and explicit user cancels.
 *
 * Side-effects: appends to chatHistory, persists to disk, and broadcasts
 * the new snapshot to every connected client so a still-online peer also
 * sees the message land. Failures swallowed — losing one partial flush
 * is acceptable; breaking a live error path is not.
 */
function commitPartialToChatHistory(
  runId: string,
  agentId: string,
  partial: string | undefined,
  status: "interrupted" | "failed" | "cancelled",
  completedAt: string,
): void {
  if (!partial || partial.length === 0) return;
  // Cancelled = explicit user action; they don't need to see what was
  // being typed at the moment they hit stop. Interrupted / failed are
  // the cases where the partial is genuinely useful.
  if (status === "cancelled") return;
  try {
    chatHistory.add({
      role: "assistant",
      text: partial,
      agentId,
      timestamp: completedAt,
      id: runId,
    });
    chatHistory.save(historyFilePath(PROJECT_CWD));
    broadcastAll(chatHistory.snapshot());
  } catch (e) {
    dbg("warn", "session",
      `commitPartialToChatHistory failed for run ${runId}: ${(e as Error).message}`);
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
  let _queryTimedOut = false;
  // C.2.4 hoisted so the catch block can read trip state when the SDK
  // throws an AbortError after we tripped the breaker.
  let _breaker: CircuitBreaker | null = null;
  let _breakerTripped = false;
  // C.2 usage log — captured at top of the function so both the success
  // path (after the for-await loop) and the catch can write a usage entry
  // for the same runId.
  const _runId = newRunId("chat");
  const _startedAt = new Date().toISOString();
  let _resultDurationMs = 0;
  let _resultCostUsd = 0;
  let _resultNumTurns = 0;
  // C.2 — open a persistent run record. Status flips to terminal in the
  // success / catch / cancel paths below.
  agentRunStore.start({
    runId: _runId,
    agentId: targetAgentId,
    taskType: "chat",
    userMessageSnippet: userMessage.slice(0, 200),
    startedAt: _startedAt,
  });
  let _runFinalText = "";
  // C.2.5 — track dispatch_ids the manager called THIS turn so the
  // post-loop detector can decide whether a "Готово:" claim was paired
  // with an actual subagent_result notification (it can't be — those
  // notifications surface via processQueue as a separate runQuery turn).
  const _dispatchedIdsThisTurn: string[] = [];
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
    // Inject tech-lead digest only for the architect role; buildOfficePrompt
    // gates on isTechLead internally so it's safe to render unconditionally.
    const digestBlock = techLeadDigest.renderForPrompt(15);
    const systemPrompt = buildOfficePrompt(
      targetAgentId,
      projectMemory,
      agentTraits,
      gameState,
      digestBlock,
    );

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

    const queryAbort = new AbortController();
    const queryOptions = {
      systemPrompt: finalSystemPrompt,
      model: targetModel,
      allowedTools,
      ...(mcpServers ? { mcpServers } : {}),
      cwd: PROJECT_CWD,
      includePartialMessages: true,
      permissionMode: "bypassPermissions" as const,
      // C.2.4 circuit breaker iteration cap. Was 50; lowered to 30 to match
      // the documented safety-net policy ($5 cost cap + 30 turn cap).
      maxTurns: 30,
      persistSession: true,
      continue: false,
      abortController: queryAbort,
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

    const nonStreamingConfig = nonStreamingProviders.get(
      targetInstance?.provider ?? -1,
    );

    const q = (targetInstance?.provider === 1) // 1 = local (Gemini CLI)
      ? (async function*() {
          // Local execution bridge
          const res = await localGemini.query({
            agentId: targetAgentId,
            systemPrompt: finalSystemPrompt,
            userMessage: prefixedPrompt,
            projectContext: projectMemory,
            onText: (text) => {
              // Send partial text to client for streaming effect
              send(ws, {
                type: "assistant_text",
                text,
                isPartial: true,
                agentId: targetAgentId,
              });
            }
          });

          // Mimic completion message
          yield {
            type: "assistant",
            subtype: "message",
            message: {
              role: "assistant",
              content: [{ type: "text", text: res.result }],
            },
            usage: {
              input_tokens: 0,
              output_tokens: 0,
              total_cost_usd: 0,
            },
            duration_ms: res.duration_ms,
            session_id: "local",
            parent_tool_use_id: null,
          } as unknown as SDKAssistantMessage;

          // Mimic result message
          yield {
            type: "result",
            result: res.result,
            duration_ms: res.duration_ms,
            total_cost_usd: 0,
          } as unknown as SDKMessage;
        })()
      : nonStreamingConfig
        ? runNonStreamingBackend({
            config: nonStreamingConfig,
            ws,
            prompt: prefixedPrompt,
            systemPrompt: finalSystemPrompt,
            model: targetModel,
            agentId: targetAgentId,
            send,
          })
        : query({
            prompt: promptParam,
            options: queryOptions,
          });

    // Abort after 5 minutes — a hung API call would lock withSessionLock
    // forever, blocking every subsequent manager query.
    const _queryTimeoutId = setTimeout(() => {
      _queryTimedOut = true;
      queryAbort.abort();
    }, 5 * 60_000);

    // Register in chat query registry so the "Active agents" UI can cancel
    // this externally. Unregistered in finally.
    const _chatQueryId = chatQueryRegistry.register({
      ws,
      agentId: targetAgentId,
      userMessage,
      abortController: queryAbort,
    });
    broadcastActiveAgents(ws);

    // C.2.4 circuit breaker — safety net for runaway loops. Tracks
    // cumulative cost + tool-call count from `assistant` SDK messages and
    // aborts the AbortController if either cap is crossed.
    _breaker = new CircuitBreaker(targetModel);

    try {
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
        let _runAssistantText = "";
        for (const block of asst.message.content) {
          if (block.type === "tool_use" && (block.name === "Agent" || block.name === "Task")) {
            const input = block.input as Record<string, unknown>;
            const delegateTo = (input.subagent_type as string) ?? "general";
            const delegateFrom = asst.parent_tool_use_id
              ? resolveAgentId(ws, asst.parent_tool_use_id)
              : targetAgentId;
            trackComm(ws, delegateFrom, delegateTo);
          }
          // C.2 persistent run record — capture tool_use + assistant text
          // for crash-recovery and reconnect snapshot. Text is appended
          // (concatenated across blocks within a single SDK message); the
          // running buffer is flushed to disk via `partialOutput` below.
          if (block.type === "tool_use") {
            agentRunStore.appendToolCall(_runId, {
              name: block.name,
              id: block.id,
              at: new Date().toISOString(),
            });
          }
          if (block.type === "text") {
            _runAssistantText += block.text;
          }
        }
        if (_runAssistantText) {
          _runFinalText += _runAssistantText;
          agentRunStore.update(_runId, { partialOutput: _runFinalText });
        }
        // C.2.4 circuit breaker — observe usage + tool_use counts.
        const trip = _breaker.observeAssistantMessage(
          asst.message.usage as unknown as
            | { input_tokens?: number; output_tokens?: number; cache_creation_input_tokens?: number; cache_read_input_tokens?: number }
            | null
            | undefined,
          asst.message.content,
        );
        if (trip) {
          _breakerTripped = true;
          dbg("warn", "breaker", `Circuit breaker tripped: ${trip.message}`);
          sendDebug(ws, "warn", "breaker", `Aborted: ${trip.message}`);
          queryAbort.abort();
        }
      }

      // C.2 usage log — capture totals from the SDK's terminating result
      // message before handleSDKMessage forwards it to the client.
      if (message.type === "result") {
        const r = message as SDKResultMessage;
        _resultDurationMs = r.duration_ms ?? 0;
        _resultCostUsd = r.total_cost_usd ?? 0;
        _resultNumTurns = r.num_turns ?? 0;
      }

      // C.2.5 — scrape dispatch_ids from `mcp__dispatch__dispatch` tool_result
      // text. The dispatchTool always emits a line of shape
      //   "Task dispatched to <agent> (ID: dispatch_<n>_<ts>)..."
      // so a single regex over the tool_result content is enough.
      if (message.type === "user") {
        const um = message as SDKUserMessage;
        const content = um.message?.content;
        if (Array.isArray(content)) {
          for (const block of content) {
            if (
              typeof block === "object" &&
              block !== null &&
              (block as { type?: string }).type === "tool_result"
            ) {
              const tr = block as { content?: unknown };
              const text =
                typeof tr.content === "string"
                  ? tr.content
                  : Array.isArray(tr.content)
                    ? (tr.content as Array<{ type?: string; text?: string }>)
                        .filter((c) => c.type === "text")
                        .map((c) => c.text ?? "")
                        .join("")
                    : "";
              const id = extractDispatchIdFromToolResult(text);
              if (id) {
                _dispatchedIdsThisTurn.push(id);
              }
            }
          }
        }
      }

      handleSDKMessage(ws, message, targetAgentId, _runId);
    }

    // Track agent → user response
    trackComm(ws, targetAgentId, "user");
    sendCommGraph(ws);

    dbg("info", "session", `Query finished. ${messageCount} SDK messages processed.`);
    sendDebug(ws, "info", "session",
      `Query complete (${targetAgentId}). ${messageCount} msgs. Session=${currentSessionId?.slice(0, 12) ?? "?"}…`
    );

    // C.2.5 — premature-complete detection. Dispatches called THIS turn
    // cannot have a paired `subagent_result` yet (those surface as a
    // separate runQuery turn via processQueue), so resolvedDispatchIds
    // is always empty here. If the manager nevertheless emitted "Готово:"
    // in its output text, that's a fabrication — record it for the daily
    // rate counter. Alert-mode only: we never block the response.
    if (_dispatchedIdsThisTurn.length > 0) {
      const pc = detectPrematureComplete({
        dispatchedIds: _dispatchedIdsThisTurn,
        managerOutputText: _runFinalText,
        resolvedDispatchIds: [],
      });
      if (pc.fabricated) {
        const roleName = roleTypeOf(targetAgentId, clientGameState.get(ws));
        // C.2.5 Stage 4 — alert-mode. We compute the rewrite the future
        // block-mode would apply, but DO NOT modify the manager text the
        // client already sees. Recording both forms lets us:
        //   (a) measure rate over time via incident_log;
        //   (b) eyeball whether the rewrite preserves the user-visible
        //       task name (no cryptic gaps in chat history);
        //   (c) flip to block-mode in one place if the baseline supports it.
        const rewritten = stripPrematureCompleteClaim(_runFinalText);
        const rewriteApplied = rewritten !== _runFinalText;
        incidentLogger.record({
          incidentId: newIncidentId("premature_complete"),
          kind: "premature_complete",
          runId: _runId,
          role: roleName,
          taskType: "chat",
          agentId: targetAgentId,
          occurredAt: new Date().toISOString(),
          details: {
            unmatchedDispatchIds: pc.unmatchedDispatchIds,
            matchedClaim: pc.matchedClaim ?? "",
            rewriteApplied,
          },
        });
        dbg("warn", "incident", `premature_complete claim by ${targetAgentId} — ${pc.unmatchedDispatchIds.length} unmatched dispatch(es). Claim: ${pc.matchedClaim}. Rewrite available: ${rewriteApplied}`);
      }
    }

    // C.2 usage log — append a completed-run entry. Breaker snapshot
    // gives us cumulative tokens / tool-calls; result message gives us
    // cost / duration / num_turns. Disk failures are swallowed inside
    // the logger so a full disk never breaks a live query.
    if (_breaker) {
      const snap = _breaker.snapshot();
      usageLogger.record({
        runId: _runId,
        role: roleTypeOf(targetAgentId, clientGameState.get(ws)),
        taskType: "chat",
        agentId: targetAgentId,
        inputTokens: snap.inputTokens,
        outputTokens: snap.outputTokens,
        cacheCreationTokens: snap.cacheCreateTokens,
        cacheReadTokens: snap.cacheReadTokens,
        costUsd: _resultCostUsd || snap.costUsd,
        durationMs: _resultDurationMs,
        numTurns: _resultNumTurns,
        numToolCalls: snap.toolCalls,
        startedAt: _startedAt,
        completedAt: new Date().toISOString(),
      });
      agentRunStore.update(_runId, {
        status: "completed",
        finalOutput: _runFinalText,
        usage: {
          inputTokens: snap.inputTokens,
          outputTokens: snap.outputTokens,
          cacheCreationTokens: snap.cacheCreateTokens,
          cacheReadTokens: snap.cacheReadTokens,
          costUsd: _resultCostUsd || snap.costUsd,
          numTurns: _resultNumTurns,
          numToolCalls: snap.toolCalls,
        },
      });
    } else {
      agentRunStore.update(_runId, {
        status: "completed",
        finalOutput: _runFinalText,
      });
    }
    } finally {
      clearTimeout(_queryTimeoutId);
      chatQueryRegistry.unregister(_chatQueryId);
      broadcastActiveAgents(ws);
      // C.2.6 — symmetric with handleSubAgentError / handleSubAgentComplete.
      // Without this, a query that terminates via the inner-finally path
      // (success OR error caught by outer catch) leaves chat-header indicator
      // stuck on the last push (e.g. "Reading") because the catch below
      // doesn't re-emit status. broadcastActiveAgents alone clears the
      // Settings tab but NOT the chat indicator (which derives from
      // agent_status pushes, not active_agents).
      send(ws, {
        type: "agent_status",
        agentId: targetAgentId,
        status: "idle",
        tools: [],
      });
    }
  } catch (err) {
    const breakerTrip = _breakerTripped ? _breaker?.snapshot().tripped ?? null : null;
    const errMsg = breakerTrip
      ? `Circuit breaker — ${breakerTrip.message}. Перезапустіть запит або змініть scope.`
      : _queryTimedOut
        ? `Manager query timed out after 5 minutes — API may be unresponsive`
        : err instanceof Error ? err.message : String(err);
    dbg("error", "session", `Query failed: ${errMsg}`);
    sendDebug(ws, "error", "session", `Query FAILED: ${errMsg}`);

    // C.2 usage log — interrupted runs still consume tokens and belong
    // in the baseline distribution. Skip if the breaker never spun up
    // (failure before the SDK loop even started, no usage to record).
    if (_breaker) {
      const snap = _breaker.snapshot();
      usageLogger.record({
        runId: _runId,
        role: roleTypeOf(targetAgentId, clientGameState.get(ws)),
        taskType: "chat",
        agentId: targetAgentId,
        inputTokens: snap.inputTokens,
        outputTokens: snap.outputTokens,
        cacheCreationTokens: snap.cacheCreateTokens,
        cacheReadTokens: snap.cacheReadTokens,
        costUsd: snap.costUsd,
        durationMs: Date.now() - new Date(_startedAt).getTime(),
        numTurns: _resultNumTurns,
        numToolCalls: snap.toolCalls,
        startedAt: _startedAt,
        completedAt: new Date().toISOString(),
      });
    }
    // C.2 — flip run status to its terminal form. Explicit user cancel
    // (abort with neither breaker nor timeout) → cancelled; everything
    // else interrupting the SDK loop → interrupted / failed.
    {
      const explicitCancel =
        !_breakerTripped &&
        !_queryTimedOut &&
        err instanceof Error &&
        (err.name === "AbortError" || /aborted/i.test(err.message));
      const status = explicitCancel
        ? "cancelled"
        : _breakerTripped || _queryTimedOut
          ? "interrupted"
          : "failed";
      const snap = _breaker?.snapshot();
      const completedAt = new Date().toISOString();
      agentRunStore.update(_runId, {
        status,
        reason: errMsg,
        partialOutput: _runFinalText || undefined,
        completedAt,
        usage: snap
          ? {
              inputTokens: snap.inputTokens,
              outputTokens: snap.outputTokens,
              cacheCreationTokens: snap.cacheCreateTokens,
              cacheReadTokens: snap.cacheReadTokens,
              costUsd: snap.costUsd,
              numTurns: _resultNumTurns,
              numToolCalls: snap.toolCalls,
            }
          : undefined,
      });
      commitPartialToChatHistory(
        _runId,
        targetAgentId,
        _runFinalText,
        status,
        completedAt,
      );
    }
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
    // C.2.6 — defensive idle emission. Inner finally already emits idle for
    // the common case (error inside the for-await loop). This covers the
    // rare case where the throw happens BEFORE the inner try block was
    // entered (e.g. query() construction failed, session-lock contention) —
    // inner finally never runs, so emit here. Double-emission on the common
    // path is idempotent on the client (status: idle is a fixed point).
    broadcastActiveAgents(ws);
    send(ws, {
      type: "agent_status",
      agentId: targetAgentId,
      status: "idle",
      tools: [],
    });
    send(ws, {
      type: "error",
      message: errMsg,
    });
  }
}

// ─── Task Board (persisted, shared across all clients) ─────────────────────
//
// On boot we hydrate from ~/.pixelcode/projects/{key}/board.json so a server
// restart no longer wipes the kanban. Mutations go through `boardWriter`
// which debounces disk writes (250ms) and writes atomically (tmp+rename).
// `flushBoard()` is wired into the SIGINT/SIGTERM handlers below.

const boardTasks: Map<string, TaskCardData> = new Map();
let boardTaskCounter = 0;
const boardWriter = new BoardWriter(PROJECT_CWD);

/**
 * Monotonically increasing revision. Bumped after every successful
 * mutation, *before* commitBoardChange()/broadcast so all observers see the
 * same number. Reconnecting clients can pass it back via
 * `board_get_state{since}` to skip a full snapshot when nothing changed.
 */
let boardRevision = 0;

(function hydrateBoard() {
  const r = loadBoard(PROJECT_CWD);
  for (const t of r.tasks) boardTasks.set(t.id, t);
  boardTaskCounter = r.taskCounter;
  if (r.source === "loaded") {
    dbg("info", "board", `Loaded ${r.tasks.length} persisted task(s) (counter=${r.taskCounter})`);
  } else if (r.source === "quarantined") {
    dbg("warn", "board", `Persisted board was unreadable; quarantined to ${r.quarantinedAs ?? "?"}`);
  }
  // Sweep any orphan-active cards that survived a crash/respawn (e.g. dispatch
  // was killed mid-run and lost the assignee). C.2 Q1 variant A — under the
  // "server as single writer" rule, cards stuck in in_progress/testing with no
  // assigned agents would never advance, so we bounce them back to backlog
  // for re-pickup. Pre-commit reset is silent (no broadcast yet — broadcast
  // happens on the next mutation).
  sweepOrphanActiveCards();
})();

/**
 * Pre-commit sweep: orphan-active cards (in_progress / testing with no
 * `assignedAgents`) are reset to backlog. Idempotent — running it on a
 * clean board mutates nothing and returns 0. Called from `commitBoardChange`
 * so every mutation cycle ships a consistent snapshot.
 */
function sweepOrphanActiveCards(): number {
  const orphans = findOrphanActiveCards(boardTasks.values());
  if (orphans.length === 0) return 0;
  const nowIso = new Date().toISOString();
  for (const id of orphans) {
    const t = boardTasks.get(id);
    if (!t) continue;
    t.column = "backlog";
    t.updatedAt = nowIso;
  }
  dbg("info", "board", `C.2 orphan-reset: ${orphans.join(", ")} → backlog`);
  return orphans.length;
}

/** Bump revision and persist. Call exactly once per applied mutation. */
function commitBoardChange(): void {
  sweepOrphanActiveCards();
  boardRevision++;
  boardWriter.schedule(Array.from(boardTasks.values()));
}

/**
 * Push a task into the tech-lead digest when it transitions into "done"
 * and broadcast the freshened pulse so the Hub strip updates without a
 * poll. Wraps the pure helper in `conversational_loop.ts` with the
 * server-only side effects (websocket broadcast).
 */
function recordTaskCompletionToDigest(task: TaskCardData): void {
  // Resolve the agent's top lesson (by frequency) at completion time,
  // so the digest entry carries a concrete "they learned X" hint the
  // tech-lead can ground its replies in. Strength lessons map to
  // frequency-1 strengths; weakness lessons surface things to watch.
  recordTaskCompletion(techLeadDigest, task, (agentId) => {
    const lessons = getLessonsForAgent(traitStore, agentId);
    const top = lessons[0];
    if (!top) return undefined;
    return {
      tag: top.tag,
      lesson: top.lesson,
      type: top.type === "strength" ? "strength" : "weakness",
    };
  });
  broadcastAll({
    type: "tech_lead_pulse",
    entries: techLeadDigest.recent(20),
  } as ServerMessage);
}

export function flushBoard(): void {
  boardWriter.flush();
}

function broadcastBoardState(): void {
  const tasks = Array.from(boardTasks.values());
  const msg: ServerMessage = { type: "board_state", tasks, revision: boardRevision };
  const payload = JSON.stringify(msg);
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  }
}

function sendBoardState(ws: WebSocket, since?: number): void {
  if (typeof since === "number" && since === boardRevision) {
    // Client is already current — no need to ship every task again.
    send(ws, { type: "board_state_unchanged", revision: boardRevision });
    return;
  }
  const tasks = Array.from(boardTasks.values());
  send(ws, { type: "board_state", tasks, revision: boardRevision });
}

function handleBoardMessage(ws: WebSocket, msg: ClientMessage): void {
  // The transport-level JSON parse only narrows by `type`; the rest of the
  // payload is untrusted (a stale client, a buggy script, or a future
  // version can send unexpected shapes). Wrap the whole switch so a
  // malformed message can never break the WebSocket — it just drops the
  // command and logs.
  try {
    handleBoardMessageInner(ws, msg);
  } catch (e) {
    dbg("warn", "board", `Dropped malformed board message (${msg.type}): ${e}`);
  }
}

function handleBoardMessageInner(ws: WebSocket, msg: ClientMessage): void {
  switch (msg.type) {
    case "board_get_state":
      sendBoardState(ws, msg.since);
      break;

    case "board_create_task": {
      // Reject empty or non-string titles silently — they correspond to a
      // buggy client that should fix itself, but should not crash the
      // server or pollute the board with blank cards.
      if (typeof msg.title !== "string" || msg.title.trim().length === 0) {
        dbg("warn", "board", `Rejected board_create_task: empty/invalid title`);
        break;
      }
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
      commitBoardChange();
      broadcastBoardState();
      break;
    }

    case "board_move_task": {
      if (!isValidBoardColumn(msg.column)) {
        dbg("warn", "board", `Rejected board_move_task: invalid column "${msg.column}"`);
        break;
      }
      const task = boardTasks.get(msg.taskId);
      if (task) {
        const oldColumn = task.column;
        task.column = msg.column;
        task.updatedAt = new Date().toISOString();
        dbg("info", "board", `Moved task ${msg.taskId}: ${oldColumn} → ${task.column}`);
        commitBoardChange();
        // Done is the archive — losing a completion in the 250ms debounce
        // window (e.g. SIGKILL from launcher) destroys progress the player
        // can't recreate. Skip the debounce on transitions into done so the
        // file is written before we ack.
        if (task.column === "done") boardWriter.flush();
        if (task.column === "done" && oldColumn !== "done") {
          recordTaskCompletionToDigest(task);
        }
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
        if (updates.column !== undefined && !isValidBoardColumn(updates.column)) {
          dbg("warn", "board", `Rejected board_update_task: invalid column "${updates.column}"`);
          break;
        }
        const oldColumn = task.column;
        if (updates.title !== undefined) task.title = updates.title;
        if (updates.description !== undefined) task.description = updates.description;
        if (updates.priority !== undefined) task.priority = updates.priority;
        if (updates.color !== undefined) task.color = updates.color;
        if (updates.column !== undefined) task.column = updates.column;
        task.updatedAt = new Date().toISOString();
        dbg("info", "board", `Updated task ${msg.taskId}`);
        commitBoardChange();
        if (task.column === "done") boardWriter.flush();
        if (task.column === "done" && oldColumn !== "done") {
          recordTaskCompletionToDigest(task);
        }
        broadcastBoardState();
      }
      break;
    }

    case "board_delete_task": {
      if (boardTasks.delete(msg.taskId)) {
        dbg("info", "board", `Deleted task ${msg.taskId}`);
        commitBoardChange();
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
        commitBoardChange();
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
      commitBoardChange();
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
        commitBoardChange();
        broadcastBoardState();
      }
      break;
    }

    case "board_seed_batch": {
      // Atomic insert. planSeedBatch is pure: it validates every entry
      // first; if any fail, no state mutates. This protects the kanban
      // from the partial-seed failure mode where the facilitator
      // pipeline could leave 4 of 10 expected tasks before erroring.
      const plan = planSeedBatch(msg.tasks ?? [], {
        counter: boardTaskCounter,
        now: () => new Date(),
        idToken: () => Date.now(),
        sourceTag: msg.source,
      });
      if (!plan.ok) {
        dbg(
          "warn",
          "board",
          `Rejected board_seed_batch (batchId=${msg.batchId ?? "-"}): ${plan.errors.length} validation error(s)`,
        );
        send(ws, {
          type: "board_seed_batch_result",
          batchId: msg.batchId,
          ok: false,
          committedIds: [],
          errors: plan.errors,
        });
        break;
      }
      // Commit + auto-dispatch. The manager-LLM was previously the only
      // one who could route a freshly-seeded backlog onto agents; this
      // MVP picks deterministic assignees so the daily flow doesn't
      // demand 10 manual drags after every facilitator intake.
      const gs = clientGameState.get(ws);
      const load = activeAgentTasks.get(ws);
      const dispatchSummary: string[] = [];
      for (const t of plan.tasks) {
        boardTasks.set(t.id, t);
        if (gs && shouldAutoDispatch(t)) {
          const pick = pickAssignee(t, {
            instances: gs.instances,
            load: load ?? new Map<string, number>(),
            enabled: true,
          });
          if (pick) {
            t.assignedAgents = [pick];
            t.column = "in_progress";
            // Bump the in-memory load so the next task in the same
            // batch sees the updated picture and we spread the work.
            const tasks = activeAgentTasks.get(ws) ?? new Map();
            tasks.set(pick, (tasks.get(pick) ?? 0) + 1);
            activeAgentTasks.set(ws, tasks);
            dispatchSummary.push(`${t.id}→${pick}`);
          }
        }
      }
      boardTaskCounter = plan.nextCounter;
      dbg(
        "info",
        "board",
        `Committed board_seed_batch (batchId=${msg.batchId ?? "-"}): ${plan.tasks.length} task(s)${
          dispatchSummary.length ? `; auto-dispatched: ${dispatchSummary.join(", ")}` : ""
        }`,
      );
      commitBoardChange();
      broadcastBoardState();
      send(ws, {
        type: "board_seed_batch_result",
        batchId: msg.batchId,
        ok: true,
        committedIds: plan.tasks.map((t) => t.id),
        errors: [],
      });
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
    try {
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
    } catch (err) {
      if (!res.headersSent) {
        res.writeHead(500);
        res.end("Internal server error");
      }
      console.error("[server] HTTP handler error:", err);
    }
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
  const flutterBin = findFlutter();

  if (flutterBin) {
    try {
      await new Promise<void>((resolve) => {
        execFile(flutterBin, ["--version"], { timeout: 10000 }, (err) => {
          hasFlutter = !err;
          resolve();
        });
      });
    } catch { /* not installed */ }
  }

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

  const flutterBin = findFlutter() ?? "flutter";

  // Step 1: Build .app bundle
  sendDeployLog(ws, "Побудова iOS додатку...");
  sendDeployLog(ws, `Команда: ${flutterBin} build ios --release`);

  const buildProcess = spawn(flutterBin, ["build", "ios", "--release"], {
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
  send(ws, { type: "ios_deploy_status", subtype: "complete", success: true } as any);
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

/** Resolve flutter binary — check PATH, then common install locations. */
function findFlutter(): string | null {
  try {
    const p = execFileSync("which", ["flutter"], { timeout: 3000 }).toString().trim();
    if (p) return p;
  } catch { /* not in PATH */ }
  for (const p of ["/opt/homebrew/bin/flutter", "/usr/local/bin/flutter", `${homedir()}/flutter/bin/flutter`]) {
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
  const flutterBin = findFlutter();

  if (flutterBin) {
    try {
      await new Promise<void>((resolve) => {
        execFile(flutterBin, ["--version"], { timeout: 10000 }, (err) => {
          hasFlutter = !err;
          resolve();
        });
      });
    } catch { /* not installed */ }
  }

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

// ─── Android device watcher (push on change, 3 s poll) ────────────────────

const activeDeviceWatchers = new Map<WebSocket, ReturnType<typeof setInterval>>();
const lastSentDeviceList = new Map<WebSocket, string>();

async function androidDeployWatchDevices(ws: WebSocket): Promise<void> {
  androidDeployUnwatchDevices(ws);
  const adbPath = findAdb();

  const poll = async () => {
    try {
      const devices = adbPath ? await listAndroidDevices(adbPath) : [];
      const json = JSON.stringify(devices);
      if (json !== lastSentDeviceList.get(ws)) {
        lastSentDeviceList.set(ws, json);
        send(ws, { type: "android_deploy_status", subtype: "devices_list", devices } as any);
      }
    } catch {
      // silently skip failed poll — next tick will retry
    }
  };

  await poll();
  activeDeviceWatchers.set(ws, setInterval(poll, 3000));
}

function androidDeployUnwatchDevices(ws: WebSocket): void {
  const timer = activeDeviceWatchers.get(ws);
  if (timer !== undefined) {
    clearInterval(timer);
    activeDeviceWatchers.delete(ws);
    lastSentDeviceList.delete(ws);
  }
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

  const flutterBin = findFlutter() ?? "flutter";

  const runFlutterBuild = async (): Promise<{ exitCode: number | null; log: string }> => {
    sendAndroidDeployLog(ws, "Побудова Android APK...");
    sendAndroidDeployLog(ws, `Команда: ${flutterBin} build apk --release`);

    const proc = spawn(flutterBin, ["build", "apk", "--release"], { cwd: PROJECT_CWD });
    activeAndroidDeployProcess.set(ws, proc);

    const logLines: string[] = [];

    proc.stdout.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        const t = line.trim();
        if (t) { sendAndroidDeployLog(ws, t); logLines.push(t); }
      }
    });
    proc.stderr.on("data", (chunk: Buffer) => {
      for (const line of chunk.toString().split("\n")) {
        const t = line.trim();
        if (t) { sendAndroidDeployError(ws, t); logLines.push(t); }
      }
    });

    const exitCode = await new Promise<number | null>((resolve) => {
      proc.on("close", resolve);
      proc.on("error", (err) => {
        sendAndroidDeployError(ws, `Помилка при побудові: ${err.message}`);
        resolve(1);
      });
    });

    return { exitCode, log: logLines.join("\n") };
  };

  let { exitCode: buildExitCode, log: buildLog } = await runFlutterBuild();

  if (buildExitCode !== 0) {
    sendAndroidDeployLog(ws, "");
    sendAndroidDeployLog(ws, "── Build Doctor ─────────────────────────────────");
    sendAndroidDeployLog(ws, "Білд впав. Запускаю AI Doctor для діагностики...");

    const doctorResult = await runBuildDoctor(
      buildLog,
      PROJECT_CWD,
      (msg) => sendAndroidDeployLog(ws, msg),
    );

    if (doctorResult.fixed) {
      sendAndroidDeployLog(ws, "");
      sendAndroidDeployLog(ws, "── Retry Build ──────────────────────────────────");
      sendAndroidDeployLog(ws, "Фікс застосовано. Повторний білд...");
      sendAndroidDeployLog(ws, "");

      ({ exitCode: buildExitCode, log: buildLog } = await runFlutterBuild());
    }

    if (buildExitCode !== 0) {
      sendAndroidDeployError(ws, `Помилка при побудові. Код виходу: ${buildExitCode}`);
      send(ws, { type: "android_deploy_status", subtype: "complete", success: false } as any);
      activeAndroidDeployProcess.delete(ws);
      return;
    }

    sendAndroidDeployLog(ws, "");
    sendAndroidDeployLog(ws, "Retry успішний!");
    sendAndroidDeployLog(ws, "");

    // Publish doctor's changes to git
    sendAndroidDeployLog(ws, "── Git ──────────────────────────────────────────");
    await publishBuildFix(
      PROJECT_CWD,
      doctorResult.summary,
      (msg) => sendAndroidDeployLog(ws, msg),
    );
    sendAndroidDeployLog(ws, "");
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
  send(ws, { type: "android_deploy_status", subtype: "complete", success: true } as any);
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
//
// On macOS we delegate to the system dns-sd(1) daemon so that the pure-JS
// bonjour-service library does not send its own A-record announcements and
// trigger a hostname-conflict dialog ("SSG-Bavovna.local is already in use").
let mdnsActive = false;
let mdnsDnsSdProcess: ChildProcess | null = null;
let mdnsBonjourInstance: Bonjour | null = null;

function unpublishMdns(cb?: () => void): void {
  if (mdnsDnsSdProcess) {
    mdnsDnsSdProcess.kill();
    mdnsDnsSdProcess = null;
    mdnsActive = false;
    cb?.();
    return;
  }
  if (mdnsBonjourInstance) {
    mdnsBonjourInstance.unpublishAll(() => {
      try { mdnsBonjourInstance!.destroy(); } catch { /* already destroyed */ }
      mdnsBonjourInstance = null;
      mdnsActive = false;
      cb?.();
    });
    return;
  }
  cb?.();
}

function publishMdns(): void {
  const name = `PixelCode @ ${hostname()}`;
  if (process.platform === "darwin") {
    // dns-sd -R registers via mDNSResponder which already owns the hostname
    // A-record — no conflict with the system daemon is possible.
    mdnsDnsSdProcess = spawn("dns-sd", [
      "-R", name, "_pixelcode._tcp", ".", String(PORT), "version=1",
    ]);
    mdnsDnsSdProcess.on("spawn", () => {
      mdnsActive = true;
      dbg("info", "mDNS", `Advertised _pixelcode._tcp on port ${PORT} as "${name}"`);
    });
    mdnsDnsSdProcess.on("error", (err) => {
      dbg("warn", "mDNS", `dns-sd spawn failed: ${err.message}`);
    });
    mdnsDnsSdProcess.on("exit", (code) => {
      if (mdnsActive) {
        mdnsActive = false;
        dbg("warn", "mDNS", `dns-sd exited unexpectedly (code=${code})`);
      }
    });
  } else {
    mdnsBonjourInstance = new Bonjour();
    const svc = mdnsBonjourInstance.publish({
      name,
      type: "pixelcode",
      protocol: "tcp",
      port: PORT,
      // Explicit TXT record — required for iOS NWBrowser.bonjourWithTXTRecord
      // (used by the `bonsoir` package) to surface the service. Without a TXT
      // record, iOS silently filters the service out, even though Android
      // (NsdManager) and raw mDNS tools still see it.
      txt: { version: "1" },
    });
    svc.on("up", () => {
      mdnsActive = true;
      dbg("info", "mDNS", `Advertised _pixelcode._tcp on port ${PORT} as "${name}"`);
    });
  }
}

publishMdns();

async function restartMdns(): Promise<boolean> {
  mdnsActive = false;
  return new Promise((resolve) => {
    unpublishMdns(() => {
      publishMdns();
      // Give mDNS a moment to re-advertise and become active.
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
    projectCwd: PROJECT_CWD,
  };
}

/** Unpublish mDNS, give "goodbye" packets a moment to fly, then exit with `code`. */
function gracefulExit(code: number, reason: string): void {
  dbg("info", "shutdown", `${reason} (exit=${code}) — flushing board, unpublishing mDNS…`);
  // Flush any pending debounced board writes before exit so the last user
  // action survives a Ctrl+C.
  try { flushBoard(); } catch (e) { dbg("warn", "shutdown", `flushBoard failed: ${e}`); }
  let exited = false;
  const doExit = () => { if (!exited) { exited = true; process.exit(code); } };
  unpublishMdns(doExit);
  setTimeout(doExit, 1500);
}

function shutdownMdns(signal: string): void {
  gracefulExit(0, `signal=${signal}`);
}

process.on("SIGINT", () => shutdownMdns("SIGINT"));
process.on("SIGTERM", () => shutdownMdns("SIGTERM"));

// Prevent unhandled promise rejections from crashing the server —
// individual handler failures (bad JSON, SDK timeout) must not kill all
// connected sessions.
process.on("unhandledRejection", (reason) => {
  console.error("[server] Unhandled rejection:", reason);
});

// For uncaught synchronous exceptions the process is in undefined state;
// flush the board and let the launcher restart.
let _uncaughtExiting = false;
process.on("uncaughtException", (err) => {
  if (_uncaughtExiting) return;
  _uncaughtExiting = true;
  console.error("[server] Uncaught exception:", err);
  gracefulExit(1, `uncaughtException: ${err.message}`);
});

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
  getQueuedTaskCount: () => taskQueue.size,
  getActiveAgentCount: () => agentRunner.getStatus().length,
  scheduleExit: (code, reason) => {
    // Defer slightly so the HTTP response flushes before we tear down.
    setTimeout(() => gracefulExit(code, reason), 100);
  },
};
process.on("exit", () => {
  try { flushBoard(); } catch { /* best effort */ }
  unpublishMdns();
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

/**
 * Apply a project-memory update to every currently-connected client.
 * `clientProjectContext` is a per-ws WeakMap, but PROJECT_CWD is global —
 * if we only set on the sender, peer devices keep stale/empty memory until
 * they reconnect, and their next agent dispatch literally asks
 * "what project are we in?". Mirrors `chatHistory.snapshot` broadcasts.
 */
function setTeamMemoryEverywhere(memory: string): void {
  for (const client of wss.clients) clientProjectContext.set(client, memory);
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
console.log(`   Trait memory:    ${getAllTraits(traitStore).length} lessons loaded, ${getAllCandidates(candidateStore).length} candidates pending`);

wss.on("error", (err) => {
  console.error("[server] WebSocketServer error:", err);
});
httpServer.on("error", (err) => {
  console.error("[server] HTTP server error:", err);
});

wss.on("connection", (ws, request) => {
  wsClientsReady = true;
  const remoteAddress = request.socket.remoteAddress ?? "unknown";
  dbg("info", "ws", `Client connected from ${remoteAddress}`);

  heartbeatMonitor.onConnect(ws);
  ws.on("pong", () => heartbeatMonitor.onPong(ws));

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
  // C.2.6 — welcome resync. Push fresh active_agents snapshot + force every
  // hired agent's status to idle UNLESS this ws actually owns a live run.
  // Prevents reconnecting clients (or freshly opened second windows) from
  // showing a stale "Reading char_0.png" indicator carried in the local
  // agentsProvider cache from before the disconnect. The push-only nature
  // of agent_status means without this, the client never receives a fresh
  // idle event for a query that finished while it was offline.
  send(ws, buildActiveAgentsMessage(ws));
  {
    const liveAgentIds = new Set<string>([
      ...agentRunner.getStatus().map((r) => r.agentId),
      ...chatQueryRegistry.list({ ws }).map((q) => q.agentId),
    ]);
    for (const agent of agentInfoForClient(ws)) {
      if (!liveAgentIds.has(agent.id)) {
        send(ws, {
          type: "agent_status",
          agentId: agent.id,
          status: "idle",
          tools: [],
        });
      }
    }
  }
  sendBoardState(ws);
  sendTraits(ws);
  // Restore shared team memory for this project so every client (incl. mobile) gets captain context
  const savedMemory = loadTeamMemory(PROJECT_CWD);
  if (savedMemory) clientProjectContext.set(ws, savedMemory);
  // Inherit any provider keys another device on this server already
  // forwarded. Single-tenant model: keys identify the user, not the ws.
  if (lastSeenDeepSeekKey) clientDeepSeekKey.set(ws, lastSeenDeepSeekKey);
  if (lastSeenKimiKey) clientKimiKey.set(ws, lastSeenKimiKey);
  // Send existing chat history so new clients are in sync
  sendChatHistory(ws);
  // Send stored game state for cross-device sync
  if (latestFullGameState) {
    send(ws, {
      type: "game_state_sync",
      fullState: latestFullGameState,
      stateUpdatedAt: latestStateUpdatedAt,
    } as any);
    // Inherit the authoritative roster into this ws's clientGameState
    // so its first dispatch/validation reads a real roster instead of
    // undefined. Without this, peers that join after a hire have an
    // empty server-side roster until they send their own set_game_state.
    try {
      const parsed = JSON.parse(latestFullGameState) as { instances?: Record<string, unknown> };
      if (parsed.instances) clientGameState.set(ws, parsed as GameStateData);
    } catch {
      // Persisted blob is malformed; leave clientGameState unset so the
      // first set_game_state from this ws seeds it cleanly.
    }
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

          // Store user message and broadcast snapshot to all clients (including sender,
          // so the sender receives the canonical server id to replace its optimistic message).
          chatHistory.add({ role: "user", text: msg.content, agentId: targetAgent, timestamp: new Date().toISOString(), id: msg.localId, ...(images?.length ? { images } : {}) });
          chatHistory.save(historyFilePath(PROJECT_CWD));
          broadcastAll(chatHistory.snapshot());

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
          // Broadcast cleared init + empty chat_history to all clients so
          // every device's chat panel clears — without chat_history peers
          // keep showing the old messages until reconnect.
          for (const c of wss.clients) {
            if (c.readyState !== WebSocket.OPEN) continue;
            send(c as WebSocket, {
              type: "init",
              sessionId: "pending",
              agents: agentInfoForClient(c as WebSocket),
              workingDirectory: PROJECT_CWD,
            });
            sendChatHistory(c as WebSocket);
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
          candidateStore = loadCandidates(PROJECT_CWD);
          chatHistory.load(historyFilePath(PROJECT_CWD));
          dbg("info", "traits", `Traits loaded for ${newPath}: ${getAllTraits(traitStore).length} lessons, ${getAllCandidates(candidateStore).length} candidates`);
          // Load shared SDK session for the new project (per-project file).
          loadPersistedSession();
          // Reload other per-project caches so peers don't read the OLD
          // project's roster / facilitator output on the new project — and
          // so the next persist doesn't clobber the new project's disk
          // file with stale data from the previous one.
          latestFullGameState = null;
          latestStateUpdatedAt = 0;
          latestFacilitatorOutput = null;
          loadPersistedGameState();
          loadPersistedFacilitatorOutput();
          // Cancel in-flight agents and drop queued tasks: they reference
          // the OLD PROJECT_CWD via the runner's read-at-dispatch-time
          // global, so executing them now would run under the wrong
          // project's filesystem. The user has to redispatch — small UX
          // cost vs. the alternative of running rm/edit in the wrong tree.
          agentRunner.cancelAll();
          const dropped = taskQueue.clear();
          if (dropped > 0) {
            dbg("info", "queue", `Dropped ${dropped} queued task(s) on project switch`);
          }
          // Kill in-flight iOS / Android deploy processes — their cwd and
          // build output paths point at projectA, so leaving them running
          // after a switch produces artifacts attributed to projectB.
          for (const peer of wss.clients) {
            if (peer.readyState !== WebSocket.OPEN) continue;
            iosDeployCancel(peer);
            androidDeployCancel(peer);
          }
          // PROJECT_CWD is global — every connected client now lives in the
          // new project. Clear per-ws scratch + restore team memory for ALL
          // peers, not just the sender. Otherwise iPhone keeps operating on
          // the OLD project's metrics/log/active-tasks until it reconnects,
          // and its agent dispatches grab the wrong project context.
          const newMemory = loadTeamMemory(PROJECT_CWD);
          // Different project may belong to a different account; force each
          // client to re-supply provider keys instead of leaking the prior
          // project's keys into a context they may not own.
          lastSeenDeepSeekKey = undefined;
          lastSeenKimiKey = undefined;
          for (const peer of wss.clients) {
            if (peer.readyState !== WebSocket.OPEN) continue;
            if (newMemory) clientProjectContext.set(peer, newMemory);
            else clientProjectContext.delete(peer);
            clientGameState.delete(peer);
            getCommLog(peer).length = 0;
            getMetrics(peer).clear();
            getActiveTasks(peer).clear();
            getAgentMap(peer).clear();
            getEmittedTools(peer).clear();
            clientDeepSeekKey.delete(peer);
            clientKimiKey.delete(peer);
            // In-flight flags reset because we just cancelled every running
            // agent above. Without these resets a peer's manager appears
            // busy forever (manager_busy guard never lifts) and the
            // first message after switch can be silently swallowed.
            clientSentAssistantMessage.delete(peer);
            managerBusy.delete(peer);
            // Tool-use → agent map is keyed by tool_use_id from the OLD
            // project's running agents; nothing in it is reachable now.
            toolUseIdToAgent.get(peer)?.clear();
            // Activity ring is the UI log for the prior project.
            clientQueryActivities.get(peer)?.splice(0);
            // Re-init every peer so their UI re-syncs to the new project.
            send(peer, {
              type: "init",
              sessionId: currentSessionId ?? "pending",
              agents: agentInfoForClient(peer),
              workingDirectory: PROJECT_CWD,
            });
            sendTraits(peer);
            // Push the new project's roster + facilitator output so peers
            // don't keep the prior project's UI state until first reload.
            if (latestFullGameState) {
              send(peer, {
                type: "game_state_sync",
                fullState: latestFullGameState,
                stateUpdatedAt: latestStateUpdatedAt,
              } as any);
              try {
                const parsed = JSON.parse(latestFullGameState) as { instances?: Record<string, unknown> };
                if (parsed.instances) clientGameState.set(peer, parsed as GameStateData);
              } catch { /* malformed blob; let next set_game_state seed it */ }
            }
            if (latestFacilitatorOutput) {
              send(peer, { type: "facilitator_output_sync", ...(latestFacilitatorOutput as object) } as any);
            }
          }
          sendDebug(ws, "info", "project", `Switched to: ${newPath}`);
          // Refresh chat history view for everyone — it just changed.
          broadcastAll(chatHistory.snapshot());
          break;
        }

        case "set_project_context": {
          const memories = (msg as { type: "set_project_context"; memories: string }).memories;
          setTeamMemoryEverywhere(memories);
          saveTeamMemory(PROJECT_CWD, memories);
          dbg("info", "project", `Project memory set (${memories.length} chars)`);
          sendDebug(ws, "info", "project", `Team memory loaded (${memories.length} chars)`);
          break;
        }

        // ─── Game economy ──────────────────────────────────────────────────

        case "set_game_state": {
          const gs: GameStateData = { instances: msg.instances };

          // Stash any newly-arrived API keys before validating so an
          // instance whose key arrives in the same message is accepted.
          // Propagate to every peer ws too: the keys identify the *user*
          // (this server is single-tenant, no auth boundary). Otherwise
          // Mac types the key, hires a deepseek agent → broadcast lands
          // on iPhone, but iPhone's `clientDeepSeekKey[ws]` is empty so
          // iPhone's first dispatch to that agent fails server-side.
          // Don't overwrite a peer's existing key — they may have typed
          // their own in Settings; let an explicit local entry win.
          if (msg.deepseekApiKey) {
            clientDeepSeekKey.set(ws, msg.deepseekApiKey);
            lastSeenDeepSeekKey = msg.deepseekApiKey;
            for (const peer of wss.clients) {
              if (peer === ws || peer.readyState !== WebSocket.OPEN) continue;
              if (!clientDeepSeekKey.has(peer)) clientDeepSeekKey.set(peer, msg.deepseekApiKey);
            }
          }
          if (msg.kimiApiKey) {
            clientKimiKey.set(ws, msg.kimiApiKey);
            lastSeenKimiKey = msg.kimiApiKey;
            for (const peer of wss.clients) {
              if (peer === ws || peer.readyState !== WebSocket.OPEN) continue;
              if (!clientKimiKey.has(peer)) clientKimiKey.set(peer, msg.kimiApiKey);
            }
          }

          // Pre-validate the payload — bad role types, two managers,
          // out-of-range stats, or non-Claude hires without a session key
          // are rejected up front. The user gets a clear, structured
          // error instead of a cryptic dispatch-time failure.
          const validation = validateGameState(gs, {
            hasDeepseekKey: !!clientDeepSeekKey.get(ws),
            hasKimiKey: !!clientKimiKey.get(ws),
          });
          if (!validation.ok) {
            send(ws, { type: "set_game_state_error", errors: validation.errors });
            dbg(
              "warn",
              "game",
              `Rejected set_game_state: ${validation.errors.length} validation error(s)`,
            );
            for (const e of validation.errors) {
              dbg("warn", "game", `  ${e.code} on ${e.instanceId}: ${e.message}`);
            }
            break;
          }

          // Diff against the previous accepted roster so we can clean up
          // any in-flight bookkeeping for instances that just got fired.
          const prevState = clientGameState.get(ws);
          const fired = firedInstanceIds(prevState, gs);

          clientGameState.set(ws, gs);

          if (fired.length > 0) {
            const tasks = activeAgentTasks.get(ws);
            for (const id of fired) {
              tasks?.delete(id);
              send(ws, { type: "agent_fired", instanceId: id });
              dbg("info", "game", `Fired instance ${id}; cleared in-flight bookkeeping`);
            }
          }

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
              // Mirror the new roster into EVERY peer's clientGameState so
              // their server-side dispatch/validation paths don't read a
              // stale roster after another device hires/fires. The sender's
              // entry was already updated above (line: `clientGameState.set(ws, gs)`).
              for (const peer of wss.clients) {
                if (peer === ws) continue;
                if (peer.readyState !== WebSocket.OPEN) continue;
                clientGameState.set(peer, gs);
              }
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

        // ─── Facilitator System ──────────────────────────────────────────

        case "facilitator_start": {
          const parsed = parseFacilitatorStart(msg);
          if (!parsed.ok) {
            sendDebug(ws, "warn", "facilitator", `Bad start payload: ${parsed.error}`);
            send(ws, {
              type: "facilitator_error",
              error: parsed.error,
              code: "unknown",
            } as any);
            break;
          }
          // Kick off the team-reaction scene in parallel with seed generation.
          // Reactions are decorative — failure is swallowed inside the helper,
          // so we never await rejection and never block the seed pipeline.
          const reactionsPromise = generateTeamReactions(
            {
              projectDescription: parsed.value.projectDescription,
              validRoles: Object.keys(roleCatalog),
              projectPath: PROJECT_CWD,
            },
            { caller: callClaude, runOptions: { timeoutMs: 30_000, retries: 0 } },
          )
            .then((reactions) => {
              if (reactions.length === 0) return;
              applyReactionsToChat(chatHistory, reactions, new Date().toISOString());
              chatHistory.save(historyFilePath(PROJECT_CWD));
              broadcastAll(chatHistory.snapshot());
              dbg(
                "info",
                "facilitator",
                `Team reactions: ${reactions.map((r) => r.role).join(", ")}`,
              );
            })
            .catch(() => {
              // Defensive: generateTeamReactions never throws, but belt-and-braces.
            });

          const result = await handleFacilitatorStart(
            facilitatorRunner,
            PROJECT_CWD,
            parsed.value,
          );
          // Make sure reactions land in chat history before we close the handler,
          // even if the seed itself raced ahead. Non-blocking for the user
          // because broadcasts already happened above.
          await reactionsPromise;
          if (!result.ok) {
            sendDebug(ws, "error", "facilitator", `Seed failed (${result.code}): ${result.error}`);
            send(ws, {
              type: "facilitator_error",
              error: result.error,
              code: result.code,
            } as any);
            break;
          }
          dbg(
            "info",
            "facilitator",
            `Seeded "${parsed.value.style.id}" → ${result.seed.outputFormat} (${result.seed.outputJson.length}B)`,
          );
          // Distil project memory from the brief so EVERY agent prompt
          // (now and after reconnect) has grounding. Without this the
          // chat path runs `clientProjectContext.get(ws) → undefined`
          // and the agent literally asks "what project are we in?" mid-
          // conversation. Persist to team_memory.txt so reconnects on
          // any device pick it up via the on-connect loadTeamMemory.
          const projectMemory = deriveProjectMemoryFromBrief(
            parsed.value.projectDescription,
          );
          setTeamMemoryEverywhere(projectMemory);
          saveTeamMemory(PROJECT_CWD, projectMemory);
          const facilitatorPayload = {
            styleId: parsed.value.style.id,
            finalScore: result.seed.finalScore,
            outputFormat: result.seed.outputFormat,
            outputJson: result.seed.outputJson,
          };
          send(ws, { type: "facilitator_seeded", ...facilitatorPayload } as any);
          // Persist and broadcast so other connected clients get it.
          latestFacilitatorOutput = facilitatorPayload;
          persistFacilitatorOutput();
          broadcastExcept(ws, { type: "facilitator_output_sync", ...facilitatorPayload } as any);
          break;
        }

        case "get_facilitator_output": {
          if (latestFacilitatorOutput) {
            send(ws, { type: "facilitator_output_sync", ...latestFacilitatorOutput } as any);
          }
          break;
        }

        case "get_tech_lead_pulse": {
          const limit = typeof msg.limit === "number" && msg.limit > 0 ? msg.limit : 20;
          send(ws, {
            type: "tech_lead_pulse",
            entries: techLeadDigest.recent(limit),
          } as ServerMessage);
          break;
        }

        case "push_facilitator_output": {
          // Client pushes its local output so the server can serve other devices.
          // Only accept if server has nothing — prevents stale client data from
          // overwriting a fresher seed.
          if (!latestFacilitatorOutput) {
            latestFacilitatorOutput = {
              styleId: "",
              finalScore: {},
              outputFormat: msg.outputFormat,
              outputJson: msg.outputJson,
            };
            persistFacilitatorOutput();
            dbg("info", "facilitator", `Accepted push_facilitator_output from client (${msg.outputJson.length}B)`);
            // Broadcast to all OTHER connected devices — this runs after server
            // restart when one device has local output and others are online
            // but haven't seeded yet.
            broadcastExcept(ws, {
              type: "facilitator_output_sync",
              ...latestFacilitatorOutput,
            } as any);
          }
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
          broadcastTraits();
          break;
        }

        case "remove_lesson": {
          const removed = removeLesson(PROJECT_CWD, traitStore, msg.lessonId);
          if (removed) {
            dbg("info", "traits", `Lesson removed: ${msg.lessonId}`);
            sendDebug(ws, "info", "traits", `Lesson removed: ${msg.lessonId}`);
          }
          broadcastTraits();
          break;
        }

        case "set_consent": {
          const { agentId, enabled } = msg;
          setConsent(PROJECT_CWD, traitStore, agentId, enabled);
          dbg("info", "traits", `Consent ${enabled ? "enabled" : "disabled"} for ${agentId}`);
          sendDebug(ws, "info", "traits", `Learning consent ${enabled ? "enabled" : "disabled"} for ${agentId}`);
          const consentMsg: ServerMessage = { type: "consent_state", consent: getAllConsent(traitStore) };
          for (const client of wss.clients) {
            if (client.readyState === WebSocket.OPEN) {
              send(client, consentMsg);
            }
          }
          break;
        }

        case "get_consent": {
          send(ws, { type: "consent_state", consent: getAllConsent(traitStore) });
          break;
        }

        case "get_reflection_kpi": {
          // Mirrors server/scripts/reflection-health.ts so the UI surface
          // and the CLI return byte-identical KPIs. Best-effort: if the log
          // is missing or unparseable, return zero counts with hasData=false.
          const windowDays = typeof msg.sinceDays === "number" ? msg.sinceDays : null;
          send(ws, buildReflectionKpiMessage(PROJECT_CWD, windowDays));
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

        case "android_deploy_watch_devices":
          androidDeployWatchDevices(ws).catch((err) => {
            sendAndroidDeployError(ws, `Watch devices failed: ${err}`);
          });
          break;

        case "android_deploy_unwatch_devices":
          androidDeployUnwatchDevices(ws);
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

          // Assign session mode: first identified client or reconnect of current primary → primary.
          // Everyone else → viewer.
          if (!activeSession || activeSession.clientId === info.clientId) {
            claimSession(ws);
            // Broadcast (not just self) — peers stuck in "viewer, no primary"
            // after a session_release need to learn who the new primary is.
            // Without this, their UI keeps showing stale session state until
            // the next primary handover or reconnect.
            broadcastSessionStatus();
          } else {
            send(ws, {
              type: "session_status",
              mode: "viewer",
              primaryDevice: activeSession.deviceName,
            } as any);
          }
          break;
        }

        // ─── Session presence ───────────────────────────────────────────
        case "session_claim": {
          if (isPrimary(ws)) break; // already primary
          if (!connectedClients.get(ws)) break;
          transferSession(ws);
          break;
        }

        case "session_release": {
          if (!isPrimary(ws)) break;
          activeSession = null;
          broadcastSessionStatus();
          break;
        }

        // ─── Active-agents control (Settings → "Активні агенти") ─────────
        case "list_active_agents": {
          send(ws, buildActiveAgentsMessage(ws));
          break;
        }

        case "cancel_dispatch_agent": {
          // C.2.6 — snapshot agentId BEFORE cancel because agent_runner's
          // explicit-cancel branch returns early without calling onError,
          // so handleSubAgentError (which would emit agent_status: idle)
          // never fires. Without this, chat-header indicator stays stuck
          // on whatever the last push status was (e.g. "running").
          const targetAgentId = agentRunner
            .getRunning()
            .find((r) => r.dispatchId === msg.dispatchId)?.agentId;
          const ok = agentRunner.cancel(msg.dispatchId);
          dbg("info", "cancel", `cancel_dispatch_agent ${msg.dispatchId} → ${ok}`);
          broadcastActiveAgents(ws);
          if (ok && targetAgentId) {
            send(ws, {
              type: "agent_status",
              agentId: targetAgentId,
              status: "idle",
              tools: [],
            });
          }
          break;
        }

        case "cancel_chat_query": {
          // chat_query cancel flows through runQuery's outer catch → emits
          // idle via the C.2.6 finally/catch patch. No extra emission needed
          // here; just the registry snapshot refresh.
          const ok = chatQueryRegistry.cancel(msg.queryId);
          dbg("info", "cancel", `cancel_chat_query ${msg.queryId} → ${ok}`);
          broadcastActiveAgents(ws);
          break;
        }

        case "cancel_all_active": {
          // C.2.6 — same explicit-cancel asymmetry as cancel_dispatch_agent.
          // Snapshot every affected agentId BEFORE cancellation so we can
          // emit idle for each. chat-side cancels propagate through
          // runQuery's catch and self-emit; the agentRunner side needs
          // the explicit follow-up here.
          const dispatchAgentIds = agentRunner
            .getRunning()
            .filter((r) => r.ws === ws)
            .map((r) => r.agentId);
          const sub = agentRunner.cancelAll(ws);
          const chat = chatQueryRegistry.cancelForWs(ws);
          dbg("info", "cancel", `cancel_all_active: sub=${sub ?? "?"} chat=${chat}`);
          broadcastActiveAgents(ws);
          for (const agentId of dispatchAgentIds) {
            send(ws, {
              type: "agent_status",
              agentId,
              status: "idle",
              tools: [],
            });
          }
          break;
        }

        // C.2 — client reconnect picks up runs that landed offline.
        // `sinceRunId === null/undefined` returns every known run; otherwise
        // only the strictly newer suffix. Reply is bounded by the store's
        // in-memory size, so the client should sliding-window if it grows.
        case "list_runs_since": {
          const runs = agentRunStore.since(msg.sinceRunId ?? null);
          send(ws, { type: "runs_since", runs } as ServerMessage);
          break;
        }

        case "get_usage_baselines": {
          // Pure analyzer — fed by the already-on-disk JSONL log. The read +
          // aggregate cost is bounded by `usage_log.jsonl` size (currently
          // unbounded — empirical baselines row in ROADMAP tracks adding a
          // rolling window if the file grows past a few MB).
          const entries = usageLogger.readAllEntries();
          const report = analyzeUsageBaselines(entries);
          send(ws, {
            type: "usage_baselines",
            generatedAt: report.generatedAt,
            totalEntries: report.totalEntries,
            buckets: report.buckets,
            health: report.health,
          } as ServerMessage);
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

  // Without this handler, network errors (ECONNRESET etc.) propagate as
  // uncaught exceptions and crash the entire server for one bad connection.
  ws.on("error", (err) => {
    const label = connectedClients.get(ws)?.deviceName ?? "unknown";
    dbg("warn", "ws", `WebSocket error from ${label}: ${err.message}`);
  });

  ws.on("close", () => {
    const clientInfo = connectedClients.get(ws);
    const disconnectLabel = clientInfo?.deviceName || "unknown";
    dbg("info", "ws", `Client disconnected: ${disconnectLabel} (${clientInfo?.platform ?? "?"}). Shared session: ${currentSessionId ?? "none"}`);
    // Drop NOT-YET-STARTED queued tasks for this client. Tasks that haven't
    // hit `runQuery` yet are pure intent and lose nothing by being cancelled
    // — the user can resubmit on reconnect with current context.
    const removed = taskQueue.removeForClient(ws);
    if (removed > 0) dbg("info", "queue", `Removed ${removed} queued tasks for disconnected client`);
    // C.2.1: do NOT cancel in-flight agents or chat queries on disconnect.
    // The work runs server-side and persists via chatHistory; on reconnect
    // the client receives the full snapshot via sendChatHistory(). Explicit
    // cancel stays available through the "Активні агенти" Settings tab
    // (cancel_dispatch_agent / cancel_chat_query / cancel_all_active).
    androidDeployUnwatchDevices(ws);
    // Disconnecting client may have an iOS/Android deploy in flight; the
    // child process is keyed on this ws and there's nobody left to cancel
    // it via UI. Without these calls the build keeps running orphaned and
    // its temp artifacts pile up under ~/.pixelcode until next restart.
    iosDeployCancel(ws);
    androidDeployCancel(ws);
    heartbeatMonitor.onDisconnect(ws);
    connectedClients.delete(ws);
    // Session presence: if primary disconnected, promote a viewer
    if (activeSession?.ws === ws) handlePrimaryDisconnect();
  });
});
