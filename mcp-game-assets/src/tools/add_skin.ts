/**
 * Tool: add_character_skin.
 *
 * Atomically appends a new `CharacterSkin` declaration to
 * lib/widgets/canvas/character_skins.dart and registers it in the
 * `allCharacterSkins` list. Defensive contract — the agent never has to
 * touch raw Dart source for skin additions.
 *
 * Idempotency: re-running with identical content returns a no-op.
 *
 * Failure modes:
 *   - skin id collision with different content → error (caller picks new id)
 *   - missing palette for any agent class → error (lists missing agents)
 *   - invalid hex in any slot → error with file:agent:slot
 *   - file path missing or unparseable → error pointing at the cause
 */

import { z } from "zod";
import * as path from "node:path";
import { existsSync } from "node:fs";

import {
  insertSkinDeclaration,
  validateSkinPalette,
  parseAgentsList,
  type CharacterSkin,
  type SkinPalette,
} from "../lib/skin_io.js";
import { readFileSync } from "node:fs";

const PALETTE_SHAPE = z.object({
  hair: z.string(),
  skin: z.string(),
  skinLight: z.string(),
  eye: z.string(),
  clothes: z.string(),
  pants: z.string(),
  boots: z.string(),
});

export const addCharacterSkinSchema = {
  skin_id: z
    .string()
    .describe(
      'snake_case identifier, e.g. "demon_slayer". Must not collide with existing skin ids.',
    ),
  name_uk: z.string().describe('Ukrainian display name, e.g. "Демоновбивця".'),
  name_en: z.string().describe('English display name, e.g. "Demon Slayer".'),
  palettes: z
    .record(z.string(), PALETTE_SHAPE)
    .describe(
      "Map of agent_id → 7-color palette (hair, skin, skinLight, eye, clothes, pants, boots). " +
        "All hex codes must be #RRGGBB. Must contain a palette for every agent class in the project " +
        "(parse the canonical list with the `_agents` const in character_skins.dart).",
    ),
  project_dir: z
    .string()
    .optional()
    .describe(
      "Override for project root if the MCP server's PROJECT_DIR env var is wrong (default uses env).",
    ),
};

export interface AddCharacterSkinResult {
  status: "added" | "noop_identical";
  skin_id: string;
  variable_name: string;
  file_path: string;
  inserted_at_line: number;
  registered_in_list: boolean;
  agents_count: number;
  warnings: string[];
}

export function runAddCharacterSkin(
  input: {
    skin_id: string;
    name_uk: string;
    name_en: string;
    palettes: Record<string, SkinPalette>;
    project_dir?: string;
  },
  defaultProjectDir: string,
): AddCharacterSkinResult {
  const projectDir = input.project_dir ?? defaultProjectDir;
  const skinFile = path.join(projectDir, "lib", "widgets", "canvas", "character_skins.dart");

  if (!existsSync(skinFile)) {
    throw new Error(
      `character_skins.dart not found at ${skinFile}. ` +
        "Pass project_dir explicitly if PROJECT_DIR env is wrong.",
    );
  }

  const src = readFileSync(skinFile, "utf8");
  const agents = parseAgentsList(src);

  const provided = Object.keys(input.palettes);
  const missing = agents.filter((a) => !provided.includes(a));
  const extra = provided.filter((a) => !agents.includes(a));
  if (missing.length > 0 || extra.length > 0) {
    const parts: string[] = [];
    if (missing.length > 0) parts.push(`missing: ${missing.join(", ")}`);
    if (extra.length > 0) parts.push(`unknown agents: ${extra.join(", ")}`);
    throw new Error(
      `Palette set incomplete or malformed. Required ${agents.length} agents (${agents.join(", ")}). ${parts.join("; ")}.`,
    );
  }

  const validated: Record<string, SkinPalette> = {};
  for (const a of agents) {
    validated[a] = validateSkinPalette(input.palettes[a], a);
  }

  const skin: CharacterSkin = {
    id: input.skin_id,
    name: input.name_uk,
    nameEn: input.name_en,
    palettes: validated,
  };

  const result = insertSkinDeclaration(skinFile, skin);

  return {
    status: result.status,
    skin_id: skin.id,
    variable_name: varNameFromId(skin.id),
    file_path: skinFile,
    inserted_at_line: result.insertedAtLine,
    registered_in_list: result.registeredInList,
    agents_count: agents.length,
    warnings: result.warnings,
  };
}

function varNameFromId(id: string): string {
  const camel = id.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
  return "skin" + camel.charAt(0).toUpperCase() + camel.slice(1);
}
