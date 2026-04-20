/**
 * Network diagnostic checks and auto-fixes for the server.
 *
 * Each check returns a HealthItem describing current state and whether a
 * safe auto-fix is available. The UI renders these in Settings → Мережа.
 */

import { execFile } from "child_process";
import { existsSync } from "fs";
import type { HealthItem, HealthItemId } from "./protocol.js";

export interface HealthContext {
  /** Port the server is listening on (used to verify funnel binding). */
  serverPort: number;
  /** True if the HTTP/WS server is currently listening. */
  serverListening: boolean;
  /** True if the Bonjour/mDNS provider is currently active. */
  mdnsActive: boolean;
  /** Called to restart Bonjour registration from outside. Returns true if successful. */
  restartMdns: () => Promise<boolean>;
}

// ─── Exec helpers ───────────────────────────────────────────────────────────

interface ExecResult {
  code: number | null;
  stdout: string;
  stderr: string;
}

function execAsync(binary: string, args: string[], timeoutMs = 5000): Promise<ExecResult> {
  return new Promise((resolve) => {
    execFile(binary, args, { timeout: timeoutMs }, (err, stdout, stderr) => {
      resolve({
        code: err && "code" in err && typeof err.code === "number" ? err.code : err ? 1 : 0,
        stdout: stdout?.toString() ?? "",
        stderr: stderr?.toString() ?? "",
      });
    });
  });
}

function findTailscale(): string | null {
  for (const p of ["/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/usr/bin/tailscale"]) {
    if (existsSync(p)) return p;
  }
  return null;
}

// ─── Individual checks ──────────────────────────────────────────────────────

async function checkTailscaleInstalled(): Promise<HealthItem> {
  const binary = findTailscale();
  if (binary) {
    return { id: "tailscaleInstalled", status: "ok", fixable: false, detail: binary };
  }
  return {
    id: "tailscaleInstalled",
    status: "fail",
    fixable: false,
    detail: "Tailscale CLI не знайдено",
    instruction: "Встанови Tailscale:\n\nbrew install tailscale\n\nабо завантаж з https://tailscale.com/download",
  };
}

async function checkTailscaleRunning(): Promise<HealthItem> {
  const binary = findTailscale();
  if (!binary) {
    return {
      id: "tailscaleRunning",
      status: "fail",
      fixable: false,
      detail: "Tailscale CLI не встановлений",
    };
  }
  const { stdout } = await execAsync(binary, ["status", "--json"]);
  try {
    const status = JSON.parse(stdout) as { BackendState?: string; Self?: { Online?: boolean; DNSName?: string } };
    const backendRunning = status?.BackendState === "Running";
    const online = status?.Self?.Online === true;
    if (backendRunning && online) {
      return { id: "tailscaleRunning", status: "ok", fixable: false, detail: status.Self?.DNSName?.replace(/\.$/, "") };
    }
    return {
      id: "tailscaleRunning",
      status: "fail",
      fixable: true,
      detail: `Стан: ${status?.BackendState ?? "unknown"}${online ? "" : ", офлайн"}`,
    };
  } catch {
    return {
      id: "tailscaleRunning",
      status: "fail",
      fixable: true,
      detail: "Не вдалось прочитати стан демона",
    };
  }
}

async function checkFunnelActive(port: number): Promise<HealthItem> {
  const binary = findTailscale();
  if (!binary) {
    return { id: "funnelActive", status: "fail", fixable: false, detail: "Tailscale CLI не встановлений" };
  }
  const { stdout } = await execAsync(binary, ["funnel", "status"]);
  const text = stdout || "";
  if (text.includes(`http://127.0.0.1:${port}`) || text.includes(`http://localhost:${port}`)) {
    return { id: "funnelActive", status: "ok", fixable: false, detail: `Порт ${port}` };
  }
  if (text.includes("No serve config") || text.trim() === "") {
    return {
      id: "funnelActive",
      status: "fail",
      fixable: true,
      detail: "Funnel не налаштований",
    };
  }
  return {
    id: "funnelActive",
    status: "fail",
    fixable: true,
    detail: `Funnel не прив'язаний до порту ${port}`,
  };
}

function checkServerListening(ctx: HealthContext): HealthItem {
  return ctx.serverListening
    ? { id: "serverListening", status: "ok", fixable: false, detail: `Порт ${ctx.serverPort}` }
    : { id: "serverListening", status: "fail", fixable: false, detail: "Сервер не слухає порт" };
}

