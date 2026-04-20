# Agent Level / Skill / Archetype System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the agent/task/skill system so that agents have an explicit `level`, 5 capability-mapped skills (Speed/Precision/Creativity/Insight/Reliability), eволюційні архетипи на базі існуючого `TraitStore`, hybrid gating задач, Energy meter для LLM-токенів, та 3 нові ролі.

**Architecture:** Breaking-change rework of data model — `SkillType` замінюється на новий enum (5 значень), `AgentGameData` отримує `level/xp/archetype/quirkIds`, `TaskCard` — `requiredLevel/allowedRoles/taskType`. Старі save-и дропаються (schema version bump + toast). Server-side: `skillsToModel` перекалібровується, додається `reviewer_pass` wrapper і `energy_tracker`.

**Tech Stack:** Flutter/Dart (client, Riverpod), TypeScript/Node (server, Claude Agent SDK), WebSocket transport. Tests: `flutter_test` (client), `node:test` (server).

**Spec:** [docs/superpowers/specs/2026-04-20-agent-level-skill-archetype-system-design.md](../specs/2026-04-20-agent-level-skill-archetype-system-design.md)

---

## File Structure

### New files (Dart client)

- `lib/models/agent_archetype.dart` — `ArchetypeVector`, `Quirk`, `quirkCatalog`.
- `lib/models/agent_level.dart` — pure functions: `xpToNextLevel`, `skillCap`, `requiredLevelFor`, XP formula.
- `lib/providers/archetype_drift_provider.dart` — listens to task completions, applies drift.
- `lib/providers/energy_provider.dart` — daily token budget state, cooldowns.
- `lib/services/archetype_drift.dart` — pure `applyDrift` function.
- `lib/services/quirk_roll.dart` — `rollQuirksAtHire()` pure function.
- `lib/widgets/agent/agent_skill_radar.dart` — pentagon radar chart.
- `lib/widgets/agent/level_badge.dart` — Lv N badge.
- `lib/widgets/energy/energy_meter.dart` — header meter.
- `test/models/agent_level_test.dart` — XP/cap formula tests.
- `test/models/agent_archetype_test.dart` — drift/quirk tests.
- `test/services/quirk_roll_test.dart` — quirk probability distribution.
- `test/services/archetype_drift_test.dart` — trait → delta mapping.
- `test/models/task_board_test.dart` — requiredLevel derivation.

### Modified files (Dart client)

- `lib/models/game_economy.dart` — replace `SkillType` enum, update `AgentGameData`, `RoleCatalogEntry`, `GameState.schemaVersion`.
- `lib/models/task_board.dart` — add `requiredLevel`, `allowedRoles`, `taskType`; remove old `requiredSkill`.
- `lib/providers/game_economy_provider.dart` — update `hireAgent` (roll quirks, init archetype), `upgradeSkill` (new cap), add `addXpToAgent`/`levelUp`.
- `lib/providers/task_board_provider.dart` — validate assignment (level + role gates).
- `lib/providers/task_progress_provider.dart` — new time formula, quality rolls.
- `lib/services/game_persistence_service.dart` — schema version check, drop if mismatch.
- `lib/widgets/board/task_board_panel.dart` — requirement chips on cards, gate error feedback.
- `lib/widgets/shop/shop_panel.dart` — use new SkillType labels/icons, respect new cap.
- `lib/main.dart` — show drop-migration toast on first boot of new schema.

### New files (TypeScript server)

- `server/src/archetype_drift.ts` — maps trait tags → vector deltas (mirror of Dart side).
- `server/src/reviewer_pass.ts` — wraps `query()`, spawns reviewer sub-agent when Precision high.
- `server/src/energy_tracker.ts` — per-user daily token budget.
- `server/test/archetype_drift.test.ts` — drift math.
- `server/test/energy_tracker.test.ts` — budget roll-over and cap logic.

### Modified files (TypeScript server)

- `server/src/agents.ts` — add 3 role templates (PM, Data Analyst, DevOps), rewrite `skillsToModel` to use `capability_score`.
- `server/src/agent_runner.ts` — integrate `reviewer_pass` wrapper, `energy_tracker` check.
- `server/src/trait_memory.ts` — emit drift events when traits cross frequency thresholds.
- `server/package.json` — add `test` script.

---

## Task Decomposition

**Reading guide:** tasks are numbered `Phase.Task`. Within each task, steps are `- [ ]` checkboxes. The engineer executes them in order. Each phase ends with a commit.

Use **TDD for pure functions** (formulas, drift logic, quirk rolls). For data model classes use JSON roundtrip tests. For widgets use a smoke test that verifies `build()` doesn't throw.

---

## Phase 0 — Test Infrastructure Setup

Flutter/Dart already has `flutter_test`. Server has no test framework — we add Node built-in `node:test`.

### Task 0.1: Server test setup

**Files:**
- Modify: `server/package.json`
- Create: `server/test/smoke.test.ts`

- [ ] **Step 1: Add test script to package.json**

Edit `server/package.json` to add a `test` script using Node's built-in test runner:

```json
{
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "start": "tsx src/server.ts",
    "test": "tsx --test test/**/*.test.ts"
  }
}
```

- [ ] **Step 2: Write a smoke test**

Create `server/test/smoke.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";

test("node test runner works", () => {
  assert.equal(1 + 1, 2);
});
```

- [ ] **Step 3: Run it**

Run: `cd server && npm test`
Expected: `✔ node test runner works` and exit 0.

- [ ] **Step 4: Commit**

```bash
git add server/package.json server/test/smoke.test.ts
git commit -m "test: add node:test infrastructure for server"
```

---

## Phase 1 — Data Model Foundation (breaking)

Changes here drop the old `SkillType` and old `AgentGameData.skillXp`, plus add new fields. Persistence schema version is bumped; old save-files auto-reset.

### Task 1.1: Bump schema version + drop-old-save service

**Files:**
- Modify: `lib/models/game_economy.dart` (`GameState.schemaVersion` field if exists, or add one)
- Modify: `lib/services/game_persistence_service.dart`
- Create: `test/services/game_persistence_service_test.dart`

- [ ] **Step 1: Inspect current persistence**

Read `lib/services/game_persistence_service.dart`. Note how state is serialized. If there's no `schemaVersion` field on `GameState`, add one.

- [ ] **Step 2: Add `schemaVersion` to `GameState`**

In `lib/models/game_economy.dart`, find `class GameState`. Add:

```dart
class GameState {
  static const int currentSchemaVersion = 3;
  final int schemaVersion;
  // ... existing fields
  const GameState({
    this.schemaVersion = currentSchemaVersion,
    // ... existing params
  });
  // in toJson: 'schemaVersion': schemaVersion,
  // in fromJson: schemaVersion: (json['schemaVersion'] as int?) ?? 1,
}
```

If `GameState.copyWith` exists, add `schemaVersion` to it.

- [ ] **Step 3: Write failing test for drop-on-mismatch**

Create `test/services/game_persistence_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelcode/services/game_persistence_service.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  test('load returns fresh state if schema version mismatches', () async {
    SharedPreferences.setMockInitialValues({
      'gameState': '{"schemaVersion":1,"grymni":999999}',
    });
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    expect(loaded.schemaVersion, GameState.currentSchemaVersion);
    expect(loaded.grymni, lessThan(999999));
    expect(prefs.getBool('schemaResetFlag'), isTrue);
  });

  test('load preserves state when schema matches', () async {
    final json = '{"schemaVersion":${GameState.currentSchemaVersion},"grymni":777}';
    SharedPreferences.setMockInitialValues({'gameState': json});
    final prefs = await SharedPreferences.getInstance();
    final loaded = GamePersistenceService.load(prefs);

    expect(loaded.grymni, 777);
  });
}
```

Replace `pixelcode` with the actual package name (check `pubspec.yaml`).

- [ ] **Step 4: Run test — verify it fails**

Run: `flutter test test/services/game_persistence_service_test.dart`
Expected: FAIL (schema check not yet implemented).

- [ ] **Step 5: Implement schema check in persistence service**

Modify `lib/services/game_persistence_service.dart`. In the `load` method, parse JSON and check `schemaVersion`. If mismatch (or missing), return a fresh `GameState` with defaults AND set a `schemaResetFlag` in prefs so the UI can show a toast on first render.

Preserve across reset (whitelist): `grymni`, `totalEarned`, `cosmeticsPurchased`, `achievementsUnlocked` if they exist in the old JSON. Copy them into the fresh state if readable.

Pseudo:
```dart
static GameState load(SharedPreferences prefs) {
  final raw = prefs.getString('gameState');
  if (raw == null) return GameState();  // fresh
  try {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final v = json['schemaVersion'] as int? ?? 1;
    if (v != GameState.currentSchemaVersion) {
      prefs.setBool('schemaResetFlag', true);
      final preserved = <String, dynamic>{
        'grymni': json['grymni'] ?? 500,
        'totalEarned': json['totalEarned'] ?? 0,
        'cosmeticsPurchased': json['cosmeticsPurchased'] ?? [],
        'achievementsUnlocked': json['achievementsUnlocked'] ?? [],
      };
      return _freshStateWithPreserved(preserved);
    }
    return GameState.fromJson(json);
  } catch (_) {
    return GameState();
  }
}
```

- [ ] **Step 6: Run test — verify it passes**

Run: `flutter test test/services/game_persistence_service_test.dart`
Expected: PASS both tests.

- [ ] **Step 7: Commit**

```bash
git add lib/models/game_economy.dart lib/services/game_persistence_service.dart test/services/game_persistence_service_test.dart
git commit -m "feat: add schema version to GameState, drop old saves on mismatch"
```

---

### Task 1.2: Replace SkillType enum

**Files:**
- Modify: `lib/models/game_economy.dart` (enum `SkillType`, extension `SkillTypeExt`)

The old enum has: `speed, quality, communication, problemSolving, specialization`.
The new enum: `speed, precision, creativity, insight, reliability`.

- [ ] **Step 1: Replace the enum**

In `lib/models/game_economy.dart:290`:

```dart
enum SkillType {
  speed,
  precision,
  creativity,
  insight,
  reliability,
}

extension SkillTypeExt on SkillType {
  String get label => switch (this) {
        SkillType.speed => 'Швидкість',
        SkillType.precision => 'Точність',
        SkillType.creativity => 'Креативність',
        SkillType.insight => 'Проникливість',
        SkillType.reliability => 'Надійність',
      };

  String get icon => switch (this) {
        SkillType.speed => '⚡',
        SkillType.precision => '🎯',
        SkillType.creativity => '💡',
        SkillType.insight => '🔮',
        SkillType.reliability => '🔒',
      };

  int get baseCost => switch (this) {
        SkillType.speed => 100,
        SkillType.precision => 150,
        SkillType.creativity => 180,
        SkillType.insight => 200,
        SkillType.reliability => 130,
      };

  /// Cost to upgrade from [currentLevel] to [currentLevel + 1].
  int upgradeCost(int currentLevel) => baseCost * (currentLevel + 1);
}
```

- [ ] **Step 2: Expect compile errors in dependent files**

Run: `flutter analyze`
Expected: errors in `shop_panel.dart`, `game_economy_provider.dart`, and others referencing removed enum values (`quality`, `communication`, etc.). Do NOT fix them yet — subsequent tasks will. Compile errors are EXPECTED at this point.

- [ ] **Step 3: Commit**

```bash
git add lib/models/game_economy.dart
git commit -m "refactor: replace SkillType enum with new 5-skill model"
```

---

### Task 1.3: ArchetypeVector model

