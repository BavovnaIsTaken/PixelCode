/**
 * Read/write character_skins.dart.
 *
 * The file is hand-written Dart, but its skin declarations follow a strict
 * pattern (`final skinX = CharacterSkin(...)` with `_buildPalettes(const [...])`).
 * We exploit that pattern instead of pulling in a Dart parser.
 *
 * Operations:
 *   - parseAgentsList: extract `const _agents = [...]` (canonical class list)
 *   - parseExistingSkins: extract every existing skin (id, name, nameEn, palettes)
 *   - insertSkinDeclaration: insert a new `final skinX = ...` block + register
 *     in `allCharacterSkins` list. Idempotent on identical content.
 */

import { readFileSync, writeFileSync } from "node:fs";

import { isValidHex, normalizeHex } from "./color.js";

export const SKIN_KEYS = ["hair", "skin", "skinLight", "eye", "clothes", "pants", "boots"] as const;
export type SkinKey = (typeof SKIN_KEYS)[number];

export type SkinPalette = Record<SkinKey, string>;

export interface CharacterSkin {
  id: string;
  name: string;
  nameEn: string;
  palettes: Record<string, SkinPalette>;
}

export function parseAgentsList(src: string): string[] {
  const m = /const\s+_agents\s*=\s*\[([\s\S]*?)\];/.exec(src);
  if (!m) throw new Error("character_skins.dart: cannot locate `const _agents = [...]`");
  const ids = [...m[1].matchAll(/'([^']+)'/g)].map((mm) => mm[1]);
  if (ids.length === 0) throw new Error("character_skins.dart: empty _agents list");
  return ids;
}

function extractBalanced(src: string, openIdx: number): { inner: string; endIdx: number } {
  if (src[openIdx] !== "(") {
    throw new Error(`extractBalanced: expected "(" at index ${openIdx}, got "${src[openIdx]}"`);
  }
  let depth = 1;
  let i = openIdx + 1;
  for (; i < src.length && depth > 0; i++) {
    const ch = src[i];
    if (ch === "(") depth++;
    else if (ch === ")") depth--;
  }
  if (depth !== 0) throw new Error("extractBalanced: unmatched paren");
  return { inner: src.slice(openIdx + 1, i - 1), endIdx: i };
}

function extractSkinPaletteBlocks(src: string): string[] {
  const blocks: string[] = [];
  const re = /\bSkinPalette\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    const openIdx = m.index + m[0].length - 1;
    const { inner, endIdx } = extractBalanced(src, openIdx);
    blocks.push(inner);
    re.lastIndex = endIdx;
  }
  return blocks;
}

