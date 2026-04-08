#!/usr/bin/env node
/**
 * PixelCode Game Assets MCP Server
 *
 * Provides tools for working with the pixel-art office game:
 * - Sprite system specs & format
 * - Color palettes for agents & furniture
 * - Office tile map & desk layout
 * - Asset listing & inspection
 * - Animation specs & state machine
 * - Sprite template generation & validation
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as fs from "fs";
import * as path from "path";
import { z } from "zod";

const ASSETS_DIR = process.env.ASSETS_DIR || path.resolve(process.cwd(), "assets");
const PROJECT_DIR = process.env.PROJECT_DIR || process.cwd();

// ─── Server setup ─────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "pixelcode-game-assets",
  version: "1.0.0",
});

// ─── Tool: get_sprite_system_spec ─────────────────────────────────────────────

server.tool(
  "get_sprite_system_spec",
  "Get the complete specification of PixelCode's pixel-art sprite system — formats, dimensions, palette keys, rendering rules. Essential context before creating or modifying any sprites.",
  {},
  async () => ({
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(
          {
            overview:
              "PixelCode uses two sprite systems: PNG sprite sheets (primary) and text-based sprites (fallback). Both are rendered on a 320×224 virtual canvas.",

            png_sprites: {
              characters: {
                sheet_size: "112×96 pixels",
                frame_size: "16×32 pixels (kSpriteW × kSpriteH)",
                layout: "7 columns × 3 rows",
                columns:
                  "walk1(0), walk2(1), walk3(2), type1(3), type2(4), read1(5), read2(6)",
                rows: "DOWN(0), UP(1), RIGHT(2) — LEFT mirrors RIGHT horizontally",
                total_sheets: 6,
                files: "char_0.png through char_5.png",
                palette_mapping: {
                  manager: 0,
                  "tech-lead": 1,
                  coder: 2,
                  reviewer: 3,
                  tester: 4,
                  security: 5,
                  "ui-ux-designer": "0 (wraps)",
                },
              },
              furniture: {
                DESK_FRONT: { size: "48×32", desc: "Desk surface, 3-tile wide" },
                PC_FRONT_OFF: { size: "16×32", desc: "Monitor powered off" },
                PC_FRONT_ON_1: {
                  size: "16×32",
                  desc: "Monitor on, frame 1 of 3",
                },
                PC_FRONT_ON_2: {
                  size: "16×32",
                  desc: "Monitor on, frame 2 of 3",
                },
                PC_FRONT_ON_3: {
                  size: "16×32",
                  desc: "Monitor on, frame 3 of 3",
                },
                CUSHIONED_CHAIR_BACK: { size: "16×16", desc: "Chair sprite" },
                PLANT: { size: "16×32", desc: "Decorative plant, 2 tiles tall" },
              },
            },

            text_sprites: {
              format:
                "Array of strings, each string is one row. Characters are palette keys.",
              character_grid: "8 columns wide, 10-12 rows tall",
              palette_keys: {
                ".": "transparent",
                h: "hair",
                s: "skin",
                f: "skin light (face highlight)",
                e: "eye",
                c: "clothes",
                p: "pants",
                b: "boots",
              },
              furniture_keys: {
                ".": "transparent",
                d: "desk wood",
                k: "desk edge / keyboard",
                m: "monitor frame",
                g: "monitor glow (dim)",
                G: "monitor glow (bright)",
              },
              furniture_sizes: {
                desk: "12×6",
                monitor: "8×6",
              },
            },

            rendering: {
              canvas: "320×224 virtual pixels (20×14 tiles of 16px)",
              z_sorting:
                "Entities sorted by Y position (foot Y). Furniture at (tile_row+1)×16. Characters at ch.y + 8.5.",
              scale:
                "Canvas is scaled to fit window maintaining aspect ratio",
              filter: "FilterQuality.none (pixel-perfect, no interpolation)",
              mirroring:
                "LEFT direction = RIGHT sprite drawn with canvas scale(-1, 1)",
            },

            file_locations: {
              png_characters: "assets/characters/char_N.png",
              png_furniture: "assets/furniture/NAME.png",
              text_sprites: "lib/widgets/canvas/pixel_sprites.dart",
              sprite_loader: "lib/widgets/canvas/character_sprites.dart",
              game_state: "lib/widgets/canvas/office_game_state.dart",
              painter: "lib/widgets/canvas/pixel_office_painter.dart",
            },
          },
          null,
          2
        ),
      },
    ],
  })
);

// ─── Tool: list_game_assets ───────────────────────────────────────────────────

server.tool(
  "list_game_assets",
  "List all game asset files (PNGs) with sizes and dimensions. Use to see what sprites and images are currently available.",
  {},
  async () => {
    const assets: Array<{
      path: string;
      category: string;
      filename: string;
      size_bytes: number;
    }> = [];

    const scanDir = (dir: string, category: string) => {
      if (!fs.existsSync(dir)) return;
      for (const file of fs.readdirSync(dir)) {
        const fullPath = path.join(dir, file);
        const stat = fs.statSync(fullPath);
        if (stat.isFile() && file.endsWith(".png")) {
          assets.push({
            path: path.relative(PROJECT_DIR, fullPath),
            category,
            filename: file,
            size_bytes: stat.size,
          });
        }
      }
    };

    scanDir(path.join(ASSETS_DIR, "characters"), "character_sprite_sheet");
    scanDir(path.join(ASSETS_DIR, "furniture"), "furniture_sprite");
    scanDir(ASSETS_DIR, "other");

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              total_assets: assets.length,
              assets_dir: path.relative(PROJECT_DIR, ASSETS_DIR),
              assets,
              notes: [
                "Character sheets are 112×96 (7 frames × 3 directions, each frame 16×32)",
                "Furniture PNGs use transparent backgrounds",
                "All assets declared in pubspec.yaml under flutter.assets",
                "New assets must be added to pubspec.yaml to be bundled",
              ],
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ─── Tool: get_color_palettes ─────────────────────────────────────────────────

server.tool(
  "get_color_palettes",
  "Get all agent color palettes (hair, skin, eyes, clothes, etc.) and furniture colors. Essential for creating visually consistent new sprites or UI elements.",
  {},
  async () => ({
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(
          {
            agent_palettes: {
              "tech-lead": {
                hair: "#1A1A2E",
                skin: "#E8B89D",
                skin_light: "#F5CDB8",
                eye: "#00C0D1",
                clothes: "#00949F",
                pants: "#2C3E50",
                boots: "#1A1A1A",
                accent: "#00C0D1",
              },
              manager: {
                hair: "#8B4513",
                skin: "#D4A574",
                skin_light: "#E8C49A",
                eye: "#F59E0B",
                clothes: "#D97706",
                pants: "#44403C",
                boots: "#292524",
                accent: "#F59E0B",
              },
              coder: {
                hair: "#2D1B69",
                skin: "#C68642",
                skin_light: "#D4956B",
                eye: "#10B981",
                clothes: "#059669",
                pants: "#1E293B",
                boots: "#0F172A",
                accent: "#10B981",
              },
              reviewer: {
                hair: "#4A1A6B",
                skin: "#E8B89D",
                skin_light: "#F5CDB8",
                eye: "#8B5CF6",
                clothes: "#7C3AED",
                pants: "#334155",
                boots: "#1E293B",
                accent: "#8B5CF6",
              },
              tester: {
                hair: "#B91C1C",
                skin: "#FDBCB4",
                skin_light: "#FFD5CC",
                eye: "#EC4899",
                clothes: "#DB2777",
                pants: "#374151",
                boots: "#1F2937",
                accent: "#EC4899",
              },
              security: {
                hair: "#1F2937",
                skin: "#8D5524",
                skin_light: "#A0714B",
                eye: "#EF4444",
                clothes: "#DC2626",
                pants: "#27272A",
                boots: "#18181B",
                accent: "#EF4444",
              },
              "ui-ux-designer": {
                hair: "#FF6B9D",
                skin: "#F3D2C1",
                skin_light: "#FBE8DC",
                eye: "#3B82F6",
                clothes: "#2563EB",
                pants: "#3F3F46",
                boots: "#27272A",
                accent: "#3B82F6",
              },
            },

            furniture_colors: {
              desk_wood: "#5C4033",
              desk_edge: "#3E2B22",
              monitor_frame: "#2A2A35",
              monitor_glow_bright: "#00C0D1",
              monitor_glow_dim: "#007A84",
            },

            environment_colors: {
              wall_base: "#1A1A2E",
              wall_top: "#252540",
              wall_inner: "#16162A",
              floor_dark: "#131320",
              floor_light: "#171728",
              floor_grid: "#1C1C30",
              vignette: "radial gradient from transparent to black 0.4 alpha",
            },

            palette_key_mapping: {
              h: "hair",
              s: "skin",
              f: "skin_light",
              e: "eye",
              c: "clothes",
              p: "pants",
              b: "boots",
              d: "desk_wood",
              k: "desk_edge",
              m: "monitor_frame",
              g: "monitor_glow_dim",
              G: "monitor_glow_bright",
              ".": "transparent",
            },
          },
          null,
          2
        ),
      },
    ],
  })
);

// ─── Tool: get_office_layout ──────────────────────────────────────────────────

server.tool(
  "get_office_layout",
  "Get the full office tile map, desk station positions, blocked tiles, walkable areas, and plant positions. Use when modifying office layout or adding new furniture.",
  {},
  async () => {
    // Build the tile map visualization
    const cols = 20;
    const rows = 14;
    const map: string[][] = [];

    for (let r = 0; r < rows; r++) {
      const row: string[] = [];
      for (let c = 0; c < cols; c++) {
        if (r === 0 || r === rows - 1 || c === 0 || c === cols - 1) {
          row.push("W"); // wall
        } else {
          row.push("."); // floor
        }
      }
      map.push(row);
    }

    // Mark stations
    const stations = [
      {
        id: "manager",
        deskCol: 9,
        deskRow: 3,
        seatCol: 9,
        seatRow: 4,
        facing: "up",
      },
      {
        id: "tech-lead",
        deskCol: 3,
        deskRow: 6,
        seatCol: 3,
        seatRow: 7,
        facing: "up",
      },
      {
        id: "coder",
        deskCol: 9,
        deskRow: 6,
        seatCol: 9,
        seatRow: 7,
        facing: "up",
      },
      {
        id: "reviewer",
        deskCol: 15,
        deskRow: 6,
        seatCol: 15,
        seatRow: 7,
        facing: "up",
      },
      {
        id: "tester",
        deskCol: 3,
        deskRow: 9,
        seatCol: 3,
        seatRow: 10,
        facing: "up",
      },
      {
        id: "security",
        deskCol: 9,
        deskRow: 9,
        seatCol: 9,
        seatRow: 10,
        facing: "up",
      },
      {
        id: "ui-ux-designer",
        deskCol: 15,
        deskRow: 9,
        seatCol: 15,
        seatRow: 10,
        facing: "up",
      },
    ];

    for (const s of stations) {
      map[s.deskRow][s.deskCol] = "D"; // desk
      map[s.seatRow][s.seatCol] = "S"; // seat
    }

    // Mark plants
    for (const [c, r] of [
      [2, 1],
      [17, 1],
      [2, 11],
      [17, 11],
    ]) {
      map[r][c] = "P";
    }

    const mapStr = map.map((row) => row.join("")).join("\n");

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              grid: { cols: 20, rows: 14, tile_size: 16 },
              canvas: { width: 320, height: 224 },
              tile_map_visual: mapStr,
              legend: {
                W: "wall",
                ".": "walkable floor",
                D: "desk (blocked)",
                S: "seat (blocked, character sits here)",
                P: "plant (decorative)",
              },

              desk_stations: stations,

              plant_positions: [
                { col: 2, row: 1, label: "top-left corner" },
                { col: 17, row: 1, label: "top-right corner" },
                { col: 2, row: 11, label: "bottom-left corner" },
                { col: 17, row: 11, label: "bottom-right corner" },
              ],

              walkable_area:
                "All floor tiles except walls (border), desk tiles, and seat tiles. Characters pathfind via BFS on this grid.",

              coordinate_system: {
                origin: "top-left (0,0)",
                pixel_x: "col * 16 + 8 (tile center)",
                pixel_y: "row * 16 + 8 (tile center)",
                z_sorting:
                  "higher Y = drawn later (in front). Furniture at (row+1)*16, characters at y + 8.5",
              },
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ─── Tool: get_animation_specs ────────────────────────────────────────────────

server.tool(
  "get_animation_specs",
  "Get animation timing, frame sequences, character state machine, and wander AI parameters. Use when adding new animations or modifying character behavior.",
  {},
  async () => ({
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(
          {
            character_states: {
              idle: {
                description:
                  "Standing still, uses walk frame 1 (standing pose)",
                frame_count: 1,
                transitions_to: ["walk (on wander timer or activated)"],
              },
              walk: {
                description:
                  "Moving along BFS path, 4-frame walk cycle",
                frame_count: 4,
                frame_sequence: "walk1 → walk2 → walk3 → walk2 (ping-pong)",
                frame_duration_sec: 0.15,
                speed: "48 px/sec (3 tiles/sec)",
                transitions_to: [
                  "idle (path complete, not at seat)",
                  "typing (path complete, at own seat)",
                ],
              },
              typing: {
                description:
                  "Seated at desk, 2-frame typing animation. Also used for reading.",
                frame_count: 2,
                frame_duration_sec: 0.3,
                transitions_to: [
                  "idle (after seat rest timer expires, if not active)",
                ],
              },
            },

            directions: {
              down: "front-facing (3 walk frames + 2 type + 1 read)",
              up: "back-facing (3 walk frames + 2 type + 1 read)",
              right: "side-facing (3 walk frames only)",
              left: "mirrored right (canvas.scale(-1, 1))",
            },

            png_frame_mapping: {
              columns: {
                0: "walk1",
                1: "walk2 (standing/idle)",
                2: "walk3",
                3: "type1",
                4: "type2",
                5: "read1",
                6: "read2",
              },
              rows: { 0: "DOWN", 1: "UP", 2: "RIGHT" },
              frame_rect:
                "Rect(col * 16, row * 32, 16, 32) — source rect from sprite sheet",
            },

            wander_ai: {
              pause_before_move: "3–15 seconds (random)",
              moves_per_cycle: "3–6 (random)",
              seat_rest_duration: "30–90 seconds (random)",
              behavior:
                "Idle → wander to random tiles → return to seat → type for rest duration → repeat",
            },

            monitor_animation: {
              frames: 3,
              cycle: "PC_FRONT_ON_1 → _2 → _3 (based on tick % 3)",
              tick_rate: "~3.3 Hz (0.3s per tick, driven by game loop timer)",
            },

            bubble_animation: {
              thinking:
                "3 dots, one highlighted per tick (cycling amber glow)",
              other_states: "solid colored circle",
              position: "above character head, offset by sitting state",
            },

            display_statuses: [
              "idle",
              "thinking",
              "typing",
              "reading",
              "reviewing",
              "testing",
              "planning",
              "discussing",
            ],
          },
          null,
          2
        ),
      },
    ],
  })
);

// ─── Tool: generate_text_sprite_template ──────────────────────────────────────

server.tool(
  "generate_text_sprite_template",
  "Generate a blank or example text-sprite template. Specify the type (character_walk, character_type, character_read, furniture, item) and dimensions. Returns a ready-to-use Dart const definition.",
  {
    sprite_type: z
      .enum([
        "character_walk",
        "character_type",
        "character_read",
        "furniture",
        "item",
      ])
      .describe("Type of sprite to generate a template for"),
    width: z
      .number()
      .optional()
      .describe("Grid width in pixels (default: 8 for character, 12 for furniture)"),
    height: z
      .number()
      .optional()
      .describe("Grid height in pixels (default: 12 for walk, 10 for type/read)"),
    name: z
      .string()
      .optional()
      .describe("Variable name for the const (e.g., 'coffeeMachine')"),
  },
  async ({ sprite_type, width, height, name }) => {
    const varName = name || "mySprite";

    let w: number;
    let h: number;
    let keys: string;
    let example: string[];

    switch (sprite_type) {
      case "character_walk":
        w = width || 8;
        h = height || 12;
        keys = "Palette keys: . h s f e c p b";
        example = [
          "...hh...",
          "..hhhh..",
          "..sffs..",
          "..sees..",
          "...ss...",
          "..cccc..",
          ".cccccc.",
          "..cccc..",
          "...pp...",
          "..p..p..",
          "..p..p..",
          "..b..b..",
        ];
        break;
      case "character_type":
        w = width || 8;
        h = height || 10;
        keys = "Palette keys: . h s f e c p b";
        example = [
          "...hh...",
          "..hhhh..",
          "..sffs..",
          "..sees..",
          "...ss...",
          "..cccc..",
          ".cccccc.",
          ".cc..cc.",
          "..cccc..",
          "...cc...",
        ];
        break;
      case "character_read":
        w = width || 8;
        h = height || 10;
        keys = "Palette keys: . h s f e c p b";
        example = [
          "...hh...",
          "..hhhh..",
          "..hhhh..",
          "..sffs..",
          "..sees..",
          "...ss...",
          "..cccc..",
          ".cccccc.",
          "..cccc..",
          "...cc...",
        ];
        break;
      case "furniture":
        w = width || 12;
        h = height || 6;
        keys = "Palette keys: . d k m g G (or define custom keys)";
        example = Array.from({ length: h }, () => ".".repeat(w));
        break;
      case "item":
        w = width || 8;
        h = height || 8;
        keys = "Define custom palette keys for your item";
        example = Array.from({ length: h }, () => ".".repeat(w));
        break;
    }

    const dartCode = `/// ${sprite_type} sprite (${w}×${h}).
/// ${keys}
const ${varName} = [
${example.map((row) => `  '${row}',`).join("\n")}
];`;

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              template: dartCode,
              sprite_type,
              dimensions: { width: w, height: h },
              palette_keys: keys,
              guidelines: [
                `All rows must be exactly ${w} characters wide`,
                "Use '.' for transparent pixels",
                "Character sprites: h=hair, s=skin, f=skin_light, e=eye, c=clothes, p=pants, b=boots",
                "Furniture sprites: d=desk_wood, k=desk_edge, m=monitor_frame, g/G=glow",
                "For custom items, define a new color resolver function",
                "Add the const to pixel_sprites.dart or a new sprites file",
                "Walk sprites need 3 frames (walk0, walk1/standing, walk2) per direction",
                "Type sprites need 2 frames per direction",
                "Read sprites need 1 frame per direction",
              ],
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ─── Tool: validate_text_sprite ───────────────────────────────────────────────

server.tool(
  "validate_text_sprite",
  "Validate a text-based sprite definition. Checks row widths, palette keys, and symmetry. Paste the sprite rows as a JSON array of strings.",
  {
    rows: z
      .array(z.string())
      .describe('Sprite rows as array of strings, e.g. ["...hh...", "..hhhh.."]'),
    allowed_keys: z
      .string()
      .optional()
      .describe(
        'Allowed palette characters (default: ".hsfecpb" for characters)'
      ),
  },
  async ({ rows, allowed_keys }) => {
    const keys = new Set((allowed_keys || ".hsfecpb").split(""));
    const errors: string[] = [];
    const warnings: string[] = [];

    if (rows.length === 0) {
      errors.push("Sprite has no rows");
      return {
        content: [{ type: "text" as const, text: JSON.stringify({ valid: false, errors }) }],
      };
    }

    const expectedWidth = rows[0].length;

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      if (row.length !== expectedWidth) {
        errors.push(
          `Row ${i}: width ${row.length} != expected ${expectedWidth}`
        );
      }
      for (let j = 0; j < row.length; j++) {
        if (!keys.has(row[j])) {
          errors.push(
            `Row ${i}, col ${j}: unknown key '${row[j]}' (allowed: ${[...keys].join("")})`
          );
        }
      }
    }

    // Check symmetry (common for characters)
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const reversed = row.split("").reverse().join("");
      if (row !== reversed) {
        // Not symmetric — just a warning, not an error
        const nonDotLeft = row.search(/[^.]/);
        const nonDotRight = row.length - 1 - [...row].reverse().findIndex((c) => c !== ".");
        if (nonDotLeft >= 0) {
          const leftPad = nonDotLeft;
          const rightPad = row.length - 1 - nonDotRight;
          if (Math.abs(leftPad - rightPad) > 1) {
            warnings.push(
              `Row ${i}: asymmetric padding (left: ${leftPad}, right: ${rightPad})`
            );
          }
        }
      }
    }

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              valid: errors.length === 0,
              dimensions: {
                width: expectedWidth,
                height: rows.length,
              },
              errors,
              warnings,
              unique_keys_used: [
                ...new Set(rows.join("").split("").filter((c) => c !== ".")),
              ],
              visual_preview: rows.join("\n"),
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ─── Tool: get_rendering_pipeline ─────────────────────────────────────────────

server.tool(
  "get_rendering_pipeline",
  "Get the rendering order, Z-sorting rules, and draw pipeline of the office scene. Use when adding new visual elements to ensure correct layering.",
  {},
  async () => ({
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(
          {
            pipeline_order: [
              "1. Floor tiles (checkerboard pattern: #131320 / #171728)",
              "2. Wall tiles (#1A1A2E with top/bottom highlights)",
              "3. Floor grid lines (0.3px stroke, #1C1C30)",
              "4. Z-sorted scene entities (sorted by zY ascending):",
              "   - Desk surfaces (zY = (deskRow+1) * 16)",
              "   - Monitor glow rectangles (zY = deskZY + 0.3)",
              "   - PC/Monitor sprites (zY = deskZY + 0.5)",
              "   - Chairs (zY = (seatRow+1) * 16 - 0.5)",
              "   - Plants (zY = (plantRow+1) * 16)",
              "   - Character active glow (zY = charZY - 0.003)",
              "   - Character selection glow (zY = charZY - 0.002)",
              "   - Character outline (zY = charZY - 0.001)",
              "   - Character sprite (zY = ch.y + 8.5)",
              "5. Speech bubbles (drawn on top, not Z-sorted)",
              "6. Vignette overlay (radial gradient, transparent → black 0.4)",
            ],

            z_sort_rules: {
              formula:
                "Entities at lower Y are drawn first (behind). Higher Y = in front.",
              character_zY: "ch.y + kTileSize/2 + 0.5 = ch.y + 8.5",
              furniture_zY: "(tileRow + 1) * kTileSize",
              sub_sorting:
                "Fractional offsets separate layers at same Y: desk(+0), glow(+0.3), monitor(+0.5)",
            },

            canvas_setup: {
              transform:
                "translate(offsetX, offsetY) then scale(min(w/320, h/224))",
              coordinate_space:
                "All drawing happens in 320×224 virtual space after transform",
              image_paint:
                "Paint with FilterQuality.none for pixel-perfect rendering",
            },

            adding_new_elements: {
              step_1:
                "Create a _Drawable(zY, drawFunction) for each visual element",
              step_2:
                "Add to the drawables list in _drawScene() or appropriate method",
              step_3:
                "Choose zY based on desired depth: furniture row, character position, or fixed layer",
              step_4:
                "For sprites, use drawImageRect with _pixelPaint for crisp pixels",
              example_furniture:
                "drawables.add(_Drawable((row+1)*16, (c) => c.drawImageRect(...)))",
              example_effect:
                "drawables.add(_Drawable(charZY - 0.005, (c) => c.drawCircle(...)))",
            },
          },
          null,
          2
        ),
      },
    ],
  })
);

// ─── Tool: get_pubspec_assets ─────────────────────────────────────────────────

server.tool(
  "get_pubspec_assets",
  "Get the current asset declarations from pubspec.yaml. New assets must be registered here to be bundled with the Flutter app.",
  {},
  async () => {
    const pubspecPath = path.join(PROJECT_DIR, "pubspec.yaml");
    let pubspecContent = "";
    try {
      pubspecContent = fs.readFileSync(pubspecPath, "utf-8");
    } catch {
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify({ error: "pubspec.yaml not found" }),
          },
        ],
      };
    }

    // Extract asset section
    const assetsMatch = pubspecContent.match(
      /assets:\s*\n((?:\s+-\s+[^\n]+\n?)*)/
    );
    const assets = assetsMatch
      ? assetsMatch[1]
          .split("\n")
          .map((l) => l.trim().replace(/^-\s*/, ""))
          .filter(Boolean)
      : [];

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(
            {
              pubspec_path: "pubspec.yaml",
              declared_assets: assets,
              how_to_add:
                'Add new entries under flutter.assets in pubspec.yaml, e.g. "- assets/new_folder/"',
              hot_reload_note:
                "After adding new assets, restart the app (hot reload won't pick up new asset declarations)",
            },
            null,
            2
          ),
        },
      ],
    };
  }
);

