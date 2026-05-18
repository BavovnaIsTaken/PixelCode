import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  bugChance,
  completionSuccessChance,
  critChance,
  divergentTaskTypes,
  lessonSuccessBonus,
  mulberry32,
  projectMemoryDepthBonus,
  rollOutcome,
  workstationTaskTypes,
  kMaxLessonSuccessBonusInRoll,
  kMaxProjectMemoryBonusInRoll,
  kMaxSpecializationCritBonusInRoll,
  kUnassignedIncompletePenalty,
  type Rng,
} from "../src/task_outcome.js";

function approx(actual: number, expected: number, eps = 1e-9): void {
  assert.ok(
    Math.abs(actual - expected) < eps,
    `expected ${expected} ± ${eps}, got ${actual}`,
  );
}

// ─── Skill curves (mirror Dart suite) ─────────────────────────────────────────

describe("bugChance", () => {
  test("clamps to [0, 0.4]", () => {
    assert.equal(bugChance(0), 0.4);
    assert.equal(bugChance(14), 0.0);
    approx(bugChance(7), 0.19);
    assert.equal(bugChance(100), 0.0);
  });
});

describe("critChance", () => {
  test("is 0.02 * creativity", () => {
    assert.equal(critChance(0), 0.0);
    approx(critChance(10), 0.2);
  });
  test("clamps at 1.0", () => {
    assert.equal(critChance(100), 1.0);
  });
});

describe("completionSuccessChance", () => {
  test("starts at 0.85", () => {
    assert.equal(completionSuccessChance(0), 0.85);
  });
  test("caps at 1.0", () => {
    assert.equal(completionSuccessChance(100), 1.0);
  });
  test("reaches 1.0 by reliability 15", () => {
    assert.equal(completionSuccessChance(15), 1.0);
  });
});

describe("lessonSuccessBonus", () => {
  test("clamps at kMaxLessonSuccessBonusInRoll (0.10)", () => {
    assert.equal(lessonSuccessBonus(0), 0.0);
    approx(lessonSuccessBonus(10), 0.05);
    assert.equal(lessonSuccessBonus(20), kMaxLessonSuccessBonusInRoll);
    assert.equal(lessonSuccessBonus(1000), kMaxLessonSuccessBonusInRoll);
  });
});

describe("projectMemoryDepthBonus", () => {
  test("clamps at kMaxProjectMemoryBonusInRoll (0.15)", () => {
    assert.equal(projectMemoryDepthBonus(0), 0.0);
    approx(projectMemoryDepthBonus(5), 0.01);
    assert.equal(projectMemoryDepthBonus(75), kMaxProjectMemoryBonusInRoll);
    assert.equal(projectMemoryDepthBonus(10000), kMaxProjectMemoryBonusInRoll);
  });
});

describe("task type sets", () => {
  test("divergentTaskTypes covers architecture/product-spec/ui-design", () => {
    assert.ok(divergentTaskTypes.has("architecture"));
    assert.ok(divergentTaskTypes.has("product-spec"));
    assert.ok(divergentTaskTypes.has("ui-design"));
    assert.equal(divergentTaskTypes.has("coding"), false);
  });
  test("workstationTaskTypes covers coding/testing/debugging", () => {
    assert.ok(workstationTaskTypes.has("coding"));
    assert.ok(workstationTaskTypes.has("testing"));
    assert.ok(workstationTaskTypes.has("debugging"));
    assert.equal(workstationTaskTypes.has("architecture"), false);
  });
});

// ─── rollOutcome — distributional / behavioral ────────────────────────────────

describe("rollOutcome — happy-path agent", () => {
  test("high-everything agent almost always gets clean", () => {
    const rng = mulberry32(1);
    let clean = 0;
    let incomplete = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 10,
        creativitySkill: 0,
        reliabilitySkill: 15,
      });
      if (r === "clean") clean++;
      if (r === "incomplete") incomplete++;
    }
    assert.ok(clean > 850, `clean=${clean}`);
    assert.equal(incomplete, 0);
  });
});

describe("rollOutcome — low-reliability agent", () => {
  test("often incomplete", () => {
    const rng = mulberry32(1);
    let incomplete = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 10,
        creativitySkill: 0,
        reliabilitySkill: 0,
      });
      if (r === "incomplete") incomplete++;
    }
    // 0.85 success rate → ~15% incomplete
    assert.ok(incomplete > 100, `incomplete=${incomplete}`);
    assert.ok(incomplete < 200, `incomplete=${incomplete}`);
  });
});

