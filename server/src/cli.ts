/**
 * PixelCode server CLI: start / stop / restart / status / logs / config.
 *
 * `start` boots the always-on launcher daemon (`launcher.ts`), which in turn
 * supervises server.ts. The launcher exposes /launcher/* on its own port for
 * remote start/stop/restart even when the server is offline; admin UIs and
 * the Flutter app rely on this.
 *
 * The remaining commands are thin HTTP clients. `stop` and `restart` prefer
 * /launcher/* (more reliable when the server is hung) and fall back to
 * /admin/api/* if the launcher isn't reachable. `status`, `logs`, `config`
 * still talk to /admin/api/* on the running server.
 */

import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { request as httpRequest } from "node:http";
import {
  loadConfig,
  updateConfigFile,
  defaultConfigPath,
  validatePatch,
  type ServerConfig,
} from "./config.js";
import { runLauncher } from "./launcher.js";

// ─── Argv parsing ───────────────────────────────────────────────────────────

interface ParsedArgs {
  command: string;
  positional: string[];
  flags: Record<string, string | boolean>;
}

function parseArgv(argv: string[]): ParsedArgs {
  const command = argv[2] ?? "help";
  const rest = argv.slice(3);
  const positional: string[] = [];
  const flags: Record<string, string | boolean> = {};
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (arg.startsWith("--") || arg.startsWith("-")) {
      const eq = arg.indexOf("=");
      if (eq !== -1) {
        flags[arg.slice(0, eq).replace(/^-+/, "")] = arg.slice(eq + 1);
      } else {
        const next = rest[i + 1];
        const isValue = next !== undefined && !next.startsWith("-");
        if (isValue) {
          flags[arg.replace(/^-+/, "")] = next;
          i++;
        } else {
          flags[arg.replace(/^-+/, "")] = true;
        }
      }
    } else {
      positional.push(arg);
    }
  }
  return { command, positional, flags };
}

// ─── HTTP client to /admin/api/* ────────────────────────────────────────────

function adminPort(args: ParsedArgs): number {
  const flagPort = typeof args.flags.port === "string" ? parseInt(args.flags.port, 10) : NaN;
  if (Number.isFinite(flagPort) && flagPort > 0) return flagPort;
  const configPath = typeof args.flags.config === "string" ? args.flags.config : undefined;
  const cfg = loadConfig({ configPath });
  return cfg.effective.port;
}

function launcherPort(args: ParsedArgs): number {
  const flagPort = typeof args.flags["launcher-port"] === "string"
    ? parseInt(args.flags["launcher-port"], 10) : NaN;
  if (Number.isFinite(flagPort) && flagPort > 0) return flagPort;
  const configPath = typeof args.flags.config === "string" ? args.flags.config : undefined;
  const cfg = loadConfig({ configPath });
  return cfg.effective.launcherPort;
}

interface AdminCallOptions {
  method: "GET" | "POST";
  path: string;
  port: number;
  body?: unknown;
}

function callAdmin<T = unknown>(opts: AdminCallOptions): Promise<{ status: number; body: T }> {
  return new Promise((res, rej) => {
    const payload = opts.body !== undefined ? JSON.stringify(opts.body) : undefined;
    const req = httpRequest(
      {
        host: "127.0.0.1",
        port: opts.port,
        method: opts.method,
        path: opts.path,
        headers: payload
          ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) }
          : {},
      },
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (c: Buffer) => chunks.push(c));
        response.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let body: unknown = text;
          try { body = text.length === 0 ? {} : JSON.parse(text); } catch { /* leave as text */ }
          res({ status: response.statusCode ?? 0, body: body as T });
        });
      },
    );
    req.on("error", rej);
    if (payload) req.write(payload);
    req.end();
  });
}

function failNotRunning(port: number, err: unknown): never {
  const msg = err instanceof Error ? err.message : String(err);
  console.error(`✗ Could not reach server at http://127.0.0.1:${port}`);
  console.error(`  ${msg}`);
  console.error(`  Hint: is it running? Try 'pixelcode-server start' (or pass --port).`);
  process.exit(2);
}

// ─── Commands ───────────────────────────────────────────────────────────────

