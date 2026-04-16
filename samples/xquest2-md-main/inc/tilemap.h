/*
 * tilemap.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Background tile map renderer
 *
 * Tile system overview
 * --------------------
 * The original game uses 16×16 pixel tiles. Genesis VDP works in 8×8 tile
 * units, so each logical 16×16 tile maps to a 2×2 block of VDP tiles.
 *
 * VRAM layout (plane B, tileset loaded at TILE_USERINDEX = 16)
 * ─────────────────────────────────────────────────────────────
 * Index 0–15       : SGDK system tiles (reserved) / transparent (never written explicitly)
 * Indices  16– 47  : WALL tiles        (8 variants × 4 subtiles)
 * Indices  48– 63  : WALL_EDGE tiles   (4 variants × 4 subtiles)
 * Indices  64–135  : FLOOR tiles       (18 variants × 4 subtiles)
 * Indices 136–151  : FLOOR_CYAN tiles  (4 variants × 4 subtiles)
 *
 * Logical tile types stored in GameData.tilemap[][]
 * ──────────────────────────────────────────────────
 * TILE_EMPTY     (0) : open floor (no collision)
 * TILE_WALL      (1) : solid wall (collision)
 * TILE_WALL_EDGE (2) : wall-to-floor transition (collision)
 * TILE_FLOOR_ALT (3) : alternate floor colour (no collision)
 *
 * VDP plane geometry
 * ──────────────────
 * Logical map  : MAP_TILES_W(20) × MAP_TILES_H(13) in 16×16 units
 * VDP plane B  : 40 × 26 in 8×8 units (fits in a 64×32 plane)
 * HUD strip    : plane A, row 0 (y=0..15), drawn over background
 */

#ifndef TILEMAP_H
#define TILEMAP_H

#include <genesis.h>
#include "xquest.h"

/* ────────────────────────────────────────────────
 * Logical tile type values (stored in tilemap[][])
 * ──────────────────────────────────────────────── */
#define TILE_EMPTY       0   /* passable floor */
#define TILE_WALL        1   /* solid, impassable */
#define TILE_WALL_EDGE   2   /* collision, visual transition */
#define TILE_FLOOR_ALT   3   /* passable alternate colour */

/* ────────────────────────────────────────────────
 * VRAM tile index bases  (1-based; 0 = transparent)
 * Each logical 16×16 tile occupies 4 consecutive
 * VRAM 8×8 indices:  TL, TR, BL, BR
 * ──────────────────────────────────────────────── */
#define BG_TILESET_VRAM_INDEX   TILE_USERINDEX        /* start of our tiles in VRAM     */
#define VRAM_WALL_BASE          (TILE_USERINDEX + 0)        /* wall variants 0-7  → 1..32     */
#define VRAM_WALL_EDGE_BASE     (TILE_USERINDEX + 32)        /* edge variants 0-3  → 33..48    */
#define VRAM_FLOOR_BASE         (TILE_USERINDEX + 48)        /* floor variants 0-17 → 49..120  */
#define VRAM_FLOOR_CYAN_BASE    (TILE_USERINDEX + 120)        /* cyan variants 0-3  → 121..136  */

/* Number of variants per tile type */
#define WALL_VARIANTS        8
#define WALL_EDGE_VARIANTS   4
#define FLOOR_VARIANTS      18
#define FLOOR_CYAN_VARIANTS  4

/* ────────────────────────────────────────────────
 * Public API
 * ──────────────────────────────────────────────── */

/**
 * tilemap_init()
 * Load the unified background tileset into VRAM and set VDP plane size.
 * Call once during game initialisation, before tilemap_draw().
 */
void tilemap_init(void);

/**
 * tilemap_draw(gd)
 * Write the full tilemap to VDP plane B.
 * Clears the plane first, then sets each 2×2 block of 8×8 VRAM tiles.
 * Safe to call on level start and after level_generate().
 */
void tilemap_draw(const GameData *gd);

/**
 * tilemap_draw_cell(gd, tx, ty)
 * Redraw a single 16×16 map cell (for partial updates if needed).
 * tx, ty are in 16×16 tile units (0..MAP_TILES_W-1, 0..MAP_TILES_H-1).
 */
void tilemap_draw_cell(const GameData *gd, u8 tx, u8 ty);

/**
 * tilemap_is_solid(gd, tx, ty)
 * Returns TRUE if the tile at (tx, ty) blocks movement.
 * Used by player, enemies, and bullet code for wall collision.
 */
u8 tilemap_is_solid(const GameData *gd, u8 tx, u8 ty);

/**
 * tilemap_cell_at_pixel(px, py, out_tx, out_ty)
 * Convert a pixel position to tile coordinates.
 * Writes tile x,y into *out_tx, *out_ty.
 */
void tilemap_cell_at_pixel(s16 px, s16 py, u8 *out_tx, u8 *out_ty);

#endif /* TILEMAP_H */
