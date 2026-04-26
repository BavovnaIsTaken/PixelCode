# Personalized Agent System — Implementation Guide

Based on Claude Agent SDK architecture and PixelCode's existing ChatHistory + TraitMemory foundation.

Companion to [`AGENT_PERSONALIZATION_SYSTEM.md`](AGENT_PERSONALIZATION_SYSTEM.md) (design rationale).

---

## 0. Status (as of 2026-04-26)

**MVP shipped.** All phases in [§9 Timeline](#9-timeline) complete; live smoke test verified the end-to-end cycle (Haiku reflection → AgentProfile → fragment in next system prompt).

### ✅ Done

| Section | Slice | Commit |
|---------|-------|--------|
| §2 Phase 1 | ProfileCache + ChatHistory ext + ExecutionHooks foundation | `b23461f` |
| §6 Memory Lifecycle | `computeScore` / decay / eviction / capacity tiers | `5cd0e2a` |
| §6 (extension) | `tokenJaccard` + `findSimilar*` semantic dedup (off-doc) | `f8c6552` |
| §3 Phase 2.1 | LessonExtractor (3 patterns + `applyLessons` with eviction) | `933da30` |
| §3 Phase 2.2 | PromptCacheManager (system prompt + `buildLearnedContext`) | `b014da8` |
| §4 Phase 3 | AgentContextPreparer (adapted for `query()` SDK shape) | `48786f3` |
| §5 Phase 4 | ProjectContextManager (cross-project migration) | `cc3ec3f` |
| (off-doc) Phase 4.5.1 | `injectLearnedContext` wired in `server.ts` | `cce3c76` |
| (off-doc) Phase 4.5.2 | `applyLlmLessons` wired in `reflectOnQuery` | `54c0c69` |

Live smoke test 2026-04-26: profiles persist, `manager#1` accumulated `unclear-delegation-scope` weakness from real Haiku reflection, apply-boost incremented `avoidedCount` and `avoidanceScore` on subsequent query.

### 🔭 Resume here — next priorities (none started yet)

1. **Retirement instead of delete** — `compactProfile` and `migrateProfileToNewProject` archive entries (`retired: true` + `retiredAt`) instead of removing them. Required before fork / breed / resurrect UX. Pure profile layer, ~30–50 LOC. **Recommended next slice — fully additive, no production wiring.**
2. **Population telemetry** — admin-API endpoint listing trending / veteran / dormant agents by `observedCount` + recency. Lives in [`server/src/admin.ts`](../server/src/admin.ts).
3. **Fork / breed alpha** — profile merge: strengths(A) + weaknesses(B) → new agent. Pure profile op, ~50 LOC.
4. **`clientId → userId`** — replace `"default-user"` hardcode in [`server.ts`](../server/src/server.ts) and [`agent_context.ts`](../server/src/agent_context.ts) once per-user identity exists in the protocol.
5. **Embedding-based dedup** — swap `findSimilarStrength` / `findSimilarWeakness` body from `tokenJaccard` to brute-force cosine over per-entry `embedding: Float32Array`. Signature stable, swap point already in place; pick provider (Voyage / OpenAI / local).

### 📂 File path reference (doc → actual)

The doc was drafted using a `backend/src/services/…` layout. Actual code lives flat under `server/src/…`:

| Doc path (referenced in §2–§6) | Actual file |
|---|---|
| `backend/src/services/profileCache.ts` | [`server/src/profile_cache.ts`](../server/src/profile_cache.ts) |
| `backend/src/services/chatHistory.ts` | [`server/src/chat_history.ts`](../server/src/chat_history.ts) |
| `backend/src/hooks/executionHooks.ts` | [`server/src/hooks/executionHooks.ts`](../server/src/hooks/executionHooks.ts) |
| `backend/src/services/lessonExtractor.ts` | [`server/src/lesson_extractor.ts`](../server/src/lesson_extractor.ts) |
| `backend/src/services/promptCacheManager.ts` | [`server/src/prompt_cache_manager.ts`](../server/src/prompt_cache_manager.ts) |
| `backend/src/agents/agentInitializer.ts` | [`server/src/agent_context.ts`](../server/src/agent_context.ts) (renamed; bundles fragment + cacheKey + recent msgs for the function-oriented `query()` SDK) |
| `backend/src/services/projectContextManager.ts` | [`server/src/project_context_manager.ts`](../server/src/project_context_manager.ts) |
| (added in §6) | [`server/src/memory_lifecycle.ts`](../server/src/memory_lifecycle.ts) |
| (added off-doc, Phase 4.5.x) | [`server/src/personalization.ts`](../server/src/personalization.ts) |

---

## 1. Strategic Overview

### Current State
- ✅ **ChatHistory** persists to disk (in-memory + file storage)
- ✅ **TraitMemory** tracks agent strengths/weaknesses with frequency counts
- ✅ **WebSocket** enables client↔server sync
- ✅ **Task Queue** maintains task state

### Goal
Integrate **Prompt Caching** (85–95% token savings) + **Explicit Message History** for robust session continuity while respecting Claude Agent SDK's stateless nature.

### Strategy
1. **Layer 1:** Enhance ChatHistory to be prompt-cache-ready (compress, version)
2. **Layer 2:** Build ProfileCache (UserProfile + AgentProfile in local JSON)
3. **Layer 3:** Implement hook-based auto-learning (strengthen ProfileCache)
4. **Layer 4:** Integrate Prompt Caching into agent initialization
5. **Layer 5:** Apply Memory Lifecycle (consolidation + decay + bounded capacity) so retention follows human-memory dynamics (see §6)

---

## 2. Phase 1: Core Infrastructure (3 days)

### 2.1 ProfileCache Data Layer

**File:** `backend/src/services/profileCache.ts`

```typescript
import * as fs from 'fs';
import * as path from 'path';
import * as zlib from 'zlib';

export interface UserProfile {
  userId: string;
  version: string;
  communicationStyle: {
    language: 'uk' | 'en';
    verbosity: 'concise' | 'detailed';
    technicalLevel: 'beginner' | 'intermediate' | 'advanced';
  };
  preferences: {
    parallelizeWork: boolean;
    preferDelegation: boolean;
    errorTolerance: 'low' | 'medium' | 'high';
  };
  globalPatterns: {
    successfulApproaches: string[];
    avoidedMistakes: string[];
    topicAffinities: Record<string, number>; // 0–1 scale
  };
  updatedAt: string;
}

export interface AgentProfile {
  agentId: string;
  version: string;
  strengths: Array<{
    skill: string;
    context: string;
    observedCount: number;
    confidence: number; // 0–1
  }>;
  weaknesses: Array<{
    pitfall: string;
    impact: string;
    observedCount: number;
    avoidanceScore: number; // 0–1
  }>;
  contextPatterns: {
    universal: Record<string, any>;
    projectSpecific: Record<string, Record<string, any>>;
  };
  promptCacheV1: string; // Compressed context (~4KB)
  updatedAt: string;
}

export class ProfileCacheService {
  private profileDir: string;

  constructor() {
    this.profileDir = path.join(process.env.HOME || '/tmp', '.pixelcode', 'profiles');
    fs.mkdirSync(this.profileDir, { recursive: true });
  }

  // Load user profile
  async loadUserProfile(userId: string): Promise<UserProfile> {
    const filePath = path.join(this.profileDir, `user-${userId}.json`);
    if (!fs.existsSync(filePath)) {
      return this.createDefaultUserProfile(userId);
    }
    const data = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(data);
  }

  // Save user profile
  async saveUserProfile(profile: UserProfile): Promise<void> {
    const filePath = path.join(this.profileDir, `user-${profile.userId}.json`);
    profile.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, JSON.stringify(profile, null, 2));
  }

  // Load agent profile
  async loadAgentProfile(agentId: string): Promise<AgentProfile> {
    const filePath = path.join(this.profileDir, `agent-${agentId}.json`);
    if (!fs.existsSync(filePath)) {
      return this.createDefaultAgentProfile(agentId);
    }
    const data = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(data);
  }

  // Save agent profile
  async saveAgentProfile(profile: AgentProfile): Promise<void> {
    const filePath = path.join(this.profileDir, `agent-${profile.agentId}.json`);
    profile.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, JSON.stringify(profile, null, 2));
  }

  // Generate prompt cache (compressed, versioned)
  async generatePromptCache(
    userProfile: UserProfile,
    agentProfile: AgentProfile,
    currentProject: string
  ): Promise<string> {
    const cacheData = {
      userStyle: userProfile.communicationStyle,
      userPrefs: userProfile.preferences,
      topStrengths: agentProfile.strengths.slice(0, 3),
      topWeaknesses: agentProfile.weaknesses.slice(0, 3),
      universalPatterns: agentProfile.contextPatterns.universal,
      projectPatterns: agentProfile.contextPatterns.projectSpecific[currentProject] || {},
      generated: new Date().toISOString(),
    };

    const json = JSON.stringify(cacheData);
    const compressed = zlib.gzipSync(json).toString('base64');
    return compressed;
  }

  // Private helpers
  private createDefaultUserProfile(userId: string): UserProfile {
    return {
      userId,
      version: '1.0',
      communicationStyle: {
        language: 'uk',
        verbosity: 'concise',
        technicalLevel: 'advanced',
      },
      preferences: {
        parallelizeWork: true,
        preferDelegation: true,
        errorTolerance: 'medium',
      },
      globalPatterns: {
        successfulApproaches: [],
        avoidedMistakes: [],
        topicAffinities: {},
      },
      updatedAt: new Date().toISOString(),
    };
  }

  private createDefaultAgentProfile(agentId: string): AgentProfile {
    return {
      agentId,
      version: '1.0',
      strengths: [],
      weaknesses: [],
      contextPatterns: {
        universal: {},
        projectSpecific: {},
      },
      promptCacheV1: '',
      updatedAt: new Date().toISOString(),
    };
  }
}

export const profileCache = new ProfileCacheService();
```

### 2.2 ChatHistory Extension

**File:** `backend/src/services/chatHistory.ts` (extend existing)

```typescript
// Add to existing ChatHistory class:

export interface EnrichedChatMessage {
  id: string;
  sender: 'user' | 'agent';
  content: string;
  timestamp: string;
  agentId?: string;
  metadata?: {
    tokensUsed?: number;
    executionTimeMs?: number;
    hooksFired?: string[];
  };
}

export class ChatHistoryService {
  // ... existing methods ...

  // Get recent messages for prompt context (last N messages, up to token budget)
  async getContextMessages(
    sessionId: string,
    maxTokens: number = 2000
  ): Promise<EnrichedChatMessage[]> {
    const messages = await this.getHistory(sessionId);
    const sorted = messages.sort(
      (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
    );

    let tokenCount = 0;
    const contextMessages: EnrichedChatMessage[] = [];

    for (const msg of sorted) {
      const msgTokens = Math.ceil(msg.content.length / 4); // Rough estimate
      if (tokenCount + msgTokens > maxTokens) break;
      contextMessages.push(msg);
      tokenCount += msgTokens;
    }

    return contextMessages.reverse();
  }

  // Mark a message as part of prompt cache
  async markForCache(sessionId: string, messageIds: string[]): Promise<void> {
    // Metadata update to database
    const messages = await this.getHistory(sessionId);
    for (const msg of messages) {
      if (messageIds.includes(msg.id)) {
        msg.metadata = msg.metadata || {};
        (msg.metadata as any).cachedForPrompt = true;
      }
    }
    await this.saveHistory(sessionId, messages);
  }
}
```

### 2.3 Hook System Foundation

**File:** `backend/src/hooks/executionHooks.ts`

```typescript
export type HookName = 'beforeDispatch' | 'afterExecution' | 'onError' | 'onLearning';

export interface HookPayload {
  timestamp: string;
  agentId: string;
  sessionId: string;
  [key: string]: any;
}

export class ExecutionHooks {
  private hooks: Map<HookName, Array<(payload: HookPayload) => Promise<void>>> = new Map();

  register(hookName: HookName, callback: (payload: HookPayload) => Promise<void>) {
    if (!this.hooks.has(hookName)) {
      this.hooks.set(hookName, []);
    }
    this.hooks.get(hookName)!.push(callback);
  }

  async fire(hookName: HookName, payload: HookPayload) {
    const callbacks = this.hooks.get(hookName) || [];
    await Promise.all(callbacks.map(cb => cb(payload).catch(err => {
      console.error(`Hook ${hookName} failed:`, err);
    })));
  }
}

export const executionHooks = new ExecutionHooks();

// Register built-in hooks
executionHooks.register('afterExecution', async (payload) => {
  const { agentId, result, lessons } = payload;
  if (result === 'success' && lessons) {
    console.log(`Agent ${agentId} learned: ${lessons.join(', ')}`);
  }
});
```

---

## 3. Phase 2: Auto-Learning & Prompt Caching (3–5 days)

### 3.1 Lesson Extraction

**File:** `backend/src/services/lessonExtractor.ts`

```typescript
import { ExecutionHooks } from '../hooks/executionHooks';
import { profileCache } from './profileCache';

export interface Lesson {
  category: 'strength' | 'weakness';
  title: string;
  context: string;
  confidence: number; // 0–1, starts low, increases with repetition
}

export class LessonExtractor {
  extractLessons(hookPayload: any): Lesson[] {
    const lessons: Lesson[] = [];

    // Pattern 1: Successful async dispatch
    if (hookPayload.action === 'dispatch' && hookPayload.result === 'success') {
      lessons.push({
        category: 'strength',
        title: 'Async dispatch effectiveness',
        context: `Successfully dispatched ${hookPayload.taskCount} tasks in parallel`,
        confidence: 0.85,
      });
    }

    // Pattern 2: Avoided a known pitfall
    if (hookPayload.avoided === 'tool-check') {
      lessons.push({
        category: 'strength',
        title: 'Tool availability verification',
        context: 'Checked tools before dispatch (avoided fallback)',
        confidence: 0.9,
      });
    }

    // Pattern 3: Error recovery
    if (hookPayload.error && hookPayload.recovery) {
      lessons.push({
        category: 'weakness',
        title: hookPayload.error,
        context: `Recovered via: ${hookPayload.recovery}`,
        confidence: 0.7,
      });
    }

    return lessons;
  }

  async applyLessons(agentId: string, lessons: Lesson[]): Promise<void> {
    const profile = await profileCache.loadAgentProfile(agentId);

    for (const lesson of lessons) {
      if (lesson.category === 'strength') {
        const existing = profile.strengths.find(s => s.skill === lesson.title);
        if (existing) {
          existing.observedCount++;
          existing.confidence = Math.min(1, existing.confidence + 0.05);
        } else {
          profile.strengths.push({
            skill: lesson.title,
            context: lesson.context,
            observedCount: 1,
            confidence: lesson.confidence,
          });
        }
      } else {
        const existing = profile.weaknesses.find(w => w.pitfall === lesson.title);
        if (existing) {
          existing.observedCount++;
          existing.avoidanceScore = Math.min(1, existing.avoidanceScore + 0.05);
        } else {
          profile.weaknesses.push({
            pitfall: lesson.title,
            impact: lesson.context,
            observedCount: 1,
            avoidanceScore: lesson.confidence,
          });
        }
      }
    }

    await profileCache.saveAgentProfile(profile);
  }
}

export const lessonExtractor = new LessonExtractor();
```

### 3.2 Prompt Cache Integration

**File:** `backend/src/services/promptCacheManager.ts`

```typescript
import { profileCache, UserProfile, AgentProfile } from './profileCache';

export class PromptCacheManager {
  async buildSystemPrompt(
    agentId: string,
    userId: string,
    currentProject: string
  ): Promise<{ systemPrompt: string; cacheKey: string }> {
    const userProfile = await profileCache.loadUserProfile(userId);
    const agentProfile = await profileCache.loadAgentProfile(agentId);

    const cacheKey = `${agentId}-${currentProject}-${agentProfile.updatedAt}`;

    // Build base system prompt
    const basePrompt = this.buildBasePrompt(agentId, userProfile);

    // Add cached context (if using Prompt Caching API)
    const cachedContext = await this.buildCachedContext(userProfile, agentProfile, currentProject);

    return {
      systemPrompt: `${basePrompt}\n\n${cachedContext}`,
      cacheKey,
    };
  }

  private buildBasePrompt(agentId: string, userProfile: UserProfile): string {
    return `You are agent: ${agentId}
Communication style: ${userProfile.communicationStyle.language}/${userProfile.communicationStyle.verbosity}
Technical level: ${userProfile.communicationStyle.technicalLevel}
Prefer delegation: ${userProfile.preferences.preferDelegation}
Parallelize when possible: ${userProfile.preferences.parallelizeWork}`;
  }

  private async buildCachedContext(
    userProfile: UserProfile,
    agentProfile: AgentProfile,
    currentProject: string
  ): Promise<string> {
    const topStrengths = agentProfile.strengths
      .sort((a, b) => b.confidence - a.confidence)
      .slice(0, 3)
      .map(s => `- ${s.skill} (confidence: ${(s.confidence * 100).toFixed(0)}%)`)
      .join('\n');

    const topWeaknesses = agentProfile.weaknesses
      .sort((a, b) => b.avoidanceScore - a.avoidanceScore)
      .slice(0, 3)
      .map(w => `- Avoid: ${w.pitfall} (score: ${(w.avoidanceScore * 100).toFixed(0)}%)`)
      .join('\n');

    const projectPatterns = agentProfile.contextPatterns.projectSpecific[currentProject]
      ? `\nProject-specific patterns:\n${JSON.stringify(agentProfile.contextPatterns.projectSpecific[currentProject], null, 2)}`
      : '';

    return `
## Your Learned Strengths
${topStrengths || 'None yet'}

## Your Known Weaknesses
${topWeaknesses || 'None yet'}

## Universal Patterns
${JSON.stringify(agentProfile.contextPatterns.universal, null, 2)}
${projectPatterns}`;
  }
}

export const promptCacheManager = new PromptCacheManager();
```

---

## 4. Phase 3: Integration with Agent Initialization (2 days)

### 4.1 Agent Startup Pipeline

**File:** `backend/src/agents/agentInitializer.ts`

```typescript
import { Agent } from '@anthropic-ai/sdk';
import { promptCacheManager } from '../services/promptCacheManager';
import { profileCache } from '../services/profileCache';
import { chatHistory } from '../services/chatHistory';

export async function initializeAgent(
  agentId: string,
  userId: string,
  sessionId: string,
  currentProject: string
): Promise<Agent> {
  // 1. Load profiles
  const userProfile = await profileCache.loadUserProfile(userId);
  const agentProfile = await profileCache.loadAgentProfile(agentId);

  // 2. Build system prompt with cached context
  const { systemPrompt, cacheKey } = await promptCacheManager.buildSystemPrompt(
    agentId,
    userId,
    currentProject
  );

  // 3. Get recent chat history for context
  const recentMessages = await chatHistory.getContextMessages(sessionId, 2000);

  // 4. Initialize agent with Claude SDK
  const agent = new Agent({
    model: 'claude-opus',
    systemPrompt,
    tools: [], // Your registered tools
    maxIterations: 10,
  });

  // 5. Attach metadata for hook system
  (agent as any)._metadata = {
    agentId,
    userId,
    sessionId,
    cacheKey,
    projectContext: currentProject,
  };

  return agent;
}
```

---

## 5. Phase 4: Cross-Project Migration (2 days)

### 5.1 Project Context Manager

**File:** `backend/src/services/projectContextManager.ts`

```typescript
import { profileCache, AgentProfile } from './profileCache';

export class ProjectContextManager {
  async migrateProfileToNewProject(
    agentId: string,
    oldProject: string,
    newProject: string
  ): Promise<void> {
    const profile = await profileCache.loadAgentProfile(agentId);

    // Clear project-specific context from old project
    delete profile.contextPatterns.projectSpecific[oldProject];

    // Initialize new project context (empty for first time)
    if (!profile.contextPatterns.projectSpecific[newProject]) {
      profile.contextPatterns.projectSpecific[newProject] = {};
    }

    // Invalidate prompt cache (will regenerate on next init)
    profile.promptCacheV1 = '';

    await profileCache.saveAgentProfile(profile);
  }

  async detectProjectChange(currentProject: string, previousProject: string): Promise<boolean> {
    return currentProject !== previousProject;
  }
}

export const projectContextManager = new ProjectContextManager();
```

---

## 6. Memory Lifecycle: Consolidation & Decay (2 days)

Cross-cutting concern that touches Phase 1 schema and Phase 2 code. Without this layer, profile JSON files grow unbounded and top-K rankings stagnate with stale lessons. Implements human-memory dynamics: **repetition strengthens, time and disuse weaken, capacity is bounded → forces specialization**.

### 6.1 Three forces

| Force | Mechanism | Status |
|-------|-----------|--------|
| **Consolidation** | `observedCount++`, `confidence += 0.05` on repeat observation | Already in Phase 2 plan |
| **Decay** | Exponential decline of effective score with time-since-last-use, weighted by topic affinity | NEW — this section |
| **Eviction** | When over capacity, drop lowest-scored entry (not FIFO, not random) | NEW — this section |

### 6.2 Schema additions

Extend each strength/weakness entry in AgentProfile with timestamp and usage fields:

```typescript
strengths: Array<{
  skill: string;
  context: string;
  observedCount: number;
  appliedCount: number;        // NEW: times this lesson was actually used in prompt cache
  confidence: number;          // 0–1
  lastObservedAt: string;      // NEW: ISO 8601, updated on every observedCount++
  lastAppliedAt: string;       // NEW: ISO 8601, updated when entry is selected for prompt
  createdAt: string;           // NEW: total-lifespan tracking
}>;

weaknesses: Array<{
  pitfall: string;
  impact: string;
  observedCount: number;
  avoidedCount: number;        // NEW: analogous to appliedCount
  avoidanceScore: number;      // 0–1
  lastObservedAt: string;      // NEW
  lastAvoidedAt: string;       // NEW
  createdAt: string;           // NEW
}>;
```

`UserProfile.globalPatterns.topicAffinities` already exists — used as decay weight (high affinity → slower decay).

The `Array<>` shape is intentional and stays the source of truth. See [§6.6](#66-in-memory-layout-array--secondary-map-index) for the rationale and the transient-index pattern used in batch operations.

### 6.3 Score formula

The "should this be in top-K" score:

```
score = confidence * decay_factor * topic_weight

decay_factor = exp(-Δt / τ)
  Δt           = (now - lastAppliedAt) in days; fallback to lastObservedAt
  τ            = base_half_life * (1 + topic_affinity)

base_half_life = 30 days (tunable)
topic_weight   = 0.5 + topic_affinity   // affinity 0 → 0.5x, affinity 1 → 1.5x
```

Worked example — same lesson, two topics:
- `confidence=0.9`, last used 30 days ago, topic affinity `1.0`: τ=60, decay≈0.61, weight=1.5 → score ≈ **0.82**
- Same lesson, topic affinity `0.0`: τ=30, decay≈0.37, weight=0.5 → score ≈ **0.17**

→ Same lesson decays ~5× faster in a topic the user doesn't engage with. Natural specialization toward what the user actually does.

### 6.4 Capacity tiers (per agent's underlying model)

| Model | top_K_strengths | top_K_weaknesses | MAX_STRENGTHS | MAX_WEAKNESSES |
|-------|-----------------|------------------|---------------|----------------|
| Opus | 5 | 5 | 150 | 150 |
| Sonnet | 3 | 3 | 75 | 75 |
| Haiku | 2 | 2 | 30 | 30 |

Rationale: larger models tolerate wider working sets without losing focus; smaller models need stricter specialization to avoid noise. When `applyLessons` would push count above MAX_*, evict the entry with the lowest current score.

### 6.5 Where each operation hooks in

| Operation | When | What runs |
|-----------|------|-----------|
| `loadAgentProfile` | session start | No mutation; scores computed lazily on read |
| `applyLessons` | after execution hook fires | Increment observedCount + confidence; touch lastObservedAt; evict by score if over MAX_* |
| `buildSystemPrompt` | agent init | Sort by score, take top_K, increment appliedCount + lastAppliedAt for selected |
| `compactProfile` (NEW) | every N sessions or on profile load if stale | Hard prune entries with score < HARD_PRUNE_THRESHOLD; persist |

### 6.6 In-memory layout: Array + secondary Map index

**Decision (after expert review, 2026-04-25):** keep `strengths` and `weaknesses` as plain `Array<Entry>` — source of truth, JSON-native, no API friction. Build a transient `Map<title, Entry>` only inside hot batch paths (e.g. `applyLessons` iterating many lessons). Do not persist any index. Recompute scores on demand; never pre-sort.

#### Why not heap / skip-list / sorted set

Score is **time-dependent**: `Δt` advances every second, so any pre-sorted structure becomes invalid the moment you stop looking at it. The standard pattern for continuously-decaying scores at sub-1000-entry scale is "keep entries unsorted, compute score on access." At n≤150 a full re-sort costs ~150 × log₂(150) ≈ 1100 score computations ≈ 50–200µs in V8 — three orders of magnitude under the 50ms budget. Heaps, skip lists, and sorted sets earn their keep past n>10⁴, not here.

#### find-by-title strategy

| Caller | Pattern |
|--------|---------|
| One-off lookup | `findStrength(profile, title)` / `findWeakness(profile, title)` helpers — wrap `.find()` today, become the single swap point for embedding-based semantic dedup later |
| Batch loop (e.g. `applyLessons` over many lessons) | Build `Map<title, Entry>` once before the loop with `buildStrengthIndex(profile)`, use `.get()` inside, discard after |

The Map is purely a transient optimization. **Never persisted, never returned from `loadAgentProfile`.**

#### Future embeddings (no structure rewrite)

When semantic dedup arrives: add `embedding?: Float32Array` field to each entry. `findStrength` swaps from `.find()` to brute-force cosine over the array (~115K multiplies for 150 vectors of dim 768 ≈ sub-millisecond). HNSW/FAISS only justify their complexity past ~10⁴ vectors. Persist embeddings inline with their entry — never in a separate file (drift hazard).

#### Persistence invariant

> **Array → disk. Indexes → memory only. Rebuild every load.**

If we ever serialize an index we open the door to silent drift after partial writes. One source of truth on disk; everything else is derived.

### 6.7 Code changes

**File:** `backend/src/services/memoryLifecycle.ts` (new)

```typescript
export const memoryLifecycleConfig = {
  baseHalfLifeDays: 30,
  hardPruneThreshold: 0.05,
  confidenceObserveBoost: 0.05,
  confidenceApplyBoost: 0.10,    // applied lesson > merely observed
  topicWeightFloor: 0.5,
  defaultTopicAffinity: 0.5,
  compactionEverySessions: 50,
};

export function computeScore(
  entry: { confidence?: number; avoidanceScore?: number; lastAppliedAt?: string; lastAvoidedAt?: string; lastObservedAt: string },
  topicAffinity: number = memoryLifecycleConfig.defaultTopicAffinity
): number {
  const lastUsedISO = entry.lastAppliedAt ?? entry.lastAvoidedAt ?? entry.lastObservedAt;
  const deltaDays = (Date.now() - new Date(lastUsedISO).getTime()) / 86400000;
  const tau = memoryLifecycleConfig.baseHalfLifeDays * (1 + topicAffinity);
  const decayFactor = Math.exp(-deltaDays / tau);
  const topicWeight = memoryLifecycleConfig.topicWeightFloor + topicAffinity;
  const strength = entry.confidence ?? entry.avoidanceScore ?? 0;
  return strength * decayFactor * topicWeight;
}

// ─── Find-by-title helpers (single swap point for future semantic lookup) ─────

export function findStrength(
  profile: AgentProfile,
  title: string
): AgentProfile['strengths'][number] | undefined {
  // v1: exact-string match. v2: nearest-neighbor over embeddings, threshold-gated.
  return profile.strengths.find(s => s.skill === title);
}

export function findWeakness(
  profile: AgentProfile,
  title: string
): AgentProfile['weaknesses'][number] | undefined {
  return profile.weaknesses.find(w => w.pitfall === title);
}

// ─── Transient batch indexes (build inside hot loops, never persist) ──────────

export function buildStrengthIndex(
  profile: AgentProfile
): Map<string, AgentProfile['strengths'][number]> {
  return new Map(profile.strengths.map(s => [s.skill, s]));
}

export function buildWeaknessIndex(
  profile: AgentProfile
): Map<string, AgentProfile['weaknesses'][number]> {
  return new Map(profile.weaknesses.map(w => [w.pitfall, w]));
}

export interface CapacityTier {
  topK_strengths: number;
  topK_weaknesses: number;
  MAX_STRENGTHS: number;
  MAX_WEAKNESSES: number;
}

export function tierForAgent(agentId: string): CapacityTier {
  // Map agent → underlying model tier. Concrete map lives wherever agents are registered.
  // Defaults to Sonnet tier.
  return { topK_strengths: 3, topK_weaknesses: 3, MAX_STRENGTHS: 75, MAX_WEAKNESSES: 75 };
}
```

**File:** `backend/src/services/lessonExtractor.ts` — eviction in `applyLessons` (uses transient Map index)

```typescript
import {
  computeScore,
  tierForAgent,
  memoryLifecycleConfig,
  buildStrengthIndex,
  buildWeaknessIndex,
} from './memoryLifecycle';

async applyLessons(agentId: string, lessons: Lesson[], userProfile: UserProfile) {
  const profile = await profileCache.loadAgentProfile(agentId);
  const tier = tierForAgent(agentId);
  const now = new Date().toISOString();
  const affinity = (key: string) =>
    userProfile.globalPatterns.topicAffinities[key] ?? memoryLifecycleConfig.defaultTopicAffinity;

  // Transient O(1) lookup for the duration of this loop. Discarded after; never persisted.
  const byStrength = buildStrengthIndex(profile);
  // const byWeakness = buildWeaknessIndex(profile); // when handling weaknesses below

  for (const lesson of lessons) {
    if (lesson.category === 'strength') {
      const existing = byStrength.get(lesson.title);
      if (existing) {
        existing.observedCount++;
        existing.confidence = Math.min(1, existing.confidence + memoryLifecycleConfig.confidenceObserveBoost);
        existing.lastObservedAt = now;
      } else {
        const entry = {
          skill: lesson.title,
          context: lesson.context,
          observedCount: 1,
          appliedCount: 0,
          confidence: lesson.confidence,
          lastObservedAt: now,
          lastAppliedAt: now,
          createdAt: now,
        };
        profile.strengths.push(entry);
        byStrength.set(lesson.title, entry);

        if (profile.strengths.length > tier.MAX_STRENGTHS) {
          profile.strengths.sort((a, b) =>
            computeScore(b, affinity(b.skill)) - computeScore(a, affinity(a.skill))
          );
          profile.strengths.length = tier.MAX_STRENGTHS;
          // byStrength now contains a stale reference to the evicted entry —
          // safe because we discard the Map at end of this function and never read
          // an evicted title in this loop (the just-pushed entry's title is unique).
        }
      }
    } else {
      // weaknesses analogous: byWeakness.get(...), lastAvoidedAt, avoidedCount, avoidanceScore
    }
  }
  await profileCache.saveAgentProfile(profile);
}
```

**File:** `backend/src/services/promptCacheManager.ts` — sort by score, touch lastAppliedAt

```typescript
const tier = tierForAgent(agentId);
const affinity = (key: string) =>
  userProfile.globalPatterns.topicAffinities[key] ?? memoryLifecycleConfig.defaultTopicAffinity;

// Spread copies array slots but keeps element references — mutating a topStrengths
// entry below mutates the original in agentProfile.strengths. No find() needed.
const topStrengths = [...agentProfile.strengths]
  .sort((a, b) => computeScore(b, affinity(b.skill)) - computeScore(a, affinity(a.skill)))
  .slice(0, tier.topK_strengths);

const now = new Date().toISOString();
for (const s of topStrengths) {
  s.appliedCount++;
  s.confidence = Math.min(1, s.confidence + memoryLifecycleConfig.confidenceApplyBoost);
  s.lastAppliedAt = now;
}
await profileCache.saveAgentProfile(agentProfile);
```

**File:** `backend/src/services/profileCache.ts` — periodic compaction

```typescript
async compactProfile(agentId: string, userProfile: UserProfile): Promise<void> {
  const profile = await this.loadAgentProfile(agentId);
  const affinity = (key: string) =>
    userProfile.globalPatterns.topicAffinities[key] ?? memoryLifecycleConfig.defaultTopicAffinity;

  profile.strengths = profile.strengths.filter(s =>
    computeScore(s, affinity(s.skill)) >= memoryLifecycleConfig.hardPruneThreshold
  );
  profile.weaknesses = profile.weaknesses.filter(w =>
    computeScore(w, affinity(w.pitfall)) >= memoryLifecycleConfig.hardPruneThreshold
  );

  await this.saveAgentProfile(profile);
}
```

### 6.8 Open questions

- **Per-agent τ?** Should `manager#1` (high-level dispatcher, slow-changing patterns) carry a longer half-life than `coder#1` (code idioms rotate faster)? Current proposal: same τ for all, only `MAX_*` differs by tier. Revisit post-MVP.
- **Apply-boost vs observe-boost.** Proposal weights "applied successfully" 2× higher than "passively observed". Empirical question — track applied/observed ratio after a few weeks of real usage and tune.
- **Topic taxonomy.** `topicAffinities` is keyed by topic string — who maintains the mapping? Initial proposal: `lessonExtractor` classifies each lesson into a fixed taxonomy (`{llm-architecture, ui-design, backend, infra, debugging, ...}`). Open: how rigid this taxonomy needs to be vs. allowing free-form topics.

---

## 7. Testing Strategy

### Unit Tests
- ProfileCache load/save
- Lesson extraction patterns
- Prompt cache generation

### Integration Tests
- Full agent initialization with profiles
- Hook firing + lesson application
- Project migration

### E2E Tests
- Session 1: Agent learns something
- Session 2: Agent remembers + applies lesson
- Project switch: Universal patterns transfer, project-specific clears

---

## 8. Success Metrics (MVP)

- ✅ Profiles persist across sessions (UserProfile + AgentProfile saved/loaded)
- ✅ System prompt includes cached context (~2–4KB)
- ✅ Lessons extracted after execution (at least 3 patterns recognized)
- ✅ Prompt cache reduces token overhead by ≥40% vs. baseline
- ✅ Cross-project migration works (universal patterns stay, project-specific clears)
- ✅ Profile JSON files stay bounded under repeated session usage (≤ MAX_* per tier; lowest-score entries evicted)
- ✅ Stale lessons (low score after decay) drop out of top-K within expected window (~2× half-life with no re-observation)

---

## 9. Timeline

| Phase | Tasks | Duration | Owner |
|-------|-------|----------|-------|
| 1 | ProfileCache, ChatHistory ext., Hooks foundation | 3 days | coder#1 |
| 2 | Lesson extraction, Prompt cache manager | 3–5 days | coder#2 + llm-specialist#1 |
| 3 | Agent initializer, integration | 2 days | coder#1 |
| 4 | Project context manager, migration | 2 days | coder#2 |
| 5 | Memory Lifecycle (decay, eviction, capacity tiers, compaction) | 2 days | llm-specialist#1 |
| **Total** | MVP completion | **12–16 days** | Team |

---

**Document Version:** 1.2
**Status:** Ready for development handoff
**Last Updated:** 2026-04-25
**Changelog 1.1:** Added §6 Memory Lifecycle (consolidation/decay/eviction with formulas, capacity tiers, code changes). Added Layer 5 to Strategy. Added 2 success metrics + Phase 5 to timeline.
**Changelog 1.2:** Locked in data structure choice after expert review — Array stays source of truth, transient `Map<title, Entry>` indexes built inside hot batch paths only, never persisted. New §6.6 "In-memory layout" with rationale (time-dependent scores invalidate pre-sorted structures). Added `findStrength` / `findWeakness` / `buildStrengthIndex` / `buildWeaknessIndex` helpers in `memoryLifecycle.ts` as single swap point for future embedding-based semantic dedup. Updated `lessonExtractor.applyLessons` to use the transient index; cleaned redundant `.find()` from `promptCacheManager`. Renumbered §6.6 Code changes → §6.7, §6.7 Open questions → §6.8.
