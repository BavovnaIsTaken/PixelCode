/**
 * Always-on launcher / supervisor daemon.
 *
 * Runs as the parent of `pixelcode-server start`. Owns:
 *   1. The child server process (spawn / kill / respawn-on-75).
 *   2. An HTTP control surface at `/launcher/*` on its own port (default 9719,
 *      loopback-only).
 *
 * The Flutter admin app (and the CLI) talk to /launcher/* to start, stop,
 * restart, and tail boot logs of the server — even when the server itself
 * is offline. /admin/* on the server stays as the fast path for
 * config-edits and runtime status while the server is alive.
 *
 * Exit-code semantics (preserved from the previous CLI supervisor):
 *   75       → server requested restart; launcher respawns it.
 *   0        → clean shutdown; do not respawn (treated as "user stop").
 *   anything → crash; record exit code, do not respawn (surface in /status).
 */

import { spawn, exec, type ChildProcess } from "child_process";
import { createServer, type IncomingMessage, type ServerResponse } from "http";
import { request as httpRequest } from "http";
import { resolve } from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const RESTART_EXIT_CODE = 75;
const READINESS_TIMEOUT_MS = 15_000;
const READINESS_POLL_MS = 200;
const STOP_GRACE_MS = 5_000;
const BOOT_LOG_CAP = 400;

export interface LauncherOptions {
  /** Port the launcher's HTTP API binds to. */
  launcherPort: number;
  /** Port the spawned server binds to (used for readiness probe). */
  serverPort: number;
  /** Absolute path to server.ts (the spawn target). */
  serverEntry: string;
  /** Absolute path to tsx binary (since we run TypeScript without a build step). */
  tsxBin: string;
  /** Args to pass to the spawned server (e.g. --cwd, --config). */
  serverArgs: string[];
  /** Whether to spawn the server on launcher boot (default true). */
  autostart: boolean;
}

interface BootLogLine {
  stream: "stdout" | "stderr";
  ts: string;
  line: string;
}

type LauncherPhase = "idle" | "starting" | "running" | "stopping" | "crashed";

interface LauncherState {
  phase: LauncherPhase;
  child: ChildProcess | null;
  startedAt: Date | null;
  exitedAt: Date | null;
  lastExitCode: number | null;
  lastSignal: NodeJS.Signals | null;
  /** Ring buffer of recent child stdout/stderr lines (since the last spawn). */
  bootLog: BootLogLine[];
  /** True if a /stop or /restart originated the most recent shutdown — suppresses
   *  auto-respawn (which only triggers on exit-code 75 anyway). */
  intentionalStop: boolean;
  /** Resolved when the current child has fully exited (used for /restart sequencing). */
  exitWaiter: Promise<void> | null;
}

