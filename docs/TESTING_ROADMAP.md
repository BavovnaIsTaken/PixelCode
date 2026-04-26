# PixelCode Testing Roadmap (Phases 1–5)

**Master testing strategy** синхронізована з [ROADMAP.md](ROADMAP.md) і [STRATEGY.md](STRATEGY.md).

---

## Phase 1: Core Game Persistence & Economy ✅ DONE

**Target**: Foundation for all gameplay — if this breaks, nothing works.  
**Status**: **COMPLETE — 91 tests, all passing**  
**Commit**: `15fdb10` (2026-04-26)

### ✅ What's Tested

| Component | File | Tests | Coverage |
|---|---|---|---|
| GameState | `test/models/game_state_test.dart` | 29 | ~95% |
| AgentGameData | `test/models/agent_game_data_test.dart` | 22 | ~98% |
| OfficeExpansion | `test/models/office_expansion_test.dart` | 22 | ~100% |
| GamePersistenceService | `test/services/game_persistence_service_test.dart` | 12 | ✓ |
| TaskOutcome | `test/services/task_outcome_test.dart` | 6 | ✓ |

---

### ✅ GameState (29 tests) — `test/models/game_state_test.dart`

**Agent hiring & capacity:**
- Fresh state starts with no agents
- `canHireMore` respects office level capacity (garage 3 → campus 100)
- Agents persist across nickname changes
- `roleCount()` and `instancesOfRole()` filtering
- `hiredAgentIds` preserves insertion order

**Office tier progression:**
- `nextLevel` chain: garage → smallOffice → modernOffice → techHub → campus
- Effective grid dimensions account for expansions (7×5 → 10×7 → ... → 22×18)
- `playableTiles` excludes 1-tile wall borders
- Expansion clamping (negative & overflow)
- `isOfficeFullyExpanded` detection
- `nextExpansion` returns null when fully expanded

**Nickname changes:**
- First 3 changes are free
- Cost accumulates after free pool exhausted (200₲ per change)

**Cosmetics & equipment:**
- `equippedFor()` returns null/cosmetic ID correctly
- `displayNickname` applies decorator

**JSON serialization:**
- Full round-trip preservation of all fields
- Out-of-bounds clamping in fromJson
- Furniture/room filtering when loading oversized saves

**Office level properties:**
- `maxAgents` increases: 3→6→12→25→100
- `speedModifier` scales: 0.75→1.0→1.1→1.25→1.5
- `upgradeCost` exponential curve: 0→1K→8K→50K→500K
- `basePlayableTiles` / `maxPlayableTiles` sensibility

**Hardware tier properties:**
- `nextTier` chains through all 6 tiers
- `speedModifier` increases monotonically (0.5x → 2.0x)
- `cost` increases: 0→200→500→1500→5000→15000

**Skill upgrade costs:**
- `upgradeCost(level)` = `baseCost * (level + 1)`
- All skills have sensible base costs

---

### ✅ AgentGameData (22 tests) — `test/models/agent_game_data_test.dart`

**Initialization:**
- Fresh agent: level 1, 0 XP, no skills
- Hardware defaults to `oldLaptop` (0.5x speed)
- Nickname is player-editable
- Role type determines behavior template

**Skill management:**
- Agents can have 0 or multiple skills
- Skill levels are non-negative
- All 5 skill types can coexist

**Level & XP progression:**
- Agents can level up beyond 1
- XP accumulates towards next level
- Level construction allows values > `maxAgentLevel` (validation in external code)

**Hardware tier progression:**
- Starts with `oldLaptop` (0.5x speed)
- Can upgrade to `serverRack` (2.0x speed)
- Tiers progress monotonically

**JSON serialization:**
- Full round-trip with all fields preserved
- Missing optional fields get sensible defaults
- Skills map round-trips correctly

**Copy constructor:**
- `copyWith()` preserves unchanged fields
- Hardware upgrade works
- Skill addition works

**Edge cases:**
- Instance ID can contain special characters (`coder#42-special_id`)
- Nickname can be empty string
- Very high XP values (999999999) are allowed
- All 5 skill types can be set simultaneously

---

### ✅ OfficeExpansion (22 tests) — `test/models/office_expansion_test.dart`