// ─── Tool: suggest_new_sprite_type ────────────────────────────────────────────

server.tool(
  "suggest_new_sprite_type",
  "Get guidance on how to add a completely new type of visual element (new furniture, decoration, effect, UI widget) to the office scene. Describes file changes needed and integration points.",
  {
    element_type: z
      .enum(["furniture", "decoration", "effect", "npc", "ui_overlay"])
      .describe("What kind of visual element to add"),
    description: z
      .string()
      .describe("Brief description of what you want to add, e.g. 'coffee machine' or 'rain effect'"),
  },
  async ({ element_type, description }) => {
    const guides: Record<string, object> = {
      furniture: {
        overview: `Adding new furniture: "${description}"`,
        steps: [
          "1. Create a PNG sprite (16×32 or appropriate size) with transparent background",
          "2. Save to assets/furniture/YOUR_NAME.png",
          "3. Add 'assets/furniture/' to pubspec.yaml if not already there",
          "4. Register in SpriteManager (character_sprites.dart) — add to _furnitureNames list and load in _loadFurniture()",
          "5. Place in the office by adding draw code to _addStationFurniture() or a new method in pixel_office_painter.dart",
          "6. Choose a tile position and calculate zY for correct depth sorting",
          "7. Optionally add to blockedTiles in office_game_state.dart if characters shouldn't walk through it",
        ],
        files_to_modify: [
          "assets/furniture/NEW.png (create)",
          "pubspec.yaml (add asset path if needed)",
          "lib/widgets/canvas/character_sprites.dart (load image)",
          "lib/widgets/canvas/pixel_office_painter.dart (draw it)",
          "lib/widgets/canvas/office_game_state.dart (block tile if solid)",
        ],
      },
      decoration: {
        overview: `Adding decoration: "${description}"`,
        steps: [
          "1. Create PNG sprite or define text-sprite in pixel_sprites.dart",
          "2. Save PNG to assets/furniture/ (decorations share the furniture folder)",
          "3. Add to SpriteManager and painter like furniture",
          "4. Place at desired tile coordinates",
          "5. Decorations typically don't block movement — skip blockedTiles",
        ],
        files_to_modify: [
          "assets/furniture/NEW.png (create)",
          "lib/widgets/canvas/character_sprites.dart (load)",
          "lib/widgets/canvas/pixel_office_painter.dart (draw)",
        ],
      },
      effect: {
        overview: `Adding visual effect: "${description}"`,
        steps: [
          "1. Effects are drawn as _Drawable items with appropriate zY",
          "2. Use Canvas API directly (drawCircle, drawRect, drawPath with shaders)",
          "3. Animate via the tick counter or game loop dt",
          "4. Add as _Drawable in _drawScene() or as overlay in paint() after _drawScene()",
          "5. For particle effects, manage state in OfficeGameState and render in painter",
        ],
        files_to_modify: [
          "lib/widgets/canvas/pixel_office_painter.dart (render)",
          "lib/widgets/canvas/office_game_state.dart (state/animation logic, if stateful)",
        ],
        tips: [
          "Use Paint.maskFilter for blur/glow effects",
          "Use Paint.shader for gradients",
          "Keep effects lightweight — painter runs every frame",
          "Use tick % N for simple frame-based animation",
        ],
      },
      npc: {
        overview: `Adding NPC character: "${description}"`,
        steps: [
          "1. Create a new 112×96 character sprite sheet (7 frames × 3 directions, each 16×32)",
          "2. Save to assets/characters/char_N.png",
          "3. Update SpriteManager to load the new sheet",
          "4. Add to agentPaletteIndex in office_game_state.dart",
          "5. Create AgentPalette entry in pixel_sprites.dart",
          "6. Add a DeskStation or free-roaming logic in OfficeGameState",
          "7. NPCs without desks can wander permanently (skip seat return in wander AI)",
        ],
        files_to_modify: [
          "assets/characters/char_N.png (create sprite sheet)",
          "lib/widgets/canvas/character_sprites.dart (load sheet)",
          "lib/widgets/canvas/pixel_sprites.dart (palette)",
          "lib/widgets/canvas/office_game_state.dart (station + AI)",
          "lib/widgets/canvas/pixel_office_painter.dart (if special rendering needed)",
        ],
      },
      ui_overlay: {
        overview: `Adding UI overlay: "${description}"`,
        steps: [
          "1. UI overlays are drawn after the Z-sorted scene, before vignette",
          "2. Add drawing code in paint() between _drawScene() and _drawVignette()",
          "3. For interactive overlays, use Flutter widgets in agent_canvas.dart instead",
          "4. Mix Canvas drawing (for pixel-art style) with Flutter widgets (for text/buttons)",
        ],
        files_to_modify: [
          "lib/widgets/canvas/pixel_office_painter.dart (canvas overlay)",
          "lib/widgets/canvas/agent_canvas.dart (widget overlay)",
        ],
      },
    };

    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(guides[element_type], null, 2),
        },
      ],
    };
  }
);

// ─── Start server ─────────────────────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("MCP server error:", err);
  process.exit(1);
});
