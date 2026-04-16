/*
 * player2.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Two-player support
 *
 * XQuest 2 originally supported two simultaneous players. On Genesis we
 * use JOY_1 for player 1 and JOY_2 for player 2, with independent ship
 * sprites, scores, and lives. Both players share the same screen.
 *
 * Two-player mode differences from single:
 *  - Each player has independent lives, score, smartbombs
 *  - Bullets from either player kill enemies (not each other)
 *  - Game ends when BOTH players have 0 lives
 *  - Final score = sum of both scores for HOF entry
 *  - Player 2 ship uses PAL1 with an alternate sprite frame (hflipped)
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "player2.h"
#include "sfx.h"

/* Global two-player flag — set by the options screen */
extern u8 g_two_player;  /* defined in main.c */

/* Player 2 data lives alongside Player 1 in GameData.
 * We extend GameData.player2 instead of the scaffold's
 * single-player design. Since adding a field to GameData
 * now would break existing code, we keep P2 state here. */
static Player p2_state;
static u8     p2_active = FALSE;

/* Direction → velocity tables (identical to player.c / shared via xquest.h) */
static const fix16 P2_DVX[8] = {
     FIX16(1),  FIX16(1),  FIX16(0), FIX16(-1),
    FIX16(-1), FIX16(-1),  FIX16(0),  FIX16(1)
};
static const fix16 P2_DVY[8] = {
     FIX16(0), FIX16(-1), FIX16(-1), FIX16(-1),
     FIX16(0),  FIX16(1),  FIX16(1),  FIX16(1)
};

/* ────────────────────────────────────────────────
 * Wall collision helper (mirrors player.c logic)
 * ──────────────────────────────────────────────── */
#define P2_HALF_HIT 5

static u8 p2_pixel_solid(const GameData *gd, s16 px, s16 py)
{
    if (px < 0 || px >= WORLD_W  || py < HUD_HEIGHT || py >= WORLD_H)
        return TRUE;
    u8 tx, ty;
    tilemap_cell_at_pixel(px, py, &tx, &ty);
    return tilemap_is_solid(gd, tx, ty);
}

static void p2_wall_collide(Player *p, GameData *gd)
{
    s16 px = fix16ToInt(p->x);
    s16 py = fix16ToInt(p->y);

    u8 hit_l = p2_pixel_solid(gd, px - P2_HALF_HIT, py) ||
               p2_pixel_solid(gd, px - P2_HALF_HIT, py - P2_HALF_HIT) ||
               p2_pixel_solid(gd, px - P2_HALF_HIT, py + P2_HALF_HIT);
    u8 hit_r = p2_pixel_solid(gd, px + P2_HALF_HIT, py) ||
               p2_pixel_solid(gd, px + P2_HALF_HIT, py - P2_HALF_HIT) ||
               p2_pixel_solid(gd, px + P2_HALF_HIT, py + P2_HALF_HIT);
    u8 hit_t = p2_pixel_solid(gd, px, py - P2_HALF_HIT) ||
               p2_pixel_solid(gd, px - P2_HALF_HIT, py - P2_HALF_HIT) ||
               p2_pixel_solid(gd, px + P2_HALF_HIT, py - P2_HALF_HIT);
    u8 hit_b = p2_pixel_solid(gd, px, py + P2_HALF_HIT) ||
               p2_pixel_solid(gd, px - P2_HALF_HIT, py + P2_HALF_HIT) ||
               p2_pixel_solid(gd, px + P2_HALF_HIT, py + P2_HALF_HIT);

    if (!hit_l && !hit_r && !hit_t && !hit_b) return;

    if (gd->difficulty == 0)
    {
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
        player2_die(gd);
    }
}

/* ────────────────────────────────────────────────
 * Public API
 * ──────────────────────────────────────────────── */

void player2_init(fix16 x, fix16 y)
{
    if (!g_two_player) return;

    p2_state.x             = x;
    p2_state.y             = y;
    p2_state.vx            = FIX16(0);
    p2_state.vy            = FIX16(0);
    p2_state.dir           = DIR_LEFT;
    p2_state.lives         = INITIAL_LIVES;
    p2_state.smartbombs    = 3;
    p2_state.score         = 0;
    p2_state.shoot_cooldown = 0;
    p2_state.invincible     = 0;
    p2_state.active         = TRUE;
    p2_state.next_life_score = g_levels[0].newman_score;

    /* Player 2 uses the same ship sprite as P1, hflipped to distinguish visually */
    p2_state.spr = SPR_addSprite(
        &spr_ship,
        fix16ToInt(x) - 8,
        fix16ToInt(y) - 8,
        TILE_ATTR(PAL_ACTIVE, TRUE, FALSE, FALSE));
    if (p2_state.spr)
        SPR_setHFlip(p2_state.spr, TRUE);

    p2_active = TRUE;
}