**Garage tier:**
- 5 expansion steps
- Grid grows: 7×5 → 10×7
- Costs increase monotonically: 80→140→200→280→380 ₲
- Max playable tiles: 40 (8×5 inner area)

**Small Office tier:**
- 8 expansion steps
- Grid grows: 9×6 → 13×10
- First expansion costs more than garage's first

**Expansion cost formula:**
- Each tier is progressively more expensive
- Upgrade to next tier > last expansion of previous tier
- Exponential scaling across tiers

**Playable tiles calculation:**
- `playableTiles = (cols-2) × (rows-2)` (excludes wall border)
- Campus is largest office
- Full expansion progression verified

**Grid boundary calculations:**
- 1-tile wall border on all sides is consistent
- Expansion formula matches effective cols/rows

**Upgrade costs:**
- Garage: 0 ₲ (base tier)
- Scaling: 0→1K→8K→50K→500K
- Ratio between tiers: 5-8x per tier

**Edge cases & clamping:**
- `effectiveCols(-999)` returns base size
- `effectiveCols(999)` returns max size
- `playableTiles()` always positive

**Integration with GameState:**
- `fromJson` clamps expansions to tier max
- Tier progression increases max agent capacity
- Playable tiles grow correctly with expansions

---

### ✅ GamePersistenceService (12 tests) — `test/services/game_persistence_service_test.dart`

**Schema migration:**
- Hard wipe on major version mismatch (with whitelist preservation)
- Soft migration for one-version-back (V5→V6 additive)
- `schemaResetFlag` set on hard reset

**PlacedRoom:**
- V5 JSON loads with default rotation/skin overrides
- Rotation 90/270 swaps footprint axes
- Skin overrides round-trip through JSON

**PlacedCorridor:**
- Round-trips through JSON with all fields

---

### ✅ TaskOutcome (6 tests) — `test/services/task_outcome_test.dart`

**Chance functions:**
- `bugChance`: 0.4 at 0 precision, 0 at 14+
- `critChance`: 0.02 × creativity, capped at 1.0
- `completionSuccessChance`: 0.85 base, capped at 1.0

**Outcome rolls:**
- High-skill agents almost always get clean results
- Low-reliability agents often get incomplete
- Low-precision agents often get bugs
- Crit only fires on divergent tasks
- All divergent task types covered

---

### 📊 Phase 1 Metrics

| Metric | Value |
|--------|-------|
| Total tests | 91 |
| Files created | 3 |
| Assertions | ~250+ |
| Test execution | ~15–20s |
| Coverage: GameState | ~95% |
| Coverage: AgentGameData | ~98% |
| Coverage: OfficeExpansion | ~100% |

---

### 🚀 Ready for Phase 2

All core game state operations verified. Safe to build Personalization UI on top.

**Run Phase 1 tests:**
```bash
flutter test test/models/game_state_test.dart \
              test/models/agent_game_data_test.dart \
              test/models/office_expansion_test.dart \
              test/services/game_persistence_service_test.dart \
              test/services/task_outcome_test.dart
```

---

## Phase 2: Agent Personalization System 🔄 IN QUEUE (Q3 2026)

**Target**: Memory lifecycle, lesson extraction, trait management — foundation for custom agents.  
**Status**: ❌ **NOT STARTED** — 0 tests  
**Blocking**: Phase 3 (Custom Agent Spawn)

### 📝 What Needs Testing

#### A. Memory Lifecycle (`server/src/memory_lifecycle.ts`)

**Tests needed** (~15 tests):
- [ ] Lesson scoring: quality, frequency, recency
- [ ] Capacity bounds: max lessons per agent (e.g., 100)
- [ ] Eviction order: LRU vs. priority-based
- [ ] Decay simulation: lessons weaken over time
- [ ] Clock mocking: advance time, verify decay rates
- [ ] Tier-based eviction: skill cap limits slots
- [ ] Round-trip: save/load agent memory state

**Property tests**:
- `total_lessons <= capacity` (always)
- `evicted_lessons.score <= kept_lessons.score` (LRU)
- `aged_lesson.confidence < fresh_lesson.confidence` (decay)

**Integration**:
- GameState + MemoryLifecycle: 100 agents, each with max lessons
- Persistence: memory survives save/load

---

#### B. Lesson Extractor (`server/src/lesson_extractor.ts`)

