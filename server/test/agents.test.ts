import { test } from "node:test";
import assert from "node:assert/strict";
import { skillsToModel } from "../src/agents.ts";

// Skill indices: 0=speed, 1=precision, 2=creativity, 3=insight, 4=reliability

test("skillsToModel — starter agent (all ~2) → haiku", () => {
  const skills = { "0": 3, "1": 3, "2": 2, "3": 3, "4": 2 };
  // capability = 0.4*3 + 0.3*3 + 0.2*2 + 0.1*2 = 1.2 + 0.9 + 0.4 + 0.2 = 2.7
  assert.equal(skillsToModel(skills), "haiku");
});

test("skillsToModel — mid-Lv reviewer (high precision+insight) → sonnet", () => {
  // Precision 10, Insight 8, Reliability 5, Creativity 1
  const skills = { "0": 1, "1": 10, "2": 1, "3": 8, "4": 5 };
  // capability = 0.4*8 + 0.3*10 + 0.2*5 + 0.1*1 = 3.2 + 3.0 + 1.0 + 0.1 = 7.3 → still haiku
  assert.equal(skillsToModel(skills), "haiku");
});

test("skillsToModel — upgraded mid-tier agent → sonnet", () => {
  // capability = 0.4*14 + 0.3*10 + 0.2*8 + 0.1*4 = 5.6 + 3.0 + 1.6 + 0.4 = 10.6
  const skills = { "0": 4, "1": 10, "2": 4, "3": 14, "4": 8 };
  assert.equal(skillsToModel(skills), "sonnet");
});

test("skillsToModel — elite agent (insight-max) → opus", () => {
  // capability = 0.4*20 + 0.3*15 + 0.2*15 + 0.1*10 = 8 + 4.5 + 3 + 1 = 16.5
  const skills = { "0": 5, "1": 15, "2": 10, "3": 20, "4": 15 };
  assert.equal(skillsToModel(skills), "opus");
});

test("skillsToModel — speed is ignored for capability", () => {
  // Very high Speed, mediocre everything else → should still be haiku.
  const skills = { "0": 50, "1": 3, "2": 3, "3": 3, "4": 3 };
  // capability = 0.4*3 + 0.3*3 + 0.2*3 + 0.1*3 = 3.0
  assert.equal(skillsToModel(skills), "haiku");
});

test("skillsToModel — empty skills → haiku", () => {
  assert.equal(skillsToModel({}), "haiku");
});
