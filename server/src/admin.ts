/**
 * Admin HTTP surface for the standalone server: status, config edit,
 * restart/stop, recent logs.
 *
 * Bound to loopback only — when the server is exposed via Tailscale Funnel
 * the same port is reachable from the public internet, so we refuse remote
 * admin requests outright. The CLI and the native server-admin Flutter app
 * (running on macOS, talking to localhost) both hit these endpoints; iOS /
 * remote support will require an opt-in token + non-loopback exception, not
 * built yet.
 */

import type { IncomingMessage, ServerResponse } from "http";
import {
  loadConfig,
  updateConfigFile,
  validatePatch,
  patchRequiresRestart,
  defaultConfigPath,
  type ServerConfig,
} from "./config.js";
import type { ConnectedClientInfo } from "./protocol.js";

// ─── Log ring buffer ────────────────────────────────────────────────────────

export interface LogEntry {
  timestamp: string;
  level: "debug" | "info" | "warn" | "error";
  category: string;
  message: string;
}

const LOG_BUFFER_CAP = 500;
const logBuffer: LogEntry[] = [];

export function recordLog(entry: LogEntry): void {
  logBuffer.push(entry);
  if (logBuffer.length > LOG_BUFFER_CAP) logBuffer.shift();
}

export function recentLogs(limit: number): LogEntry[] {
  if (limit <= 0 || limit >= logBuffer.length) return logBuffer.slice();
  return logBuffer.slice(logBuffer.length - limit);
}

// ─── Admin handler context ──────────────────────────────────────────────────

export interface AdminContext {
  /** Path to the config file currently in use. */
  configPath: string;
  /** Effective config snapshot (file + env + flags merged). */
  getEffectiveConfig: () => ServerConfig;
  /** Where each config value came from — env / flag / file. */
  getConfigSources: () => {
    envOverrides: Array<keyof ServerConfig>;
    flagOverrides: Array<keyof ServerConfig>;
  };
  /** Number of currently connected WebSocket clients. */
  getClientCount: () => number;
  /** Snapshot of currently connected clients (for the admin UI). */
  getConnectedClients: () => ConnectedClientInfo[];
  /** mDNS advertisement state. */
  getMdnsActive: () => boolean;
  /** Tailscale Funnel URL (or null if not configured). */
  getTailscaleUrl: () => string | null;
  /** Pending tasks in the manager queue (size of TaskQueue). */
  getQueuedTaskCount: () => number;
  /** Currently running sub-agent dispatches. */
  getActiveAgentCount: () => number;
  /** Server boot time (ms epoch). */
  bootedAtMs: number;
  /**
   * Trigger a graceful exit. The CLI supervisor restarts the process on
   * exit-code 75; for `stop` we use 0.
   */
  scheduleExit: (code: number, reason: string) => void;
}

// ─── Metrics sampler ────────────────────────────────────────────────────────

interface CpuSample {
  /** process.cpuUsage() snapshot (microseconds, monotonically increasing). */
  usage: NodeJS.CpuUsage;
  /** Wall-clock ms at the sample time. */
  atMs: number;
}

let __lastCpuSample: CpuSample | null = null;

interface MetricsSnapshot {
  memory: {
    rss: number;
    heapUsed: number;
    heapTotal: number;
    external: number;
  };
  /** CPU percent over the interval since the previous sample. Null on first call. */
  cpuPercent: number | null;
  /** Cumulative CPU microseconds since process start. */
  cpuUserUs: number;
  cpuSystemUs: number;
  queuedTasks: number;
  activeAgents: number;
  nodeVersion: string;
  platform: string;
}

