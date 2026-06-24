/**
 * Account-scoped storage paths.
 *
 * The user's *team* (roster, levels, skills, traits, currency, office) belongs
 * to their account, not to any one project. A project is just a working
 * directory the team is pointed at. So account-scoped data lives under
 * `~/.pixelcode/accounts/{accountKey}/…`, independent of the active project —
 * switching projects never changes the team.
 *
 * Multi-account is not built yet: there is a single, well-known default account
 * (`local`). Crucially, the default id is a CONSTANT shared by every device, so
 * two clients talking to the same single-tenant server resolve to the same
 * account and keep syncing. Real per-user ids (and a server-authoritative
 * reconciliation) arrive with multi-account; the explicit `accountId` plumbing
 * means that lands as config, not a refactor.
 *
 * Pure module — every path helper takes an optional `baseDir` (defaulting to
 * the home directory) so tests can redirect IO to a temp dir.
 */

import { join } from "path";
import { homedir } from "os";

/** The single default account. A constant, NOT a per-device random id — see file header. */
export const DEFAULT_ACCOUNT_ID = "local";

/**
 * Sanitize a (possibly client-supplied) account id into a filesystem-safe key.
 *
 * Account ids come over the wire, so this is also the path-traversal guard:
 * anything outside `[A-Za-z0-9_-]` (including `/`, `.`, and `..`) collapses to
 * `-`. An empty / whitespace / all-illegal id falls back to the default account
 * rather than producing an empty or dot path segment.
 */
export function accountKey(accountId: string | null | undefined): string {
  const raw = (accountId ?? "").trim();
  const sanitized = raw.replace(/[^A-Za-z0-9_-]/g, "-").replace(/^-+/, "");
  // A leading-dash strip can empty an all-illegal id; guard both cases.
  return sanitized.length > 0 ? sanitized : DEFAULT_ACCOUNT_ID;
}

/** Root directory for an account's portable data. */
export function accountDir(accountId: string, baseDir?: string): string {
  return join(baseDir ?? homedir(), ".pixelcode", "accounts", accountKey(accountId));
}

/** Authoritative game-state envelope (roster + economy + office) for an account. */
export function accountGameStateFile(accountId: string, baseDir?: string): string {
  return join(accountDir(accountId, baseDir), "game_state.json");
}

/** Learned trait store (lessons that follow the agent across projects). */
export function accountTraitsFile(accountId: string, baseDir?: string): string {
  return join(accountDir(accountId, baseDir), "traits.json");
}

/** Candidate-lesson pool (the confabulation gate), account-scoped alongside traits. */
export function accountCandidatesFile(accountId: string, baseDir?: string): string {
  return join(accountDir(accountId, baseDir), "trait_candidates.json");
}

/** Root directory for legacy per-PROJECT data (where the team used to live). */
export function legacyProjectsRoot(baseDir?: string): string {
  return join(baseDir ?? homedir(), ".pixelcode", "projects");
}
