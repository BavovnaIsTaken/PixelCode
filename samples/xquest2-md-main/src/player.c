/*
 * player.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Player ship: 8-direction movement with inertia, firing, smartbomb
 * Preserves original XQuest 2 physics feel
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "sfx.h"
#include "resources.h"

/* ============================================================
 * WALL COLLISION HELPERS
 *
 * We test the four corners of the ship's 10x10 hitbox
 * (centred on p->x, p->y) against the tile map.
 * On contact: bounce velocity component and push out of wall.
 * On Easy difficulty (DiffLevel 0): rebound instead of die.
 * All other difficulties: die on wall contact.
 * ============================================================ */
#define HALF_HIT  5   /* half of SHIP_HIT_W / SHIP_HIT_H */

/* Return TRUE if pixel (px,py) is inside a solid tile */
static u8 pixel_solid(const GameData *gd, s16 px, s16 py)
{
    if (px < 0 || px >= WORLD_W  || py < HUD_HEIGHT || py >= WORLD_H)
        return TRUE;   /* treat off-screen as solid */
    u8 tx, ty;
    tilemap_cell_at_pixel(px, py, &tx, &ty);
    return tilemap_is_solid(gd, tx, ty);
}

static void player_wall_collide(Player *p, GameData *gd)
{
    s16 px = fix16ToInt(p->x);
    s16 py = fix16ToInt(p->y);

    /* Test left / right edges */
    u8 hit_l = pixel_solid(gd, px - HALF_HIT, py) ||
               pixel_solid(gd, px - HALF_HIT, py - HALF_HIT) ||
               pixel_solid(gd, px - HALF_HIT, py + HALF_HIT);
    u8 hit_r = pixel_solid(gd, px + HALF_HIT, py) ||
               pixel_solid(gd, px + HALF_HIT, py - HALF_HIT) ||
               pixel_solid(gd, px + HALF_HIT, py + HALF_HIT);

    /* Test top / bottom edges */
    u8 hit_t = pixel_solid(gd, px, py - HALF_HIT) ||
               pixel_solid(gd, px - HALF_HIT, py - HALF_HIT) ||
               pixel_solid(gd, px + HALF_HIT, py - HALF_HIT);
    u8 hit_b = pixel_solid(gd, px, py + HALF_HIT) ||
               pixel_solid(gd, px - HALF_HIT, py + HALF_HIT) ||
               pixel_solid(gd, px + HALF_HIT, py + HALF_HIT);

    if (!hit_l && !hit_r && !hit_t && !hit_b) return;

    u8 diff = gd->difficulty;
    if (diff == 0)
    {
        /* Easy: stop velocity on hit axis and push out of wall.
         * With direct-velocity physics, zeroing vx/vy is the correct
         * bounce — the player re-presses to move away. */
        if (hit_l || hit_r)
        {
            p->vx = FIX16(0);
            if (hit_l) p->x = fix16Add(p->x, FIX16(3));
            else       p->x = fix16Sub(p->x, FIX16(3));
        }
        if (hit_t || hit_b)
        {
            p->vy = FIX16(0);
            if (hit_t) p->y = fix16Add(p->y, FIX16(3));
            else       p->y = fix16Sub(p->y, FIX16(3));
        }
    }
    else
    {
        player_die(p, gd);
    }
}

/* Ship hitbox (centred on sprite) */
#define SHIP_HIT_W    10
#define SHIP_HIT_H    10

/* Direction -> delta velocity table (8-way)
 * Shared with enemy.c via extern in xquest.h */
const fix16 DIR_DVX[8] = {
     FIX16(1),  FIX16(1),  FIX16(0), FIX16(-1),
    FIX16(-1), FIX16(-1),  FIX16(0),  FIX16(1)
};
const fix16 DIR_DVY[8] = {
     FIX16(0), FIX16(-1), FIX16(-1), FIX16(-1),
     FIX16(0),  FIX16(1),  FIX16(1),  FIX16(1)
};

/* ============================================================
 * PLAYER INIT
 * ============================================================ */
void player_init(Player *p, fix16 x, fix16 y)
{
    p->x             = x;
    p->y             = y;
    p->vx            = FIX16(0);
    p->vy            = FIX16(0);
    p->dir           = DIR_RIGHT;
    p->lives         = INITIAL_LIVES;
    p->smartbombs    = 3;
    p->score         = 0;
    p->shoot_cooldown = 0;
    p->invincible     = 0;
    p->active         = TRUE;
    /* First extra life at level-1 newman threshold */
    p->next_life_score = g_levels[0].newman_score;

    p->spr = SPR_addSprite(&spr_ship,
                           fix16ToInt(x) - 8,
                           fix16ToInt(y) - 8,
                           TILE_ATTR(PAL_ACTIVE, TRUE, FALSE, FALSE));
    if (!p->spr) { p->active = FALSE; return; }
    SPR_setAnim(p->spr, 0);
}

