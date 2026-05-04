/**
 * Pure board-message handler — owns the in-memory `boardTasks` map and
 * mutates it in response to client `board_*` messages.
 *
 * Extracted from server.ts so the team-collaboration flows (create →
 * broadcast, move → auto-enqueue manager dispatch, assign delegation,
 * cross-client sync) are testable without a live WebSocket server.
 *
 * Behaviour mirrors the original handler line-for-line; no protocol
 * changes. The only structural change is dependency injection for
 * `broadcast`, `taskQueue`, the dispatch hooks, and the logger.
 */

import type { WebSocket } from "ws";

import type {
  ClientMessage,
  ServerMessage,
  TaskCardData,
  TaskAttachmentData,
  TaskColumnKey,
  TaskPriorityKey,
  StickyColorKey,
} from "./protocol.js";
import type { TaskQueue } from "./task_queue.js";

// ─── Types ────────────────────────────────────────────────────────────────

export type DebugLevel = "info" | "warn" | "error" | "debug";

export interface BoardHandlerDeps {
  /** Shared in-memory board state. The handler mutates entries in place. */
  boardTasks: Map<string, TaskCardData>;
  /** Returns the next sequential task id token. Caller owns the counter. */
  nextTaskId: () => string;
  /** Sends a single message to one client (used by `board_get_state`). */
  send: (ws: WebSocket, msg: ServerMessage) => void;
  /** Broadcasts the board snapshot to every connected client. */
  broadcastBoardState: () => void;
  /** Manager dispatch queue. Receiving an in_progress move enqueues a job. */
  taskQueue: TaskQueue;
  /** Notifies the originating client about queue length changes. */
  sendQueueStatus: (ws: WebSocket) => void;
  /** Kicks the dispatch loop after enqueue. Non-blocking. */
  processQueue: (ws: WebSocket) => void;
  /** Structured logger (mirrors server.ts `dbg`). */
  dbg: (level: DebugLevel, category: string, message: string, data?: unknown) => void;
  /** Hard cap on per-attachment payload size (bytes). */
  maxAttachmentBytes?: number;
  /** Time source — overridable for deterministic tests. */
  now?: () => Date;
}

// ─── Helpers ──────────────────────────────────────────────────────────────

const DEFAULT_MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024;

function isoNow(deps: BoardHandlerDeps): string {
  const d = deps.now ? deps.now() : new Date();
  return d.toISOString();
}

export function buildBoardSnapshot(
  boardTasks: Map<string, TaskCardData>,
): ServerMessage {
  return { type: "board_state", tasks: Array.from(boardTasks.values()) };
}

// ─── Entry point ──────────────────────────────────────────────────────────

/**
 * Handles a single board_* client message. Returns true when the message
 * matched a board case (so the caller knows whether to keep dispatching).
 */