export function parseExistingSkins(src: string, agents: string[]): CharacterSkin[] {
  const skins: CharacterSkin[] = [];
  const headerRe = /final\s+(skin[A-Z]\w*)\s*=\s*CharacterSkin\(/g;
  let m: RegExpExecArray | null;
  while ((m = headerRe.exec(src)) !== null) {
    const openIdx = m.index + m[0].length - 1;
    const { inner: body, endIdx } = extractBalanced(src, openIdx);
    headerRe.lastIndex = endIdx;

    const id = matchField(body, "id");
    const name = matchField(body, "name");
    const nameEn = matchField(body, "nameEn");
    if (!id || !name || !nameEn) {
      throw new Error(`Skin "${m[1]}" missing id/name/nameEn fields`);
    }

    const buildIdx = body.search(/_buildPalettes\s*\(/);
    if (buildIdx < 0) throw new Error(`Skin "${id}" has no _buildPalettes block`);
    const afterBuild = body.indexOf("(", buildIdx);
    const { inner: buildArgs } = extractBalanced(body, afterBuild);
    const listOpen = buildArgs.indexOf("[");
    const listClose = buildArgs.lastIndexOf("]");
    if (listOpen < 0 || listClose < 0) {
      throw new Error(`Skin "${id}" _buildPalettes argument is not a list literal`);
    }
    const listInner = buildArgs.slice(listOpen + 1, listClose);

    const paletteBlocks = extractSkinPaletteBlocks(listInner);
    if (paletteBlocks.length !== agents.length) {
      throw new Error(
        `Skin "${id}" has ${paletteBlocks.length} palettes but agents list has ${agents.length}`,
      );
    }

    const palettes: Record<string, SkinPalette> = {};
    for (let i = 0; i < agents.length; i++) {
      palettes[agents[i]] = parseSkinPaletteBlock(paletteBlocks[i]);
    }
    skins.push({ id, name, nameEn, palettes });
  }
  return skins;
}

function matchField(body: string, field: string): string | null {
  const re = new RegExp(`${field}:\\s*'([^']*)'`);
  const m = re.exec(body);
  return m ? m[1] : null;
}

function parseSkinPaletteBlock(block: string): SkinPalette {
  const out = {} as SkinPalette;
  for (const key of SKIN_KEYS) {
    const re = new RegExp(`${key}:\\s*Color\\(0xFF([0-9A-Fa-f]{6})\\)`);
    const m = re.exec(block);
    if (!m) throw new Error(`SkinPalette block missing key "${key}"`);
    out[key] = "#" + m[1].toUpperCase();
  }
  return out;
}

export function validateSkinPalette(p: unknown, agentId: string): SkinPalette {
  if (!p || typeof p !== "object") {
    throw new Error(`Palette for agent "${agentId}" must be an object`);
  }
  const out = {} as SkinPalette;
  for (const key of SKIN_KEYS) {
    const v = (p as Record<string, unknown>)[key];
    if (typeof v !== "string" || !isValidHex(v)) {
      throw new Error(
        `Palette for agent "${agentId}" key "${key}": expected #RRGGBB hex, got ${JSON.stringify(v)}`,
      );
    }
    out[key] = normalizeHex(v);
  }
  return out;
}

export interface SkinAdditionResult {
  status: "added" | "noop_identical";
  filePath: string;
  insertedAtLine: number;
  registeredInList: boolean;
  warnings: string[];
}

export function buildSkinDeclaration(
  varName: string,
  skin: CharacterSkin,
  agents: string[],
): string {
  const palettesSrc = agents
    .map((agentId) => {
      const p = skin.palettes[agentId];
      return [
        `    // ${agentId}`,
        `    SkinPalette(`,
        `      hair: Color(0xFF${stripHash(p.hair)}), skin: Color(0xFF${stripHash(p.skin)}),`,
        `      skinLight: Color(0xFF${stripHash(p.skinLight)}), eye: Color(0xFF${stripHash(p.eye)}),`,
        `      clothes: Color(0xFF${stripHash(p.clothes)}), pants: Color(0xFF${stripHash(p.pants)}),`,
        `      boots: Color(0xFF${stripHash(p.boots)}),`,
        `    ),`,
      ].join("\n");
    })
    .join("\n");

  return [
    ``,
    `// ─── ${skin.nameEn} ────────────────────────────────────────────────────────`,
    ``,
    `final ${varName} = CharacterSkin(`,
    `  id: '${skin.id}',`,
    `  name: '${escapeSingleQuote(skin.name)}',`,
    `  nameEn: '${escapeSingleQuote(skin.nameEn)}',`,
    `  palettes: _buildPalettes(const [`,
    palettesSrc,
    `  ]),`,
    `);`,
    ``,
  ].join("\n");
}

function stripHash(hex: string): string {
  return hex.startsWith("#") ? hex.slice(1).toUpperCase() : hex.toUpperCase();
}

function escapeSingleQuote(s: string): string {
  return s.replace(/'/g, "\\'");
}

export function insertSkinDeclaration(
  filePath: string,
  skin: CharacterSkin,
): SkinAdditionResult {
  const src = readFileSync(filePath, "utf8");
  const agents = parseAgentsList(src);
  const existing = parseExistingSkins(src, agents);

  for (const a of agents) {
    if (!skin.palettes[a]) {
      throw new Error(
        `Skin "${skin.id}": missing palette for agent "${a}". All ${agents.length} agents required: ${agents.join(", ")}`,
      );
    }
  }

  const dup = existing.find((s) => s.id === skin.id);
  if (dup) {
    if (skinsEqual(dup, skin)) {
      return {
        status: "noop_identical",
        filePath,
        insertedAtLine: -1,
        registeredInList: true,
        warnings: [],
      };
    }
    throw new Error(
      `Skin id "${skin.id}" already exists with different content. Choose a different id, ` +
        `or remove the existing entry manually before re-adding.`,
    );
  }

  const varName = skinIdToVarName(skin.id);
  const declaration = buildSkinDeclaration(varName, skin, agents);

  const allSkinsHeaderIdx = src.indexOf("// ─── All skins");
  if (allSkinsHeaderIdx < 0) {
    throw new Error('character_skins.dart: cannot locate "All skins" section header');
  }

  let cutoff = allSkinsHeaderIdx;
  while (cutoff > 0 && src[cutoff - 1] !== "\n") cutoff--;

  const before = src.slice(0, cutoff);
  const after = src.slice(cutoff);

  const listBlockRe = /(final\s+allCharacterSkins\s*=\s*<CharacterSkin>\[)([\s\S]*?)(\n\];)/;
  const listMatch = listBlockRe.exec(after);
  if (!listMatch) throw new Error("character_skins.dart: cannot locate allCharacterSkins list");

  const listEntries = listMatch[2];
  if (new RegExp(`\\b${varName}\\b`).test(listEntries)) {
    throw new Error(
      `allCharacterSkins already references "${varName}" but skin not found. File may be partially edited.`,
    );
  }
  const updatedList = listMatch[1] + listEntries + `\n  ${varName},` + listMatch[3];
  const updatedAfter = after.replace(listBlockRe, updatedList);

  const newSrc = before + declaration + updatedAfter;
  writeFileSync(filePath, newSrc, "utf8");

  const insertedAtLine = before.split("\n").length;
  return {
    status: "added",
    filePath,
    insertedAtLine,
    registeredInList: true,
    warnings: [],
  };
}

function skinsEqual(a: CharacterSkin, b: CharacterSkin): boolean {
  if (a.id !== b.id || a.name !== b.name || a.nameEn !== b.nameEn) return false;
  const aKeys = Object.keys(a.palettes).sort();
  const bKeys = Object.keys(b.palettes).sort();
  if (aKeys.length !== bKeys.length) return false;
  for (let i = 0; i < aKeys.length; i++) {
    if (aKeys[i] !== bKeys[i]) return false;
    const ap = a.palettes[aKeys[i]];
    const bp = b.palettes[bKeys[i]];
    for (const k of SKIN_KEYS) {
      if (normalizeHex(ap[k]) !== normalizeHex(bp[k])) return false;
    }
  }
  return true;
}

export function skinIdToVarName(id: string): string {
  if (!/^[a-z][a-z0-9_]*$/.test(id)) {
    throw new Error(
      `Invalid skin id "${id}". Use snake_case starting with a letter, e.g. "demon_slayer".`,
    );
  }
  const camel = id.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
  return "skin" + camel.charAt(0).toUpperCase() + camel.slice(1);
}