function sampleMetrics(ctx: AdminContext): MetricsSnapshot {
  const mem = process.memoryUsage();
  const usage = process.cpuUsage();
  const nowMs = Date.now();

  let cpuPercent: number | null = null;
  if (__lastCpuSample) {
    const elapsedMs = nowMs - __lastCpuSample.atMs;
    if (elapsedMs > 0) {
      const deltaUs =
        usage.user - __lastCpuSample.usage.user +
        (usage.system - __lastCpuSample.usage.system);
      // deltaUs is microseconds of CPU across N cores; elapsedMs * 1000 is the
      // wall-clock window in microseconds. Ratio = single-core utilisation.
      cpuPercent = (deltaUs / (elapsedMs * 1000)) * 100;
      if (cpuPercent < 0) cpuPercent = 0;
    }
  }
  __lastCpuSample = { usage, atMs: nowMs };

  return {
    memory: {
      rss: mem.rss,
      heapUsed: mem.heapUsed,
      heapTotal: mem.heapTotal,
      external: mem.external,
    },
    cpuPercent,
    cpuUserUs: usage.user,
    cpuSystemUs: usage.system,
    queuedTasks: ctx.getQueuedTaskCount(),
    activeAgents: ctx.getActiveAgentCount(),
    nodeVersion: process.version,
    platform: process.platform,
  };
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function isLoopback(req: IncomingMessage): boolean {
  const addr = req.socket.remoteAddress ?? "";
  return (
    addr === "127.0.0.1" ||
    addr === "::1" ||
    addr === "::ffff:127.0.0.1" ||
    addr.startsWith("127.")
  );
}

function sendJson(res: ServerResponse, status: number, body: unknown): void {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(payload);
}

function readBody(req: IncomingMessage, maxBytes = 64 * 1024): Promise<string> {
  return new Promise((resolve, reject) => {
    let total = 0;
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => {
      total += chunk.length;
      if (total > maxBytes) {
        reject(new Error("request body too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

// ─── Route handlers ─────────────────────────────────────────────────────────

function handleStatus(ctx: AdminContext, res: ServerResponse): void {
  const cfg = ctx.getEffectiveConfig();
  const sources = ctx.getConfigSources();
  sendJson(res, 200, {
    running: true,
    pid: process.pid,
    uptimeMs: Date.now() - ctx.bootedAtMs,
    bootedAt: new Date(ctx.bootedAtMs).toISOString(),
    config: cfg,
    configPath: ctx.configPath,
    envOverrides: sources.envOverrides,
    flagOverrides: sources.flagOverrides,
    clients: ctx.getClientCount(),
    mdnsActive: ctx.getMdnsActive(),
    tailscaleUrl: ctx.getTailscaleUrl(),
    nodeVersion: process.version,
    platform: process.platform,
    metrics: sampleMetrics(ctx),
  });
}

function handleGetConfig(ctx: AdminContext, res: ServerResponse): void {
  const source = loadConfig({ configPath: ctx.configPath });
  sendJson(res, 200, {
    file: source.fromFile,
    effective: source.effective,
    configPath: ctx.configPath,
    envOverrides: Object.keys(source.envOverrides),
    flagOverrides: Object.keys(source.flagOverrides),
  });
}

async function handlePostConfig(
  ctx: AdminContext,
  req: IncomingMessage,
  res: ServerResponse,
): Promise<void> {
  let raw: string;
  try {
    raw = await readBody(req);
  } catch (err) {
    sendJson(res, 400, { error: (err as Error).message });
    return;
  }
  let parsed: unknown;
  try {
    parsed = raw.length === 0 ? {} : JSON.parse(raw);
  } catch (err) {
    sendJson(res, 400, { error: `invalid JSON: ${(err as Error).message}` });
    return;
  }
  let patch;
  try {
    patch = validatePatch(parsed);
  } catch (err) {
    sendJson(res, 400, { error: (err as Error).message });
    return;
  }
  const updated = updateConfigFile(ctx.configPath, patch);
  sendJson(res, 200, {
    ok: true,
    file: updated,
    restartRequired: patchRequiresRestart(patch),
    note: "Saved to config file. Env/flag overrides remain in effect for the running process.",
  });
}

function handleClients(ctx: AdminContext, res: ServerResponse): void {
  sendJson(res, 200, { clients: ctx.getConnectedClients() });
}

function handleLogs(req: IncomingMessage, res: ServerResponse): void {
  const url = new URL(req.url ?? "/", "http://localhost");
  const limitRaw = url.searchParams.get("n") ?? url.searchParams.get("limit") ?? "200";
  const limit = Math.max(1, Math.min(LOG_BUFFER_CAP, parseInt(limitRaw, 10) || 200));
  sendJson(res, 200, { entries: recentLogs(limit), capacity: LOG_BUFFER_CAP });
}

function handleRestart(ctx: AdminContext, res: ServerResponse): void {
  sendJson(res, 202, {
    ok: true,
    note: "Server will exit with code 75 (supervisor restart). If launched without the supervisor, it will simply stop.",
  });
  ctx.scheduleExit(75, "admin: restart requested");
}

function handleStop(ctx: AdminContext, res: ServerResponse): void {
  sendJson(res, 202, { ok: true, note: "Server is shutting down." });
  ctx.scheduleExit(0, "admin: stop requested");
}

// ─── Public entry point ─────────────────────────────────────────────────────

export interface AdminHandlerResult {
  /** True if the request was an /admin/* path and the response was sent. */
  handled: boolean;
}

/**
 * Try to serve `req` as an admin request. Returns `{ handled: true }` if the
 * URL began with /admin and we wrote a response — caller should bail out.
 * Returns `{ handled: false }` if the URL is not under /admin and the caller
 * should fall through to its normal handler.
 */
export async function handleAdminRequest(
  ctx: AdminContext,
  req: IncomingMessage,
  res: ServerResponse,
): Promise<AdminHandlerResult> {
  const rawUrl = req.url ?? "/";
  if (!rawUrl.startsWith("/admin")) return { handled: false };

  if (!isLoopback(req)) {
    sendJson(res, 403, {
      error: "admin endpoints are loopback-only — connect via http://localhost:" +
        ctx.getEffectiveConfig().port + "/admin/",
    });
    return { handled: true };
  }

  const url = new URL(rawUrl, "http://localhost");
  const path = url.pathname;
  const method = (req.method ?? "GET").toUpperCase();

  if (path === "/admin" || path === "/admin/" || path === "/admin/index.html") {
    sendJson(res, 200, {
      ok: true,
      hint: "Admin HTTP API only — no web UI. Use the server_admin Flutter app or the pixelcode-server CLI.",
      endpoints: [
        "GET /admin/api/status",
        "GET /admin/api/config",
        "POST /admin/api/config",
        "GET /admin/api/clients",
        "POST /admin/api/restart",
        "POST /admin/api/stop",
        "GET /admin/api/logs?n=N",
      ],
    });
    return { handled: true };
  }

  if (path === "/admin/api/status" && method === "GET") {
    handleStatus(ctx, res);
    return { handled: true };
  }
  if (path === "/admin/api/config" && method === "GET") {
    handleGetConfig(ctx, res);
    return { handled: true };
  }
  if (path === "/admin/api/config" && method === "POST") {
    await handlePostConfig(ctx, req, res);
    return { handled: true };
  }
  if (path === "/admin/api/clients" && method === "GET") {
    handleClients(ctx, res);
    return { handled: true };
  }
  if (path === "/admin/api/logs" && method === "GET") {
    handleLogs(req, res);
    return { handled: true };
  }
  if (path === "/admin/api/restart" && method === "POST") {
    handleRestart(ctx, res);
    return { handled: true };
  }
  if (path === "/admin/api/stop" && method === "POST") {
    handleStop(ctx, res);
    return { handled: true };
  }

  sendJson(res, 404, { error: `unknown admin endpoint: ${method} ${path}` });
  return { handled: true };
}

export { defaultConfigPath };
