/**
 * Pure helpers for classifying errors from the local `gemini` CLI.
 *
 * Kept in its own file (no server.ts imports) so unit tests can import it
 * without triggering the server bootstrap chain.
 */

export type LocalGeminiErrorKind =
  | "binary_missing"
  | "not_authenticated"
  | "quota_exhausted"
  | "process_error";

export class LocalGeminiError extends Error {
  readonly kind: LocalGeminiErrorKind;
  readonly retryAfterMs?: number;

  constructor(kind: LocalGeminiErrorKind, message: string, retryAfterMs?: number) {
    super(message);
    this.name = "LocalGeminiError";
    this.kind = kind;
    this.retryAfterMs = retryAfterMs;
  }
}

export interface GeminiJsonEnvelope {
  session_id?: string;
  response?: string;
  error?: { type?: string; message?: string; code?: number };
}

export function tryParseGeminiJson(text: string): GeminiJsonEnvelope | null {
  // The CLI may print warnings before the JSON. Find the first '{' that starts
  // a balanced object covering the rest of the output.
  const start = text.indexOf("{");
  if (start < 0) return null;
  try {
    return JSON.parse(text.slice(start)) as GeminiJsonEnvelope;
  } catch {
    return null;
  }
}

export function classifyGeminiError(
  error: { message?: string; code?: number },
  stderr: string,
): LocalGeminiError {
  const haystack = `${error.message ?? ""}\n${stderr}`.toLowerCase();

  if (haystack.includes("quota") || haystack.includes("exhausted") || error.code === 429) {
    const retryMs = parseRetryDelayMs(haystack);
    return new LocalGeminiError(
      "quota_exhausted",
      error.message ?? "Gemini free-tier quota exhausted",
      retryMs,
    );
  }
  if (haystack.includes("unauthenticated") ||
      haystack.includes("login") ||
      haystack.includes("oauth") ||
      error.code === 401) {
    return new LocalGeminiError(
      "not_authenticated",
      "Gemini CLI is not authenticated. Run `gemini` once to log in.",
    );
  }
  return new LocalGeminiError(
    "process_error",
    error.message ?? "Gemini CLI failed",
  );
}

function parseRetryDelayMs(text: string): number | undefined {
  // CLI emits patterns like "reset after 7h28m25s" or "retryDelayMs: 26905031".
  const ms = /retrydelayms[^\d]*(\d+)/i.exec(text);
  if (ms) return Number(ms[1]);
  const hms = /reset[^\d]*(\d+)h(\d+)m(\d+)?s?/i.exec(text);
  if (hms) {
    const h = Number(hms[1]);
    const m = Number(hms[2]);
    const s = Number(hms[3] ?? 0);
    return ((h * 3600) + (m * 60) + s) * 1000;
  }
  return undefined;
}