describe("rollOutcome — low-precision agent", () => {
  test("often bugs", () => {
    const rng = mulberry32(1);
    let bugs = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 0,
        creativitySkill: 0,
        reliabilitySkill: 15,
      });
      if (r === "bug") bugs++;
    }
    // 0.4 bug rate
    assert.ok(bugs > 350, `bugs=${bugs}`);
    assert.ok(bugs < 450, `bugs=${bugs}`);
  });
});

describe("rollOutcome — crit gating", () => {
  test("never crits on convergent task type", () => {
    const rng = mulberry32(42);
    let crit = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 15,
        creativitySkill: 50,
        reliabilitySkill: 15,
        isDivergentTask: false,
      });
      if (r === "crit") crit++;
    }
    assert.equal(crit, 0);
  });

  test("crits on divergent task with high creativity", () => {
    const rng = mulberry32(42);
    let crit = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 15,
        creativitySkill: 50,
        reliabilitySkill: 15,
        isDivergentTask: true,
      });
      if (r === "crit") crit++;
    }
    // creativity 50 → cap 1.0 → essentially always crits
    assert.ok(crit > 900, `crit=${crit}`);
  });

  test("specializationCritBonus is clamped to 0.30", () => {
    const rng = mulberry32(7);
    let crit = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 15,
        isDivergentTask: true,
        specializationCritBonus: 1.0, // clamps to 0.30
      });
      if (r === "crit") crit++;
    }
    // crit chance = 0 + 0.30 = 0.30 → ~300 of 1000
    assert.ok(crit > 230, `crit=${crit}`);
    assert.ok(crit < 370, `crit=${crit}`);
  });

  test("projectMemoryBonus only applies to architecture", () => {
    const rngArch = mulberry32(9);
    const rngSpec = mulberry32(9);
    let critArch = 0;
    let critSpec = 0;
    for (let i = 0; i < 1000; i++) {
      const rArch = rollOutcome({
        rng: rngArch,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 15,
        isDivergentTask: true,
        taskType: "architecture",
        projectMemoryBonus: 1.0, // clamped to 0.15
      });
      const rSpec = rollOutcome({
        rng: rngSpec,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 15,
        isDivergentTask: true,
        taskType: "product-spec",
        projectMemoryBonus: 1.0, // ignored — not architecture
      });
      if (rArch === "crit") critArch++;
      if (rSpec === "crit") critSpec++;
    }
    assert.ok(critArch > 100, `critArch=${critArch}`);
    assert.equal(critSpec, 0, `critSpec=${critSpec}`);
  });
});

describe("rollOutcome — workstation desk penalty", () => {
  test("unassigned coder hits −0.25 success penalty", () => {
    const rngWith = mulberry32(11);
    const rngWithout = mulberry32(11);
    let incompleteWith = 0;
    let incompleteWithout = 0;
    for (let i = 0; i < 1000; i++) {
      const rWith = rollOutcome({
        rng: rngWith,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 0,
        taskType: "coding",
        isUnassigned: false,
      });
      const rWithout = rollOutcome({
        rng: rngWithout,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 0,
        taskType: "coding",
        isUnassigned: true,
      });
      if (rWith === "incomplete") incompleteWith++;
      if (rWithout === "incomplete") incompleteWithout++;
    }
    // base success 0.85 → 15% incomplete; with penalty 0.85−0.25=0.60 → 40% incomplete
    approx(incompleteWith / 1000, 0.15, 0.05);
    approx(incompleteWithout / 1000, 0.40, 0.06);
  });

  test("desk penalty does NOT apply to non-workstation tasks", () => {
    const rng = mulberry32(13);
    let incomplete = 0;
    for (let i = 0; i < 1000; i++) {
      const r = rollOutcome({
        rng,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 0,
        taskType: "architecture",
        isUnassigned: true, // ignored — not a workstation task
      });
      if (r === "incomplete") incomplete++;
    }
    approx(incomplete / 1000, 0.15, 0.05);
  });
});