/* ============================================================
 * READ INPUT & DETERMINE DIRECTION
 * ============================================================ */
static Direction read_direction(u16 joy)
{
    u8 right = (joy & BUTTON_RIGHT) != 0;
    u8 left  = (joy & BUTTON_LEFT)  != 0;
    u8 up    = (joy & BUTTON_UP)    != 0;
    u8 down  = (joy & BUTTON_DOWN)  != 0;

    /* Latch-based diagonal input: each axis latches independently.
     * When an axis key is held, that axis is active.
     * When released, the latch holds for DIAG_HOLD frames.
     * This produces diagonals even when the keyboard/emulator only
     * reports one direction key at a time. */
#define DIAG_HOLD 12   /* ~200ms at 60fps */
    static s8 h_latch = 0;   /* active H direction: -1 left, 0 none, +1 right */
    static s8 v_latch = 0;   /* active V direction: -1 up,   0 none, +1 down  */
    static u8 h_held  = 0;   /* countdown frames H latch remains after key release */
    static u8 v_held  = 0;   /* countdown frames V latch remains after key release */

    /* Update H latch */
    if      (right)  { h_latch =  1; h_held = DIAG_HOLD; }
    else if (left)   { h_latch = -1; h_held = DIAG_HOLD; }
    else if (h_held) { h_held--; }          /* hold for a bit after release */
    else             { h_latch = 0; }        /* fully expired */

    /* Update V latch */
    if      (up)     { v_latch = -1; v_held = DIAG_HOLD; }
    else if (down)   { v_latch =  1; v_held = DIAG_HOLD; }
    else if (v_held) { v_held--; }
    else             { v_latch = 0; }

    /* If CURRENT input has both axes, use them directly */
    s8 hv = (right || left) ? ((right) ? 1 : -1) : h_latch;
    s8 vv = (up    || down) ? ((up)    ? -1 : 1) : v_latch;

    if (hv == 0 && vv == 0) return DIR_NONE;

    if (hv ==  1 && vv ==  0) return DIR_RIGHT;
    if (hv ==  1 && vv == -1) return DIR_UP_RIGHT;
    if (hv ==  0 && vv == -1) return DIR_UP;
    if (hv == -1 && vv == -1) return DIR_UP_LEFT;
    if (hv == -1 && vv ==  0) return DIR_LEFT;
    if (hv == -1 && vv ==  1) return DIR_DOWN_LEFT;
    if (hv ==  0 && vv ==  1) return DIR_DOWN;
    if (hv ==  1 && vv ==  1) return DIR_DOWN_RIGHT;

    return DIR_NONE;
}

/* ============================================================
 * PLAYER UPDATE  (called once per frame)
 * ============================================================ */