**Files:**
- Create: `lib/models/agent_archetype.dart`
- Create: `test/models/agent_archetype_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/models/agent_archetype_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_archetype.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  group('ArchetypeVector', () {
    test('uniform() returns weights 0.2 for each skill', () {
      final v = ArchetypeVector.uniform();
      for (final s in SkillType.values) {
        expect(v.weights[s], 0.2);
      }
    });

    test('normalize() scales weights to sum to 1.0', () {
      final v = ArchetypeVector(weights: {
        SkillType.speed: 2.0,
        SkillType.precision: 3.0,
        SkillType.creativity: 1.0,
        SkillType.insight: 2.0,
        SkillType.reliability: 2.0,
      });
      final n = v.normalize();
      final sum = n.weights.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
      expect(n.weights[SkillType.speed], closeTo(0.2, 1e-9));
    });

    test('clampDrift keeps weights within ±15% of baseline', () {
      final baseline = ArchetypeVector(weights: {
        SkillType.speed: 0.10,
        SkillType.precision: 0.40,
        SkillType.creativity: 0.10,
        SkillType.insight: 0.30,
        SkillType.reliability: 0.10,
      });
      final drifted = ArchetypeVector(weights: {
        SkillType.speed: 0.50,   // +40%, should clamp to +15%
        SkillType.precision: 0.40,
        SkillType.creativity: 0.10,
        SkillType.insight: 0.00,
        SkillType.reliability: 0.00,
      });
      final clamped = drifted.clampDrift(baseline, maxDelta: 0.15);
      expect(clamped.weights[SkillType.speed]!, closeTo(0.25, 1e-9));
    });

    test('toJson/fromJson roundtrip', () {
      final v = ArchetypeVector(weights: {
        for (final s in SkillType.values) s: 0.2,
      });
      final json = v.toJson();
      final back = ArchetypeVector.fromJson(json);
      for (final s in SkillType.values) {
        expect(back.weights[s]!, closeTo(0.2, 1e-9));
      }
    });
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/models/agent_archetype_test.dart`
Expected: FAIL (file doesn't exist).

- [ ] **Step 3: Implement ArchetypeVector**

Create `lib/models/agent_archetype.dart`:

```dart
/// Archetype vector: per-skill weights for stat-budget distribution.
/// Sum of weights == 1.0 after normalization.
library;

import 'game_economy.dart';

class ArchetypeVector {
  final Map<SkillType, double> weights;

  const ArchetypeVector({required this.weights});

  factory ArchetypeVector.uniform() => ArchetypeVector(
        weights: {for (final s in SkillType.values) s: 0.2},
      );

  ArchetypeVector normalize() {
    final sum = weights.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return ArchetypeVector.uniform();
    return ArchetypeVector(weights: {
      for (final e in weights.entries) e.key: e.value / sum,
    });
  }

  /// Clamp each weight to `baseline ± maxDelta`, then re-normalize.
  ArchetypeVector clampDrift(ArchetypeVector baseline, {double maxDelta = 0.15}) {
    final clamped = <SkillType, double>{};
    for (final s in SkillType.values) {
      final base = baseline.weights[s] ?? 0.2;
      final current = weights[s] ?? 0.0;
      clamped[s] = current.clamp(base - maxDelta, base + maxDelta);
    }
    return ArchetypeVector(weights: clamped).normalize();
  }

  /// Apply a per-skill delta, return new vector (not normalized/clamped).
  ArchetypeVector withDelta(Map<SkillType, double> delta) {
    return ArchetypeVector(weights: {
      for (final s in SkillType.values)
        s: (weights[s] ?? 0) + (delta[s] ?? 0),
    });
  }

  Map<String, dynamic> toJson() => {
        for (final e in weights.entries) e.key.index.toString(): e.value,
      };

  factory ArchetypeVector.fromJson(Map<String, dynamic> json) => ArchetypeVector(
        weights: {
          for (final e in json.entries)
            SkillType.values[int.parse(e.key)]: (e.value as num).toDouble(),
        },
      );
}
```

- [ ] **Step 4: Run test — verify it passes**

Run: `flutter test test/models/agent_archetype_test.dart`
Expected: PASS all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/agent_archetype.dart test/models/agent_archetype_test.dart
git commit -m "feat: add ArchetypeVector with clamp/normalize/drift"
```

---

### Task 1.4: Quirk model and catalog

**Files:**
- Modify: `lib/models/agent_archetype.dart` (add Quirk class + catalog)

- [ ] **Step 1: Add Quirk class and catalog**

Append to `lib/models/agent_archetype.dart`:

```dart
class Quirk {
  final String id;
  final String nameUk;
  final String description;

  const Quirk({
    required this.id,
    required this.nameUk,
    required this.description,
  });
}

const quirkCatalog = <Quirk>[
  Quirk(id: 'night_owl', nameUk: 'Сова', description: '+25% speed after 20:00 local, -10% before 12:00'),
  Quirk(id: 'perfectionist', nameUk: 'Перфекціоніст', description: '+15% precision, +15% task time'),
  Quirk(id: 'caffeine', nameUk: 'Кофеїнозалежний', description: '+30% reliability, 5% chance -50% speed crash'),
  Quirk(id: 'fast_learner', nameUk: 'Швидконавчаний', description: '+50% XP gain, skills start -1'),
  Quirk(id: 'mentor', nameUk: 'Наставник', description: 'Nearby agents get +5% speed'),
  Quirk(id: 'minimalist', nameUk: 'Мінімаліст', description: '-20% tokens per task'),
  Quirk(id: 'over_engineer', nameUk: 'Оверінженір', description: '+20% quality on Hard+, +15% time'),
  Quirk(id: 'team_player', nameUk: 'Командний', description: '+10% in multi-assignee tasks'),
  Quirk(id: 'lone_wolf', nameUk: 'Одинак', description: '+15% speed solo, -15% in multi'),
  Quirk(id: 'polyglot', nameUk: 'Поліглот', description: 'Can do ui-design and coding equally'),
  Quirk(id: 'rookie', nameUk: 'Новачок', description: '-10% all stats, +100% XP gain'),
  Quirk(id: 'legend', nameUk: 'Легенда', description: 'Stats start 1.5× normal, 0 XP gain'),
];

Quirk? quirkById(String id) {
  for (final q in quirkCatalog) {
    if (q.id == id) return q;
  }
  return null;
}

/// IDs that MUST NOT coexist on the same agent.
const quirkConflicts = <Set<String>>{
  {'rookie', 'legend'},
};

bool hasQuirkConflict(List<String> ids) {
  for (final pair in quirkConflicts) {
    if (pair.every(ids.contains)) return true;
  }
  return false;
}
```

- [ ] **Step 2: Extend the test file**

In `test/models/agent_archetype_test.dart`, append:

```dart
  group('Quirk catalog', () {
    test('has 12 entries', () {
      expect(quirkCatalog.length, 12);
    });

    test('all ids are unique', () {
      final ids = quirkCatalog.map((q) => q.id).toSet();
      expect(ids.length, quirkCatalog.length);
    });

    test('hasQuirkConflict detects rookie+legend', () {
      expect(hasQuirkConflict(['rookie', 'legend']), isTrue);
      expect(hasQuirkConflict(['rookie']), isFalse);
      expect(hasQuirkConflict(['perfectionist', 'mentor']), isFalse);
    });

    test('quirkById returns correct entry', () {
      expect(quirkById('night_owl')!.nameUk, 'Сова');
      expect(quirkById('nonexistent'), isNull);
    });
  });
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/models/agent_archetype_test.dart`
Expected: PASS all tests.

- [ ] **Step 4: Commit**

```bash
git add lib/models/agent_archetype.dart test/models/agent_archetype_test.dart
git commit -m "feat: add quirk catalog with 12 entries and conflict detection"
```

---

### Task 1.5: AgentGameData — new fields

**Files:**
- Modify: `lib/models/game_economy.dart` (class `AgentGameData`)

- [ ] **Step 1: Update class**

Replace `class AgentGameData` (currently at line ~333) with:

```dart
class AgentGameData {
  final String instanceId;
  final String roleType;
  final String nickname;
  final HardwareTier hardware;
  final Map<SkillType, int> skills;

  // NEW fields
  final int level;                         // 1..20
  final int xp;                            // XP towards next level
  final ArchetypeVector archetype;         // current (post-drift) vector
  final List<String> quirkIds;             // assigned at hire, permanent

  const AgentGameData({
    required this.instanceId,
    required this.roleType,
    required this.nickname,
    this.hardware = HardwareTier.oldLaptop,
    this.skills = const {},
    this.level = 1,
    this.xp = 0,
    required this.archetype,
    this.quirkIds = const [],
  });

  /// Backward-compat proxy — capability-oriented aggregate for `skillsToModel`.
  double get capabilityScore {
    double v(SkillType s) => (skills[s] ?? 1).toDouble();
    return 0.4 * v(SkillType.insight)
         + 0.3 * v(SkillType.precision)
         + 0.2 * v(SkillType.reliability)
         + 0.1 * v(SkillType.creativity);
  }

  double get totalSpeedModifier => hardware.speedModifier;

  AgentGameData copyWith({
    String? nickname,
    HardwareTier? hardware,
    Map<SkillType, int>? skills,
    int? level,
    int? xp,
    ArchetypeVector? archetype,
    List<String>? quirkIds,
  }) =>
      AgentGameData(
        instanceId: instanceId,
        roleType: roleType,
        nickname: nickname ?? this.nickname,
        hardware: hardware ?? this.hardware,
        skills: skills ?? this.skills,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        archetype: archetype ?? this.archetype,
        quirkIds: quirkIds ?? this.quirkIds,
      );

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'roleType': roleType,
        'nickname': nickname,
        'hardware': hardware.index,
        'skills': {
          for (final e in skills.entries) e.key.index.toString(): e.value,
        },
        'level': level,
        'xp': xp,
        'archetype': archetype.toJson(),
        'quirkIds': quirkIds,
      };

  factory AgentGameData.fromJson(Map<String, dynamic> json) => AgentGameData(
        instanceId: json['instanceId'] as String,
        roleType: json['roleType'] as String,
        nickname: json['nickname'] as String? ?? '',
        hardware: HardwareTier.values[json['hardware'] as int? ?? 0],
        skills: {
          for (final e in (json['skills'] as Map<String, dynamic>? ?? {}).entries)
            SkillType.values[int.parse(e.key)]: e.value as int,
        },
        level: json['level'] as int? ?? 1,
        xp: json['xp'] as int? ?? 0,
        archetype: json['archetype'] != null
            ? ArchetypeVector.fromJson(json['archetype'] as Map<String, dynamic>)
            : ArchetypeVector.uniform(),
        quirkIds: (json['quirkIds'] as List?)?.map((e) => e as String).toList() ?? const [],
      );
}
```

Note: `skillXp`, `skillLevel`, and `xpForNextLevel(SkillType)` are REMOVED. XP is now agent-level, not skill-level.

- [ ] **Step 2: Add import**

At the top of `lib/models/game_economy.dart`, add:

```dart
import 'agent_archetype.dart';
```

- [ ] **Step 3: Write a JSON roundtrip test**

Create `test/models/agent_game_data_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/agent_archetype.dart';

