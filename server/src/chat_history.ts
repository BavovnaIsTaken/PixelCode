/**
 * In-memory chat history shared across all connected clients.
 *
 * Single source of truth for the current conversation.
 * Persisted to disk so history survives server restarts.
 *
 * Intentionally scoped to one active conversation — if multi-session
 * support is ever needed, key this by sessionId.
 */

import { readFileSync, writeFileSync, mkdirSync, renameSync } from "fs";
import { dirname } from "path";
import { randomUUID } from "node:crypto";
import type { ServerMessage } from "./protocol.js";

export interface StoredChatMessage {
  role: "user" | "assistant";
  text: string;
  agentId: string;
  timestamp: string; // ISO 8601
  id?: string; // stable identifier for cross-device sync; generated if not provided
  images?: string[]; // base64-encoded image data
}

/**
 * Enhanced chat message with optional metadata for prompt caching and analytics.
 */
export interface EnrichedChatMessage extends StoredChatMessage {
  id?: string; // Unique message identifier
  metadata?: {
    tokensUsed?: number;
    executionTimeMs?: number;
    hooksFired?: string[];
    cachedForPrompt?: boolean;
  };
}

export class ChatHistory {
  private readonly _messages: StoredChatMessage[] = [];
  private readonly _enrichedMetadata: Map<string, EnrichedChatMessage["metadata"]> = new Map();

  /**
   * Append a message. Idempotent when the caller supplies an id: a second
   * call with the same id is ignored. Lets clients safely replay queued
   * messages after a reconnect without producing chat duplicates — the
   * outbox cannot tell whether the original send actually reached the
   * server before the socket dropped.
   */
  add(msg: StoredChatMessage): void {
    if (msg.id) {
      for (const existing of this._messages) {
        if (existing.id === msg.id) return;
      }
    }
    const withId = { ...msg, id: msg.id ?? randomUUID() };
    this._messages.push(withId);
  }

  clear(): void {
    this._messages.length = 0;
    this._enrichedMetadata.clear();
  }

  /** Returns a snapshot message ready to send over WebSocket. */
  snapshot(): ServerMessage {
    return { type: "chat_history", messages: [...this._messages] };
  }

  get isEmpty(): boolean {
    return this._messages.length === 0;
  }

  /** Persist current history to disk. Logged no-op on failure (non-critical). */
  save(filePath: string): void {
    try {
      mkdirSync(dirname(filePath), { recursive: true });
      // Atomic: write to a sibling .tmp then rename (same pattern as
      // board_persistence). A crash mid-write leaves the previous file
      // intact instead of truncated JSON that load() silently discards.
      const tmp = `${filePath}.tmp-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      writeFileSync(tmp, JSON.stringify(this._messages), "utf8");
      renameSync(tmp, filePath);
    } catch (e) {
      // Non-critical — history will still work in-memory
      console.warn(`[chat_history] save failed: ${(e as Error).message}`);
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

  /**
   * Get recent messages within a token budget.
   * Returns messages in chronological order (oldest first).
   * Token estimation: roughly msg.text.length / 4
   *
   * @param sessionId Session identifier (currently stored in metadata if available)
   * @param maxTokens Maximum tokens to include (default 2000)
   * @returns Array of enriched chat messages within token budget
   */
  getContextMessages(sessionId: string, maxTokens: number = 2000): EnrichedChatMessage[] {
    let tokenCount = 0;
    const result: EnrichedChatMessage[] = [];

    // Iterate from oldest to newest (reverse iteration then reverse result)
    for (let i = this._messages.length - 1; i >= 0; i--) {
      const storedMsg = this._messages[i];
      const msgTokens = Math.ceil(storedMsg.text.length / 4);

      if (tokenCount + msgTokens > maxTokens) {
        // Stop if adding this message would exceed budget
        break;
      }

      const enrichedMsg: EnrichedChatMessage = {
        ...storedMsg,
        id: `msg_${i}_${storedMsg.timestamp}`, // Generate stable ID based on index and timestamp
        metadata: this._enrichedMetadata.get(`msg_${i}_${storedMsg.timestamp}`),
      };

      result.unshift(enrichedMsg); // Insert at beginning to maintain chronological order
      tokenCount += msgTokens;
    }

    return result;
  }

  /**
   * Mark specific messages as cached for prompt injection.
   * Updates the metadata.cachedForPrompt field for selected messages.
   *
   * @param sessionId Session identifier (for future multi-session support)
   * @param messageIds Array of message IDs to mark as cached
   */
  markForCache(sessionId: string, messageIds: string[]): void {
    const messageIdSet = new Set(messageIds);

    for (let i = 0; i < this._messages.length; i++) {
      const storedMsg = this._messages[i];
      const msgId = `msg_${i}_${storedMsg.timestamp}`;

      if (messageIdSet.has(msgId)) {
        // Get or create metadata for this message
        let metadata = this._enrichedMetadata.get(msgId);
        if (!metadata) {
          metadata = {};
          this._enrichedMetadata.set(msgId, metadata);
        }
        metadata.cachedForPrompt = true;
      }
    }
  }
}