export function runLauncher(opts: LauncherOptions): void {
  const state: LauncherState = {
    phase: "idle",
    child: null,
    startedAt: null,
    exitedAt: null,
    lastExitCode: null,
    lastSignal: null,
    bootLog: [],
    intentionalStop: false,
    exitWaiter: null,
  };

  const log = (msg: string): void => {
    const ts = new Date().toISOString().slice(11, 23);
    console.log(`${ts} ⚙️  [launcher] ${msg}`);
  };

  const pushBoot = (stream: "stdout" | "stderr", chunk: string): void => {
    const ts = new Date().toISOString();
    for (const raw of chunk.split(/\r?\n/)) {
      if (!raw) continue;
      state.bootLog.push({ stream, ts, line: raw });
      if (state.bootLog.length > BOOT_LOG_CAP) state.bootLog.shift();
    }
  };

  // ─── Child lifecycle ────────────────────────────────────────────────────

  const probeServer = (): Promise<boolean> =>
    new Promise((res) => {
      const req = httpRequest(
        { host: "127.0.0.1", port: opts.serverPort, method: "GET", path: "/admin/api/status" },
        (response) => {
          response.resume();
          res((response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 500);
        },
      );
      req.on("error", () => res(false));
      req.setTimeout(1500, () => { req.destroy(); res(false); });
      req.end();
    });

  const waitUntilReady = async (): Promise<boolean> => {
    const deadline = Date.now() + READINESS_TIMEOUT_MS;
    while (Date.now() < deadline) {
      if (state.child === null) return false;
      if (await probeServer()) return true;
      await new Promise((r) => setTimeout(r, READINESS_POLL_MS));
    }
    return false;
  };

  const freeServerPort = (): Promise<void> =>
    new Promise((resolve) => {
      exec(`lsof -ti :${opts.serverPort}`, (_err, stdout) => {
        const pids = stdout.trim().split(/\s+/).filter(Boolean);
        if (pids.length === 0) { resolve(); return; }
        log(`port ${opts.serverPort} occupied by PID(s) ${pids.join(", ")} — evicting orphan…`);
        for (const pid of pids) {
          try { process.kill(parseInt(pid, 10), "SIGKILL"); } catch {}
        }
        setTimeout(resolve, 300);
      });
    });

  const spawnChild = (): { ok: boolean; reason?: string } => {
    if (state.child) return { ok: true };
    state.bootLog.length = 0;
    state.intentionalStop = false;
    state.phase = "starting";
    state.exitedAt = null;
    state.lastExitCode = null;
    state.lastSignal = null;

    const child = spawn(opts.tsxBin, [opts.serverEntry, ...opts.serverArgs], {
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    });

    state.child = child;
    state.startedAt = new Date();

    child.stdout?.on("data", (buf: Buffer) => {
      const text = buf.toString("utf8");
      process.stdout.write(text);
      pushBoot("stdout", text);
    });
    child.stderr?.on("data", (buf: Buffer) => {
      const text = buf.toString("utf8");
      process.stderr.write(text);
      pushBoot("stderr", text);
    });

    let exitResolve: () => void = () => {};
    state.exitWaiter = new Promise<void>((res) => { exitResolve = res; });

    child.on("exit", (code, signal) => {
      const wasIntentional = state.intentionalStop;
      state.child = null;
      state.exitedAt = new Date();
      state.lastExitCode = code;
      state.lastSignal = signal;
      log(`child exited code=${code} signal=${signal ?? "-"} intentional=${wasIntentional}`);
      exitResolve();

      if (code === RESTART_EXIT_CODE && !wasIntentional) {
        log("child requested restart (exit 75); respawning…");
        // Defer spawn so the OS can fully release the port.
        setTimeout(() => {
          const { ok, reason } = spawnChild();
          if (!ok) log(`respawn failed: ${reason}`);
        }, 250);
      } else if (code === 0 || wasIntentional) {
        state.phase = "idle";
      } else {
        state.phase = "crashed";
      }
    });

    state.phase = "starting";
    log(`spawned PID ${child.pid} on :${opts.serverPort}`);
    void (async () => {
      const ready = await waitUntilReady();
      if (state.child && ready) {
        state.phase = "running";
        log(`server is ready on :${opts.serverPort}`);
      } else if (state.child && !ready) {
        log(`server failed readiness probe within ${READINESS_TIMEOUT_MS}ms — leaving it; subsequent /status will reflect reachability`);
      }
    })();

    return { ok: true };
  };

  const stopChild = async (reason: string): Promise<{ ok: boolean; note?: string }> => {
    if (!state.child) return { ok: true, note: "not running" };
    state.intentionalStop = true;
    state.phase = "stopping";
    log(`stopping child (reason: ${reason})`);
    const child = state.child;
    const waiter = state.exitWaiter ?? Promise.resolve();
    child.kill("SIGTERM");

    const killed = await Promise.race([
      waiter.then(() => true),
      new Promise<boolean>((res) => setTimeout(() => res(false), STOP_GRACE_MS)),
    ]);
    if (!killed && state.child) {
      log(`SIGTERM grace expired (${STOP_GRACE_MS}ms); sending SIGKILL`);
      state.child.kill("SIGKILL");
      await state.exitWaiter;
    }
    return { ok: true };
  };

  // ─── HTTP surface ───────────────────────────────────────────────────────

  const isLoopback = (req: IncomingMessage): boolean => {
    const addr = req.socket.remoteAddress ?? "";
    return addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1" || addr.startsWith("127.");
  };

  const sendJson = (res: ServerResponse, status: number, body: unknown): void => {
    const payload = JSON.stringify(body);
    res.writeHead(status, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    });
    res.end(payload);
  };

  const handleStatus = (res: ServerResponse): void => {
    sendJson(res, 200, {
      launcher: {
        phase: state.phase,
        port: opts.launcherPort,
        pid: process.pid,
      },
      server: {
        running: state.child !== null,
        pid: state.child?.pid ?? null,
        port: opts.serverPort,
        startedAt: state.startedAt?.toISOString() ?? null,
        exitedAt: state.exitedAt?.toISOString() ?? null,
        lastExitCode: state.lastExitCode,
        lastSignal: state.lastSignal,
        bootLogCount: state.bootLog.length,
      },
    });
  };

  const currentPid = (): number | null => state.child?.pid ?? null;

  const handleStart = async (res: ServerResponse): Promise<void> => {
    if (state.child) {
      sendJson(res, 200, { ok: true, alreadyRunning: true, pid: currentPid() });
      return;
    }
    await freeServerPort();
    const { ok, reason } = spawnChild();
    if (!ok) {
      sendJson(res, 500, { ok: false, error: reason ?? "spawn failed" });
      return;
    }
    // Wait briefly for readiness so the response carries truthy state.
    const ready = await waitUntilReady();
    sendJson(res, ready ? 200 : 202, {
      ok: true,
      ready,
      pid: currentPid(),
      note: ready ? "server is up" : "server spawned; readiness probe still pending — see /launcher/logs",
    });
  };

  const handleStop = async (res: ServerResponse): Promise<void> => {
    const result = await stopChild("admin: launcher /stop");
    sendJson(res, 200, result);
  };

  const handleRestart = async (res: ServerResponse): Promise<void> => {
    if (state.child) await stopChild("admin: launcher /restart");
    const { ok, reason } = spawnChild();
    if (!ok) {
      sendJson(res, 500, { ok: false, error: reason ?? "spawn failed" });
      return;
    }
    const ready = await waitUntilReady();
    sendJson(res, ready ? 200 : 202, { ok: true, ready, pid: currentPid() });
  };

  const handleLogs = (req: IncomingMessage, res: ServerResponse): void => {
    const url = new URL(req.url ?? "/", "http://localhost");
    const limitRaw = url.searchParams.get("n") ?? "200";
    const limit = Math.max(1, Math.min(BOOT_LOG_CAP, parseInt(limitRaw, 10) || 200));
    const start = Math.max(0, state.bootLog.length - limit);
    sendJson(res, 200, { entries: state.bootLog.slice(start), capacity: BOOT_LOG_CAP });
  };

  const handler = async (req: IncomingMessage, res: ServerResponse): Promise<void> => {
    const rawUrl = req.url ?? "/";
    if (!rawUrl.startsWith("/launcher")) {
      sendJson(res, 404, { error: "this is the launcher daemon — use /launcher/* endpoints" });
      return;
    }
    if (!isLoopback(req)) {
      sendJson(res, 403, { error: "launcher endpoints are loopback-only" });
      return;
    }

    const url = new URL(rawUrl, "http://localhost");
    const path = url.pathname;
    const method = (req.method ?? "GET").toUpperCase();

    try {
      if (path === "/launcher" || path === "/launcher/" || path === "/launcher/status") {
        handleStatus(res);
        return;
      }
      if (path === "/launcher/start" && method === "POST") {
        await handleStart(res);
        return;
      }
      if (path === "/launcher/stop" && method === "POST") {
        await handleStop(res);
        return;
      }
      if (path === "/launcher/restart" && method === "POST") {
        await handleRestart(res);
        return;
      }
      if (path === "/launcher/logs" && method === "GET") {
        handleLogs(req, res);
        return;
      }
      sendJson(res, 404, { error: `unknown launcher endpoint: ${method} ${path}` });
    } catch (err) {
      sendJson(res, 500, { error: (err as Error).message });
    }
  };

  // ─── Boot ──────────────────────────────────────────────────────────────

  const httpServer = createServer((req, res) => { void handler(req, res); });

  httpServer.listen(opts.launcherPort, "127.0.0.1", () => {
    log(`HTTP API listening on http://127.0.0.1:${opts.launcherPort}/launcher/`);
    if (opts.autostart) {
      void freeServerPort().then(() => {
        const { ok, reason } = spawnChild();
        if (!ok) log(`autostart failed: ${reason}`);
      });
    } else {
      log("autostart disabled — server will idle until POST /launcher/start");
    }
  });

  httpServer.on("error", (err: NodeJS.ErrnoException) => {
    if (err.code === "EADDRINUSE") {
      console.error(`✗ launcher port :${opts.launcherPort} already in use — is another launcher running?`);
      console.error(`  Use --launcher-port to pick a different port, or stop the other instance.`);
      process.exit(1);
    }
    console.error(`✗ launcher HTTP error: ${err.message}`);
    process.exit(1);
  });

  // Forward signals to child but keep launcher alive a moment for graceful exit.
  const onSignal = (sig: NodeJS.Signals) => async () => {
    log(`received ${sig} — stopping child and exiting`);
    if (state.child) {
      state.intentionalStop = true;
      state.child.kill(sig);
      await Promise.race([
        state.exitWaiter ?? Promise.resolve(),
        new Promise((r) => setTimeout(r, 3000)),
      ]);
    }
    httpServer.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1500);
  };
  process.on("SIGINT", () => void onSignal("SIGINT")());
  process.on("SIGTERM", () => void onSignal("SIGTERM")());
}

// ─── Standalone entry (when imported directly via tsx) ──────────────────

const isMain = (() => {
  try {
    return resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1] ?? "");
  } catch { return false; }
})();

if (isMain) {
  // Lightweight argv parser shared with cli.ts shape (--launcher-port, --port, etc.)
  const argv = process.argv.slice(2);
  const flags: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const eq = arg.indexOf("=");
    if (eq !== -1) flags[arg.slice(0, eq).replace(/^-+/, "")] = arg.slice(eq + 1);
    else if (arg.startsWith("-")) {
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith("-")) {
        flags[arg.replace(/^-+/, "")] = next;
        i++;
      } else flags[arg.replace(/^-+/, "")] = "true";
    }
  }
  const here = dirname(fileURLToPath(import.meta.url));
  runLauncher({
    launcherPort: parseInt(flags["launcher-port"] ?? "9719", 10),
    serverPort: parseInt(flags.port ?? "9720", 10),
    serverEntry: resolve(here, "server.ts"),
    tsxBin: resolve(here, "..", "node_modules", ".bin", "tsx"),
    serverArgs: process.argv.slice(2),
    autostart: flags["no-autostart"] !== "true",
  });
}