void main() {
  test('AgentGameData JSON roundtrip preserves all fields', () {
    final a = AgentGameData(
      instanceId: 'coder#1',
      roleType: 'coder',
      nickname: 'Neo',
      hardware: HardwareTier.gamingPC,
      skills: {SkillType.speed: 5, SkillType.precision: 7},
      level: 4,
      xp: 120,
      archetype: ArchetypeVector.uniform(),
      quirkIds: ['night_owl', 'mentor'],
    );
    final back = AgentGameData.fromJson(a.toJson());
    expect(back.instanceId, 'coder#1');
    expect(back.level, 4);
    expect(back.xp, 120);
    expect(back.skills[SkillType.speed], 5);
    expect(back.quirkIds, ['night_owl', 'mentor']);
    expect(back.archetype.weights[SkillType.speed], closeTo(0.2, 1e-9));
  });
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/models/agent_game_data_test.dart`
Expected: PASS (ignore other compile errors outside this file).

- [ ] **Step 5: Commit**

```bash
git add lib/models/game_economy.dart test/models/agent_game_data_test.dart
git commit -m "feat: add level/xp/archetype/quirks to AgentGameData"
```

---

### Task 1.6: TaskCard — new fields, drop `requiredSkill`

**Files:**
- Modify: `lib/models/task_board.dart`
- Create: `test/models/task_board_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/models/task_board_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/task_board.dart';

void main() {
  test('requiredLevelFor maps difficulty 1-5 correctly', () {
    expect(requiredLevelFor(1), 1);
    expect(requiredLevelFor(2), 2);
    expect(requiredLevelFor(3), 4);
    expect(requiredLevelFor(4), 7);
    expect(requiredLevelFor(5), 11);
  });

  test('requiredLevelFor clamps out-of-range difficulty', () {
    expect(requiredLevelFor(0), 1);
    expect(requiredLevelFor(99), 11);
  });

  test('TaskCard roundtrip preserves new fields', () {
    final now = DateTime.now();
    final t = TaskCard(
      id: 't1',
      title: 'Do a thing',
      createdAt: now,
      updatedAt: now,
      difficulty: 3,
      allowedRoles: const ['coder', 'tech-lead'],
      taskType: 'coding',
    );
    final back = TaskCard.fromJson(t.toJson());
    expect(back.difficulty, 3);
    expect(back.requiredLevel, 4);  // derived
    expect(back.allowedRoles, ['coder', 'tech-lead']);
    expect(back.taskType, 'coding');
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `flutter test test/models/task_board_test.dart`
Expected: FAIL (fields don't exist yet).

- [ ] **Step 3: Update `TaskCard` and remove `TaskDifficultyExt.requiredSkill`**

In `lib/models/task_board.dart`:

1. Remove the `requiredSkill` getter from `TaskDifficultyExt` (currently at ~line 91).
2. Add a top-level pure function:

```dart
/// Required agent level for the given task difficulty.
/// Clamps out-of-range input to the nearest valid difficulty (1-5).
int requiredLevelFor(int difficulty) {
  final d = difficulty.clamp(1, 5);
  return const [0, 1, 2, 4, 7, 11][d];
}
```

3. Add fields to `TaskCard`:

```dart
class TaskCard {
  final String id;
  final String title;
  final String description;
  final TaskColumn column;
  final TaskPriority priority;
  final StickyColor color;
  final List<String> assignedAgents;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int difficulty;

  // NEW
  final List<String> allowedRoles;   // role types that can execute this task
  final String taskType;             // 'coding', 'review', 'testing', etc.

  const TaskCard({
    required this.id,
    required this.title,
    this.description = '',
    this.column = TaskColumn.backlog,
    this.priority = TaskPriority.normal,
    this.color = StickyColor.yellow,
    this.assignedAgents = const [],
    required this.createdAt,
    required this.updatedAt,
    this.difficulty = 2,
    this.allowedRoles = const ['coder'],
    this.taskType = 'coding',
  });

  /// Derived: minimum agent level required to take this task.
  int get requiredLevel => requiredLevelFor(difficulty);

  TaskCard copyWith({
    String? title,
    String? description,
    TaskColumn? column,
    TaskPriority? priority,
    StickyColor? color,
    List<String>? assignedAgents,
    DateTime? updatedAt,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
  }) =>
      TaskCard(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        column: column ?? this.column,
        priority: priority ?? this.priority,
        color: color ?? this.color,
        assignedAgents: assignedAgents ?? this.assignedAgents,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        difficulty: difficulty ?? this.difficulty,
        allowedRoles: allowedRoles ?? this.allowedRoles,
        taskType: taskType ?? this.taskType,
      );

  factory TaskCard.fromJson(Map<String, dynamic> json) => TaskCard(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        column: TaskColumn.fromKey(json['column'] as String? ?? 'backlog'),
        priority: TaskPriority.fromKey(json['priority'] as String? ?? 'normal'),
        color: StickyColor.fromKey(json['color'] as String? ?? 'yellow'),
        assignedAgents: (json['assignedAgents'] as List?)?.map((e) => e as String).toList() ?? [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        difficulty: json['difficulty'] as int? ?? 2,
        allowedRoles: (json['allowedRoles'] as List?)?.map((e) => e as String).toList() ?? const ['coder'],
        taskType: json['taskType'] as String? ?? 'coding',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'column': column.key,
        'priority': priority.key,
        'color': color.key,
        'assignedAgents': assignedAgents,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'difficulty': difficulty,
        'allowedRoles': allowedRoles,
        'taskType': taskType,
      };
}
```

- [ ] **Step 4: Run test — verify it passes**

Run: `flutter test test/models/task_board_test.dart`
Expected: PASS all 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/task_board.dart test/models/task_board_test.dart
git commit -m "feat: add requiredLevel/allowedRoles/taskType to TaskCard"
```

---

### Task 1.7: RoleCatalogEntry — new fields

**Files:**
- Modify: `lib/models/game_economy.dart`

- [ ] **Step 1: Add fields to `RoleCatalogEntry`**

Replace `class RoleCatalogEntry` at line ~436 with:

```dart
class RoleCatalogEntry {
  final String roleType;
  final String baseName;
  final String role;
  final String specialization;
  final String weakness;
  final int hireCost;
  final int salary;
  final bool singleton;
  final int defaultSeedCount;
  final AgentPassive passive;

  // NEW
  final ArchetypeVector defaultArchetype;
  final List<String> taskTypes;         // what kinds of tasks this role can do

  const RoleCatalogEntry({
    required this.roleType,
    required this.baseName,
    required this.role,
    required this.specialization,
    required this.weakness,
    required this.hireCost,
    required this.salary,
    required this.passive,
    required this.defaultArchetype,
    required this.taskTypes,
    this.singleton = false,
    this.defaultSeedCount = 0,
  });
}
```

- [ ] **Step 2: Update existing 7 entries in `roleCatalog`**

Each entry in `const roleCatalog` must now include `defaultArchetype` and `taskTypes`. Use these vectors (mapped from the spec's archetype-weight lines):

| Role | speed | precision | creativity | insight | reliability | taskTypes |
|---|---|---|---|---|---|---|
| manager | 0.20 | 0.20 | 0.15 | 0.30 | 0.15 | `['management']` |
| coder | 0.30 | 0.25 | 0.10 | 0.20 | 0.15 | `['coding']` |
| tech-lead | 0.10 | 0.30 | 0.15 | 0.35 | 0.10 | `['architecture', 'coding']` |
| reviewer | 0.10 | 0.40 | 0.05 | 0.30 | 0.15 | `['review']` |
| tester | 0.25 | 0.20 | 0.05 | 0.15 | 0.35 | `['testing']` |
| security | 0.05 | 0.35 | 0.10 | 0.40 | 0.10 | `['security-audit']` |
| ui-ux-designer | 0.15 | 0.30 | 0.40 | 0.10 | 0.05 | `['ui-design']` |

Example for `coder`:

```dart
  RoleCatalogEntry(
    roleType: 'coder',
    baseName: 'Майстер',
    role: 'Розробник',
    specialization: 'Програмування — реалізація фіч, фікс багів, рефакторинг.',
    weakness: 'Дизайн UI/UX та глибокий security-аудит — не його коник.',
    hireCost: 0,
    salary: 40,
    defaultSeedCount: 1,
    passive: AgentPassive(/* existing */),
    defaultArchetype: ArchetypeVector(weights: {
      SkillType.speed: 0.30,
      SkillType.precision: 0.25,
      SkillType.creativity: 0.10,
      SkillType.insight: 0.20,
      SkillType.reliability: 0.15,
    }),
    taskTypes: ['coding'],
  ),
```

Apply the same pattern to all 7 existing entries.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze lib/models/game_economy.dart`
Expected: no errors inside `game_economy.dart` (errors in dependent files OK at this phase).

- [ ] **Step 4: Commit**

```bash
git add lib/models/game_economy.dart
git commit -m "feat: add defaultArchetype and taskTypes to RoleCatalogEntry"
```

---

## Phase 2 — XP & Level System

### Task 2.1: XP/level pure functions

**Files:**
- Create: `lib/models/agent_level.dart`
- Create: `test/models/agent_level_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/models/agent_level_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_level.dart';

void main() {
  test('xpToNextLevel uses 50 * level^1.6 formula', () {
    expect(xpToNextLevel(1), 50);          // 50 * 1^1.6 = 50
    expect(xpToNextLevel(2), 152);         // 50 * 2^1.6 ≈ 151.57 → 152
    expect(xpToNextLevel(10), 1991);       // 50 * 10^1.6 ≈ 1991.5 → 1991
  });

  test('skillCap = 10 + 2*level', () {
    expect(skillCap(1), 12);
    expect(skillCap(5), 20);
    expect(skillCap(20), 50);
  });

  test('xpForTask difficulty^2 * multiplier', () {
    expect(xpForTask(difficulty: 1, quality: 1.0, agentLevel: 1), 1);   // 1^2 * 1 * 1
    expect(xpForTask(difficulty: 3, quality: 1.0, agentLevel: 1), 9);   // 3^2 * 1 * 1
    expect(xpForTask(difficulty: 5, quality: 1.5, agentLevel: 1), 37); // 5^2 * 1.5 = 37.5 → 37
  });

  test('xpForTask applies 0.25 diminishing when agent overqualified', () {
    // difficulty 1, agent level 10, diff is 1 - 10 = -9; diff + 3 = -6 < 0 ⇒ diminish
    expect(xpForTask(difficulty: 1, quality: 1.0, agentLevel: 10), 0);  // 1 * 0.25 = 0.25 → 0
    expect(xpForTask(difficulty: 2, quality: 1.0, agentLevel: 10), 1);  // 4 * 0.25 = 1
  });

  test('failureBonus applies +20%', () {
    // difficulty 3, quality 1.0, agent lvl 3, failure recovered
    expect(xpForTask(difficulty: 3, quality: 1.0, agentLevel: 3, recoveredFromFailure: true), 10); // 9 * 1.2 = 10.8 → 10
  });
}
```

- [ ] **Step 2: Run test**

Run: `flutter test test/models/agent_level_test.dart`
Expected: FAIL (file missing).

- [ ] **Step 3: Implement**

Create `lib/models/agent_level.dart`:

```dart
/// Pure level/XP/skill-cap functions for agents.
library;

import 'dart:math';

const int maxAgentLevel = 20;

/// XP required to advance from [level] to [level + 1].
int xpToNextLevel(int level) {
  final n = level.clamp(1, maxAgentLevel).toDouble();
  return (50 * pow(n, 1.6)).floor();
}

/// Maximum value each skill can be upgraded to at [level].
int skillCap(int level) => 10 + 2 * level.clamp(1, maxAgentLevel);

/// XP awarded on task completion.
/// Formula: difficulty² × quality × diminishing × failureBonus
int xpForTask({
  required int difficulty,
  required double quality,          // 0.5 bug, 1.0 normal, 1.5 clean
  required int agentLevel,
  bool recoveredFromFailure = false,
}) {
  double xp = pow(difficulty.clamp(1, 5), 2).toDouble() * quality;

  // Diminishing: Lv10 on Trivial gives ~nothing.
  if (difficulty + 3 < agentLevel) xp *= 0.25;

  if (recoveredFromFailure) xp *= 1.2;

  return xp.floor();
}
```

- [ ] **Step 4: Run test — verify pass**

Run: `flutter test test/models/agent_level_test.dart`
Expected: PASS all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/models/agent_level.dart test/models/agent_level_test.dart
git commit -m "feat: add XP/skillCap pure functions for agent leveling"
```

---

### Task 2.2: addXp / levelUp logic in GameEconomyNotifier

**Files:**
- Modify: `lib/providers/game_economy_provider.dart`

- [ ] **Step 1: Replace old skill-upgrade logic**

In `lib/providers/game_economy_provider.dart`:

1. Delete these existing methods (no longer applicable):
   - `canUpgradeSkill` (currently checks per-skill XP — obsolete since XP is now agent-level)
   - `hasXpButNotGrymni`

Keep the names `canUpgradeSkill` and `upgradeSkill`, but rewrite their semantics.

2. Rewrite `upgradeSkill` to respect `skillCap(agent.level)` and require only grymni (no per-skill XP):

```dart
import '../models/agent_level.dart';

// ...

bool canUpgradeSkill(String instanceId, SkillType skill) {
  final agent = state.agents[instanceId];
  if (agent == null) return false;
  final currentLevel = agent.skills[skill] ?? 1;
  if (currentLevel >= skillCap(agent.level)) return false;
  return state.grymni >= skill.upgradeCost(currentLevel);
}

void upgradeSkill(String instanceId, SkillType skill) {
  if (!canUpgradeSkill(instanceId, skill)) return;
  final agent = state.agents[instanceId]!;
  final currentLevel = agent.skills[skill] ?? 1;
  final cost = skill.upgradeCost(currentLevel);

  final newSkills = Map<SkillType, int>.from(agent.skills);
  newSkills[skill] = currentLevel + 1;

  final updated = Map<String, AgentGameData>.from(state.agents);
  updated[instanceId] = agent.copyWith(skills: newSkills);

  state = state.copyWith(
    grymni: state.grymni - cost,
    totalSpent: state.totalSpent + cost,
    agents: updated,
  );
  _scheduleSave();
  _syncToServer();
}
```

3. Add `addXpToAgent` method:

```dart
/// Awards XP to an agent and triggers level-up if threshold crossed.
/// Returns the amount of levels gained (0 if none).
int addXpToAgent(String instanceId, int xpGained) {
  final agent = state.agents[instanceId];
  if (agent == null || xpGained <= 0) return 0;
  if (agent.level >= maxAgentLevel) return 0;

  int level = agent.level;
  int xp = agent.xp + xpGained;
  int levelsGained = 0;

  while (level < maxAgentLevel && xp >= xpToNextLevel(level)) {
    xp -= xpToNextLevel(level);
    level += 1;
    levelsGained += 1;
  }

  final updated = Map<String, AgentGameData>.from(state.agents);
  updated[instanceId] = agent.copyWith(level: level, xp: xp);

  state = state.copyWith(agents: updated);
  _scheduleSave();
  _syncToServer();
  return levelsGained;
}
```

- [ ] **Step 2: Write provider test**

Create `test/providers/game_economy_xp_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('addXpToAgent crosses single level threshold', () async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(gameEconomyProvider.notifier);
    final existing = container.read(gameEconomyProvider).agents.keys.first;

    // Agent starts at Lv1, xp=0. xpToNextLevel(1) == 50.
    final gained = notifier.addXpToAgent(existing, 60);
    expect(gained, 1);
    final after = container.read(gameEconomyProvider).agents[existing]!;
    expect(after.level, 2);
    expect(after.xp, 10);   // 60 - 50 carry-over
  });
}
```

- [ ] **Step 3: Run test**

Run: `flutter test test/providers/game_economy_xp_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/providers/game_economy_provider.dart test/providers/game_economy_xp_test.dart
git commit -m "feat: agent-level XP with addXpToAgent and new skillCap-based upgrade"
```

---

### Task 2.3: Remove obsolete `_onTaskCompleted` gold-only path, add XP award

**Files:**
- Modify: `lib/providers/game_economy_provider.dart`

- [ ] **Step 1: Patch `_onTaskCompleted`**

In `_onTaskCompleted`, after the gold-awarding logic (currently ~line 175), call `addXpToAgent` for each agent attached to the completed task. If the message carries `agentId`, use it; otherwise fall back to looking up the task by id.

Pseudo (adapt to what `ResultMessage` exposes; check [lib/models/agent_message.dart](../../lib/models/agent_message.dart)):

```dart
void _onTaskCompleted(ResultMessage msg) {
  // ... existing gold award ...

  // NEW: XP to the agent who ran it
  final agentId = msg.agentId;  // check field name
  final difficulty = _inferTaskDifficulty(msg);  // from taskBoardProvider using msg.taskId
  final quality = msg.hadBug ? 0.5 : (msg.cleanCompletion ? 1.5 : 1.0);
  final agent = state.agents[agentId];
  if (agent != null) {
    final xp = xpForTask(
      difficulty: difficulty,
      quality: quality,
      agentLevel: agent.level,
    );
    addXpToAgent(agentId, xp);
  }
}
```

If `ResultMessage` doesn't carry `hadBug`/`cleanCompletion`, those come from outcome logic later (Phase 6). In this step, simply use `quality: 1.0` as placeholder; Phase 6 wires real values.

- [ ] **Step 2: Commit**

```bash
git add lib/providers/game_economy_provider.dart
git commit -m "feat: award agent XP on task completion"
```

---

## Phase 3 — Archetype Evolution

### Task 3.1: Drift mapping table

**Files:**
- Create: `lib/services/archetype_drift.dart`
- Create: `test/services/archetype_drift_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/services/archetype_drift_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/archetype_drift.dart';
import 'package:pixelcode/models/agent_archetype.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  test('fast-delivery trait shifts weights toward speed', () {
    final baseline = ArchetypeVector(weights: {
      SkillType.speed: 0.20,
      SkillType.precision: 0.30,
      SkillType.creativity: 0.10,
      SkillType.insight: 0.20,
      SkillType.reliability: 0.20,
    });
    final drifted = applyDrift(
      current: baseline,
      baseline: baseline,
      traitTag: 'fast-delivery',
      traitType: TraitType.strength,
    );
    expect(drifted.weights[SkillType.speed]!, greaterThan(0.20));
    expect(drifted.weights[SkillType.precision]!, lessThan(0.30));
  });

  test('drift is bounded by ±15% of baseline', () {
    final baseline = ArchetypeVector(weights: {
      SkillType.speed: 0.20,
      SkillType.precision: 0.30,
      SkillType.creativity: 0.10,
      SkillType.insight: 0.20,
      SkillType.reliability: 0.20,
    });
    var v = baseline;
    for (var i = 0; i < 100; i++) {
      v = applyDrift(
        current: v,
        baseline: baseline,
        traitTag: 'fast-delivery',
        traitType: TraitType.strength,
      );
    }
    expect(v.weights[SkillType.speed]!, lessThanOrEqualTo(0.35 + 1e-9));
  });

  test('unknown trait tag is a no-op', () {
    final baseline = ArchetypeVector.uniform();
    final after = applyDrift(
      current: baseline,
      baseline: baseline,
      traitTag: 'unknown-tag',
      traitType: TraitType.strength,
    );
    for (final s in SkillType.values) {
      expect(after.weights[s]!, closeTo(baseline.weights[s]!, 1e-9));
    }
  });
}
```

- [ ] **Step 2: Run test — verify fails**

Run: `flutter test test/services/archetype_drift_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement drift table**