void player_update(Player *p, GameData *gd)
{
    if (!p->active) return;

    u16 joy = JOY_readJoypad(JOY_1);

    /* --- Movement (matches original XQuest 2 direct-input physics)
     * Original: velocity is set directly to max speed when key held;
     * no build-up. Friction applied only on key release for brief coast.
     * Diagonal speed normalised: ≈ SHIP_MAX_SPEED × 0.707 per axis. */
    Direction dir = read_direction(joy);
    if (dir != DIR_NONE)
    {
        p->dir = dir;
        /* Direct velocity: set each axis to SHIP_MAX_SPEED independently.
         * Diagonal is ~41% faster than cardinal — same as original DOS XQuest. */
        p->vx = (DIR_DVX[dir] > 0) ?  SHIP_MAX_SPEED
                : (DIR_DVX[dir] < 0) ? -SHIP_MAX_SPEED : FIX16(0);
        p->vy = (DIR_DVY[dir] > 0) ?  SHIP_MAX_SPEED
                : (DIR_DVY[dir] < 0) ? -SHIP_MAX_SPEED : FIX16(0);
    }
    else
    {
        /* No input: friction brings ship to a stop */
        p->vx = (fix16)((s32)(p->vx >> 8) * SHIP_FRICTION >> 8);
        p->vy = (fix16)((s32)(p->vy >> 8) * SHIP_FRICTION >> 8);
    }

    /* Integrate position */
    p->x = fix16Add(p->x, p->vx);
    p->y = fix16Add(p->y, p->vy);

    /* World wrap — wrap at world edges (WORLD_W x WORLD_H), not screen edges */
    if (fix16ToInt(p->x) < 0)          p->x = FIX16(WORLD_W - 1);
    if (fix16ToInt(p->x) >= WORLD_W)   p->x = FIX16(0);
    if (fix16ToInt(p->y) < HUD_HEIGHT) p->y = FIX16(WORLD_H - 1);
    if (fix16ToInt(p->y) >= WORLD_H)   p->y = FIX16(HUD_HEIGHT);

    /* Wall / background collision.
     * Shield forces bounce mode regardless of difficulty. */
    if (p->active && p->invincible == 0)
    {
        if (powerup_active(gd, PU_SHIELD))
        {
            u8 saved = gd->difficulty;
            gd->difficulty = 0;
            player_wall_collide(p, gd);
            gd->difficulty = saved;
        }
        else
            player_wall_collide(p, gd);
    }

    /* --- Firing (Button A or C) --- */
    if (p->shoot_cooldown > 0)
        p->shoot_cooldown--;

    if ((joy & (BUTTON_A | BUTTON_C)) && p->shoot_cooldown == 0 && p->dir != DIR_NONE)
    {
        /* Bullet velocity: table lookup avoids M68K split-shift edge cases.
         * BSPD = BULLET_SPEED = FIX16(8.0) = 8 px/frame. */
        static const fix16 BUL_VX[8] = {
             FIX16(8), FIX16(8), FIX16(0), FIX16(-8),
            FIX16(-8),FIX16(-8), FIX16(0),  FIX16(8)
        };
        static const fix16 BUL_VY[8] = {
             FIX16(0),FIX16(-8),FIX16(-8), FIX16(-8),
             FIX16(0), FIX16(8), FIX16(8),  FIX16(8)
        };
        u8 diri = (p->dir == DIR_NONE) ? 0 : (u8)p->dir;
        fix16 bvx = BUL_VX[diri];
        fix16 bvy = BUL_VY[diri];

        /* AimedFire: redirect toward nearest active enemy */
        if (powerup_active(gd, PU_AIMEDFIRE))
        {
            s16 best_dx = 0, best_dy = 0;
            u32 best_d  = 0xFFFFFFFFu;
            Enemy *best_e = NULL;
            for (u8 ei = 0; ei < MAX_ENEMIES; ei++)
            {
                if (!gd->enemies[ei].active) continue;
                s16 ex = fix16ToInt(fix16Sub(gd->enemies[ei].x, p->x));
                s16 ey = fix16ToInt(fix16Sub(gd->enemies[ei].y, p->y));
                u32 d  = (u32)((s32)ex*ex + (s32)ey*ey);
                if (d < best_d) { best_d=d; best_dx=ex; best_dy=ey; best_e=&gd->enemies[ei]; }
            }
            if (best_d < 0xFFFFFFFFu && best_e)
            {
                /* Lead shot: aim where enemy will be when bullet arrives.
                 * frames_to_hit ≈ Manhattan_dist / 5 (BULLET_SPEED = 5 px/f) */
                s16 di = (s16)(abs(best_dx) + abs(best_dy));
                if (di > 0) {
                    s16 ftf = di / 5;
                    s16 lx  = best_dx + fix16ToInt((fix16)((s32)best_e->vx * ftf));
                    s16 ly  = best_dy + fix16ToInt((fix16)((s32)best_e->vy * ftf));
                    s16 ld  = (s16)(abs(lx) + abs(ly));
                    if (ld > 0) {
                        bvx = (fix16)((s32)lx * BULLET_SPEED / ld);
                        bvy = (fix16)((s32)ly * BULLET_SPEED / ld);
                    } else {
                        bvx = (fix16)((s32)best_dx * BULLET_SPEED / di);
                        bvy = (fix16)((s32)best_dy * BULLET_SPEED / di);
                    }
                }
            }
        }

        /* Fire main bullet */
        bullet_fire(gd, p->x, p->y, bvx, bvy, BULLET_PLAYER);

        /* AssFire: simultaneous rear shot */
        if (powerup_active(gd, PU_ASSFIRE))
            bullet_fire(gd, p->x, p->y, -bvx, -bvy, BULLET_PLAYER);

        /* MultiFire: two extra shots at ±10°.
         * Rotation by ±10°: cos10=0.9848→64534/65536, sin10=0.1736→11380/65536.
         * Split-shift: shift bvx/bvy >>8 before multiply to stay in s32. */
        if (powerup_active(gd, PU_MULTIFIRE))
        {
            s32 bx = (s32)bvx >> 8, by = (s32)bvy >> 8;
            /* Left spread (+10°): vx=bx*cos-by*sin, vy=by*cos+bx*sin */
            fix16 lx = (fix16)((bx*64534 - by*11380) >> 8);
            fix16 ly = (fix16)((by*64534 + bx*11380) >> 8);
            /* Right spread (-10°) */
            fix16 rx = (fix16)((bx*64534 + by*11380) >> 8);
            fix16 ry = (fix16)((by*64534 - bx*11380) >> 8);
            bullet_fire(gd, p->x, p->y, lx, ly, BULLET_PLAYER);
            bullet_fire(gd, p->x, p->y, rx, ry, BULLET_PLAYER);
            if (powerup_active(gd, PU_ASSFIRE))
            {
                bullet_fire(gd, p->x, p->y, -lx, -ly, BULLET_PLAYER);
                bullet_fire(gd, p->x, p->y, -rx, -ry, BULLET_PLAYER);
            }
        }

        /* RapidFire halves the cooldown */
        p->shoot_cooldown = powerup_active(gd, PU_RAPIDFIRE)
                            ? (SHIP_FIRE_COOLDOWN / 2)
                            : SHIP_FIRE_COOLDOWN;
        sfx_play(SFX_SHOOT);
    }

    /* --- SmartBomb (Button B) --- */
    static u8 bomb_pressed = FALSE;
    if ((joy & BUTTON_B) && p->smartbombs > 0)
    {
        if (!bomb_pressed)
        {
            smartbomb_activate(gd);
            p->smartbombs--;
            sfx_play(SFX_SMARTBOMB);
        }
        bomb_pressed = TRUE;
    }
    else
    {
        bomb_pressed = FALSE;
    }

    /* --- Invincibility countdown --- */
    if (p->invincible > 0)
    {
        p->invincible--;
        /* Flash sprite during invincibility */
        SPR_setVisibility(p->spr, (p->invincible & 4) ? HIDDEN : VISIBLE);
    }
    else
    {
        SPR_setVisibility(p->spr, VISIBLE);
    }

    /* --- Extra life check (original: BonusShip / NewManScore) ---
     * Each extra life sets the next threshold to current + newman_score
     * for this level (or the level-50 value if beyond the table). */
    while (p->score >= p->next_life_score)
    {
        p->lives = MIN(p->lives + 1, 9);
        u16 li = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
        p->next_life_score += g_levels[li].newman_score;
        sfx_play(SFX_EXTRA_LIFE);
    }

    /* --- Draw --- */
    player_draw(p, gd);
}