**Tests needed** (~12 tests):
- [ ] Pattern recognition: extract task insights from outcomes
- [ ] Quality filtering: high-confidence lessons only
- [ ] Topic affinity: skill-to-task mapping
- [ ] Contradiction handling: conflicting lessons
- [ ] Edge cases: empty input, no patterns, noise

**Example test**:
```
Given: 10 successful code-review tasks
When: extractor processes outcomes
Then: lesson "improves on precision-heavy tasks" scored high
```

---

#### C. Trait Memory (`lib/models/agent_trait.dart`)

**Tests needed** (~10 tests):
- [ ] Trait creation from lessons
- [ ] Trait scoring: sum of contributing lessons
- [ ] Trait application: inject into system prompt
- [ ] Trait updates: lessons flow → trait changes
- [ ] Trait expiry: old traits fade

---

#### D. Profile Cache (`server/src/profile_cache.ts`)

**Tests needed** (~8 tests):
- [ ] Cache hit/miss rates
- [ ] Staleness detection
- [ ] Time-based invalidation
- [ ] Concurrent access safety (if applicable)

---

#### E. Personalization Orchestrator (`server/src/personalization.ts`)

**Tests needed** (~6 tests):
- [ ] Full lifecycle: lesson → trait → prompt injection
- [ ] Integration: memory + extraction + caching
- [ ] Performance: batch 100 lessons, time it
- [ ] Persistence: orchestrator state survives reload

---

#### F. UI Tests (Flutter)

**Widget tests** (~12 tests):
- [ ] `PersonalizationPanel`: display lessons
- [ ] Lesson edit UI: allow/deny edits
- [ ] Trait inspector: show affinity scores
- [ ] Consent flow: opt-in for recording
- [ ] Per-agent facilitator binding: dropdown

**Test setup**:
```dart
testWidgets('PersonalizationPanel shows lessons', (tester) async {
  final state = GameState(agents: {
    'coder#1': AgentGameData(...),
  });
  await tester.pumpWidget(testApp(state));
  // Tap personalization, verify lessons listed
});
```

---

### 📊 Phase 2 Test Target

**~70 tests** (server logic + UI)  
**Duration**: 2–3 weeks (1 dev)  
**Blocking**: None (parallel with Android deploy polish)

---

## Phase 3: Custom Agent Spawn & Self-Play 📋 QUEUED (Q3 2026)

**Target**: MVP for ecosystem — users create + export agents.  
**Status**: ❌ **NOT STARTED** — 0 tests  
**Blocking**: Phase 4 (Marketplace v1)  
**Depends on**: Phase 2 (Personalization UI)

### 📝 What Needs Testing

#### A. Self-Play Simulation (`server/src/dungeon.ts` extension)

**Tests needed** (~15 tests):
- [ ] Run agent on same task N times
- [ ] Select best attempt
- [ ] Worst attempt → correction signal
- [ ] Data collection: "self-play generated X lessons"
- [ ] Timeout/safety: agent can't loop infinitely
- [ ] Edge cases: task too hard (0% success), too easy (100%)

**Property test**:
```
forall n in [1..100]:
  best_attempt.score >= avg_score >= worst_attempt.score
```

---

#### B. Agent JSON Export/Import

**Tests needed** (~12 tests):
- [ ] Full agent round-trip: create → export JSON → import → verify
- [ ] Validation: schema checks before listing
- [ ] Uniqueness: instanceId collisions
- [ ] Backwards compat: old agent JSON loads

**Test example**:
```dart
test('agent export/import preserves skills', () {
  final original = AgentGameData(
    instanceId: 'coder#1',
    skills: {SkillType.precision: 7, SkillType.speed: 5},
  );
  final json = AgentExporter.export(original);
  final restored = AgentImporter.import(json);
  expect(restored.skills, original.skills);
});
```

---

#### C. Agent Signature/Identity

**Tests needed** (~8 tests):
- [ ] Unique ID generation (UUID or hash)
- [ ] Creation timestamp preservation
- [ ] Training history tracking
- [ ] Signature verification (if signed)

---

#### D. Custom Agent Spawn Flow (UI)

**Widget tests** (~10 tests):
- [ ] Form: system prompt input, role bias sliders, skill weights
- [ ] Validation: prompt length, bias ranges
- [ ] Preview: show resulting agent stats
- [ ] Confirmation: "Create Agent" triggers backend
- [ ] Personality presets: templates for quick start