Create `lib/services/archetype_drift.dart`:

```dart
/// Trait-tag → archetype weight delta mapping.
library;

import '../models/agent_archetype.dart';
import '../models/game_economy.dart';
import '../models/agent_trait.dart';

/// One drift step (each unit = one trait observation past threshold).
const double _step = 0.005;   // 0.5 percentage points per trait observation

/// Delta table: strength traits.
const Map<String, Map<SkillType, double>> _strengthDeltas = {
  'fast-delivery': {
    SkillType.speed: _step,
    SkillType.precision: -_step / 2,
    SkillType.reliability: -_step / 2,
  },
  'architecture': {
    SkillType.insight: _step,
    SkillType.speed: -_step / 2,
  },
  'refactoring-patience': {
    SkillType.precision: _step,
    SkillType.speed: -_step,
  },
  'rapid-iteration': {
    SkillType.reliability: _step,
    SkillType.speed: _step / 2,
    SkillType.precision: -_step,
  },
  'divergent-brainstorm': {
    SkillType.creativity: _step,
    SkillType.precision: -_step / 2,
  },
};

/// Delta table: weakness traits (often negative — agent grows cautious).
const Map<String, Map<SkillType, double>> _weaknessDeltas = {
  'complex-reasoning': {
    SkillType.insight: -_step,
  },
};

ArchetypeVector applyDrift({
  required ArchetypeVector current,
  required ArchetypeVector baseline,
  required String traitTag,
  required TraitType traitType,
}) {
  final table = traitType == TraitType.strength ? _strengthDeltas : _weaknessDeltas;
  final delta = table[traitTag];
  if (delta == null) return current;

  return current.withDelta(delta).clampDrift(baseline, maxDelta: 0.15);
}
```

- [ ] **Step 4: Run test**

Run: `flutter test test/services/archetype_drift_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/archetype_drift.dart test/services/archetype_drift_test.dart
git commit -m "feat: archetype drift with trait-tag → weight-delta table"
```

---

### Task 3.2: Wire drift to trait-frequency events

**Files:**
- Modify: `lib/providers/game_economy_provider.dart`
- Inspect: `lib/providers/agent_provider.dart` (where `AgentTrait` updates happen)

- [ ] **Step 1: Locate trait-update logic on client**

Run: `grep -nR "AgentTrait\|TraitType\.strength\|TraitType\.weakness" lib/ --include="*.dart"`

Find where traits are added/updated (likely in `agent_provider.dart` or a `TraitsNotifier`). Note the function signature.

- [ ] **Step 2: Emit drift when trait crosses threshold**

Wherever a trait's `frequency` is incremented, after the update:

```dart
import '../services/archetype_drift.dart';

// ...inside trait-update method, after incrementing frequency:
if (trait.frequency == 3) {  // crossed to 'important'
  _applyDriftForTrait(trait);
}
```

Add helper in `GameEconomyNotifier`:

```dart
void _applyDriftForTrait(AgentTrait trait) {
  final agent = state.agents[trait.agentId];
  if (agent == null) return;
  final role = roleCatalogFor(agent.roleType);
  if (role == null) return;

  final newVector = applyDrift(
    current: agent.archetype,
    baseline: role.defaultArchetype,
    traitTag: trait.tag,
    traitType: trait.type,
  );

  final updated = Map<String, AgentGameData>.from(state.agents);
  updated[trait.agentId] = agent.copyWith(archetype: newVector);
  state = state.copyWith(agents: updated);
  _scheduleSave();
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/providers/game_economy_provider.dart
git commit -m "feat: apply archetype drift when trait crosses frequency threshold"
```

---

## Phase 4 — Quirks

### Task 4.1: Quirk roll at hire

**Files:**
- Create: `lib/services/quirk_roll.dart`
- Create: `test/services/quirk_roll_test.dart`

- [ ] **Step 1: Write failing tests**

Create `test/services/quirk_roll_test.dart`:

