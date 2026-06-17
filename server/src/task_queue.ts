/**
 * Priority task queue for non-blocking agent orchestration.
 *
 * Tasks are ordered by priority (critical > high > normal > low),
 * then FIFO within the same priority level.
 */

import type { WebSocket } from "ws";

// ─── Types ──────────────────────────────────────────────────────────────────

export type TaskPriority = "critical" | "high" | "normal" | "low";

const PRIORITY_ORDER: Record<TaskPriority, number> = {
  critical: 0,
  high: 1,
  normal: 2,
  low: 3,
};

export interface QueuedTask {
  id: string;
  priority: TaskPriority;
  type: "chat" | "board" | "subagent_result";

  // Chat tasks
  userMessage?: string;
  targetAgentId?: string;
  images?: string[];

  // Sub-agent result tasks
  agentId?: string;
  result?: string;
  dispatchId?: string;
  costUsd?: number;
  durationMs?: number;
  /** True when the sub-agent errored / timed out instead of completing —
   *  the manager gets a failure prompt (re-plan or return the card to
   *  backlog) rather than the "move card to done" acknowledgement. */
  failed?: boolean;

  // Board tasks
  boardTaskId?: string;
  boardTaskTitle?: string;
  boardTaskDescription?: string;

  // Metadata
  enqueuedAt: number;
  ws: WebSocket;
  /** Active project at enqueue time. The runner verifies it still matches
   *  the server's active project at dispatch time and drops the task
   *  otherwise — a queued task must never execute in a different tree than
   *  the one it was created for. */
  projectCwd: string;
}

// ─── TaskQueue ──────────────────────────────────────────────────────────────

export class TaskQueue {
  private items: QueuedTask[] = [];

  /** Insert a task in priority order (stable: FIFO within same priority). */
  enqueue(task: QueuedTask): void {
    const order = PRIORITY_ORDER[task.priority];
    // Find insertion point: after all items with same or higher priority
    let i = this.items.length;
    while (i > 0 && PRIORITY_ORDER[this.items[i - 1].priority] > order) {
      i--;
    }
    this.items.splice(i, 0, task);
  }

  /** Remove and return the highest-priority task. */
  dequeue(): QueuedTask | undefined {
    return this.items.shift();
  }

  /** Peek at the highest-priority task without removing it. */
  peek(): QueuedTask | undefined {
    return this.items[0];
  }

  /** Check if the queue is empty. */
  get isEmpty(): boolean {
    return this.items.length === 0;
  }

  /** Number of queued tasks. */
  get size(): number {
    return this.items.length;
  }

  /** Remove all tasks for a specific WebSocket client (e.g. on disconnect). */
  removeForClient(ws: WebSocket): number {
    const before = this.items.length;
    this.items = this.items.filter((t) => t.ws !== ws);
    return before - this.items.length;
  }

  /** Drop everything. Used on project switch — queued tasks were created
   *  for the prior project (see `QueuedTask.projectCwd`), so they must not
   *  execute after the swap. The runner's dispatch-time projectCwd check is
   *  the backstop; clearing here gives the user immediate, visible feedback. */
  clear(): number {
    const n = this.items.length;
    this.items = [];
    return n;
  }

  /** Get a snapshot of all queued tasks (for status reporting). */
  snapshot(): Array<{ id: string; type: string; priority: TaskPriority; agentId?: string }> {
    return this.items.map((t) => ({
      id: t.id,
      type: t.type,
      priority: t.priority,
      agentId: t.targetAgentId ?? t.agentId,
    }));
  }
}
