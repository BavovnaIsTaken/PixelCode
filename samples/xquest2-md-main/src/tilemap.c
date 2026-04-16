/*
 * tilemap.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Background tile map renderer
 *
 * Design
 * ──────
 * Each 16×16 logical tile is drawn as a 2×2 block of 8×8 VDP tiles on
 * plane B. We select tile variants deterministically from the map
 * coordinates so the same cell always gets the same visual without
 * storing a full variant array.
 *
 * Subtile addressing inside a 16×16 tile
 * ───────────────────────────────────────
 *   VRAM base N for a given logical tile:
 *     [N+0][N+1]      ← top-left, top-right
 *     [N+2][N+3]      ← bottom-left, bottom-right
 *
 *   Written to plane B at VDP coordinates (vx, vy):
 *     (vx,   vy  ) = N+0    (vx+1, vy  ) = N+1
 *     (vx,   vy+1) = N+2    (vx+1, vy+1) = N+3
 *
 * HUD offset
 * ──────────
 * The HUD occupies the top 16px (2 VDP rows). The playfield therefore
 * starts at VDP row 2. A logical tile at row 0 maps to VDP row 2.
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "resources.h"

/* ────────────────────────────────────────────────
 * Constants
 * ──────────────────────────────────────────────── */

/* VDP plane B row offset: HUD uses top 2 VDP rows (16px) */
#define VDP_ROW_OFFSET   2

/* Simple hash to pick a tile variant deterministically from position */
#define TILE_HASH(tx, ty)   (((u8)(tx) * 7u + (u8)(ty) * 13u) & 0xFFu)

/* ────────────────────────────────────────────────
 * Internal helpers
 * ──────────────────────────────────────────────── */

/**
 * vram_base_for_tile()
 *
 * Given a logical tile type and map coordinates, return the VRAM index of
 * the top-left 8×8 subtile for that 16×16 tile. Variant selection uses a
 * fast position hash so adjacent tiles of the same type look different.
 *
 * For walls, we also check neighbors to auto-select edge tiles where a
 * wall meets open floor.
 */
static u16 vram_base_for_tile(const GameData *gd, u8 tx, u8 ty)
{
    u8 type = gd->tilemap[ty][tx];

    /* Helper: is (ntx, nty) inside bounds and a wall? */
    #define IS_WALL(ntx, nty) \
        ((ntx) < MAP_TILES_W && (nty) < MAP_TILES_H && \
         gd->tilemap[(nty)][(ntx)] == TILE_WALL)

    switch (type)
    {
        case TILE_EMPTY:
        {
            /* Floor: pick variant from position hash */
            u8 hash    = TILE_HASH(tx, ty);
            /* Occasionally (1-in-8) use the cyan floor variant */
            if ((hash & 0x07u) == 0)
            {
                u8 variant = (hash >> 3) & (FLOOR_CYAN_VARIANTS - 1);
                return VRAM_FLOOR_CYAN_BASE + variant * 4u;
            }
            u8 variant = hash % FLOOR_VARIANTS;
            return VRAM_FLOOR_BASE + variant * 4u;
        }

        case TILE_WALL:
        {
            /* Check if any of the 4 cardinal neighbors is open floor.
             * If so, prefer an edge tile for that face. */
            u8 open_n = (ty == 0)             || !IS_WALL(tx,   ty-1);
            u8 open_s = (ty == MAP_TILES_H-1) || !IS_WALL(tx,   ty+1);
            u8 open_w = (tx == 0)             || !IS_WALL(tx-1, ty  );
            u8 open_e = (tx == MAP_TILES_W-1) || !IS_WALL(tx+1, ty  );

            /* Edge tile if exactly one open face */
            if ((open_n + open_s + open_w + open_e) == 1u)
            {
                u8 hash    = TILE_HASH(tx, ty);
                u8 variant = hash & (WALL_EDGE_VARIANTS - 1u);
                return VRAM_WALL_EDGE_BASE + variant * 4u;
            }

            /* Solid wall: pick variant */
            u8 hash    = TILE_HASH(tx, ty);
            u8 variant = hash & (WALL_VARIANTS - 1u);
            return VRAM_WALL_BASE + variant * 4u;
        }

        case TILE_WALL_EDGE:
        {
            u8 hash    = TILE_HASH(tx, ty);
            u8 variant = hash & (WALL_EDGE_VARIANTS - 1u);
            return VRAM_WALL_EDGE_BASE + variant * 4u;
        }

        case TILE_FLOOR_ALT:
        {
            u8 hash    = TILE_HASH(tx, ty);
            u8 variant = hash & (FLOOR_CYAN_VARIANTS - 1u);
            return VRAM_FLOOR_CYAN_BASE + variant * 4u;
        }

        default:
            return VRAM_FLOOR_BASE;   /* fallback: plain floor */
    }

    #undef IS_WALL
}