async function cmdStart(args: ParsedArgs): Promise<void> {
  const here = dirname(fileURLToPath(import.meta.url));
  const serverEntry = resolve(here, "server.ts");
  const tsxBin = resolve(here, "..", "node_modules", ".bin", "tsx");

  const cfg = loadConfig({
    configPath: typeof args.flags.config === "string" ? args.flags.config : undefined,
  });

  const portFlag = typeof args.flags.port === "string" ? parseInt(args.flags.port, 10) : NaN;
  const launcherPortFlag = typeof args.flags["launcher-port"] === "string"
    ? parseInt(args.flags["launcher-port"], 10) : NaN;
  const serverPort = Number.isFinite(portFlag) ? portFlag : cfg.effective.port;
  const launcherPort = Number.isFinite(launcherPortFlag) ? launcherPortFlag : cfg.effective.launcherPort;

  // Pass through the same flags to server.ts so it loads the right config.
  const serverArgs: string[] = [];
  if (Number.isFinite(portFlag)) serverArgs.push("--port", String(portFlag));
  if (typeof args.flags.cwd === "string") serverArgs.push("--cwd", args.flags.cwd);
  if (typeof args.flags["project-cwd"] === "string") serverArgs.push("--cwd", String(args.flags["project-cwd"]));
  if (typeof args.flags.config === "string") serverArgs.push("--config", args.flags.config);
  if (typeof args.flags["ota-hostname"] === "string") serverArgs.push("--ota-hostname", String(args.flags["ota-hostname"]));

  const autostart = args.flags["no-autostart"] !== true;

  console.log(`⚙️  Launcher port: ${launcherPort}   Server port: ${serverPort}   Autostart: ${autostart}`);

  runLauncher({
    launcherPort,
    serverPort,
    serverEntry,
    tsxBin,
    serverArgs,
    autostart,
  });
}

async function cmdStatus(args: ParsedArgs): Promise<void> {
  const port = adminPort(args);
  let res;
  try {
    res = await callAdmin<{
      pid: number; uptimeMs: number; bootedAt: string;
      config: ServerConfig; configPath: string;
      envOverrides: string[]; flagOverrides: string[];
      clients: number; mdnsActive: boolean; tailscaleUrl: string | null;
    }>({ method: "GET", path: "/admin/api/status", port });
  } catch (err) { failNotRunning(port, err); }
  if (res.status !== 200) {
    console.error(`HTTP ${res.status}`);
    console.error(JSON.stringify(res.body, null, 2));
    process.exit(1);
  }
  const s = res.body;
  const fmtSrc = (k: keyof ServerConfig) => {
    if (s.flagOverrides.includes(k)) return " (flag)";
    if (s.envOverrides.includes(k)) return " (env)";
    return "";
  };
  console.log(`✓ Running on :${s.config.port}${fmtSrc("port")}`);
  console.log(`  PID:        ${s.pid}`);
  console.log(`  Uptime:     ${Math.floor(s.uptimeMs / 1000)}s`);
  console.log(`  Booted:     ${s.bootedAt}`);
  console.log(`  cwd:        ${s.config.projectCwd}${fmtSrc("projectCwd")}`);
  console.log(`  OTA host:   ${s.config.otaHostname ?? "(auto)"}${fmtSrc("otaHostname")}`);
  console.log(`  Clients:    ${s.clients}`);
  console.log(`  mDNS:       ${s.mdnsActive ? "active" : "inactive"}`);
  console.log(`  Tailscale:  ${s.tailscaleUrl ?? "—"}`);
  console.log(`  Config:     ${s.configPath}`);
  console.log(`  Admin UI:   http://localhost:${s.config.port}/admin/`);
}

async function cmdStopOrRestart(args: ParsedArgs, action: "stop" | "restart"): Promise<void> {
  // Prefer the launcher (works even when server.ts is hung). Fall back to
  // /admin/api/* for installations that started server.ts without the launcher.
  const lp = launcherPort(args);
  try {
    const res = await callAdmin<{ ok?: boolean; error?: string; ready?: boolean }>({
      method: "POST",
      path: `/launcher/${action}`,
      port: lp,
      body: {},
    });
    if (res.status >= 200 && res.status < 300) {
      console.log(`✓ ${action} via launcher (:${lp})`);
      return;
    }
    console.error(`✗ launcher HTTP ${res.status}: ${res.body.error ?? "unknown error"}`);
    process.exit(1);
  } catch {
    // Launcher unreachable — fall back to talking to the server directly.
  }
  const port = adminPort(args);
  try {
    const res = await callAdmin<{ ok?: boolean; error?: string }>({
      method: "POST",
      path: `/admin/api/${action}`,
      port,
      body: {},
    });
    if (res.status >= 200 && res.status < 300) {
      console.log(`✓ ${action} via /admin/api/* (:${port}) — launcher (:${lp}) unreachable`);
    } else {
      console.error(`✗ HTTP ${res.status}: ${res.body.error ?? "unknown error"}`);
      process.exit(1);
    }
  } catch (err) {
    console.error(`✗ Could not reach launcher (:${lp}) or server (:${port})`);
    console.error(`  ${err instanceof Error ? err.message : String(err)}`);
    console.error(`  Hint: launch the launcher with 'pixelcode-server start'.`);
    process.exit(2);
  }
}

async function cmdLogs(args: ParsedArgs): Promise<void> {
  const port = adminPort(args);
  const n = typeof args.flags.n === "string" ? parseInt(args.flags.n, 10)
    : typeof args.flags.limit === "string" ? parseInt(args.flags.limit, 10) : 200;
  let res;
  try {
    res = await callAdmin<{ entries: Array<{ timestamp: string; level: string; category: string; message: string }> }>({
      method: "GET",
      path: `/admin/api/logs?n=${n}`,
      port,
    });
  } catch (err) { failNotRunning(port, err); }
  for (const e of res.body.entries) {
    const ts = e.timestamp.slice(11, 23);
    const tag = { debug: "🔍", info: "ℹ️ ", warn: "⚠️ ", error: "❌" }[e.level] ?? "  ";
    console.log(`${ts} ${tag} [${e.category}] ${e.message}`);
  }
}