/* ============================================================
 * PLAYER DRAW
 * ============================================================ */
void player_draw(Player *p, GameData *gd)
{
    if (!p->active) return;
    SPR_setPosition(p->spr,
                    fix16ToInt(p->x) - 8 - gd->cam_x,
                    fix16ToInt(p->y) - 8 - gd->cam_y);
    /* Map Genesis Direction enum to the correct GFX frame index.
     * The DOS original uses: ShipDir = round(theta/(2π)*24)
     * where theta=0 = pointing DOWN, increasing clockwise.
     * Frame 0=DOWN, 3=DOWN_RIGHT, 6=RIGHT, 9=UP_RIGHT,
     *       12=UP,  15=UP_LEFT,  18=LEFT, 21=DOWN_LEFT */
    static const u8 DIR_TO_FRAME[8] = {
         6,   /* DIR_RIGHT      */
         9,   /* DIR_UP_RIGHT   */
        12,   /* DIR_UP         */
        15,   /* DIR_UP_LEFT    */
        18,   /* DIR_LEFT       */
        21,   /* DIR_DOWN_LEFT  */
         0,   /* DIR_DOWN       */
         3,   /* DIR_DOWN_RIGHT */
    };
    if (p->dir != DIR_NONE)
        SPR_setFrame(p->spr, DIR_TO_FRAME[(u8)p->dir]);
    SPR_setHFlip(p->spr, FALSE);
}
/* ============================================================
 * PLAYER DIE
 * ============================================================ */
void player_die(Player *p, GameData *gd)
{
    if (p->invincible > 0) return;   /* already dying */

    sfx_play(SFX_PLAYER_DIE);   /* sfx_5 = explosion burst */

    /* Spawn explosion at player position */
    for (u8 i = 0; i < MAX_EXPLOSIONS; i++)
    {
        if (!gd->explosions[i].active)
        {
            gd->explosions[i].x      = p->x;
            gd->explosions[i].y      = p->y;
            gd->explosions[i].active = TRUE;
            gd->explosions[i].frame  = 0;
            break;
        }
    }

    p->lives--;
    if (p->lives == 0)
    {
        p->active = FALSE;
        SPR_setVisibility(p->spr, HIDDEN);
        gd->state = STATE_GAME_OVER;
        return;
    }

    /* Respawn at centre with invincibility frames */
    p->x          = FIX16(WORLD_W / 2);
    p->y          = FIX16(WORLD_H / 2);
    p->vx         = FIX16(0);
    p->vy         = FIX16(0);
    p->invincible = 120;   /* 2 seconds @ 60fps */
}
