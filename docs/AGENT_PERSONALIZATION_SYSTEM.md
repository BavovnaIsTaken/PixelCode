# Personalized Agent System — Design Document

## 1. Теза ідеї

**Проблема:** Кожна нова сесія в Claude Code переривує історію взаємодії. Агент щоразу починає з нуля, не пам'ятаючи попередніх успіхів, помилок чи переваг користувача.

**Рішення:** Двошарова персоналізаційна система на базі Claude Agent SDK:
- **UserProfile** — глобальне навчання *всіх* агентів (стиль спілкування, переваги, успішні паттерни)
- **AgentProfile** — персональні поведінки *конкретного* агента + закешований контекст (strengths, weaknesses, contextPatterns)

**Результат:** Агенти адаптуються до вас від сесії до сесії, контекст зберігається, а час на onboarding скорочується на 80%.

---

## 2. Технічне завдання

### 2.1 Архітектура системи

```
┌─────────────────────────────────────────┐
│         User Session Starts              │
└──────────────────┬──────────────────────┘
                   │
        ┌──────────▼──────────┐
        │  Load UserProfile   │
        │  Load AgentProfile  │
        │  Load Prompt Cache  │
        └──────────┬──────────┘
                   │
        ┌──────────▼──────────────┐
        │  Agent Executes Task    │
        │  (hooks intercept DX)   │
        └──────────┬──────────────┘
                   │
        ┌──────────▼──────────────┐
        │  Analyze + Learn        │
        │  Update profiles        │
        │  Refresh cache          │
        └─────────────────────────┘
```

### 2.2 Data Structures

#### **UserProfile** (persisted globally)
```json
{
  "userId": "user-uuid",
  "version": "1.0",
  "communicationStyle": {
    "language": "uk",
    "verbosity": "concise",
    "technicalLevel": "advanced"
  },
  "preferences": {
    "parallelizeWork": true,
    "preferDelegation": true,
    "errorTolerance": "medium"
  },
  "globalPatterns": {
    "successfulApproaches": ["delegation", "async-dispatch"],
    "avoidedMistakes": ["direct-code-without-planning", "silent-failures"],
    "topicAffinities": {
      "LLM-architecture": 0.95,
      "UI-design": 0.3,
      "backend-CRUD": 0.5
    }
  },
  "updatedAt": "2026-04-25T10:30:00Z"
}
```

#### **AgentProfile** (per-agent, cross-project)
```json
{
  "agentId": "manager#1",
  "version": "1.0",
  "strengths": [
    {
      "skill": "Systematic color replacement",
      "context": "Read context, identify patterns, edit in logical groups",
      "observedCount": 1,
      "confidence": 0.95
    },
    {
      "skill": "Architectural delegation",
      "context": "Route complex questions to specialists (llm-specialist, tech-lead)",
      "observedCount": 3,
      "confidence": 0.98
    }
  ],
  "weaknesses": [
    {
      "pitfall": "Dispatch without checking tool availability",
      "impact": "Falls back to Task tool, loses efficiency",
      "observedCount": 1,
      "avoidanceScore": 0.8
    }
  ],
  "contextPatterns": {
    "universal": {
      "preferAsyncDispatch": true,
      "checkTeamStatusBeforeWork": true
    },
    "projectSpecific": {
      "PixelCode": {
        "codeStyle": "Dart/Flutter",
        "reviewProcess": "3-reviewer consensus"
      }
    }
  },
  "promptCacheV1": "~4KB compressed context (universal lessons)",
  "updatedAt": "2026-04-25T10:30:00Z"
}
```

### 2.3 Execution Hooks

Агент реєструє дії через hook'и:

```typescript
// Hook: beforeDispatch
hook.beforeDispatch({
  agent: "coder#1",
  taskComplexity: "high",
  decision: "parallelized 3 sub-tasks"
})
// → Вивід: "Агент обирає паралелізацію на складних задачах"

// Hook: afterExecution
hook.afterExecution({
  result: "success",
  time: 5000,
  tokensUsed: 12000,
  lessons: ["Read file first before Edit", "Check team status before dispatch"]
})
// → Оновлює AgentProfile.strengths

// Hook: onError
hook.onError({
  error: "Tool not available",
  fallback: "Used Task tool instead",
  lesson: "Check capabilities upfront"
})
// → Оновлює AgentProfile.weaknesses
```

