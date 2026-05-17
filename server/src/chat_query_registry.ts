import { randomUUID } from "node:crypto";
import { WebSocket } from "ws";

export interface ActiveChatQuery {
  queryId: string;
  ws: WebSocket;
  agentId: string;
  /** First 200 chars of the user message — for UI surfacing. */
  userMessage: string;
  startedAt: number;
  abortController: AbortController;
}

export interface ActiveChatQuerySummary {
  queryId: string;
  agentId: string;
  userMessage: string;
  elapsedMs: number;
}

/**
 * Tracks in-flight main manager queries so UI can list/cancel them without
 * relying on ws-disconnect cleanup. Sub-agent dispatches live in
 * AgentRunner — this only handles `runQuery()` entries.
 */
export class ChatQueryRegistry {
  private readonly active = new Map<string, ActiveChatQuery>();

  register(params: {
    ws: WebSocket;
    agentId: string;
    userMessage: string;
    abortController: AbortController;
    now?: () => number;
  }): string {
    const queryId = randomUUID();
    this.active.set(queryId, {
      queryId,
      ws: params.ws,
      agentId: params.agentId,
      userMessage: params.userMessage.slice(0, 200),
      startedAt: (params.now ?? Date.now)(),
      abortController: params.abortController,
    });
    return queryId;
  }

  unregister(queryId: string): void {
    this.active.delete(queryId);
  }

  /** Cancel a specific query. Returns true if the entry existed. */
  cancel(queryId: string): boolean {
    const entry = this.active.get(queryId);
    if (!entry) return false;
    entry.abortController.abort();
    this.active.delete(queryId);
    return true;
  }

  /** Cancel every active query owned by `ws`. Returns count cancelled. */
  cancelForWs(ws: WebSocket): number {
    let n = 0;
    for (const [id, entry] of this.active) {
      if (entry.ws !== ws) continue;
      entry.abortController.abort();
      this.active.delete(id);
      n++;
    }
    return n;
  }

  /** Cancel queries for a given agent on this ws. Returns count cancelled. */
  cancelForAgent(ws: WebSocket, agentId: string): number {
    let n = 0;
    for (const [id, entry] of this.active) {
      if (entry.ws !== ws || entry.agentId !== agentId) continue;
      entry.abortController.abort();
      this.active.delete(id);
      n++;
    }
    return n;
  }

  list(opts?: { ws?: WebSocket; now?: () => number }): ActiveChatQuerySummary[] {
    const now = (opts?.now ?? Date.now)();
    const out: ActiveChatQuerySummary[] = [];
    for (const entry of this.active.values()) {
      if (opts?.ws && entry.ws !== opts.ws) continue;
      out.push({
        queryId: entry.queryId,
        agentId: entry.agentId,
        userMessage: entry.userMessage,
        elapsedMs: now - entry.startedAt,
      });
    }
    return out;
  }

  get size(): number {
    return this.active.size;
  }
}
