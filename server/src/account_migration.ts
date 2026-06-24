/**
 * One-time migration: lift the team out of per-project storage into the account.
 *
 * Before account-scoping, the authoritative team (game_state) and learned
 * traits lived under `~/.pixelcode/projects/{projectKey}/`. After the upgrade
 * the team belongs to the account (`~/.pixelcode/accounts/{accountId}/`). On the
 * first boot after upgrade we seed the default account from the user's existing
 * data so nobody loses their roster.
 *
 * Strategy: pick the project whose game_state was touched most recently (the
 * one the user was actually playing) and adopt its game_state + traits +
 * candidates wholesale. Merging traits across *every* project is intentionally
 * deferred — it risks duplicate lessons and is a follow-up.
 *
 * Idempotent: gated on the account game_state file's existence. Once the
 * account is initialized we never overwrite it (it may have diverged via normal
 * play / cross-device sync since the migration ran).
 *
 * Pure-ish: all IO is rooted at `baseDir` (default home) so tests run in a temp
 * dir without touching real user data.
 */

import {
  existsSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  readdirSync,
} from "fs";
import { dirname } from "path";
import {
  accountDir,
  accountGameStateFile,
  accountTraitsFile,
  accountCandidatesFile,
  legacyProjectsRoot,
} from "./account_paths.js";
import { classifyPersistedGameState } from "./roster_validation.js";

export interface MigrationStep {
  migrated: boolean;
  /** Machine-readable outcome: "account_exists" | "no_legacy" | "migrated" | "no_source". */
  reason: string;
}

export interface AccountMigrationReport extends MigrationStep {
  /** projectKey the team was lifted from, when a migration happened. */
  fromProjectKey?: string;
  /** updatedAt of the adopted game_state envelope (epoch ms). */
  updatedAt?: number;
  traits: MigrationStep;
  candidates: MigrationStep;
}

/** Copy a legacy project file into the account dir if the source exists. */
function adoptFile(
  src: string,
  dest: string,
): MigrationStep {
  if (!existsSync(src)) return { migrated: false, reason: "no_source" };
  try {
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, readFileSync(src, "utf-8"));
    return { migrated: true, reason: "migrated" };
  } catch {
    return { migrated: false, reason: "no_source" };
  }
}

/**
 * Seed `accountId`'s storage from the newest legacy per-project data, once.
 * Returns a report describing what (if anything) was migrated.
 */
export function migrateLegacyAccountData(
  accountId: string,
  baseDir?: string,
): AccountMigrationReport {
  const skipped: MigrationStep = { migrated: false, reason: "account_exists" };
  const gsTarget = accountGameStateFile(accountId, baseDir);

  // Already initialized — never clobber a live account.
  if (existsSync(gsTarget)) {
    return { ...skipped, traits: skipped, candidates: skipped };
  }

  const projectsRoot = legacyProjectsRoot(baseDir);
  const none: MigrationStep = { migrated: false, reason: "no_legacy" };
  if (!existsSync(projectsRoot)) {
    return { ...none, traits: none, candidates: none };
  }

  // Find the project whose game_state was updated most recently.
  let best: { key: string; updatedAt: number; rawText: string } | null = null;
  let entries: string[] = [];
  try {
    entries = readdirSync(projectsRoot, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name);
  } catch {
    return { ...none, traits: none, candidates: none };
  }

  for (const key of entries) {
    const file = `${projectsRoot}/${key}/game_state.json`;
    if (!existsSync(file)) continue;
    let rawText: string;
    try {
      rawText = readFileSync(file, "utf-8");
    } catch {
      continue;
    }
    const result = classifyPersistedGameState(rawText);
    if (result.kind !== "loaded") continue;
    const updatedAt = result.envelope.updatedAt;
    if (!best || updatedAt > best.updatedAt) {
      best = { key, updatedAt, rawText };
    }
  }

  if (!best) {
    return { ...none, traits: none, candidates: none };
  }

  // Adopt the chosen project's game_state verbatim (preserve the envelope).
  try {
    mkdirSync(accountDir(accountId, baseDir), { recursive: true });
    writeFileSync(gsTarget, best.rawText);
  } catch {
    return { ...none, traits: none, candidates: none };
  }

  const projectDir = `${projectsRoot}/${best.key}`;
  const traits = adoptFile(
    `${projectDir}/traits.json`,
    accountTraitsFile(accountId, baseDir),
  );
  const candidates = adoptFile(
    `${projectDir}/trait_candidates.json`,
    accountCandidatesFile(accountId, baseDir),
  );

  return {
    migrated: true,
    reason: "migrated",
    fromProjectKey: best.key,
    updatedAt: best.updatedAt,
    traits,
    candidates,
  };
}