```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/quirk_roll.dart';
import 'package:pixelcode/models/agent_archetype.dart';

void main() {
  test('rollQuirks produces 0, 1, or 2 quirks', () {
    final rng = Random(42);
    for (var i = 0; i < 1000; i++) {
      final ids = rollQuirks(rng: rng);
      expect(ids.length, inInclusiveRange(0, 2));
      for (final id in ids) {
        expect(quirkById(id), isNotNull);
      }
    }
  });

  test('rollQuirks never yields rookie+legend', () {
    final rng = Random(42);
    for (var i = 0; i < 10000; i++) {
      final ids = rollQuirks(rng: rng);
      expect(hasQuirkConflict(ids), isFalse);
    }
  });

  test('rollQuirks approximate distribution', () {
    final rng = Random(1);
    int zero = 0, one = 0, two = 0;
    for (var i = 0; i < 10000; i++) {
      final n = rollQuirks(rng: rng).length;
      if (n == 0) zero++;
      if (n == 1) one++;
      if (n == 2) two++;
    }
    // Expected: 5% zero, 70% one, 25% two (with tolerance)
    expect(zero / 10000, closeTo(0.05, 0.02));
    expect(one / 10000, closeTo(0.70, 0.03));
    expect(two / 10000, closeTo(0.25, 0.03));
  });
}
```

- [ ] **Step 2: Implement**

Create `lib/services/quirk_roll.dart`:

```dart
import 'dart:math';
import '../models/agent_archetype.dart';

/// Roll quirks for a new hire. Returns 0-2 non-conflicting quirk IDs.
List<String> rollQuirks({Random? rng}) {
  final r = rng ?? Random();
  final roll = r.nextDouble();

  final int count;
  if (roll < 0.05) {
    count = 0;
  } else if (roll < 0.75) {
    count = 1;
  } else {
    count = 2;
  }

  if (count == 0) return const [];

  final pool = quirkCatalog.map((q) => q.id).toList()..shuffle(r);
  final picked = <String>[];

  for (final id in pool) {
    if (picked.length == count) break;
    final candidate = [...picked, id];
    if (!hasQuirkConflict(candidate)) picked.add(id);
  }

  return picked;
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/services/quirk_roll_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/services/quirk_roll.dart test/services/quirk_roll_test.dart
git commit -m "feat: quirk roll with 70/25/5 distribution and conflict exclusion"
```

---

### Task 4.2: Integrate quirks + archetype into `hireAgent`

**Files:**
- Modify: `lib/providers/game_economy_provider.dart`

- [ ] **Step 1: Patch `hireAgent`**

Replace the `hireAgent` body's `AgentGameData(...)` construction with:

```dart
import '../services/quirk_roll.dart';
import '../models/agent_archetype.dart';
import '../models/agent_level.dart';

// ...inside hireAgent:
final instanceId = nextInstanceId(roleType, state.agents.keys);
final ordinal = state.roleCount(roleType) + 1;

// New: initialize archetype with noise, roll quirks.
final archetype = _initArchetypeFromRole(role);
final quirkIds = rollQuirks();
final initialSkills = _distributeStatBudget(
  archetype: archetype,
  budget: 30,
  cap: skillCap(1),
);

final updated = Map<String, AgentGameData>.from(state.agents);
updated[instanceId] = AgentGameData(
  instanceId: instanceId,
  roleType: roleType,
  nickname: defaultNicknameFor(role, ordinal),
  hardware: HardwareTier.oldLaptop,
  skills: initialSkills,
  level: 1,
  xp: 0,
  archetype: archetype,
  quirkIds: quirkIds,
);
```

Add helper functions to the same file:

```dart
import 'dart:math';

ArchetypeVector _initArchetypeFromRole(RoleCatalogEntry role) {
  final rng = Random();
  final noisy = <SkillType, double>{};
  for (final s in SkillType.values) {
    final base = role.defaultArchetype.weights[s] ?? 0.2;
    final noise = (rng.nextDouble() * 0.30 - 0.15) * base;  // ±15% of base
    noisy[s] = (base + noise).clamp(0.01, 1.0);
  }
  return ArchetypeVector(weights: noisy).normalize();
}

Map<SkillType, int> _distributeStatBudget({
  required ArchetypeVector archetype,
  required int budget,
  required int cap,
}) {
  // First pass: raw allocation by weight.
  final raw = <SkillType, double>{
    for (final e in archetype.weights.entries) e.key: e.value * budget,
  };
  final result = <SkillType, int>{};
  int allocated = 0;
  for (final e in raw.entries) {
    final v = e.value.floor().clamp(1, cap);
    result[e.key] = v;
    allocated += v;
  }
  // Distribute leftover to highest-weight skills.
  int leftover = budget - allocated;
  final byWeight = archetype.weights.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in byWeight) {
    if (leftover <= 0) break;
    if ((result[e.key] ?? 0) < cap) {
      result[e.key] = (result[e.key] ?? 0) + 1;
      leftover--;
    }
  }
  return result;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/providers/game_economy_provider.dart
git commit -m "feat: hireAgent initializes archetype, quirks, and distributed stats"
```

---

## Phase 5 — Hybrid Gating

### Task 5.1: Assignment validation

**Files:**
- Modify: `lib/providers/task_board_provider.dart`
- Create: `test/providers/task_board_provider_test.dart`

- [ ] **Step 1: Write failing test**

Create `test/providers/task_board_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/task_board_provider.dart';

void main() {
  group('assignmentRejectionReason', () {
    test('accepts matching role and level', () {
      final task = _mkTask(difficulty: 3, allowedRoles: ['coder'], taskType: 'coding');
      final agent = _mkAgent(roleType: 'coder', level: 5);
      expect(assignmentRejectionReason(task, agent), isNull);
    });

    test('rejects when agent role is not in allowedRoles', () {
      final task = _mkTask(difficulty: 2, allowedRoles: ['tester'], taskType: 'testing');
      final agent = _mkAgent(roleType: 'coder', level: 5);
      expect(assignmentRejectionReason(task, agent), contains('роль'));
    });

    test('rejects when agent level below requiredLevel', () {
      final task = _mkTask(difficulty: 4, allowedRoles: ['coder'], taskType: 'coding');
      // difficulty 4 → requiredLevel 7; agent level 3
      final agent = _mkAgent(roleType: 'coder', level: 3);
      expect(assignmentRejectionReason(task, agent), contains('Lv 7'));
    });
  });
}

TaskCard _mkTask({required int difficulty, required List<String> allowedRoles, required String taskType}) =>
    TaskCard(
      id: 't', title: 't',
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
      difficulty: difficulty, allowedRoles: allowedRoles, taskType: taskType,
    );

AgentGameData _mkAgent({required String roleType, required int level}) =>
    AgentGameData(
      instanceId: '$roleType#1',
      roleType: roleType,
      nickname: 'T',
      skills: {},
      level: level,
      archetype: ArchetypeVector.uniform(),
    );
```

- [ ] **Step 2: Run test**

Run: `flutter test test/providers/task_board_provider_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Add a top-level pure function to `lib/providers/task_board_provider.dart` (or a neighboring file — your call):

```dart
/// Returns a human-readable rejection reason (Ukrainian), or null if OK.
String? assignmentRejectionReason(TaskCard task, AgentGameData agent) {
  if (!task.allowedRoles.contains(agent.roleType)) {
    final roleLabels = task.allowedRoles.map((r) => roleCatalogFor(r)?.role ?? r).join(', ');
    return 'Ця задача потребує роль: $roleLabels';
  }
  if (agent.level < task.requiredLevel) {
    return 'Потрібен Lv ${task.requiredLevel}+ (агент: Lv ${agent.level})';
  }
  return null;
}
```

Then integrate it into `assignAgent` (or the corresponding method that adds an agent id to `task.assignedAgents`). If rejection reason is non-null, **do not** assign; return the reason to UI for toast/snackbar display.

- [ ] **Step 4: Run test**

Run: `flutter test test/providers/task_board_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/task_board_provider.dart test/providers/task_board_provider_test.dart
git commit -m "feat: hybrid gating validates role + level at task assignment"
```

---

## Phase 6 — Task Execution Formulas

### Task 6.1: New time formula

**Files:**
- Modify: `lib/providers/task_progress_provider.dart`

- [ ] **Step 1: Update `_workSeconds`**

Find `_workSeconds` (currently at ~line 111). Replace with:

```dart
double _workSeconds(TaskCard task) {
  final d = task.difficulty.clamp(1, 5);
  final baseTime = switch (task.column) {
    TaskColumn.backlog => 10.0 + (d - 1) * 2,
    TaskColumn.inProgress => d * 12.0,
    TaskColumn.testing => d * 6.0,
    TaskColumn.done => 0.0,
  };
  if (task.assignedAgents.isEmpty) return baseTime;

  final agents = ref.read(gameEconomyProvider).agents;
  double bestModifier = 2.0;
  for (final id in task.assignedAgents) {
    final agent = agents[id];
    if (agent == null) continue;
    final speed = agent.skills[SkillType.speed] ?? 1;
    final speedMod = 20.0 / (10.0 + speed);
    final hwMod = 1.0 / agent.hardware.speedModifier;
    final mod = speedMod * hwMod;
    if (mod < bestModifier) bestModifier = mod;
  }
  return baseTime * bestModifier;
}
```

Note: when multiple agents are assigned, use the **fastest** (lowest modifier). Quirk effects come in a later task.

- [ ] **Step 2: Commit**

```bash
git add lib/providers/task_progress_provider.dart
git commit -m "feat: speed/hardware-based time formula for task progress"
```

---

### Task 6.2: Quality rolls at completion

**Files:**
- Create: `lib/services/task_outcome.dart`
- Create: `test/services/task_outcome_test.dart`

- [ ] **Step 1: Write tests**

Create `test/services/task_outcome_test.dart`:

```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/services/task_outcome.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  test('bugChance formula clamps at 0 and 0.4', () {
    expect(bugChance(precisionSkill: 0), 0.4);
    expect(bugChance(precisionSkill: 14), 0.0);    // negative clamped
    expect(bugChance(precisionSkill: 7), closeTo(0.19, 1e-9));
  });

  test('critChance is 0.02 × creativity', () {
    expect(critChance(creativitySkill: 0), 0.0);
    expect(critChance(creativitySkill: 10), 0.2);
  });

  test('completionSuccessChance 0.85 + 0.01 × reliability, capped 1.0', () {
    expect(completionSuccessChance(reliabilitySkill: 0), 0.85);
    expect(completionSuccessChance(reliabilitySkill: 15), 1.0);  // capped
  });

  test('rollOutcome: high precision + reliability yields clean completion', () {
    // Deterministic with seeded RNG
    final rng = Random(1);
    int clean = 0, bugs = 0, incomplete = 0;
    for (var i = 0; i < 1000; i++) {
      final r = rollOutcome(
        rng: rng,
        precisionSkill: 10,
        creativitySkill: 0,
        reliabilitySkill: 15,
      );
      if (r == TaskOutcome.incomplete) incomplete++;
      else if (r == TaskOutcome.bug) bugs++;
      else clean++;
    }
    expect(incomplete, lessThan(5));
    expect(bugs, lessThan(120));
    expect(clean, greaterThan(850));
  });
}
```

- [ ] **Step 2: Run — fail**

Run: `flutter test test/services/task_outcome_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

Create `lib/services/task_outcome.dart`:

```dart
import 'dart:math';

enum TaskOutcome { clean, bug, crit, incomplete }

double bugChance({required int precisionSkill}) =>
    (0.4 - 0.03 * precisionSkill).clamp(0.0, 0.4);

double critChance({required int creativitySkill}) =>
    (0.02 * creativitySkill).clamp(0.0, 1.0);

double completionSuccessChance({required int reliabilitySkill}) =>
    (0.85 + 0.01 * reliabilitySkill).clamp(0.0, 1.0);

/// Roll outcome once. RNG is passed to keep tests deterministic.
/// [isDivergentTask] gates crit rolls (only on divergent task types).
TaskOutcome rollOutcome({
  required Random rng,
  required int precisionSkill,
  required int creativitySkill,
  required int reliabilitySkill,
  bool isDivergentTask = false,
}) {
  if (rng.nextDouble() > completionSuccessChance(reliabilitySkill: reliabilitySkill)) {
    return TaskOutcome.incomplete;
  }
  if (rng.nextDouble() < bugChance(precisionSkill: precisionSkill)) {
    return TaskOutcome.bug;
  }
  if (isDivergentTask && rng.nextDouble() < critChance(creativitySkill: creativitySkill)) {
    return TaskOutcome.crit;
  }
  return TaskOutcome.clean;
}
```

