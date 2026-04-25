/**
 * Server configuration: file + env + CLI flags.
 *
 * Resolution order (highest first):
 *   1. CLI flags (passed via applyOverrides)
 *   2. Environment variables (PORT, PROJECT_CWD, OTA_HOSTNAME)
 *   3. Config file (~/.pixelcode-server/config.json by default)
 *   4. Built-in defaults
 *
 * The file is the source of truth for the admin UI / CLI `config set`. Env and
 * CLI overrides are non-persistent and only apply to the current process — this
 * matters for systemd / docker setups that pin values via environment.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import { dirname, join, resolve } from "path";

export interface ServerConfig {
  port: number;
  projectCwd: string;
  otaHostname: string | null;
  /** Port the always-on launcher daemon listens on (separate from `port`). */
  launcherPort: number;
}

export interface ConfigSource {
  /** Where the persisted config file lives. */
  filePath: string;
  /** Effective config after merging file + env + flag overrides. */
  effective: ServerConfig;
  /** Raw config-file contents (defaults if file missing). */
  fromFile: ServerConfig;
  /** Which keys came from env (not the file). */
  envOverrides: Partial<Record<keyof ServerConfig, true>>;
  /** Which keys came from CLI flags (not env, not file). */
  flagOverrides: Partial<Record<keyof ServerConfig, true>>;
}

const DEFAULTS: ServerConfig = {
  port: 9720,
  projectCwd: process.cwd(),
  otaHostname: null,
  launcherPort: 9719,
};

export function defaultConfigPath(): string {
  return join(homedir(), ".pixelcode-server", "config.json");
}

function parsePort(raw: unknown): number | undefined {
  if (raw === undefined || raw === null || raw === "") return undefined;
  const n = typeof raw === "number" ? raw : parseInt(String(raw), 10);
  return Number.isFinite(n) && n > 0 && n < 65536 ? n : undefined;
}

function readConfigFile(filePath: string): Partial<ServerConfig> {
  if (!existsSync(filePath)) return {};
  try {
    const raw = JSON.parse(readFileSync(filePath, "utf8")) as Record<string, unknown>;
    const out: Partial<ServerConfig> = {};
    const port = parsePort(raw.port);
    if (port !== undefined) out.port = port;
    const launcherPort = parsePort(raw.launcherPort);
    if (launcherPort !== undefined) out.launcherPort = launcherPort;
    if (typeof raw.projectCwd === "string" && raw.projectCwd.length > 0) {
      out.projectCwd = resolve(raw.projectCwd);
    }
    if (typeof raw.otaHostname === "string" && raw.otaHostname.length > 0) {
      out.otaHostname = raw.otaHostname;
    } else if (raw.otaHostname === null) {
      out.otaHostname = null;
    }
    return out;
  } catch (err) {
    console.warn(`⚠️  Failed to parse ${filePath}: ${(err as Error).message} — using defaults`);
    return {};
  }
}

function readEnvOverrides(): Partial<ServerConfig> {
  const out: Partial<ServerConfig> = {};
  const port = parsePort(process.env.PORT);
  if (port !== undefined) out.port = port;
  const launcherPort = parsePort(process.env.LAUNCHER_PORT);
  if (launcherPort !== undefined) out.launcherPort = launcherPort;
  if (process.env.PROJECT_CWD) out.projectCwd = resolve(process.env.PROJECT_CWD);
  if (process.env.OTA_HOSTNAME) out.otaHostname = process.env.OTA_HOSTNAME;
  return out;
}

export interface LoadOptions {
  /** Override the config-file location. */
  configPath?: string;
  /** CLI-flag overrides (highest precedence). */
  flags?: Partial<ServerConfig>;
}

export function loadConfig(options: LoadOptions = {}): ConfigSource {
  const filePath = options.configPath ?? defaultConfigPath();
  const fromFileRaw = readConfigFile(filePath);
  const fromFile: ServerConfig = { ...DEFAULTS, ...fromFileRaw };
  const envRaw = readEnvOverrides();
  const flagRaw = options.flags ?? {};

  const effective: ServerConfig = { ...fromFile, ...envRaw, ...flagRaw };

  const envOverrides: Partial<Record<keyof ServerConfig, true>> = {};
  for (const k of Object.keys(envRaw) as (keyof ServerConfig)[]) envOverrides[k] = true;

  const flagOverrides: Partial<Record<keyof ServerConfig, true>> = {};
  for (const k of Object.keys(flagRaw) as (keyof ServerConfig)[]) flagOverrides[k] = true;

  return { filePath, effective, fromFile, envOverrides, flagOverrides };
}

/** Persist the given config to disk. Creates parent directories as needed. */
export function saveConfig(filePath: string, config: ServerConfig): void {
  mkdirSync(dirname(filePath), { recursive: true });
  const payload = JSON.stringify(config, null, 2) + "\n";
  writeFileSync(filePath, payload);
}

/**
 * Merge a partial update into the persisted file. Returns the resulting file
 * contents (not the env- or flag-merged effective config).
 */
export function updateConfigFile(filePath: string, patch: Partial<ServerConfig>): ServerConfig {
  const current: ServerConfig = { ...DEFAULTS, ...readConfigFile(filePath) };
  const next: ServerConfig = { ...current, ...patch };
  saveConfig(filePath, next);
  return next;
}

/** Validate a partial patch coming from the admin API. Throws on bad input. */
export function validatePatch(input: unknown): Partial<ServerConfig> {
  if (!input || typeof input !== "object") throw new Error("body must be a JSON object");
  const raw = input as Record<string, unknown>;
  const patch: Partial<ServerConfig> = {};
  if ("port" in raw) {
    const port = parsePort(raw.port);
    if (port === undefined) throw new Error("port must be an integer in 1..65535");
    patch.port = port;
  }
  if ("launcherPort" in raw) {
    const lp = parsePort(raw.launcherPort);
    if (lp === undefined) throw new Error("launcherPort must be an integer in 1..65535");
    patch.launcherPort = lp;
  }
  if ("projectCwd" in raw) {
    if (typeof raw.projectCwd !== "string" || raw.projectCwd.length === 0) {
      throw new Error("projectCwd must be a non-empty string");
    }
    patch.projectCwd = resolve(raw.projectCwd);
  }
  if ("otaHostname" in raw) {
    if (raw.otaHostname === null || raw.otaHostname === "") patch.otaHostname = null;
    else if (typeof raw.otaHostname === "string") patch.otaHostname = raw.otaHostname;
    else throw new Error("otaHostname must be a string or null");
  }
  return patch;
}

/** Keys whose change requires a full server restart to take effect. */
export const RESTART_REQUIRED_KEYS: ReadonlyArray<keyof ServerConfig> = ["port", "launcherPort"];

export function patchRequiresRestart(patch: Partial<ServerConfig>): boolean {
  return RESTART_REQUIRED_KEYS.some((k) => k in patch);
}
