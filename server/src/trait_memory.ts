/**
 * Agent Trait Memory — persistent learning system.
 *
 * Agents learn from mistakes and successes. The more frequently
 * a lesson is observed, the stronger it becomes in the agent's behavior.
 *
 * Frequency scale:
 *  1-2  → Note (mild influence)
 *  3-4  → Important (moderate influence)
 *  5+   → Critical (strong directive)
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

// ─── Types ─────────────────────────────────────────────────────────────────

export type LessonType = "strength" | "weakness";

export type LessonCategory =
  | "code_quality"
  | "architecture"
  | "testing"
  | "security"
  | "communication"
  | "delegation"
  | "problem_solving"
  | "tools_usage";

export interface AgentLesson {
  id: string;
  agentId: string;
  type: LessonType;
  category: LessonCategory;
  tag: string;            // kebab-case key for dedup / matching
  lesson: string;         // one-sentence description
  frequency: number;      // 1–10, higher = stronger memory
  firstSeen: string;      // ISO 8601
  lastSeen: string;       // ISO 8601
}

export interface TraitStore {
  version: number;
  agents: Record<string, AgentLesson[]>;
}

// ─── Storage paths ─────────────────────────────────────────────────────────

function traitsDir(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key);
}

function traitsFile(projectPath: string): string {
  return join(traitsDir(projectPath), "traits.json");
}

// ─── Load / Save ───────────────────────────────────────────────────────────

export function loadTraits(projectPath: string): TraitStore {
  const file = traitsFile(projectPath);
  if (!existsSync(file)) {
    return { version: 1, agents: {} };
  }
  try {
    return JSON.parse(readFileSync(file, "utf-8")) as TraitStore;
  } catch {
    return { version: 1, agents: {} };
  }
}

export function saveTraits(projectPath: string, store: TraitStore): void {
  const dir = traitsDir(projectPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(traitsFile(projectPath), JSON.stringify(store, null, 2));
}

// ─── Lesson CRUD ───────────────────────────────────────────────────────────

const MAX_LESSONS_PER_AGENT = 20;

/** Get all lessons for an agent, sorted by frequency descending. */
export function getLessonsForAgent(store: TraitStore, agentId: string): AgentLesson[] {
  const lessons = store.agents[agentId] ?? [];
  return [...lessons].sort((a, b) => b.frequency - a.frequency);
}

/**
 * Record a lesson. If a matching lesson exists (same agentId + tag),
 * its frequency is incremented. Otherwise a new lesson is created.
 * Returns the updated (or new) lesson.
 */
export function recordLesson(
  projectPath: string,
  store: TraitStore,
  input: {
    agentId: string;
    type: LessonType;
    category: LessonCategory;
    tag: string;
    lesson: string;
  },
): AgentLesson {
  const { agentId, type, category, tag, lesson } = input;
  const now = new Date().toISOString();

  if (!store.agents[agentId]) {
    store.agents[agentId] = [];
  }

  const lessons = store.agents[agentId];
  const existing = lessons.find((l) => l.tag === tag);

  if (existing) {
    existing.frequency = Math.min(existing.frequency + 1, 10);
    existing.lastSeen = now;
    // Keep the longer (more descriptive) lesson text
    if (lesson.length > existing.lesson.length) {
      existing.lesson = lesson;
    }
    // Allow type migration if pattern changes (e.g. weakness becomes strength)
    existing.type = type;
    saveTraits(projectPath, store);
    return existing;
  }

  const newLesson: AgentLesson = {
    id: `${agentId}_${type}_${Date.now()}`,
    agentId,
    type,
    category,
    tag,
    lesson,
    frequency: 1,
    firstSeen: now,
    lastSeen: now,
  };
  lessons.push(newLesson);

  // Cap per-agent — drop least frequent
  if (lessons.length > MAX_LESSONS_PER_AGENT) {
    lessons.sort((a, b) => b.frequency - a.frequency);
    lessons.length = MAX_LESSONS_PER_AGENT;
  }

  saveTraits(projectPath, store);
  return newLesson;
}

/** Remove a specific lesson by id. */
export function removeLesson(
  projectPath: string,
  store: TraitStore,
  lessonId: string,
): boolean {
  for (const agentId of Object.keys(store.agents)) {
    const lessons = store.agents[agentId];
    const idx = lessons.findIndex((l) => l.id === lessonId);
    if (idx >= 0) {
      lessons.splice(idx, 1);
      saveTraits(projectPath, store);
      return true;
    }
  }
  return false;
}

// ─── Prompt formatting ─────────────────────────────────────────────────────

/**
 * Build a prompt section describing the agent's learned traits.
 * Weaknesses get progressively stronger language as frequency grows.
 * Strengths get progressively more confident language.
 */
export function formatTraitsForPrompt(store: TraitStore, agentId: string): string {
  const lessons = getLessonsForAgent(store, agentId);
  if (lessons.length === 0) return "";

  const weaknesses = lessons.filter((l) => l.type === "weakness");
  const strengths = lessons.filter((l) => l.type === "strength");

  const lines: string[] = [];

  if (weaknesses.length > 0) {
    lines.push("### Known Weaknesses (learn from past mistakes)");
    for (const w of weaknesses) {
      const emphasis =
        w.frequency >= 5 ? "CRITICAL — repeatedly observed" :
        w.frequency >= 3 ? "Important" :
        "Note";
      lines.push(`- **[${emphasis}]** ${w.lesson} _(observed ${w.frequency}×)_`);
    }
    lines.push("");
  }

  if (strengths.length > 0) {
    lines.push("### Known Strengths (leverage these)");
    for (const s of strengths) {
      const emphasis =
        s.frequency >= 5 ? "Expert-level" :
        s.frequency >= 3 ? "Strong" :
        "Capable";
      lines.push(`- **[${emphasis}]** ${s.lesson} _(confirmed ${s.frequency}×)_`);
    }
  }

  return lines.join("\n");
}

/** Flat array of all lessons across all agents (for sending to client). */
export function getAllTraits(store: TraitStore): AgentLesson[] {
  const all: AgentLesson[] = [];
  for (const lessons of Object.values(store.agents)) {
    all.push(...lessons);
  }
  return all;
}