---

#### E. Self-Play Integration

**Integration tests** (~6 tests):
- [ ] User spawns agent → self-play runs → agent improved
- [ ] Progress tracking: "3/10 training runs completed"
- [ ] Results: before/after agent stats shown

---

### 📊 Phase 3 Test Target

**~50 tests** (self-play logic + UI)  
**Duration**: 2–3 weeks (1 dev)  
**Blocking**: Marketplace v1 depends on this

---

## Phase 4: Marketplace v1 🎯 QUEUED (Q4 2026)

**Target**: Agent trading infrastructure.  
**Status**: ❌ **NOT STARTED** — 0 tests  
**Blocking**: Phase 5+ (real-money economics)  
**Depends on**: Phase 3 (Custom Agent Spawn)

### 📝 What Needs Testing

#### A. Agent Quality Scoring

**Tests needed** (~10 tests):
- [ ] Standardized dungeon challenges (fixed tasks)
- [ ] Score: success rate on challenges
- [ ] Minimum quality threshold before listing
- [ ] Scoring determinism: same agent, same score

**Property test**:
```
agent_A.skills_sum > agent_B.skills_sum
  => agent_A.quality_score >= agent_B.quality_score
```

---

#### B. Marketplace Backend (Server)

**Tests needed** (~15 tests):
- [ ] Agent listing creation (DB or JSON store)
- [ ] Listing retrieval (filter by role, sort by rating)
- [ ] Rating/review system (1–5 stars, comment)
- [ ] Anti-collusion: account X can't trade with itself

---

#### C. Marketplace UI (Flutter)

**Widget tests** (~12 tests):
- [ ] Catalog display: grid of agents
- [ ] Filtering: by role, skill, rating
- [ ] Listing detail: full stats, reviews, author
- [ ] Purchase flow: "Buy Agent" → transaction
- [ ] Author view: "My Listings", analytics

---

#### D. Marketplace Commission

**Tests needed** (~6 tests):
- [ ] Calculate 15–20% commission
- [ ] Track total marketplace revenue
- [ ] Player payout calculation (80–85% of sale)
- [ ] Commission on real-money conversions

---

#### E. Crowdsourced Training Data Pool (Opt-In)

**Tests needed** (~8 tests):
- [ ] Consent flow: "Share gameplay?"
- [ ] Anonymization: remove identifying info
- [ ] Aggregation: batch gameplay data
- [ ] Opt-out: user can revoke consent
- [ ] Privacy: no sensitive data leaked

---

### 📊 Phase 4 Test Target

**~50 tests** (backend + UI + economics)  
**Duration**: 3–4 weeks (1 dev, coordinate with legal review)  
**Blocking**: Real-money operations (Phase 5)

---

## Phase 5: Backend Abstraction & Training 🔮 QUEUED (Q1 2027)

**Target**: Multiple agent backends + Foundation Model.  
**Status**: ❌ **NOT STARTED** — 0 tests  
**Depends on**: Phase 4 (Marketplace v1 API established)

### 📝 What Needs Testing

#### A. AgentBackend Interface

**Tests needed** (~8 tests):
- [ ] `AgentBackend.dispatch()` contract
- [ ] `AgentBackend.executeTools()` variations
- [ ] Session lifecycle (create, execute, cleanup)
- [ ] Error handling (timeout, invalid tool, API down)

---

#### B. ClaudeAgentSdkBackend (Refactor)

**Tests needed** (~12 tests):
- [ ] All existing dungeon/task logic still works
- [ ] No regression in session management
- [ ] Tool use compatibility maintained

---

#### C. LocalRuntimeBackend (Ollama/MLX)

**Tests needed** (~15 tests):
- [ ] Ollama integration (spawn, health check, shutdown)
- [ ] Model loading (llama3.2:1b, phi4-mini)
- [ ] Prompt formatting (match Claude conventions)
- [ ] Tool use parsing (JSON output → tool calls)
- [ ] Latency benchmarks (local vs. cloud)

---

#### D. Tier Routing (`local-fast` / `local-quality` / `cloud`)

