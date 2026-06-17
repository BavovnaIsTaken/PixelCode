/**
 * Project-path guard for client → server messages.
 *
 * The server runs every agent under one global active project (PROJECT_CWD).
 * Clients persist their own "selected project" locally, so the two can drift:
 * a server restart resets the global to the config default while the client
 * UI keeps showing the previously selected project. Executing a task in that
 * state silently writes files into the wrong tree.
 *
 * `send_message` therefore carries the path the client *believes* is active
 * (`projectPath`), and the server refuses to run the task when it disagrees —
 * the client gets a typed `project_mismatch` event instead of a wrong-tree run.
 */

import { resolve, sep } from "path";

export interface ProjectMismatch {
  /** Project the client believes is active (normalized). */
  requested: string;
  /** Project the server is actually running in (normalized). */
  active: string;
}

/** Resolve to an absolute path and strip a trailing separator so
 *  `/foo/bar/` and `/foo/bar` compare equal. Root (`/`) is left intact. */
export function normalizeProjectPath(p: string): string {
  const abs = resolve(p);
  return abs.length > 1 && abs.endsWith(sep) ? abs.slice(0, -1) : abs;
}

/**
 * Compare the project path claimed by a client against the server's active
 * project. Returns `null` when the message is safe to run: either the client
 * did not claim a path (legacy clients) or it matches the active project.
 * Returns the normalized pair on mismatch so the caller can report it.
 */
export function checkProjectPath(
  requested: string | undefined,
  active: string,
): ProjectMismatch | null {
  if (requested === undefined || requested.length === 0) return null;
  const normRequested = normalizeProjectPath(requested);
  const normActive = normalizeProjectPath(active);
  if (normRequested === normActive) return null;
  return { requested: normRequested, active: normActive };
}
