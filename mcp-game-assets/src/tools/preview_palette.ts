/**
 * Tool: preview_skin_palette.
 *
 * Static analysis of a proposed (or existing) palette: per-slot hex codes,
 * WCAG contrast against floor colors of every office tier, verdict per tier.
 * The agent reads this output to detect unreadable skins before they ship.
 *
 * Inputs accept either a single `palette + class_id` pair OR a map of
 * agent_id → palette so the agent can preview a full skin in one call.
 */

import { z } from "zod";

import { contrastRatio, contrastVerdict, parseHex, normalizeHex, isValidHex } from "../lib/color.js";
import { ROOM_THEME_FLOORS } from "../lib/room_themes.js";
import { SKIN_KEYS, validateSkinPalette, type SkinPalette } from "../lib/skin_io.js";

const PALETTE_SHAPE = z.object({
  hair: z.string(),
  skin: z.string(),
  skinLight: z.string(),
  eye: z.string(),
  clothes: z.string(),
  pants: z.string(),
  boots: z.string(),
});

export const previewSkinPaletteSchema = {
  palette: PALETTE_SHAPE.optional().describe(
    "Single 7-color palette to preview. Use with class_id to label the report.",
  ),
  class_id: z
    .string()
    .optional()
    .describe('Agent class id when previewing a single palette, e.g. "tester".'),
  palettes: z
    .record(z.string(), PALETTE_SHAPE)
    .optional()
    .describe(
      "Map of agent_id → palette to preview a full skin. Mutually exclusive with `palette`.",
    ),
};

export interface FloorContrast {
  tier: number;
  room_id: string;
  floor_light_ratio: number;
  floor_dark_ratio: number;
  worst_ratio: number;
  verdict: "readable" | "borderline" | "unreadable";
}

export interface PaletteReport {
  class_id: string;
  hex_codes: SkinPalette;
  floor_contrast: FloorContrast[];
  silhouette_slots: ("clothes" | "pants" | "boots" | "hair")[];
  worst_slot: { slot: string; tier: number; verdict: string; ratio: number };
}

export interface PreviewResult {
  reports: PaletteReport[];
  summary: {
    total_palettes: number;
    unreadable_count: number;
    borderline_count: number;
    notes: string[];
  };
}

export function runPreviewSkinPalette(input: {
  palette?: SkinPalette;
  class_id?: string;
  palettes?: Record<string, SkinPalette>;
}): PreviewResult {
  if (input.palette && input.palettes) {
    throw new Error("Pass either `palette` (single) or `palettes` (map), not both.");
  }
  if (!input.palette && !input.palettes) {
    throw new Error("Pass `palette` + `class_id`, or `palettes` map of agent_id → palette.");
  }

  const reports: PaletteReport[] = [];

  if (input.palette) {
    const classId = input.class_id ?? "(unspecified)";
    reports.push(buildReport(classId, validateSkinPalette(input.palette, classId)));
  } else if (input.palettes) {
    for (const [classId, p] of Object.entries(input.palettes)) {
      reports.push(buildReport(classId, validateSkinPalette(p, classId)));
    }
  }

  let unreadable = 0;
  let borderline = 0;
  for (const r of reports) {
    if (r.worst_slot.verdict === "unreadable") unreadable++;
    else if (r.worst_slot.verdict === "borderline") borderline++;
  }

  const notes: string[] = [];
  if (unreadable > 0) {
    notes.push(
      `${unreadable} palette(s) have an unreadable silhouette slot on at least one office tier — character will blend with floor.`,
    );
  }
  if (borderline > 0) {
    notes.push(
      `${borderline} palette(s) have borderline (3.0–4.5) contrast — readable for large shapes, risky for small details.`,
    );
  }
  if (unreadable === 0 && borderline === 0) {
    notes.push("All palettes pass readability checks across all 5 office tiers.");
  }

  return {
    reports,
    summary: {
      total_palettes: reports.length,
      unreadable_count: unreadable,
      borderline_count: borderline,
      notes,
    },
  };
}

const SILHOUETTE_SLOTS: PaletteReport["silhouette_slots"] = ["hair", "clothes", "pants", "boots"];

function buildReport(classId: string, palette: SkinPalette): PaletteReport {
  const floorContrasts: FloorContrast[] = [];
  let worst: PaletteReport["worst_slot"] = {
    slot: "clothes",
    tier: 1,
    verdict: "readable",
    ratio: 21,
  };

  for (const floor of ROOM_THEME_FLOORS) {
    const floorLight = parseHex(floor.floorLight);
    const floorDark = parseHex(floor.floorDark);

    let tierWorstRatio = 21;
    let tierWorstVerdict: ReturnType<typeof contrastVerdict> = "readable";
    for (const slot of SILHOUETTE_SLOTS) {
      const slotRgb = parseHex(palette[slot]);
      const ratioLight = contrastRatio(slotRgb, floorLight);
      const ratioDark = contrastRatio(slotRgb, floorDark);
      const slotWorst = Math.min(ratioLight, ratioDark);
      if (slotWorst < tierWorstRatio) {
        tierWorstRatio = slotWorst;
        tierWorstVerdict = contrastVerdict(slotWorst);
        if (slotWorst < worst.ratio) {
          worst = { slot, tier: floor.tier, verdict: tierWorstVerdict, ratio: slotWorst };
        }
      }
    }

    const overallLightRatio = SILHOUETTE_SLOTS.reduce((min, s) => {
      const r = contrastRatio(parseHex(palette[s]), floorLight);
      return Math.min(min, r);
    }, 21);
    const overallDarkRatio = SILHOUETTE_SLOTS.reduce((min, s) => {
      const r = contrastRatio(parseHex(palette[s]), floorDark);
      return Math.min(min, r);
    }, 21);

    floorContrasts.push({
      tier: floor.tier,
      room_id: floor.id,
      floor_light_ratio: round2(overallLightRatio),
      floor_dark_ratio: round2(overallDarkRatio),
      worst_ratio: round2(tierWorstRatio),
      verdict: tierWorstVerdict,
    });
  }

  return {
    class_id: classId,
    hex_codes: normalizePaletteHexes(palette),
    floor_contrast: floorContrasts,
    silhouette_slots: SILHOUETTE_SLOTS,
    worst_slot: { ...worst, ratio: round2(worst.ratio) },
  };
}

function normalizePaletteHexes(p: SkinPalette): SkinPalette {
  const out = {} as SkinPalette;
  for (const k of SKIN_KEYS) {
    out[k] = isValidHex(p[k]) ? normalizeHex(p[k]) : p[k];
  }
  return out;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