describe("rollOutcome — lesson bonus offsets incomplete", () => {
  test("20 lessons cancels 10% of incomplete rate (cap)", () => {
    const rngWith = mulberry32(17);
    const rngWithout = mulberry32(17);
    let incompleteWith = 0;
    let incompleteWithout = 0;
    for (let i = 0; i < 1000; i++) {
      const rWith = rollOutcome({
        rng: rngWith,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 0,
        lessonBonus: lessonSuccessBonus(20), // +0.10
      });
      const rWithout = rollOutcome({
        rng: rngWithout,
        precisionSkill: 15,
        creativitySkill: 0,
        reliabilitySkill: 0,
        lessonBonus: 0.0,
      });
      if (rWith === "incomplete") incompleteWith++;
      if (rWithout === "incomplete") incompleteWithout++;
    }
    // baseline 0.85 → 0.95 with bonus → 5% incomplete vs 15%
    approx(incompleteWith / 1000, 0.05, 0.04);
    approx(incompleteWithout / 1000, 0.15, 0.05);
  });

  test("lessonBonus is defensively clamped to 0.10", () => {
    // Force success-check to always pass by feeding a deterministic RNG that
    // returns < 1.0; the clamp protects against a caller passing a huge bonus.
    const rng: Rng = () => 0.94; // > 0.85 baseline, must rely on bonus to pass
    const r = rollOutcome({
      rng,
      precisionSkill: 15,
      creativitySkill: 0,
      reliabilitySkill: 0,
      lessonBonus: 999, // clamps to 0.10 → adjusted = 0.95
    });
    // 0.94 < 0.95 → success branch → bug check → clean
    assert.notEqual(r, "incomplete");
  });
});

describe("rollOutcome — known check-order", () => {
  test("first roll is reliability (incomplete path)", () => {
    // Force rng() > adjustedSuccess on first call.
    const seq = [0.99, 0.0, 0.0];
    let i = 0;
    const rng: Rng = () => seq[i++]!;
    const r = rollOutcome({
      rng,
      precisionSkill: 15,
      creativitySkill: 0,
      reliabilitySkill: 0, // baseline 0.85; 0.99 > 0.85 → incomplete
    });
    assert.equal(r, "incomplete");
  });

  test("second roll is bug (precision)", () => {
    // Skip reliability (yields success), then trigger bug.
    const seq = [0.0, 0.0, 0.0];
    let i = 0;
    const rng: Rng = () => seq[i++]!;
    const r = rollOutcome({
      rng,
      precisionSkill: 0, // bugChance 0.4 → 0.0 < 0.4 → bug
      creativitySkill: 0,
      reliabilitySkill: 15,
    });
    assert.equal(r, "bug");
  });

  test("third roll is crit (divergent only)", () => {
    const seq = [0.0, 0.99, 0.0];
    let i = 0;
    const rng: Rng = () => seq[i++]!;
    const r = rollOutcome({
      rng,
      precisionSkill: 15,
      creativitySkill: 50, // crit cap 1.0
      reliabilitySkill: 15,
      isDivergentTask: true,
    });
    assert.equal(r, "crit");
  });

  test("non-divergent skips crit roll → clean", () => {
    const seq = [0.0, 0.99, 0.0];
    let i = 0;
    const rng: Rng = () => seq[i++]!;
    const r = rollOutcome({
      rng,
      precisionSkill: 15,
      creativitySkill: 50,
      reliabilitySkill: 15,
      isDivergentTask: false,
    });
    assert.equal(r, "clean");
  });
});

describe("constants — Dart parity pins", () => {
  test("must equal Dart-side constants exactly", () => {
    // If any of these drift, update lib/services/task_outcome.dart in the
    // same commit. Keeping the values inline (not imported) is intentional.
    assert.equal(kUnassignedIncompletePenalty, 0.25);
    assert.equal(kMaxSpecializationCritBonusInRoll, 0.30);
    assert.equal(kMaxLessonSuccessBonusInRoll, 0.10);
    assert.equal(kMaxProjectMemoryBonusInRoll, 0.15);
  });
});

describe("mulberry32 — determinism", () => {
  test("same seed → same sequence", () => {
    const a = mulberry32(123);
    const b = mulberry32(123);
    for (let i = 0; i < 20; i++) {
      assert.equal(a(), b());
    }
  });
  test("different seeds → different sequences", () => {
    const a = mulberry32(123);
    const b = mulberry32(124);
    let differed = 0;
    for (let i = 0; i < 20; i++) {
      if (a() !== b()) differed++;
    }
    assert.ok(differed > 18, `differed=${differed}`);
  });
});
