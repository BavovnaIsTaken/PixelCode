/**
 * Network diagnostic checks and auto-fixes for the server.
 *
 * Each check returns a HealthItem describing current state and whether a
 * safe auto-fix is available. The UI renders these in Settings → Мережа.
 */

import { execFile } from "child_process";
import { existsSync } from "fs";
import { request as httpsRequest } from "https";
import { Resolver } from "dns/promises";
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

/**
 * End-to-end funnel probe: resolves `dnsName` via public DNS (1.1.1.1 / 8.8.8.8)
 * to bypass MagicDNS, then does an HTTPS HEAD `/` to the public Tailscale
 * ingress IP with the correct `Host:` and SNI. This path mirrors what a remote
 * client would traverse — catches ACL/ingress failures the CLI-config parse
 * cannot see.
 */
async function probeFunnelPublic(dnsName: string): Promise<{ ok: boolean; detail: string }> {
  const resolver = new Resolver();
  resolver.setServers(["1.1.1.1", "8.8.8.8"]);
  let ip: string;
  try {
    const ips = await resolver.resolve4(dnsName);
    if (!ips.length) return { ok: false, detail: `Публічний DNS не резолвить ${dnsName}` };
    ip = ips[0];
  } catch (e) {
    return { ok: false, detail: `Публічний DNS: ${(e as Error).message}` };
  }

  return new Promise((resolve) => {
    const req = httpsRequest(
      {
        host: ip,
        port: 443,
        method: "HEAD",
        path: "/",
        headers: { Host: dnsName },
        servername: dnsName,
        timeout: 5000,
      },
      (res) => {
        res.resume();
        const code = res.statusCode ?? 0;
        // Any response from our Node (incl. 404) means funnel ingress → node works.
        // 502/503/504 = Tailscale ingress couldn't reach the node (ACL or offline).
        if (code >= 502 && code <= 504) {
          resolve({ ok: false, detail: `Tailscale ingress повертає HTTP ${code} (ACL funnel?)` });
        } else {
          resolve({ ok: true, detail: `Публічний funnel відповідає (HTTP ${code})` });
        }
      }
    );
    req.on("error", (e) => resolve({ ok: false, detail: `Funnel probe: ${e.message}` }));
    req.on("timeout", () => {
      req.destroy();
      resolve({ ok: false, detail: "Funnel probe timeout (5s)" });
    });
    req.end();
  });
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
  const configBound =
    text.includes(`http://127.0.0.1:${port}`) || text.includes(`http://localhost:${port}`);

  if (!configBound) {
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

  // Config gate passed. Verify the funnel is actually reachable end-to-end
  // via public DNS → Tailscale ingress → node → local server.
  const dnsName = await readTailscaleDnsName(binary);
  if (!dnsName) {
    return {
      id: "funnelActive",
      status: "fail",
      fixable: false,
      detail: "Не вдалось отримати tailscale DNS-імʼя",
    };
  }
  const probe = await probeFunnelPublic(dnsName);
  if (probe.ok) {
    return { id: "funnelActive", status: "ok", fixable: false, detail: probe.detail };
  }
  return {
    id: "funnelActive",
    status: "fail",
    fixable: false,
    detail: probe.detail,
    instruction:
      "Funnel CLI сконфігурований локально, але публічна точка не відповідає.\n" +
      "Перевір:\n" +
      "  1. У Tailscale Admin → Access Controls → tagOwners/ACL має бути атрибут `\"funnel\"` для цього node.\n" +
      "  2. `tailscale funnel status` — що там показано серед ACTIVE.\n" +
      "  3. Спробуй `curl -I https://<твій>.ts.net/` з клієнтського девайса.",
  };
}

async function readTailscaleDnsName(binary: string): Promise<string | null> {
  const { stdout } = await execAsync(binary, ["status", "--json"]);
  try {
    const status = JSON.parse(stdout) as { Self?: { DNSName?: string } };
    const raw = status?.Self?.DNSName;
    if (!raw) return null;
    return raw.replace(/\.$/, "");
  } catch {
    return null;
  }
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