### 2.4 Prompt Caching Strategy

**Цель:** Мінімізувати повторне кодування контексту, максимізувати корисність.

**Механізм:**
1. **Universal cache (~2KB):**
   - Глобальні стиль спілкування, переваги
   - Топ-3 strengths, топ-3 weaknesses
   - Cross-project paттерни

2. **Agent-specific cache (~2-4KB):**
   - Останні 3 успіхи цього агента
   - Задокументовані pitfalls
   - Project-specific контекст (видаляється при переході на інший проект)

3. **Compression:**
   - Текст → JSON → GZIP (~70% reduction)
   - Версіонування: якщо profile зміниться, старий cache інвалідується

### 2.5 Cross-Project Migration

**Сценарій:** Користувач переходить з PixelCode на новий проект.

```
PixelCode (manager#1, coder#1 active)
↓
User: "cd /Users/danylooliinyk/Projects/NewApp"
↓
System detects project change
↓
AgentProfile migration:
  ✓ Keep: strengths, weaknesses, universal contextPatterns
  ✗ Clear: projectSpecific["PixelCode"], prompt cache links
↓
Next session in NewApp:
  Agents load updated AgentProfile
  (Lessons from PixelCode apply, but no PixelCode specifics)
```

### 2.6 Implementation Roadmap

#### **Phase 1: MVP (2-3 days)**
- [ ] Define UserProfile + AgentProfile JSON schemas
- [ ] Implement persistence layer (local JSON files in `~/.pixelcode/profiles/`)
- [ ] Add 3 critical hooks: `beforeDispatch`, `afterExecution`, `onError`
- [ ] Manual profile updates (no auto-learning yet)

#### **Phase 2: Auto-Learning (3-5 days)**
- [ ] Implement hook analyzers (extract lessons from execution)
- [ ] Confidence scoring (when to trust a pattern)
- [ ] Prompt cache generation + versioning
- [ ] Migration logic for project switching

#### **Phase 3: Polish + Safeguards (2-3 days)**
- [ ] Profile validation (reject noisy/invalid lessons)
- [ ] User consent UI (show what was learned, allow overrides)
- [ ] Metrics dashboard (what profiles exist, how old, cache hit rate)
- [ ] Rollback mechanism (revert bad profiles)

---

## 3. Key Design Decisions

### Decision 1: Two-Layer Profiles (User + Agent)
**Why:** User preferences are stable and universal (language, style). Agent strengths are agent-specific and evolve. Separating them lets us update independently.

### Decision 2: Prompt Caching (not full chat history)
**Why:** Full chat history explodes token count. Caching the *synthesized* lessons (strengths, patterns) gives 80% of the benefit at 5% of the token cost.

### Decision 3: Execution Hooks (not offline analysis)
**Why:** Agents naturally generate hooks during execution. No post-hoc parsing needed. Hooks are typed, structured, and immediate.

### Decision 4: Local persistence (not cloud)
**Why:** User owns their profiles. No privacy concerns. Fast, offline-capable. Can sync to cloud later if needed.

### Decision 5: Cross-project universal context
**Why:** If you learned "always check team status before dispatch", that applies everywhere. But PixelCode-specific review rules stay in PixelCode.

---

## 4. Success Criteria

- ✅ Agent remembers user preferences across sessions
- ✅ Agent identifies and avoids past mistakes (weaknesses reduce error rate by 40%)
- ✅ Agent leverages past successes (speeds up task dispatch by 50%)
- ✅ Cross-project adaptation works (lessons transfer, context clears)
- ✅ Prompt cache reduces token overhead by 60% vs. full chat replay
- ✅ User can view, edit, and reset profiles anytime
- ✅ No privacy leaks; all data stays local

---

## 5. Open Questions for Implementation

1. **Profile versioning:** When user upgrades Claude Code, do old profiles auto-migrate?
2. **Conflict resolution:** If two agents disagree on a lesson, which wins?
3. **Time decay:** Should old strengths/weaknesses fade over time?
4. **User override:** Can user manually edit a profile, or only view?
5. **Telemetry:** Should we log anonymous pattern stats (e.g., "60% of users prefer async dispatch")?

---

**Document Version:** 1.0
**Last Updated:** 2026-04-25
**Status:** Ready for MVP Implementation