/**
 * write_cell_to_vdp()
 *
 * Write four 8×8 tile references to VDP plane B for a 16×16 logical cell.
 * vram_base is the index of TL; TL=base, TR=base+1, BL=base+2, BR=base+3.
 * pal is PAL0 (background palette).
 */
static void write_cell_to_vdp(u8 tx, u8 ty, u16 vram_base)
{
    /* VDP column/row in 8×8 units */
    u16 vdp_col = (u16)tx * 2u;
    u16 vdp_row = (u16)ty * 2u + VDP_ROW_OFFSET;

    u16 attr_tl = TILE_ATTR_FULL(PAL_BG, FALSE, FALSE, FALSE, vram_base);
    u16 attr_tr = TILE_ATTR_FULL(PAL_BG, FALSE, FALSE, FALSE, vram_base + 1u);
    u16 attr_bl = TILE_ATTR_FULL(PAL_BG, FALSE, FALSE, FALSE, vram_base + 2u);
    u16 attr_br = TILE_ATTR_FULL(PAL_BG, FALSE, FALSE, FALSE, vram_base + 3u);

    VDP_setTileMapXY(BG_B, attr_tl, vdp_col,     vdp_row    );
    VDP_setTileMapXY(BG_B, attr_tr, vdp_col + 1, vdp_row    );
    VDP_setTileMapXY(BG_B, attr_bl, vdp_col,     vdp_row + 1);
    VDP_setTileMapXY(BG_B, attr_br, vdp_col + 1, vdp_row + 1);
}

/* ────────────────────────────────────────────────
 * Public API implementation
 * ──────────────────────────────────────────────── */

void tilemap_init(void)
{
    /* SGDK defaults to 64x32 plane size - do NOT call VDP_setPlaneSize here,
     * as calling it with setupVram=TRUE after SPR_init remaps VRAM regions. */

    /* Load the unified background tileset into VRAM at our reserved base */
    VDP_loadTileSet(&bg_tileset, BG_TILESET_VRAM_INDEX, CPU);

    /* Clear plane B */
    VDP_clearPlane(BG_B, TRUE);
}

void tilemap_draw(const GameData *gd)
{
    /* Clear the ENTIRE plane B first — this removes any title screen or
     * previous-level tile indices from the VDP columns beyond MAP_TILES_W*2.
     * Without this, columns 50-63 of the 64-wide VDP plane retain stale
     * tile data that wraps into view when the camera scrolls. */
    VDP_clearPlane(BG_B, TRUE);

    /* Draw every cell */
    for (u8 ty = 0; ty < MAP_TILES_H; ty++)
        for (u8 tx = 0; tx < MAP_TILES_W; tx++)
            tilemap_draw_cell(gd, tx, ty);
}

void tilemap_draw_cell(const GameData *gd, u8 tx, u8 ty)
{
    if (tx >= MAP_TILES_W || ty >= MAP_TILES_H) return;

    u16 vram_base = vram_base_for_tile(gd, tx, ty);
    write_cell_to_vdp(tx, ty, vram_base);
}

u8 tilemap_is_solid(const GameData *gd, u8 tx, u8 ty)
{
    if (tx >= MAP_TILES_W || ty >= MAP_TILES_H) return TRUE; /* out of bounds = solid */
    u8 type = gd->tilemap[ty][tx];
    return (type == TILE_WALL || type == TILE_WALL_EDGE);
}

void tilemap_cell_at_pixel(s16 px, s16 py, u8 *out_tx, u8 *out_ty)
{
    /* Clamp to playfield */
    if (px < 0)            px = 0;
    if (px >= WORLD_W)     px = WORLD_W - 1;
    if (py < HUD_HEIGHT)   py = HUD_HEIGHT;
    if (py >= WORLD_H)     py = WORLD_H - 1;

    *out_tx = (u8)((u16)px / TILE_W);
    *out_ty = (u8)(((u16)py - HUD_HEIGHT) / TILE_H);
}