- [ ] **Step 4: Run — pass**

Run: `flutter test test/services/task_outcome_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/task_outcome.dart test/services/task_outcome_test.dart
git commit -m "feat: task outcome rolls (bug/crit/incomplete) based on skills"
```

---

### Task 6.3: Apply outcome to task column + XP + rewards

**Files:**
- Modify: `lib/providers/task_progress_provider.dart`

- [ ] **Step 1: Update `_tick` completion branch**

When `secondsRemaining <= 0` and the task should advance, consult `rollOutcome` to decide the next column:

```dart
import '../services/task_outcome.dart';
import 'dart:math';

final _rng = Random();

// inside _tick, in the advancement branch:
final agents = ref.read(gameEconomyProvider).agents;
final assignedAgent = task.assignedAgents.isEmpty ? null : agents[task.assignedAgents.first];
if (assignedAgent == null) continue;

final isDivergent = _isDivergentTaskType(task.taskType);
final outcome = rollOutcome(
  rng: _rng,
  precisionSkill: assignedAgent.skills[SkillType.precision] ?? 1,
  creativitySkill: assignedAgent.skills[SkillType.creativity] ?? 1,
  reliabilitySkill: assignedAgent.skills[SkillType.reliability] ?? 1,
  isDivergentTask: isDivergent,
);

final TaskColumn next;
final double quality;
switch (outcome) {
  case TaskOutcome.clean:
    next = task.column.next();
    quality = 1.5;
  case TaskOutcome.crit:
    next = task.column.next();
    quality = 1.5;
    // +100% gold: call economy provider to top up
    ref.read(gameEconomyProvider.notifier).awardBonus(100);
  case TaskOutcome.bug:
    next = TaskColumn.inProgress;   // bounce back from testing
    quality = 0.5;
  case TaskOutcome.incomplete:
    next = TaskColumn.backlog;      // full reset
    quality = 0.5;
}

// award XP
final xp = xpForTask(
  difficulty: task.difficulty,
  quality: quality,
  agentLevel: assignedAgent.level,
  recoveredFromFailure: false,  // wire on second-pass success in future tuning
);
ref.read(gameEconomyProvider.notifier).addXpToAgent(assignedAgent.instanceId, xp);

ref.read(taskBoardProvider.notifier).moveTask(task.id, next);
```

Helpers:
- Add `TaskColumn.next()` extension if not present: `inProgress → testing → done`; `backlog → inProgress`.
- Add `_isDivergentTaskType(String taskType)` local fn: returns true for `'architecture', 'product-spec', 'ui-design'`.
- Add `awardBonus(int pct)` on `GameEconomyNotifier`.

- [ ] **Step 2: Commit**

```bash
git add lib/providers/task_progress_provider.dart lib/providers/game_economy_provider.dart lib/models/task_board.dart
git commit -m "feat: task completion rolls outcome, updates column and XP"
```

---

## Phase 7 — Energy Meter

### Task 7.1: Energy provider state

**Files:**
- Create: `lib/providers/energy_provider.dart`
- Create: `test/providers/energy_provider_test.dart`

- [ ] **Step 1: Tests**

Create `test/providers/energy_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelcode/providers/energy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh state has full daily budget', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final s = c.read(energyProvider);
    expect(s.tokensUsedToday, 0);
    expect(s.opusTasksUsedToday, 0);
    expect(s.sonnetTasksUsedToday, 0);
  });

  test('recordTaskTokens increments usage', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    c.read(energyProvider.notifier).recordTaskTokens('opus', 12000);
    final s = c.read(energyProvider);
    expect(s.tokensUsedToday, 12000);
    expect(s.opusTasksUsedToday, 1);
  });

  test('effectiveModel downgrades when budget exceeded', () async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    c.read(energyProvider.notifier).recordTaskTokens('opus', 500000);
    expect(c.read(energyProvider.notifier).effectiveModel(requested: 'opus'), 'haiku');
  });
}
```

- [ ] **Step 2: Implementation**

Create `lib/providers/energy_provider.dart`:

```dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'settings_provider.dart';

class EnergyState {
  final int tokensUsedToday;
  final int opusTasksUsedToday;
  final int sonnetTasksUsedToday;
  final int dailyTokenCap;       // default 500000
  final int opusCapPerDay;       // default 3
  final int sonnetCapPerDay;     // default 20
  final DateTime windowStart;

  const EnergyState({
    this.tokensUsedToday = 0,
    this.opusTasksUsedToday = 0,
    this.sonnetTasksUsedToday = 0,
    this.dailyTokenCap = 500000,
    this.opusCapPerDay = 3,
    this.sonnetCapPerDay = 20,
    required this.windowStart,
  });

  EnergyState copyWith({
    int? tokensUsedToday,
    int? opusTasksUsedToday,
    int? sonnetTasksUsedToday,
    int? dailyTokenCap,
    DateTime? windowStart,
  }) => EnergyState(
        tokensUsedToday: tokensUsedToday ?? this.tokensUsedToday,
        opusTasksUsedToday: opusTasksUsedToday ?? this.opusTasksUsedToday,
        sonnetTasksUsedToday: sonnetTasksUsedToday ?? this.sonnetTasksUsedToday,
        dailyTokenCap: dailyTokenCap ?? this.dailyTokenCap,
        opusCapPerDay: opusCapPerDay,
        sonnetCapPerDay: sonnetCapPerDay,
        windowStart: windowStart ?? this.windowStart,
      );

  Map<String, dynamic> toJson() => {
        'tokensUsedToday': tokensUsedToday,
        'opusTasksUsedToday': opusTasksUsedToday,
        'sonnetTasksUsedToday': sonnetTasksUsedToday,
        'dailyTokenCap': dailyTokenCap,
        'opusCapPerDay': opusCapPerDay,
        'sonnetCapPerDay': sonnetCapPerDay,
        'windowStart': windowStart.toIso8601String(),
      };

  static EnergyState fromJson(Map<String, dynamic> j) => EnergyState(
        tokensUsedToday: j['tokensUsedToday'] as int? ?? 0,
        opusTasksUsedToday: j['opusTasksUsedToday'] as int? ?? 0,
        sonnetTasksUsedToday: j['sonnetTasksUsedToday'] as int? ?? 0,
        dailyTokenCap: j['dailyTokenCap'] as int? ?? 500000,
        opusCapPerDay: j['opusCapPerDay'] as int? ?? 3,
        sonnetCapPerDay: j['sonnetCapPerDay'] as int? ?? 20,
        windowStart: DateTime.parse(j['windowStart'] as String),
      );
}

class EnergyNotifier extends Notifier<EnergyState> {
  static const _prefsKey = 'energyState';

  @override
  EnergyState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return EnergyState(windowStart: _today());
    try {
      final s = EnergyState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!_sameDay(s.windowStart, DateTime.now())) {
        return EnergyState(windowStart: _today(), dailyTokenCap: s.dailyTokenCap);
      }
      return s;
    } catch (_) {
      return EnergyState(windowStart: _today());
    }
  }

  static DateTime _today() => DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void recordTaskTokens(String model, int tokens) {
    state = state.copyWith(
      tokensUsedToday: state.tokensUsedToday + tokens,
      opusTasksUsedToday: state.opusTasksUsedToday + (model == 'opus' ? 1 : 0),
      sonnetTasksUsedToday: state.sonnetTasksUsedToday + (model == 'sonnet' ? 1 : 0),
    );
    _persist();
  }

  /// Downgrade the requested model if limits are exceeded.
  String effectiveModel({required String requested}) {
    if (state.tokensUsedToday >= state.dailyTokenCap) return 'haiku';
    if (requested == 'opus' && state.opusTasksUsedToday >= state.opusCapPerDay) return 'sonnet';
    if (requested == 'sonnet' && state.sonnetTasksUsedToday >= state.sonnetCapPerDay) return 'haiku';
    return requested;
  }

  void _persist() {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }
}

final energyProvider = NotifierProvider<EnergyNotifier, EnergyState>(EnergyNotifier.new);
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/providers/energy_provider_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/providers/energy_provider.dart test/providers/energy_provider_test.dart
git commit -m "feat: EnergyProvider tracks daily token budget and model caps"
```

---

### Task 7.2: Server-side `energy_tracker`

**Files:**
- Create: `server/src/energy_tracker.ts`
- Create: `server/test/energy_tracker.test.ts`

- [ ] **Step 1: Write tests**

Create `server/test/energy_tracker.test.ts`:

```ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { EnergyTracker } from "../src/energy_tracker.js";

test("EnergyTracker downgrades opus when cap exceeded", () => {
  const t = new EnergyTracker({ opusCapPerDay: 2, dailyTokenCap: 1_000_000 });
  t.record("user1", "opus", 50_000);
  t.record("user1", "opus", 50_000);
  assert.equal(t.effectiveModel("user1", "opus"), "sonnet");
});

test("EnergyTracker downgrades to haiku on total budget exhaustion", () => {
  const t = new EnergyTracker({ dailyTokenCap: 100_000 });
  t.record("user1", "opus", 200_000);
  assert.equal(t.effectiveModel("user1", "sonnet"), "haiku");
});

test("EnergyTracker isolates per-user state", () => {
  const t = new EnergyTracker({ opusCapPerDay: 1 });
  t.record("a", "opus", 10_000);
  assert.equal(t.effectiveModel("a", "opus"), "sonnet");
  assert.equal(t.effectiveModel("b", "opus"), "opus");
});
```

- [ ] **Step 2: Run — fail**

Run: `cd server && npm test`
Expected: FAIL (file missing).

- [ ] **Step 3: Implement**

Create `server/src/energy_tracker.ts`:

```ts
/**
 * Per-user daily token budget tracker.
 * Mirror of client EnergyProvider; used to downgrade model on the server
 * as a safety net.
 */

export type ModelTier = "haiku" | "sonnet" | "opus";

export interface EnergyLimits {
  dailyTokenCap: number;
  opusCapPerDay: number;
  sonnetCapPerDay: number;
}

const DEFAULT_LIMITS: EnergyLimits = {
  dailyTokenCap: 500_000,
  opusCapPerDay: 3,
  sonnetCapPerDay: 20,
};

interface UserState {
  windowStart: number;
  tokensUsed: number;
  opusTasksUsed: number;
  sonnetTasksUsed: number;
}

function startOfDay(ts: number): number {
  const d = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export class EnergyTracker {
  private limits: EnergyLimits;
  private users = new Map<string, UserState>();

  constructor(overrides: Partial<EnergyLimits> = {}) {
    this.limits = { ...DEFAULT_LIMITS, ...overrides };
  }

  private getOrInit(userId: string): UserState {
    const now = Date.now();
    const today = startOfDay(now);
    let s = this.users.get(userId);
    if (!s || s.windowStart !== today) {
      s = { windowStart: today, tokensUsed: 0, opusTasksUsed: 0, sonnetTasksUsed: 0 };
      this.users.set(userId, s);
    }
    return s;
  }

  record(userId: string, model: ModelTier, tokens: number): void {
    const s = this.getOrInit(userId);
    s.tokensUsed += tokens;
    if (model === "opus") s.opusTasksUsed += 1;
    if (model === "sonnet") s.sonnetTasksUsed += 1;
  }

  effectiveModel(userId: string, requested: ModelTier): ModelTier {
    const s = this.getOrInit(userId);
    if (s.tokensUsed >= this.limits.dailyTokenCap) return "haiku";
    if (requested === "opus" && s.opusTasksUsed >= this.limits.opusCapPerDay) return "sonnet";
    if (requested === "sonnet" && s.sonnetTasksUsed >= this.limits.sonnetCapPerDay) return "haiku";
    return requested;
  }
}
```