export function handleBoardMessage(
  deps: BoardHandlerDeps,
  ws: WebSocket,
  msg: ClientMessage,
): boolean {
  switch (msg.type) {
    case "board_get_state":
      deps.send(ws, buildBoardSnapshot(deps.boardTasks));
      return true;

    case "board_create_task": {
      const id = deps.nextTaskId();
      const now = isoNow(deps);
      const task: TaskCardData = {
        id,
        title: msg.title,
        description: msg.description ?? "",
        column: "backlog",
        priority: (msg.priority as TaskPriorityKey) ?? "normal",
        color: (msg.color as StickyColorKey) ?? "yellow",
        assignedAgents: [],
        createdAt: now,
        updatedAt: now,
        difficulty: msg.difficulty,
        allowedRoles: msg.allowedRoles,
        taskType: msg.taskType,
        attachments: [],
      };
      deps.boardTasks.set(id, task);
      deps.dbg("info", "board", `Created task: ${task.title} (${id})`);
      deps.broadcastBoardState();
      return true;
    }

    case "board_move_task": {
      const task = deps.boardTasks.get(msg.taskId);
      if (!task) return true;
      const oldColumn = task.column;
      task.column = msg.column as TaskColumnKey;
      task.updatedAt = isoNow(deps);
      deps.dbg(
        "info",
        "board",
        `Moved task ${msg.taskId}: ${oldColumn} → ${task.column}`,
      );
      deps.broadcastBoardState();

      if (task.column === "in_progress") {
        const assignees =
          task.assignedAgents.length > 0
            ? `Assigned agents: ${task.assignedAgents.join(", ")}.`
            : "No specific agents assigned — decide who should handle this.";
        deps.taskQueue.enqueue({
          id: `board_${task.id}`,
          priority: "normal",
          type: "board",
          boardTaskId: task.id,
          boardTaskTitle: task.title,
          boardTaskDescription: task.description,
          targetAgentId: "manager",
          userMessage: `Board task "${task.title}": ${task.description}. ${assignees} Please dispatch this work.`,
          enqueuedAt: Date.now(),
          ws,
        });
        deps.dbg(
          "info",
          "board",
          `Auto-enqueued board task "${task.title}" for manager dispatch`,
        );
        deps.sendQueueStatus(ws);
        deps.processQueue(ws);
      }
      return true;
    }

    case "board_update_task": {
      const task = deps.boardTasks.get(msg.taskId);
      if (!task) return true;
      const updates = msg.updates;
      if (updates.title !== undefined) task.title = updates.title;
      if (updates.description !== undefined) task.description = updates.description;
      if (updates.priority !== undefined) task.priority = updates.priority;
      if (updates.color !== undefined) task.color = updates.color;
      if (updates.column !== undefined) task.column = updates.column;
      task.updatedAt = isoNow(deps);
      deps.dbg("info", "board", `Updated task ${msg.taskId}`);
      deps.broadcastBoardState();
      return true;
    }

    case "board_delete_task": {
      if (deps.boardTasks.delete(msg.taskId)) {
        deps.dbg("info", "board", `Deleted task ${msg.taskId}`);
        deps.broadcastBoardState();
      }
      return true;
    }

    case "board_assign_agent": {
      const task = deps.boardTasks.get(msg.taskId);
      if (!task) return true;
      if (msg.assign) {
        if (!task.assignedAgents.includes(msg.agentId)) {
          task.assignedAgents.push(msg.agentId);
        }
      } else {
        task.assignedAgents = task.assignedAgents.filter(
          (a) => a !== msg.agentId,
        );
      }
      task.updatedAt = isoNow(deps);
      deps.dbg(
        "info",
        "board",
        `${msg.assign ? "Assigned" : "Unassigned"} ${msg.agentId} on task ${msg.taskId}`,
      );
      deps.broadcastBoardState();
      return true;
    }

    case "board_add_attachment": {
      const task = deps.boardTasks.get(msg.taskId);
      if (!task) return true;
      const cap = deps.maxAttachmentBytes ?? DEFAULT_MAX_ATTACHMENT_BYTES;
      if (msg.sizeBytes > cap) {
        deps.dbg(
          "warn",
          "board",
          `Rejected attachment ${msg.name} on ${msg.taskId}: ${msg.sizeBytes} > ${cap}`,
        );
        return true;
      }
      const uploadedAt = isoNow(deps);
      const attachment: TaskAttachmentData = {
        id: `att_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        name: msg.name,
        mimeType: msg.mimeType,
        sizeBytes: msg.sizeBytes,
        dataBase64: msg.dataBase64,
        uploadedAt,
      };
      task.attachments = [...(task.attachments ?? []), attachment];
      task.updatedAt = uploadedAt;
      deps.dbg(
        "info",
        "board",
        `Added attachment "${msg.name}" (${msg.sizeBytes}B) to ${msg.taskId}`,
      );
      deps.broadcastBoardState();
      return true;
    }

    case "board_remove_attachment": {
      const task = deps.boardTasks.get(msg.taskId);
      if (!task || !task.attachments) return true;
      const before = task.attachments.length;
      task.attachments = task.attachments.filter(
        (a) => a.id !== msg.attachmentId,
      );
      if (task.attachments.length !== before) {
        task.updatedAt = isoNow(deps);
        deps.dbg(
          "info",
          "board",
          `Removed attachment ${msg.attachmentId} from ${msg.taskId}`,
        );
        deps.broadcastBoardState();
      }
      return true;
    }
  }

  return false;
}