async function cmdConfig(args: ParsedArgs): Promise<void> {
  const sub = args.positional[0] ?? "show";
  const configPath = typeof args.flags.config === "string" ? args.flags.config : defaultConfigPath();
  if (sub === "path") {
    console.log(configPath);
    return;
  }
  if (sub === "show") {
    const src = loadConfig({ configPath });
    console.log(`Config file: ${src.filePath}`);
    console.log(`File contents:`);
    console.log(JSON.stringify(src.fromFile, null, 2));
    const overrides: string[] = [];
    for (const k of Object.keys(src.envOverrides)) overrides.push(`  ${k}: ENV override active`);
    for (const k of Object.keys(src.flagOverrides)) overrides.push(`  ${k}: FLAG override active`);
    if (overrides.length > 0) {
      console.log(`Effective overrides for current shell:`);
      console.log(overrides.join("\n"));
    }
    return;
  }
  if (sub === "set") {
    const key = args.positional[1];
    const value = args.positional[2];
    if (!key || value === undefined) {
      console.error(`Usage: pixelcode-server config set <key> <value>`);
      console.error(`  Keys: port | launcherPort | projectCwd | otaHostname (use '' to clear)`);
      process.exit(1);
    }
    const raw: Record<string, unknown> =
      key === "port" ? { port: parseInt(value, 10) }
      : key === "launcherPort" ? { launcherPort: parseInt(value, 10) }
      : key === "projectCwd" ? { projectCwd: value }
      : key === "otaHostname" ? { otaHostname: value === "" ? null : value }
      : { [key]: value };
    let patch;
    try {
      patch = validatePatch(raw);
    } catch (err) {
      console.error(`✗ ${(err as Error).message}`);
      process.exit(1);
    }
    const next = updateConfigFile(configPath, patch);
    console.log(`✓ Wrote ${configPath}`);
    console.log(JSON.stringify(next, null, 2));
    // Best-effort: also push to a running server so non-restart-required
    // changes apply immediately. We always read the current file's port for this.
    const port = loadConfig({ configPath }).effective.port;
    try {
      const res = await callAdmin({
        method: "POST", path: "/admin/api/config", port, body: patch,
      });
      if (res.status >= 200 && res.status < 300) {
        console.log(`  (also synced to running server on :${port})`);
      }
    } catch { /* server not running; that's fine */ }
    return;
  }
  console.error(`Unknown config subcommand: ${sub}`);
  console.error(`Usage: pixelcode-server config [show|set <k> <v>|path]`);
  process.exit(1);
}

function printHelp(): void {
  console.log(`PixelCode server CLI

Usage: pixelcode-server <command> [options]

Commands:
  start [--port N] [--launcher-port N] [--cwd DIR] [--config FILE]
        [--no-autostart]
                       Boot the launcher daemon. The launcher binds
                       /launcher/* on its own port and supervises server.ts;
                       it respawns server.ts on exit-code 75 (the value the
                       /restart endpoints emit). Pass --no-autostart to
                       leave the server idle until POST /launcher/start.
  stop                 Stop the server. Tries /launcher/stop first
                       (reliable when server is hung), then falls back to
                       /admin/api/stop.
  restart              Restart the server, with the same fallback chain.
  status               Print runtime info from /admin/api/status.
  logs [-n N]          Print the last N (default 200) log lines.
  config show          Show the persisted config file.
  config set <k> <v>   Write a key to the config file (port|projectCwd|otaHostname).
  config path          Print the config file path.

Common options:
  --port N        Talk to / launch on this port (overrides config + env).
  --config PATH   Use this config file instead of ${defaultConfigPath()}.

The admin HTTP API ('/admin/*' on the same port) is loopback-only.
`);
}

// ─── Entry ──────────────────────────────────────────────────────────────────

(async () => {
  const args = parseArgv(process.argv);
  switch (args.command) {
    case "start":   await cmdStart(args); break;
    case "stop":    await cmdStopOrRestart(args, "stop"); break;
    case "restart": await cmdStopOrRestart(args, "restart"); break;
    case "status":  await cmdStatus(args); break;
    case "logs":    await cmdLogs(args); break;
    case "config":  await cmdConfig(args); break;
    case "help":
    case "--help":
    case "-h":      printHelp(); break;
    default:
      console.error(`Unknown command: ${args.command}\n`);
      printHelp();
      process.exit(1);
  }
})().catch((err) => {
  console.error(`✗ ${err instanceof Error ? err.stack ?? err.message : err}`);
  process.exit(1);
});