async function checkIosSigning(): Promise<HealthItem> {
  const { stdout } = await execAsync("security", ["find-identity", "-v", "-p", "codesigning"]);
  const hasDev = /Apple Development|iPhone Developer/i.test(stdout);
  if (hasDev) {
    return { id: "iosSigning", status: "ok", fixable: false, detail: "Сертифікат Apple Development присутній" };
  }
  return {
    id: "iosSigning",
    status: "fail",
    fixable: false,
    detail: "Сертифікат підпису для iOS не знайдено у Keychain",
    instruction:
      "Відкрий Xcode → Settings → Accounts → обери свій Apple ID → Manage Certificates → додай 'Apple Development'. Без нього iOS OTA-деплой не працюватиме.",
  };
}

async function checkXcodeTools(): Promise<HealthItem> {
  const { code, stdout } = await execAsync("xcode-select", ["-p"]);
  if (code === 0 && stdout.trim()) {
    return { id: "xcodeTools", status: "ok", fixable: false, detail: stdout.trim() };
  }
  return {
    id: "xcodeTools",
    status: "fail",
    fixable: false,
    detail: "Xcode Command Line Tools не встановлені",
    instruction: "Встанови інструменти:\n\nxcode-select --install",
  };
}

async function checkAndroidSdk(): Promise<HealthItem> {
  const { code: adbCode, stdout: adbPath } = await execAsync("which", ["adb"]);
  const androidHome = process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (adbCode === 0 && adbPath.trim() && androidHome) {
    return { id: "androidSdk", status: "ok", fixable: false, detail: `${androidHome}` };
  }
  const missing: string[] = [];
  if (adbCode !== 0 || !adbPath.trim()) missing.push("adb не в PATH");
  if (!androidHome) missing.push("$ANDROID_HOME не заданий");
  return {
    id: "androidSdk",
    status: "fail",
    fixable: false,
    detail: missing.join(", "),
    instruction:
      "Встанови Android SDK через Android Studio або brew install --cask android-commandlinetools, потім додай $ANDROID_HOME у ~/.zshrc і PATH до platform-tools (adb).",
  };
}

function checkMdnsActive(ctx: HealthContext): HealthItem {
  return ctx.mdnsActive
    ? { id: "mdnsActive", status: "ok", fixable: false, detail: "Bonjour реєстрація активна" }
    : { id: "mdnsActive", status: "fail", fixable: true, detail: "Bonjour провайдер не активний" };
}

// ─── Public API ─────────────────────────────────────────────────────────────

/** Run all server-side checks in parallel. Client fills in `clientConnected` separately. */
export async function runAllChecks(ctx: HealthContext): Promise<HealthItem[]> {
  return Promise.all([
    checkTailscaleInstalled(),
    checkTailscaleRunning(),
    checkFunnelActive(ctx.serverPort),
    Promise.resolve(checkServerListening(ctx)),
    checkIosSigning(),
    checkXcodeTools(),
    checkAndroidSdk(),
    Promise.resolve(checkMdnsActive(ctx)),
  ]);
}

/** Re-run a single check by id. Returns null if id is unknown or client-only. */
export async function runSingleCheck(id: HealthItemId, ctx: HealthContext): Promise<HealthItem | null> {
  switch (id) {
    case "tailscaleInstalled": return checkTailscaleInstalled();
    case "tailscaleRunning":   return checkTailscaleRunning();
    case "funnelActive":       return checkFunnelActive(ctx.serverPort);
    case "serverListening":    return checkServerListening(ctx);
    case "iosSigning":         return checkIosSigning();
    case "xcodeTools":         return checkXcodeTools();
    case "androidSdk":         return checkAndroidSdk();
    case "mdnsActive":         return checkMdnsActive(ctx);
    default:                   return null;
  }
}

/**
 * Attempt to auto-fix a health item. Returns `true` if the fix command ran
 * (not necessarily that the check now passes — caller should re-run the check).
 */
export async function runFix(id: HealthItemId, ctx: HealthContext): Promise<boolean> {
  switch (id) {
    case "tailscaleRunning": {
      const binary = findTailscale();
      if (!binary) return false;
      const { code } = await execAsync(binary, ["up"], 30_000);
      return code === 0;
    }
    case "funnelActive": {
      const binary = findTailscale();
      if (!binary) return false;
      const { code } = await execAsync(binary, ["funnel", "--bg", String(ctx.serverPort)], 15_000);
      return code === 0;
    }
    case "mdnsActive": {
      return ctx.restartMdns();
    }
    default:
      return false;
  }
}