- [ ] **Step 4: Run — pass**

Run: `cd server && npm test`
Expected: PASS all 3 energy tests + smoke.

- [ ] **Step 5: Commit**

```bash
git add server/src/energy_tracker.ts server/test/energy_tracker.test.ts
git commit -m "feat: server-side EnergyTracker for per-user token budget"
```

---

## Phase 8 — New Roles

### Task 8.1: Dart role catalog additions

**Files:**
- Modify: `lib/models/game_economy.dart`

- [ ] **Step 1: Append 3 entries to `roleCatalog`**

Add to the end of the existing `const roleCatalog = <RoleCatalogEntry>[ ... ];`:

```dart
  RoleCatalogEntry(
    roleType: 'product-manager',
    baseName: 'Продакт',
    role: 'Продакт менеджер',
    specialization: 'Написання specs, roadmap, feature prioritization.',
    weakness: 'Не пише код; залежить від coder для реалізації.',
    hireCost: 600,
    salary: 60,
    passive: AgentPassive(
      icon: '📋',
      name: 'Clarity of Vision',
      nameUk: 'Чіткість візії',
      description: 'PM-написані тикети дають -20% bug_chance coder-у.',
    ),
    defaultArchetype: ArchetypeVector(weights: {
      SkillType.speed: 0.15,
      SkillType.precision: 0.30,
      SkillType.creativity: 0.25,
      SkillType.insight: 0.25,
      SkillType.reliability: 0.05,
    }),
    taskTypes: ['product-spec', 'management'],
  ),
  RoleCatalogEntry(
    roleType: 'data-analyst',
    baseName: 'Аналітик',
    role: 'Аналітик даних',
    specialization: 'Funnel аналіз, A/B testing, retention reports.',
    weakness: 'Повільний на implement-задачах; не вміє в UI.',
    hireCost: 700,
    salary: 55,
    passive: AgentPassive(
      icon: '📊',
      name: 'Pattern Recognition',
      nameUk: 'Розпізнавання патернів',
      description: 'Завершена analysis-задача дає -20% time наступній coding-задачі.',
    ),
    defaultArchetype: ArchetypeVector(weights: {
      SkillType.speed: 0.10,
      SkillType.precision: 0.40,
      SkillType.creativity: 0.15,
      SkillType.insight: 0.30,
      SkillType.reliability: 0.05,
    }),
    taskTypes: ['data-analysis'],
  ),
  RoleCatalogEntry(
    roleType: 'devops',
    baseName: 'Опс',
    role: 'DevOps інженер',
    specialization: 'CI/CD, infra, incidents, monitoring.',
    weakness: 'Не пише фічі; реактивна роль.',
    hireCost: 650,
    salary: 55,
    passive: AgentPassive(
      icon: '🔧',
      name: 'Infra Stability',
      nameUk: 'Стабільність інфри',
      description: 'DevOps-активний = -50% шанс production incident (v2 mech).',
    ),
    defaultArchetype: ArchetypeVector(weights: {
      SkillType.speed: 0.20,
      SkillType.precision: 0.25,
      SkillType.creativity: 0.05,
      SkillType.insight: 0.20,
      SkillType.reliability: 0.30,
    }),
    taskTypes: ['devops'],
  ),
```

- [ ] **Step 2: Commit**

```bash
git add lib/models/game_economy.dart
git commit -m "feat: add product-manager, data-analyst, devops to role catalog"
```

---

### Task 8.2: Server role templates

**Files:**
- Modify: `server/src/agents.ts`

- [ ] **Step 1: Add three entries to `roleTemplates`**

Append (inside the `export const roleTemplates` object):

```ts
  "product-manager": {
    description: "Product Manager. Writes specs, prioritizes features, defines acceptance criteria.",
    prompt: `This sub-agent is a Product Manager.

Tasks:
- Write clear feature specs from natural-language requests.
- Define acceptance criteria.
- Prioritize backlog items.

Guidelines:
- Read existing product docs and issue tracker first.
- Output structured specs (title / goal / scope / acceptance).
- ${LANG_RULE}`,
    tools: ["Read", "Write", "Grep"],
    model: "sonnet",
  },

  "data-analyst": {
    description: "Data Analyst. Reads logs, runs queries, reports metrics and trends.",
    prompt: `This sub-agent is a Data Analyst.

Tasks:
- Read logs, metrics, and data sources.
- Identify trends, funnels, and anomalies.
- Produce concise reports with charts in markdown (no code changes).

Guidelines:
- Use Read/Bash for exploration; never Write or Edit code files.
- ${LANG_RULE}`,
    tools: ["Read", "Bash", "Grep"],
    model: "sonnet",
  },

  "devops": {
    description: "DevOps / SRE. CI/CD, infra scripts, deployments, monitoring.",
    prompt: `This sub-agent is a DevOps engineer.

Tasks:
- Configure CI/CD pipelines.
- Write infra-as-code (shell, YAML).
- Debug deployment failures.

Guidelines:
- Prefer editing existing config over inventing new.
- ${LANG_RULE}`,
    tools: ["Read", "Bash", "Write", "Edit"],
    model: "sonnet",
  },
```

- [ ] **Step 2: Commit**

```bash
git add server/src/agents.ts
git commit -m "feat: add PM, Data Analyst, DevOps role templates to server"
```

---

## Phase 9 — Reviewer Pass (Server)

### Task 9.1: `reviewer_pass` wrapper

**Files:**
- Create: `server/src/reviewer_pass.ts`
- Modify: `server/src/agent_runner.ts`

- [ ] **Step 1: Implement wrapper**

Create `server/src/reviewer_pass.ts`:

```ts
/**
 * When an agent has Precision skill >= 7, after the main query() completes,
 * spawn the reviewer sub-agent as a second pass to validate the output.
 *
 * Caller is responsible for accumulating token cost (energy_tracker).
 */

import { query, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { roleTemplates } from "./agents.js";

export interface ReviewerPassResult {
  reviewerText: string;
  tokensUsed: number;
}

export async function runReviewerPass(opts: {
  originalTask: string;
  originalOutput: string;
  projectCwd: string;
}): Promise<ReviewerPassResult> {
  const reviewerTemplate = roleTemplates["reviewer"];
  const prompt = `${reviewerTemplate.prompt}

Task under review:
${opts.originalTask}

Agent output to review:
${opts.originalOutput}

Review the output for bugs, anti-patterns, and correctness issues.`;

  let reviewerText = "";
  let tokensUsed = 0;

  for await (const msg of query({
    prompt,
    options: {
      cwd: opts.projectCwd,
      model: reviewerTemplate.model ?? "sonnet",
      allowedTools: reviewerTemplate.tools,
    },
  })) {
    if (msg.type === "result" && msg.subtype === "success") {
      reviewerText = msg.result ?? "";
      tokensUsed = (msg.usage?.input_tokens ?? 0) + (msg.usage?.output_tokens ?? 0);
    }
  }

  return { reviewerText, tokensUsed };
}

/// Trigger threshold: Precision skill level at which reviewer-pass kicks in.
export const REVIEWER_PASS_THRESHOLD = 7;
```

- [ ] **Step 2: Integrate into `agent_runner.ts`**

In `server/src/agent_runner.ts`, after the main sub-agent completes (in `onComplete`), check the dispatching agent's Precision skill. If `>= REVIEWER_PASS_THRESHOLD`, call `runReviewerPass` and append the review to the result.

Locate where `SubAgentResult` is built and patch to include optional review text. Publish the additional tokens via `EnergyTracker.record`.

- [ ] **Step 3: Commit**

```bash
git add server/src/reviewer_pass.ts server/src/agent_runner.ts
git commit -m "feat: reviewer-pass wrapper triggered at Precision>=7"
```

---

### Task 9.2: Update `skillsToModel` with capability score

**Files:**
- Modify: `server/src/agents.ts`

- [ ] **Step 1: Rewrite function**

Replace `skillsToModel` (line ~235):

```ts
/**
 * Maps skill vector to a Claude model using capability-weighted score.
 * Speed is NOT part of capability — it affects reasoning_effort only.
 */
export function skillsToModel(skills: Record<string, number>): "haiku" | "sonnet" | "opus" {
  // New SkillType enum indices: 0=speed, 1=precision, 2=creativity, 3=insight, 4=reliability
  const precision   = skills["1"] ?? 1;
  const creativity  = skills["2"] ?? 1;
  const insight     = skills["3"] ?? 1;
  const reliability = skills["4"] ?? 1;

  const capability = 0.4 * insight + 0.3 * precision + 0.2 * reliability + 0.1 * creativity;
  if (capability >= 14) return "opus";
  if (capability >= 8) return "sonnet";
  return "haiku";
}
```

- [ ] **Step 2: Commit**

```bash
git add server/src/agents.ts
git commit -m "refactor: skillsToModel uses capability score over new skill set"
```

---

## Phase 10 — UI

UI widgets get smoke tests (build doesn't throw). Visual polish is manual.

### Task 10.1: Radar chart widget

**Files:**
- Create: `lib/widgets/agent/agent_skill_radar.dart`
- Create: `test/widgets/agent_skill_radar_test.dart`

- [ ] **Step 1: Smoke test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pixelcode/widgets/agent/agent_skill_radar.dart';
import 'package:pixelcode/models/game_economy.dart';

void main() {
  testWidgets('AgentSkillRadar builds without error', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AgentSkillRadar(skills: {
        SkillType.speed: 5,
        SkillType.precision: 7,
        SkillType.creativity: 3,
        SkillType.insight: 8,
        SkillType.reliability: 4,
      }),
    ));
    expect(find.byType(AgentSkillRadar), findsOneWidget);
  });
}
```

- [ ] **Step 2: Implement with `CustomPainter`**

Create `lib/widgets/agent/agent_skill_radar.dart`:

```dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/game_economy.dart';

class AgentSkillRadar extends StatelessWidget {
  final Map<SkillType, int> skills;
  final double size;
  final Color fillColor;
  final Color lineColor;

  const AgentSkillRadar({
    super.key,
    required this.skills,
    this.size = 120,
    this.fillColor = const Color(0x88448AFF),
    this.lineColor = const Color(0xFF448AFF),
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RadarPainter(
            skills: skills,
            fillColor: fillColor,
            lineColor: lineColor,
          ),
        ),
      );
}

class _RadarPainter extends CustomPainter {
  final Map<SkillType, int> skills;
  final Color fillColor, lineColor;

