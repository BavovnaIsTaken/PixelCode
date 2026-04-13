/**
 * In-memory chat history shared across all connected clients.
 *
 * Single source of truth for the current conversation.
 * Persisted to disk so history survives server restarts.
 *
 * Intentionally scoped to one active conversation — if multi-session
 * support is ever needed, key this by sessionId.
 */

import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname } from "path";
import type { ServerMessage } from "./protocol.js";

export interface StoredChatMessage {
  role: "user" | "assistant";
  text: string;
  agentId: string;
  timestamp: string; // ISO 8601
}

export class ChatHistory {
  private readonly _messages: StoredChatMessage[] = [];

  add(msg: StoredChatMessage): void {
    this._messages.push(msg);
  }

  clear(): void {
    this._messages.length = 0;
  }

  /** Returns a snapshot message ready to send over WebSocket. */
  snapshot(): ServerMessage {
    return { type: "chat_history", messages: [...this._messages] };
  }

  get isEmpty(): boolean {
    return this._messages.length === 0;
  }

  /** Persist current history to disk. No-op on failure (non-critical). */
  save(filePath: string): void {
    try {
      mkdirSync(dirname(filePath), { recursive: true });
      writeFileSync(filePath, JSON.stringify(this._messages), "utf8");
    } catch {
      // Non-critical — history will still work in-memory
    }
  }

  /** Load history from disk. No-op if file doesn't exist. */
  load(filePath: string): void {
    try {
      const raw = readFileSync(filePath, "utf8");
      const parsed = JSON.parse(raw) as StoredChatMessage[];
      if (Array.isArray(parsed)) {
        this._messages.length = 0;
        this._messages.push(...parsed);
      }
    } catch {
      // File doesn't exist or is corrupt — start fresh
    }
  }
}
