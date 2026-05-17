/**
 * Tool: diff_against_existing_palettes.
 *
 * For a proposed palette, find the top-K nearest existing palettes in the
 * project's character_skins.dart. Distance metric is Euclidean RGB summed
 * over the 7 slots — fast, deterministic, sufficient for "is this a clone
 * of skin X / class Y" detection.
 *
 * The character-artist agent uses this to actively avoid mode collapse:
 * before publishing a new skin, it self-checks against the existing 8 × N
 * palette grid and shifts hue/value if the proposal is too close.
 *
 * Threshold: total distance ≤ 80 across 7 slots is flagged as `is_clone`.
 * That's an average of ~11 per slot, which is roughly imperceptible drift.
 * (For reference: max possible per-slot RGB distance is ~441.)
 */

import { z } from "zod";
import * as path from "node:path";
import { readFileSync, existsSync } from "node:fs";

import { hexDistance } from "../lib/color.js";
import {
  parseAgentsList,
  parseExistingSkins,
  validateSkinPalette,
  SKIN_KEYS,
  type SkinPalette,
} from "../lib/skin_io.js";

const PALETTE_SHAPE = z.object({
  hair: z.string(),
  skin: z.string(),
  skinLight: z.string(),
  eye: z.string(),
  clothes: z.string(),
  pants: z.string(),
  boots: z.string(),
});

export const diffAgainstExistingPalettesSchema = {
  palette: PALETTE_SHAPE.describe("Proposed 7-color palette to compare against existing skins."),
  class_id: z
    .string()
    .describe('Agent class to compare against, e.g. "tester". Existing skins are filtered by this id.'),
  top_k: z.number().int().min(1).max(10).optional().describe("How many nearest matches to return (default 3)."),
  clone_threshold: z
    .number()
    .min(0)
    .optional()
    .describe("Total distance below this is flagged is_clone (default 80)."),
  project_dir: z
    .string()
    .optional()
    .describe("Override for project root if PROJECT_DIR env is wrong."),
};

export interface PaletteMatch {
  skin_id: string;
  skin_name_en: string;
  total_distance: number;
  per_slot_distance: Record<string, number>;
}

export interface DiffResult {
  class_id: string;
  proposed: SkinPalette;
  matches: PaletteMatch[];
  is_clone: boolean;
  closest_skin_id: string | null;
  threshold_used: number;
  notes: string[];
}

const DEFAULT_THRESHOLD = 80;
const DEFAULT_TOP_K = 3;

export function runDiffAgainstExistingPalettes(
  input: {
    palette: SkinPalette;
    class_id: string;
    top_k?: number;
    clone_threshold?: number;
    project_dir?: string;
  },
  defaultProjectDir: string,
): DiffResult {
  const projectDir = input.project_dir ?? defaultProjectDir;
  const skinFile = path.join(projectDir, "lib", "widgets", "canvas", "character_skins.dart");

  if (!existsSync(skinFile)) {
    throw new Error(`character_skins.dart not found at ${skinFile}.`);
  }

  const proposed = validateSkinPalette(input.palette, input.class_id);
  const topK = input.top_k ?? DEFAULT_TOP_K;
  const threshold = input.clone_threshold ?? DEFAULT_THRESHOLD;

  const src = readFileSync(skinFile, "utf8");
  const agents = parseAgentsList(src);

  if (!agents.includes(input.class_id)) {
    throw new Error(
      `Unknown class_id "${input.class_id}". Valid classes: ${agents.join(", ")}.`,
    );
  }

  const existing = parseExistingSkins(src, agents);
  const candidates: PaletteMatch[] = [];

  for (const skin of existing) {
    const ep = skin.palettes[input.class_id];
    if (!ep) continue;

    const perSlot: Record<string, number> = {};
    let total = 0;
    for (const slot of SKIN_KEYS) {
      const d = hexDistance(proposed[slot], ep[slot]);
      perSlot[slot] = round2(d);
      total += d;
    }
    candidates.push({
      skin_id: skin.id,
      skin_name_en: skin.nameEn,
      total_distance: round2(total),
      per_slot_distance: perSlot,
    });
  }

  candidates.sort((a, b) => a.total_distance - b.total_distance);
  const matches = candidates.slice(0, topK);
  const closest = candidates[0];
  const isClone = closest != null && closest.total_distance <= threshold;

  const notes: string[] = [];
  if (isClone && closest) {
    notes.push(
      `Proposed palette is within ${threshold} total RGB distance of existing skin "${closest.skin_id}" (distance ${closest.total_distance}). ` +
        `This is functionally a clone — shift hue or value on the dominant slots before adding.`,
    );
    const dominantSlots = Object.entries(closest.per_slot_distance)
      .sort((a, b) => a[1] - b[1])
      .slice(0, 2)
      .map(([slot, d]) => `${slot}=${d}`);
    notes.push(`Closest slots: ${dominantSlots.join(", ")}.`);
  } else if (closest) {
    notes.push(
      `Distinct from all ${existing.length} existing skins — closest is "${closest.skin_id}" at distance ${closest.total_distance} (threshold ${threshold}).`,
    );
  } else {
    notes.push("No existing skins found for this class — first palette in the file.");
  }

  return {
    class_id: input.class_id,
    proposed,
    matches,
    is_clone: isClone,
    closest_skin_id: closest?.skin_id ?? null,
    threshold_used: threshold,
    notes,
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