  _RadarPainter({required this.skills, required this.fillColor, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final axes = SkillType.values;
    final n = axes.length;   // 5

    // grid rings
    final gridPaint = Paint()..style = PaintingStyle.stroke..color = Colors.grey.withOpacity(0.3);
    for (final frac in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -pi / 2 + i * 2 * pi / n;
        final p = center + Offset(cos(angle), sin(angle)) * radius * frac;
        if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // data polygon
    final fill = Paint()..style = PaintingStyle.fill..color = fillColor;
    final stroke = Paint()..style = PaintingStyle.stroke..color = lineColor..strokeWidth = 2;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = ((skills[axes[i]] ?? 1) / 20).clamp(0.05, 1.0);
      final angle = -pi / 2 + i * 2 * pi / n;
      final p = center + Offset(cos(angle), sin(angle)) * radius * v;
      if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // labels (icons)
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < n; i++) {
      final angle = -pi / 2 + i * 2 * pi / n;
      tp.text = TextSpan(text: axes[i].icon, style: const TextStyle(fontSize: 10));
      tp.layout();
      final lp = center + Offset(cos(angle), sin(angle)) * (radius + 6);
      tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.skills != skills;
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/widgets/agent_skill_radar_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/agent/agent_skill_radar.dart test/widgets/agent_skill_radar_test.dart
git commit -m "feat: AgentSkillRadar pentagon chart widget"
```

---

### Task 10.2: Level badge

**Files:**
- Create: `lib/widgets/agent/level_badge.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/material.dart';

class LevelBadge extends StatelessWidget {
  final int level;
  final double fontSize;
  const LevelBadge({super.key, required this.level, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    final label = level >= 10 ? '⚡$level' : 'Lv $level';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: level >= 10 ? Colors.amber.shade700 : Colors.blueGrey.shade700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/agent/level_badge.dart
git commit -m "feat: LevelBadge widget for agent level display"
```

---

### Task 10.3: Task card requirement chips + rejection tooltip

**Files:**
- Modify: `lib/widgets/board/task_board_panel.dart`

- [ ] **Step 1: Add requirement chip rendering**

Locate the task-card rendering in `task_board_panel.dart`. Near the existing `_DifficultyBadge` (line ~2054), add a new small widget that renders:

```dart
class _RequirementChip extends StatelessWidget {
  final TaskCard task;
  const _RequirementChip({required this.task});

  @override
  Widget build(BuildContext context) {
    final roleLabel = task.allowedRoles.length == 1
        ? (roleCatalogFor(task.allowedRoles.first)?.role ?? task.allowedRoles.first)
        : '${task.allowedRoles.length} ролей';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('🎯 Lv ${task.requiredLevel}+ · $roleLabel',
          style: const TextStyle(fontSize: 10, color: Colors.white70)),
    );
  }
}
```

Render it inside the card row next to `_DifficultyBadge`.

- [ ] **Step 2: Wire rejection feedback on assignment**

Locate where drag-drop or assignment triggers `assignAgent`. Instead of silent no-op on rejection, surface `assignmentRejectionReason` result as a `SnackBar`:

```dart
final reason = assignmentRejectionReason(task, agent);
if (reason != null) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
  return;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/board/task_board_panel.dart
git commit -m "feat: task card shows role/level requirements and rejection reason"
```

---

### Task 10.4: Energy meter widget

**Files:**
- Create: `lib/widgets/energy/energy_meter.dart`
- Modify: wherever the office header is rendered (check `lib/screens/hub/hub_screen.dart`)

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/energy_provider.dart';

class EnergyMeter extends ConsumerWidget {
  const EnergyMeter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(energyProvider);
    final pct = (e.tokensUsedToday / e.dailyTokenCap).clamp(0.0, 1.0);
    final color = pct > 0.9 ? Colors.red : (pct > 0.7 ? Colors.orange : Colors.greenAccent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🪫 ', style: TextStyle(fontSize: 14)),
        Text('${_fmtK(e.tokensUsedToday)} / ${_fmtK(e.dailyTokenCap)}',
            style: TextStyle(color: color, fontSize: 12)),
        const SizedBox(width: 10),
        Text('⚡ O ${e.opusTasksUsedToday}/${e.opusCapPerDay}',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        const SizedBox(width: 8),
        Text('S ${e.sonnetTasksUsedToday}/${e.sonnetCapPerDay}',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  static String _fmtK(int v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : '$v';
}
```

- [ ] **Step 2: Wire into header**

Add `const EnergyMeter()` to the top bar in `hub_screen.dart`.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/energy/energy_meter.dart lib/screens/hub/hub_screen.dart
git commit -m "feat: EnergyMeter widget in office header"
```

---

### Task 10.5: Reviewer-pass indicator

**Files:**
- Modify: `lib/widgets/board/task_board_panel.dart`

- [ ] **Step 1: Add indicator**

Inside the task card widget, if any `assignedAgent` has `skills[SkillType.precision] >= 7`, render:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  decoration: BoxDecoration(
    color: Colors.amber.withOpacity(0.3),
    borderRadius: BorderRadius.circular(3),
  ),
  child: const Text('⚡ ×1.8 tokens', style: TextStyle(fontSize: 9, color: Colors.amber)),
)
```

Tooltip on hover: "Високий Precision автоматично запускає reviewer-pass — додатковий sub-agent для перевірки. Це token-heavy."

- [ ] **Step 2: Commit**

```bash
git add lib/widgets/board/task_board_panel.dart
git commit -m "feat: reviewer-pass token cost indicator on task cards"
```

---

### Task 10.6: Shop panel — update skill labels and cap

**Files:**
- Modify: `lib/widgets/shop/shop_panel.dart`

- [ ] **Step 1: Fix compile errors**

Old references to `SkillType.quality`, `SkillType.communication`, etc. will be present. Replace with the new enum values.

Where the upgrade UI currently shows "1-10 level bar", change the max to `skillCap(agent.level)`.

Import:
```dart
import '../../models/agent_level.dart';
```

Example spot (adapt to actual code):
```dart
// old: final maxLevel = 10;
final maxLevel = skillCap(agent.level);
```

- [ ] **Step 2: Ensure `flutter analyze` is clean for this file**

Run: `flutter analyze lib/widgets/shop/shop_panel.dart`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/shop/shop_panel.dart
git commit -m "fix(ui): shop panel uses new SkillType and dynamic skillCap"
```

---

## Phase 11 — Drop-Migration Toast

### Task 11.1: Show reset toast on first boot of new schema

**Files:**
- Modify: `lib/main.dart` (or appropriate root widget)

- [ ] **Step 1: Check prefs flag after first frame**

In the root widget's `initState` or a top-level `addPostFrameCallback`:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  final prefs = ref.read(sharedPrefsProvider);
  if (prefs.getBool('schemaResetFlag') == true) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'Оновлення системи агентів вимагає перезапуску прогресу. '
          'Ваші гримні, ачівки та косметика збережені.',
        ),
      ),
    );
    prefs.remove('schemaResetFlag');
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add lib/main.dart
git commit -m "feat: show drop-migration toast after schema reset"
```

---

## Phase 12 — Server drift emission

### Task 12.1: Server-side drift mirror

**Files:**
- Create: `server/src/archetype_drift.ts`
- Modify: `server/src/trait_memory.ts`

The server also holds agent state (for prompt composition). When traits cross thresholds in `TraitStore`, we need to emit the drift so server-rendered system prompts reflect the updated archetype.

- [ ] **Step 1: Mirror the Dart drift table**

Create `server/src/archetype_drift.ts` — exact same table as the Dart one (Task 3.1). Use TypeScript objects.

```ts
const STEP = 0.005;
const STRENGTH_DELTAS: Record<string, Record<string, number>> = {
  "fast-delivery": { speed: STEP, precision: -STEP / 2, reliability: -STEP / 2 },
  architecture: { insight: STEP, speed: -STEP / 2 },
  "refactoring-patience": { precision: STEP, speed: -STEP },
  "rapid-iteration": { reliability: STEP, speed: STEP / 2, precision: -STEP },
  "divergent-brainstorm": { creativity: STEP, precision: -STEP / 2 },
};
const WEAKNESS_DELTAS: Record<string, Record<string, number>> = {
  "complex-reasoning": { insight: -STEP },
};

export function archetypeDelta(
  traitTag: string,
  traitType: "strength" | "weakness",
): Record<string, number> | null {
  const table = traitType === "strength" ? STRENGTH_DELTAS : WEAKNESS_DELTAS;
  return table[traitTag] ?? null;
}
```

- [ ] **Step 2: Emit from `trait_memory.ts`**

Where a trait's `frequency` is incremented, if crossing 3, emit an event/callback that the WS server can forward to clients. (Exact integration depends on the existing module — read the file first.)

- [ ] **Step 3: Commit**

```bash
git add server/src/archetype_drift.ts server/src/trait_memory.ts
git commit -m "feat: server-side archetype drift table mirrors client"
```

---

## Phase 13 — End-to-End Smoke + Polish

### Task 13.1: Manual verification checklist

- [ ] **Step 1: Run app against a fresh save**

```
rm ~/Library/Preferences/com.pixelcode.*.plist   # macOS, adjust for platform
flutter run -d macos
```

Expected: fresh state, tutorial-like defaults.

- [ ] **Step 2: Hire a coder, verify**

- Appears with Lv 1, some skills 1-7 distributed by archetype.
- 1-2 quirks visible.
- Radar chart shows pentagon.

- [ ] **Step 3: Create a task with difficulty 5**

- Assign Lv 1 coder → should see SnackBar "Потрібен Lv 11+...".
- Change to difficulty 2 → assignment succeeds.

- [ ] **Step 4: Complete several tasks**

- XP accrues; agent levels up; skill-upgrade cap moves from 12 to 14 at Lv 2.

- [ ] **Step 5: Verify Energy meter**

- Top-right shows `🪫 ... / 500k`.
- After many tasks, color shifts orange → red.

- [ ] **Step 6: Trigger old-save toast**

- Manually write an old-version save JSON to prefs, restart; toast appears.

- [ ] **Step 7: Run all tests**

Run: `flutter test && cd server && npm test`
Expected: all pass.

- [ ] **Step 8: Commit final (empty if nothing changed)**

If any last fixups came up, commit them. Otherwise skip.

---

## Self-Review Checklist

Against the spec at [docs/superpowers/specs/2026-04-20-agent-level-skill-archetype-system-design.md](../specs/2026-04-20-agent-level-skill-archetype-system-design.md):

- [x] Level (spec §3) → Phase 1.5, 2.1, 2.2.
- [x] 5 skills + LLM mapping (spec §4) → Phase 1.2, 9.2 (skillsToModel rewrite), 9.1 (reviewer-pass).
- [x] Hybrid gating (spec §5) → Phase 1.6, 5.1.
- [x] Evolutionary archetypes via TraitStore (spec §6) → Phase 1.3, 3.1, 3.2, 12.1.
- [x] Quirks catalog (spec §7) → Phase 1.4, 4.1, 4.2.
- [x] Task completion formulas (spec §8) → Phase 6.1, 6.2, 6.3, 9.1.
- [x] Energy meter (spec §9) → Phase 7.1, 7.2, 10.4.
- [x] 3 new roles (spec §10) → Phase 8.1, 8.2.
- [x] UI changes (spec §11) → Phase 10.*.
- [x] Schema drop migration (spec §10.3) → Phase 1.1, 11.1.
- [x] Server skillsToModel recalibration → Phase 9.2.

No placeholders. Types consistent (`ArchetypeVector`, `Quirk`, `TaskOutcome`, `EnergyState` used consistently across tasks).

---

## Notes for the engineer

- Type changes in Phase 1 will cause **compile errors** in `shop_panel.dart`, `game_economy_provider.dart`, `chat_panel.dart`, and others. This is expected. Phases 2, 4, 10 clean them up progressively. Do NOT spot-fix out of order — it creates diff churn.
- `flutter analyze` will be red between Phase 1.2 and end of Phase 10.6. Green only at the end of Phase 10.
- `ResultMessage` and similar server-message shapes in [lib/models/agent_message.dart](../../lib/models/agent_message.dart) may need `hadBug`/`cleanCompletion`/`agentId` fields added to propagate outcome info. If so, extend both Dart model and server serializer; treat as a small sidecar task if discovered.
- The existing `lib/providers/task_progress_provider.dart` uses a simple `_rng` and column-aware time; preserve that pattern. The outcome roll plugs into the advancement branch, not the tick.
- Flutter package name in `import 'package:XXX/...'` — check `pubspec.yaml`. Tests above use `pixelcode` as placeholder; substitute the real name.