**Tests needed** (~10 tests):
- [ ] Task → tier mapping (difficulty-based)
- [ ] Model selection per tier
- [ ] Fallback chain (cloud ↓ on local failure)
- [ ] Cost tracking (tokens for cloud, CPU for local)

---

#### E. Distillation Pipeline (`server/src/distillation.ts`)

**Tests needed** (~10 tests):
- [ ] Cloud Opus generates training examples
- [ ] Examples filtered by quality
- [ ] Data formatted for fine-tuning
- [ ] Versioning (training set v1.0, v1.1, etc.)

---

#### F. LoRA Adapter Spec

**Tests needed** (~6 tests):
- [ ] Adapter format serialization
- [ ] Adapter merge: weight averaging
- [ ] Adapter loading + inference
- [ ] Adapter versioning/compatibility

---

#### G. Self-Distillation Loop

**Tests needed** (~12 tests):
- [ ] Self-play → training data collection
- [ ] Local judge (Haiku) scores attempts
- [ ] Best attempts → adapter gradient steps
- [ ] Overnight training (scheduling, thermal limits)
- [ ] Adapter update reflection in agent stats

---

#### H. On-Device Training (Alpha)

**Tests needed** (~8 tests):
- [ ] Device capability check (NPU available?)
- [ ] Memory pressure handling
- [ ] Thermal throttling simulation
- [ ] QLoRA 1B training benchmark
- [ ] Error recovery (interrupted training)

---

### 📊 Phase 5 Test Target

**~80 tests** (backend abstraction + distillation + on-device)  
**Duration**: 4–6 weeks (1 dev + infrastructure setup)  
**Blocking**: Local AI era features

---

## Summary Table

| Phase | Component | Tests | Status | Duration | Blocker |
|---|---|---|---|---|---|
| **1** | Core Game State | 91 | ✅ DONE | Done | — |
| **2** | Personalization | ~70 | ❌ TODO | 2–3w | Phase 1 |
| **3** | Custom Agent Spawn | ~50 | ❌ TODO | 2–3w | Phase 2 |
| **4** | Marketplace v1 | ~50 | ❌ TODO | 3–4w | Phase 3 |
| **5** | Backend + Training | ~80 | ❌ TODO | 4–6w | Phase 4 |
| **TOTAL** | — | **~340 tests** | — | **~15–18w solo** | — |

---

## Testing Principles

### 1. **Unit tests first**
- Individual models (GameState, AgentGameData, etc.)
- Business logic functions (scoring, routing, merging)
- Edge cases and invariants

### 2. **Integration tests next**
- GameState ↔ Persistence
- Agent ↔ Dungeon judge
- Personalization ↔ Prompt cache
- Marketplace ↔ Backend abstraction

### 3. **UI tests last**
- Widget tree rendering
- User interactions (tap, drag, scroll)
- State mutations (form input → backend call)

### 4. **Property-based testing**
- Monotonicity: costs, stats, multipliers always increase per tier
- Invariants: hiring ≤ capacity, expansion ≤ max, quality ≥ threshold
- Consistency: round-trip preservation, determinism

### 5. **Performance tests**
- Memory usage (100 agents, each with 100 lessons)
- Serialization (100MB save file JSON)
- Distillation latency (training time per adapter)

---

## Quick Commands

**Run Phase 1 tests:**
```bash
flutter test test/models/game_state_test.dart \
              test/models/agent_game_data_test.dart \
              test/models/office_expansion_test.dart \
              test/services/game_persistence_service_test.dart \
              test/services/task_outcome_test.dart
```

**Run all tests (current):**
```bash
flutter test
```

**Run single test file:**
```bash
flutter test test/models/game_state_test.dart
```

**Run with coverage:**
```bash
flutter test --coverage
open coverage/index.html
```

---

## Notes for Future Sessions

- **Memory helpers**: Extract `GameState.withAgents()` helper for bulk setup (reuse in Phase 2+)
- **Mock patterns**: Clock mocking for decay tests, RNG seeding for outcome rolls
- **CI/CD**: Add GitHub Actions matrix for Flutter tests (macOS, Linux, Windows)
- **Benchmarks**: Baseline Phase 1 performance (should be <100ms per test)

---

**Last updated:** 2026-04-26  
**Owner**: @danylooliinyk  
**Sync with**: [ROADMAP.md](ROADMAP.md), [STRATEGY.md](STRATEGY.md)