void player2_update(GameData *gd)
{
    if (!g_two_player || !p2_active) return;
    Player *p = &p2_state;
    if (!p->active) return;

    u16 joy = JOY_readJoypad(JOY_2);

    /* Direction from D-pad */
    u8 right = (joy & BUTTON_RIGHT) != 0;
    u8 left  = (joy & BUTTON_LEFT)  != 0;
    u8 up    = (joy & BUTTON_UP)    != 0;
    u8 down  = (joy & BUTTON_DOWN)  != 0;

    /* Latch-based diagonal: each axis latches for DIAG_HOLD frames */
#ifndef DIAG_HOLD
#define DIAG_HOLD 12
#endif
    static s8 p2_hl = 0, p2_vl = 0;
    static u8 p2_hh = 0, p2_vh = 0;
    if      (right) { p2_hl =  1; p2_hh = DIAG_HOLD; }
    else if (left)  { p2_hl = -1; p2_hh = DIAG_HOLD; }
    else if (p2_hh) { p2_hh--; } else { p2_hl = 0; }
    if      (up)    { p2_vl = -1; p2_vh = DIAG_HOLD; }
    else if (down)  { p2_vl =  1; p2_vh = DIAG_HOLD; }
    else if (p2_vh) { p2_vh--; } else { p2_vl = 0; }
    s8 hv = (right||left) ? (right ? 1 : -1) : p2_hl;
    s8 vv = (up||down)    ? (up    ? -1 : 1) : p2_vl;
    Direction dir = DIR_NONE;
    if      (hv== 1 && vv== 0) dir = DIR_RIGHT;
    else if (hv== 1 && vv==-1) dir = DIR_UP_RIGHT;
    else if (hv== 0 && vv==-1) dir = DIR_UP;
    else if (hv==-1 && vv==-1) dir = DIR_UP_LEFT;
    else if (hv==-1 && vv== 0) dir = DIR_LEFT;
    else if (hv==-1 && vv== 1) dir = DIR_DOWN_LEFT;
    else if (hv== 0 && vv== 1) dir = DIR_DOWN;
    else if (hv== 1 && vv== 1) dir = DIR_DOWN_RIGHT;

    /* Movement — direct velocity, matches original XQuest physics */
    if (dir != DIR_NONE)
    {
        p->dir = dir;
        p->vx = (P2_DVX[dir] > 0) ?  SHIP_MAX_SPEED
                : (P2_DVX[dir] < 0) ? -SHIP_MAX_SPEED : FIX16(0);
        p->vy = (P2_DVY[dir] > 0) ?  SHIP_MAX_SPEED
                : (P2_DVY[dir] < 0) ? -SHIP_MAX_SPEED : FIX16(0);
    }
    else
    {
        p->vx = (fix16)((s32)(p->vx >> 8) * SHIP_FRICTION >> 8);
        p->vy = (fix16)((s32)(p->vy >> 8) * SHIP_FRICTION >> 8);
    }

    /* Integrate */
    p->x = fix16Add(p->x, p->vx);
    p->y = fix16Add(p->y, p->vy);

    /* Screen wrap */
    /* World wrap */
    if (fix16ToInt(p->x) < 0)         p->x = FIX16(WORLD_W - 1);
    if (fix16ToInt(p->x) >= WORLD_W)  p->x = FIX16(0);
    if (fix16ToInt(p->y) < HUD_HEIGHT) p->y = FIX16(WORLD_H - 1);
    if (fix16ToInt(p->y) >= WORLD_H)  p->y = FIX16(HUD_HEIGHT);

    /* Wall collision: Shield forces bounce regardless of difficulty */
    if (p->active && p->invincible == 0)
    {
        if (powerup_active(gd, PU_SHIELD))
        {
            u8 saved = gd->difficulty;
            gd->difficulty = 0;
            p2_wall_collide(p, gd);
            gd->difficulty = saved;
        }
        else
            p2_wall_collide(p, gd);
    }

    /* Fire: buttons A or C */
    if (p->shoot_cooldown > 0) p->shoot_cooldown--;
    if ((joy & (BUTTON_A | BUTTON_C)) && p->shoot_cooldown == 0 && p->dir != DIR_NONE)
    {
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

        /* AimedFire: redirect toward nearest enemy */
        if (powerup_active(gd, PU_AIMEDFIRE))
        {
            s16 best_dx = 0, best_dy = 0;
            u32 best_d = 0xFFFFFFFFu;
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

        bullet_fire_ex(gd, p->x, p->y, bvx, bvy, BULLET_PLAYER, 2);

        /* AssFire: rear shot */
        if (powerup_active(gd, PU_ASSFIRE))
            bullet_fire_ex(gd, p->x, p->y, -bvx, -bvy, BULLET_PLAYER, 2);

        /* MultiFire: ±10° spread */
        if (powerup_active(gd, PU_MULTIFIRE))
        {
            s32 bx = (s32)bvx >> 8, by = (s32)bvy >> 8;
            fix16 lx = (fix16)((bx*64534 - by*11380) >> 8);
            fix16 ly = (fix16)((by*64534 + bx*11380) >> 8);
            fix16 rx = (fix16)((bx*64534 + by*11380) >> 8);
            fix16 ry = (fix16)((by*64534 - bx*11380) >> 8);
            bullet_fire_ex(gd, p->x, p->y, lx, ly, BULLET_PLAYER, 2);
            bullet_fire_ex(gd, p->x, p->y, rx, ry, BULLET_PLAYER, 2);
            if (powerup_active(gd, PU_ASSFIRE))
            {
                bullet_fire_ex(gd, p->x, p->y, -lx, -ly, BULLET_PLAYER, 2);
                bullet_fire_ex(gd, p->x, p->y, -rx, -ry, BULLET_PLAYER, 2);
            }
        }

        p->shoot_cooldown = powerup_active(gd, PU_RAPIDFIRE)
                            ? (SHIP_FIRE_COOLDOWN / 2)
                            : SHIP_FIRE_COOLDOWN;
        sfx_play(SFX_SHOOT);
    }

    /* SmartBomb: button B */
    {
        static u8 bomb_held = FALSE;
        if ((joy & BUTTON_B) && p->smartbombs > 0)
        {
            if (!bomb_held)
            {
                smartbomb_activate(gd);
                p->smartbombs--;
                sfx_play(SFX_SMARTBOMB);
            }
            bomb_held = TRUE;
        }
        else
        {
            bomb_held = FALSE;
        }
    }

    /* Invincibility flash */
    if (p->invincible > 0)
    {
        p->invincible--;
        if (p->spr)
            SPR_setVisibility(p->spr, (p->invincible & 4) ? HIDDEN : VISIBLE);
    }
    else if (p->spr)
    {
        SPR_setVisibility(p->spr, VISIBLE);
    }

    /* Extra life check for P2 */
    /* Extra life: same logic as player 1 */
    while (p->score >= p->next_life_score)
    {
        p->lives = MIN(p->lives + 1, 9);
        u16 li = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
        p->next_life_score += g_levels[li].newman_score;
        sfx_play(SFX_EXTRA_LIFE);
    }

    /* Update sprite */
    if (p->spr)
    {
        SPR_setPosition(p->spr,
                        fix16ToInt(p->x) - 8 - gd->cam_x,
                        fix16ToInt(p->y) - 8 - gd->cam_y);
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
    }
}

void player2_collision(GameData *gd)
{
    if (!g_two_player || !p2_active) return;
    Player *p = &p2_state;
    if (!p->active || p->invincible > 0) return;

    /* vs enemies */
    for (u8 i = 0; i < MAX_ENEMIES; i++)
    {
        Enemy *e = &gd->enemies[i];
        if (!e->active) continue;
        if (rects_overlap(p->x, p->y, 10, 10, e->x, e->y, 12, 12))
        { if (!powerup_active(gd, PU_SHIELD)) { player2_die(gd); return; } }
    }
    /* vs mines */
    for (u8 i = 0; i < MAX_MINES; i++)
    {
        Mine *m = &gd->mines[i];
        if (!m->active) continue;
        if (rects_overlap(p->x, p->y, 10, 10, m->x, m->y, 10, 10))
        {
            m->active = FALSE;
            if (m->spr) { SPR_releaseSprite(m->spr); m->spr = NULL; }
            if (!powerup_active(gd, PU_SHIELD)) { player2_die(gd); return; }
        }
    }
    /* vs gems — P2 collects gems too */
    for (u8 i = 0; i < MAX_GEMS; i++)
    {
        Gem *g = &gd->gems[i];
        if (!g->active || g->collected) continue;
        if (rects_overlap(p->x, p->y, 10, 10, g->x, g->y, 10, 10))
        {
            g->collected = TRUE;
            g->active    = FALSE;
            if (g->spr) { SPR_releaseSprite(g->spr); g->spr = NULL; }
            p->score += 200;   /* original: 200 pts per crystal */
            gd->gems_remaining--;
            sfx_play(SFX_GEM_COLLECT);
        }
    }
    /* vs powercharges (smartbomb pickups) */
    for (u8 i = 0; i < MAX_POWERCHARGES; i++)
    {
        PowerCharge *pc = &gd->powercharges[i];
        if (!pc->active) continue;
        if (rects_overlap(p->x, p->y, 10, 10, pc->x, pc->y, 12, 12))
        {
            p->smartbombs = MIN(p->smartbombs + 1, MAX_SMARTBOMBS);
            pc->active = FALSE;
            if (pc->spr) { SPR_releaseSprite(pc->spr); pc->spr = NULL; }
            sfx_play(SFX_POWERUP);
        }
    }
    /* vs supercrystals */
    for (u8 i = 0; i < MAX_SUPERCRYSTALS; i++)
    {
        Supercrystal *sc = &gd->supercrystals[i];
        if (!sc->active) continue;
        s16 sdx = fix16ToInt(sc->x) - fix16ToInt(p->x);
        s16 sdy = fix16ToInt(sc->y) - fix16ToInt(p->y);
        if (abs(sdx) < 14 && abs(sdy) < 14)
        {
            static const PowerUpId SC_TABLE[17] = {
                PU_RAPIDFIRE,PU_RAPIDFIRE,PU_RAPIDFIRE,
                PU_MULTIFIRE,PU_MULTIFIRE,PU_MULTIFIRE,
                PU_HEAVYFIRE,PU_HEAVYFIRE,PU_HEAVYFIRE,
                PU_ASSFIRE,  PU_ASSFIRE,  PU_ASSFIRE,
                PU_AIMEDFIRE,PU_AIMEDFIRE,
                PU_BOUNCE,   PU_BOUNCE,
                PU_SHIELD
            };
            powerup_award(gd, SC_TABLE[random() % 17]);
            sfx_play(SFX_POWERUP);
            sc->active = FALSE;
            if (sc->spr) { SPR_releaseSprite(sc->spr); sc->spr = NULL; }
        }
    }
    /* vs enemy bullets */
    for (u8 i = 0; i < MAX_BULLETS; i++)
    {
        Bullet *b = &gd->bullets[i];
        if (!b->active || b->is_player) continue;
        if (rects_overlap(b->x, b->y, 6, 6, p->x, p->y, 10, 10))
        {
            b->active = FALSE;
            if (b->spr) { SPR_releaseSprite(b->spr); b->spr = NULL; }
            if (!powerup_active(gd, PU_SHIELD)) { player2_die(gd); return; }
        }
    }
}

void player2_die(GameData *gd)
{
    Player *p = &p2_state;
    if (!p->active || p->invincible > 0) return;

    sfx_play(SFX_PLAYER_DIE);
    p->lives--;

    if (p->lives == 0)
    {
        p->active = FALSE;
        if (p->spr) SPR_setVisibility(p->spr, HIDDEN);
        p2_active = FALSE;
        if (!gd->player.active || gd->player.lives == 0)
            gd->state = STATE_GAME_OVER;
        return;
    }

    p->x = FIX16(WORLD_W / 4);
    p->y = FIX16(WORLD_H / 2);
    p->vx = p->vy = FIX16(0);
    p->invincible = 120;
}

u8 player2_is_active(void)
{
    return p2_active && p2_state.active;
}

Player *player2_get(void)
{
    return &p2_state;
}

u32 player2_get_score(void)
{
    return p2_active ? p2_state.score : 0;
}
