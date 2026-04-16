/*
 * collision.c - pixel-accurate hitbox collision (preserved from original)
 * level.c     - procedural level generation
 * gem.c       - gem collection
 * bullet.c    - projectile system
 * mine.c      - mine placement and triggering
 * smartbomb.c - screen-clear weapon
 * hud.c       - score/lives/bombs display
 * title.c     - title screen
 * sfx.c       - sound effects
 *
 * All in one file for scaffold clarity; split as needed during full port.
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "screens.h"
#include "player2.h"
#include "sfx.h"
#include "enemy_variants.h"
#include "resources.h"

/* ============================================================
 * LEVEL DEFINITIONS  (from original xqvars.pas)
 * erelease_prob: original float probability × 65535, stored as u16.
 * e.g. 0.005 × 65535 = 328, 0.01 × 65535 = 655, 0.025 × 65535 = 1638
 * ============================================================ */
const LevelDef g_levels[MAX_LEVEL_DATA] = {
/*  cryst mine maxen erel   gateW  gmov  tpar   newman */
/* 1 */  { 15,  0, 20,  328, 27, 0, 20, 15000 },
/* 2 */  { 16,  3,  4,  328, 27, 0, 20, 15000 },
/* 3 */  { 17,  4,  5,  328, 26, 0, 20, 15000 },
/* 4 */  { 18,  5,  6,  328, 26, 0, 25, 15000 },
/* 5 */  { 19,  6,  7,  328, 25, 0, 25, 15000 },
/* 6 */  { 20,  6,  8,  328, 25, 0, 30, 15000 },
/* 7 */  { 21,  7,  9,  328, 24, 0, 30, 15000 },
/* 8 */  { 22,  7, 10,  393, 24, 0, 35, 20000 },
/* 9 */  { 23,  8, 10,  393, 23, 0, 35, 20000 },
/* 10 */ { 24,  8, 10,  393, 23, 0, 40, 20000 },
/* 11 */ { 24,  9, 10,  393, 22, 0, 40, 20000 },
/* 12 */ { 25,  9, 10,  458, 22, 0, 45, 20000 },
/* 13 */ { 25, 10, 10,  458, 21, 0, 45, 40000 },
/* 14 */ { 26, 10, 10,  524, 21, 0, 45, 40000 },
/* 15 */ { 26, 10, 10,  524, 20, 0, 50, 40000 },
/* 16 */ { 27, 11, 10,  589, 20, 0, 50, 40000 },
/* 17 */ { 27, 11, 10,  589, 19, 0, 50, 40000 },
/* 18 */ { 28, 11, 10,  655, 19, 0, 55, 40000 },
/* 19 */ { 28, 12, 10,  655, 18, 0, 55, 40000 },
/* 20 */ { 29, 12, 10,  655, 18, 0, 55, 40000 },
/* 21 */ { 29, 12, 10,  655, 17, 0, 60, 70000 },
/* 22 */ { 30, 13, 10,  655, 17, 0, 60, 70000 },
/* 23 */ { 30, 13, 10,  655, 17, 0, 60, 70000 },
/* 24 */ { 31, 13, 10,  655, 17, 0, 60, 70000 },
/* 25 */ { 31, 13, 10,  655, 17, 0, 65, 70000 },
/* 26 */ { 32, 14, 10,  655, 17, 0, 65, 70000 },
/* 27 */ { 32, 14, 11,  655, 17, 0, 65, 70000 },
/* 28 */ { 33, 14, 11,  655, 17, 0, 65, 70000 },
/* 29 */ { 33, 14, 12,  655, 17, 0, 70, 70000 },
/* 30 */ { 34, 15, 12,  655, 17, 0, 70, 70000 },
/* 31 */ { 34, 15, 13,  655, 17, 0, 70, 70000 },
/* 32 */ { 35, 15, 13,  655, 17, 0, 70, 70000 },
/* 33 */ { 35, 15, 14,  655, 17,10, 75,100000 },
/* 34 */ { 36, 16, 14,  655, 17,20, 75,100000 },
/* 35 */ { 36, 16, 15,  655, 17,30, 75,100000 },
/* 36 */ { 37, 16, 15,  655, 17,40, 75,100000 },
/* 37 */ { 37, 16, 16, 1638, 17,50, 80,100000 },
/* 38 */ { 38, 17, 16,  720, 17,60, 80,100000 },
/* 39 */ { 38, 17, 17,  786, 17,70, 80,100000 },
/* 40 */ { 39, 17, 17,  786, 17,80, 80,100000 },
/* 41 */ { 39, 17, 18,  852, 17,90, 85,100000 },
/* 42 */ { 40, 18, 18,  852, 17,100,85,100000 },
/* 43 */ { 40, 18, 19,  917, 17,100,85,100000 },
/* 44 */ { 40, 18, 19,  917, 17,100,85,100000 },
/* 45 */ { 40, 18, 20,  983, 17,100,90,100000 },
/* 46 */ { 40, 19, 20, 1048, 17,100,90,100000 },
/* 47 */ { 40, 19, 20, 1048, 17,100,90,100000 },
/* 48 */ { 40, 19, 20, 1114, 17,100,90,100000 },
/* 49 */ { 40, 19, 20, 1114, 17,100,90,100000 },
/* 50 */ { 40, 20, 20, 1179, 17,100,90,100000 },
};

/* Enemy type probability weights per level.
 * Columns: GRUNGER ZIPPO ZINGER VINCE MINER MEEBY RETALIATOR TERRIER
 *          DOINGER SNIPE TRIBBLER BUCKSHOT CLUSTER STICKTIGHT REPULSOR
 *
 * Faithfully derived from the original probs[level][0..18] in xqvars.pas,
 * skipping indices 0 (supercrystal), 1 (explosion), 5 (blank col), 14 (blank).
 * Original column order: [Grunger=2, Zippo=3, Zinger=4, Vince=5, (skip6),
 *   Meeby=7, Retaliator=8, Terrier=9, Doinger=10, Snipe=11, Tribbler=12,
 *   (Tribble=13 → maps to Grunger splits), Buckshot=15, Cluster=16,
 *   Sticktight=17, Repulsor=18].
 *
 * Key design principle from the original: each new enemy type is introduced
 * ONE AT A TIME, getting its own pure "introduction level" (100% weight),
 * before being blended into the mix on subsequent levels.  The Genesis port
 * broke this completely by mixing all enemy types from level 1.
 *
 * Mapping of original indices to our EnemyType enum:
 *   orig[2]=Grunger  → GR   orig[3]=Zippo    → ZP   orig[4]=Zinger  → ZI
 *   orig[5]=Vince    → VI   orig[7]=Meeby    → ME   orig[8]=Retaliat→ RE
 *   orig[9]=Terrier  → TE   orig[10]=Doinger → DO   orig[11]=Snipe  → SN
 *   orig[12]=Tribbler→ TR   orig[15]=Buckshot→ BK   orig[16]=Cluster→ CL
 *   orig[17]=Sticktig→ ST   orig[18]=Repulsor→ RP
 * (MINER is index 6 in the original "blank" slot — never appeared in probs[],
 *  so MI stays 0 throughout; Miner is a mid-game surprise introduced via
 *  a non-zero weight starting at level 9 to fill the original "blank" role.)
 */
const u8 g_level_probs[MAX_LEVEL_DATA][LEVEL_PROB_COUNT] = {
/*       GR   ZP   ZI   VI   MI   ME   RE   TE   DO   SN   TR   BK   CL   ST   RP */
/* 1 */  { 60,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 2 */  {100,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 3 */  {  0,100,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 4 */  { 15, 85,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 5 */  {  0,  0, 100,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 6 */  { 15, 15,  70,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 7 */  {  0,  0,   0, 100,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 8 */  { 15, 15,  15,  55,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 9 */  {  0,  0,   0,   0,   0, 100,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 10 */ { 15, 15,  15,  15,   0,  50,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 11 */ {  0,  0,   0,   0,   0,   0, 100,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 12 */ { 10, 10,  10,  10,   0,  10,  60,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 13 */ {  0,  0,   0,   0,   0,   0,   0, 100,   0,   0,   0,   0,   0,   0,   0 },
/* 14 */ { 10, 10,  10,  10,   0,  10,   3,  60,   0,   0,   0,   0,   0,   0,   0 },
/* 15 */ {  0,  0,   0,   0,   0,   0,   0,   0, 100,   0,   0,   0,   0,   0,   0 },
/* 16 */ { 10, 10,  10,  10,   0,  10,   3,   3,  60,   0,   0,   0,   0,   0,   0 },
/* 17 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0, 100,   0,   0,   0,   0,   0 },
/* 18 */ { 10, 10,  10,  10,   0,  10,  10,   3,   3,  60,   0,   0,   0,   0,   0 },
/* 19 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0,   0, 100,   0,   0,   0,   0 },
/* 20 */ { 10, 10,  10,  10,   0,  10,  10,   5,   3,   3,  60,   0,   0,   0,   0 },
/* 21 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 100,   0 },
/* 22 */ { 10, 10,  10,  10,   0,  10,  10,  10,   5,   3,   3,   0,   0,  60,   0 },
/* 23 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 100,   0,   0,   0 },
/* 24 */ { 10, 10,  10,  10,   0,  10,  10,  10,   5,   5,   3,   3,   0,  60,   0 },
/* 25 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 100 },
/* 26 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,   5,   5,   3,   0,   3,  60 },
/* 27 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,   5,   5,   5,   0,   3,   3 },
/* 28 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,   5,   5,   0,   3,   3 },
/* 29 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,   5,   0,   3,   3 },
/* 30 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,   5,   5 },
/* 31 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 32 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 33 */ {  0,100,   0, 100,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0 },
/* 34 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 35 */ {  0,  0,   0,   0,   0,  50,   0,   0,   0,   0,   0,   0,   0,  50,   0 },
/* 36 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 37 */ {  0,  0,   0,   0,   0,   0,  50,   0,   0,   0,   0,  50,   0,   0,   0 },
/* 38 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 39 */ {  0,  0,   0,   0,   0,   0,   0,  50,   0,  50,   0,   0,   0,   0,   0 },
/* 40 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 41 */ {  0,  0,   0,   0,   0,   0,   0,   0,  50,   0,  50,   0,   0,   0,   0 },
/* 42 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 43 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  50,  50 },
/* 44 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 45 */ {  0,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,  50,  50 },
/* 46 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 47 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 48 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 49 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
/* 50 */ { 10, 10,  10,  10,   0,  10,  10,  10,  10,  10,  10,  10,   0,  10,  10 },
};

/* ============================================================
 * collision.c
 * ============================================================ */
u8 rects_overlap(fix16 ax, fix16 ay, u8 aw, u8 ah,
                 fix16 bx, fix16 by, u8 bw, u8 bh)
{
    s16 ax1 = fix16ToInt(ax) - aw/2,  ax2 = ax1 + aw;
    s16 ay1 = fix16ToInt(ay) - ah/2,  ay2 = ay1 + ah;
    s16 bx1 = fix16ToInt(bx) - bw/2,  bx2 = bx1 + bw;
    s16 by1 = fix16ToInt(by) - bh/2,  by2 = by1 + bh;
    return (ax1 < bx2 && ax2 > bx1 && ay1 < by2 && ay2 > by1);
}

void collision_check_all(GameData *gd)
{
    Player *p = &gd->player;
    if (!p->active || p->invincible > 0) return;

    /* Player vs Enemies */
    for (u8 i = 0; i < MAX_ENEMIES; i++)
    {
        Enemy *e = &gd->enemies[i];
        if (!e->active) continue;
        if (rects_overlap(p->x, p->y, 10, 10, e->x, e->y, 12, 12))
        {
            if (!powerup_active(gd, PU_SHIELD))
            {
                player_die(p, gd);
                return;
            }
        }
    }

    /* Player vs Mines */
    for (u8 i = 0; i < MAX_MINES; i++)
    {
        Mine *m = &gd->mines[i];
        if (!m->active) continue;
        if (rects_overlap(p->x, p->y, 10, 10, m->x, m->y, 10, 10))
        {
            m->active = FALSE;
            if (m->spr) { SPR_releaseSprite(m->spr); m->spr = NULL; }
            if (!powerup_active(gd, PU_SHIELD))
            {
                player_die(p, gd);
                return;
            }
        }
    }

    /* Player vs Gems */
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

    /* Player vs PowerCharges (smartbomb pickups)
     * Original: collecting the floor attractor always gives +1 smartbomb
     * and plays the "allright" sound (SFX_POWERUP). Nothing else. */
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

    /* Player bullets vs Enemies */
    for (u8 bi = 0; bi < MAX_BULLETS; bi++)
    {
        Bullet *b = &gd->bullets[bi];
        if (!b->active || !b->is_player) continue;
        for (u8 ei = 0; ei < MAX_ENEMIES; ei++)
        {
            Enemy *e = &gd->enemies[ei];
            if (!e->active) continue;
            if (rects_overlap(b->x, b->y, 6, 6, e->x, e->y, 12, 12))
            {
                /* HeavyFire: bullet pierces (stays active).  Otherwise deactivate. */
                if (!powerup_active(gd, PU_HEAVYFIRE))
                {
                    b->active = FALSE;
                    if (b->spr) { SPR_releaseSprite(b->spr); b->spr = NULL; }
                }
                e->last_hit_by = b->owner;   /* P1=1, P2=2 — for score credit */
                /* HeavyFire instantly kills (original: enemy.hit:=0).
                 * Normal fire: decrement HP. */
                if (powerup_active(gd, PU_HEAVYFIRE))
                    e->hp = 0;
                else
                    e->hp--;
                if (e->hp <= 0)
                    enemy_die(e, gd);
                /* Retaliator fires back immediately when hit.
                 * Original: emisskind[3] mspeed=200/64 ≈ 3.1 px/tick. */
                else if (e->type == ENEMY_RETALIATOR)
                {
                    fix16 spd = FIX16(3.1);
                    s16 dx_i = fix16ToInt(fix16Sub(p->x, e->x));
                    s16 dy_i = fix16ToInt(fix16Sub(p->y, e->y));
                    s16 dist_i = (s16)(abs(dx_i) + abs(dy_i));
                    if (dist_i > 0)
                        bullet_fire(gd, e->x, e->y,
                                    (fix16)((s32)dx_i * spd / dist_i),
                                    (fix16)((s32)dy_i * spd / dist_i), BULLET_PURPLE);
                }
                if (!b->active) break;   /* stopped bullet: move on */
            }
        }
    }

    /* Enemy bullets vs Player */
    for (u8 bi = 0; bi < MAX_BULLETS; bi++)
    {
        Bullet *b = &gd->bullets[bi];
        if (!b->active || b->is_player) continue;
        if (rects_overlap(b->x, b->y, 6, 6, p->x, p->y, 10, 10))
        {
            b->active = FALSE;
            if (b->spr) { SPR_releaseSprite(b->spr); b->spr = NULL; }
            if (!powerup_active(gd, PU_SHIELD))
            {
                player_die(p, gd);
                return;
            }
        }
    }
}

/* ============================================================
 * gem.c
 * ============================================================ */
void gems_init(GameData *gd, u8 count)
{
    gd->gems_remaining = 0;
    for (u8 i = 0; i < count && i < MAX_GEMS; i++)
    {
        Gem *g = &gd->gems[i];
        /* Random position on open floor tiles */
        do {
            g->x = FIX16(16 + random() % (WORLD_W - 32));
            g->y = FIX16(HUD_HEIGHT + 16 + random() % (WORLD_H - HUD_HEIGHT - 32));
        } while (tilemap_is_solid(gd, fix16ToInt(g->x)/TILE_W, (fix16ToInt(g->y)-HUD_HEIGHT)/TILE_H));

        g->collected = FALSE;
        g->spr = SPR_addSprite(&spr_gem,
                               fix16ToInt(g->x) - 8,
                               fix16ToInt(g->y) - 8,
                               TILE_ATTR(PAL_COLLECT, TRUE, FALSE, FALSE));
        if (!g->spr) continue;   /* VRAM alloc failed, skip gem */
        g->active    = TRUE;
        gd->gems_remaining++;
    }
}

void gems_update(GameData *gd)
{
    for (u8 i = 0; i < MAX_GEMS; i++)
    {
        Gem *g = &gd->gems[i];
        if (!g->active) continue;
        if (g->spr) SPR_setPosition(g->spr,
            fix16ToInt(g->x) - 8 - gd->cam_x,
            fix16ToInt(g->y) - 8 - gd->cam_y);
    }
}

void gems_draw(GameData *gd) { (void)gd; }

/* ============================================================
 * bullet.c
 * ============================================================ */
void bullet_fire(GameData *gd, fix16 x, fix16 y, fix16 vx, fix16 vy, BulletType type)
{
    /* Sprite + palette per bullet type */
    static const SpriteDefinition *BULLET_SPR[] = {
        &spr_bullet_player,   /* BULLET_PLAYER   */
        &spr_bullet_green,    /* BULLET_GREEN    */
        &spr_bullet_yellow,   /* BULLET_YELLOW   */
        &spr_bullet_purple,   /* BULLET_PURPLE   */
        &spr_bullet_buckshot, /* BULLET_BUCKSHOT */
    };
    static const u8 BULLET_PAL[] = {
        PAL_ACTIVE, /* BULLET_PLAYER   */
        PAL_ENEMY,  /* BULLET_GREEN    */
        PAL_ENEMY,  /* BULLET_YELLOW   */
        PAL_ENEMY,  /* BULLET_PURPLE   */
        PAL_ENEMY,  /* BULLET_BUCKSHOT */
    };

    for (u8 i = 0; i < MAX_BULLETS; i++)
    {
        Bullet *b = &gd->bullets[i];
        if (b->active) continue;
        b->x = x;  b->y = y;
        b->vx = vx; b->vy = vy;
        b->is_player   = (type == BULLET_PLAYER);
        b->owner       = (type == BULLET_PLAYER) ? 1 : 0;  /* default: P1 or enemy */
        b->bullet_type = type;
        b->active = TRUE;
        b->spr = SPR_addSprite(BULLET_SPR[type],
                               fix16ToInt(x) - 2, fix16ToInt(y) - 2,
                               TILE_ATTR(BULLET_PAL[type], TRUE, FALSE, FALSE));
        if (!b->spr) { b->active = FALSE; return; }
        return;
    }
}

/* bullet_fire_ex: like bullet_fire but sets explicit owner (1=P1, 2=P2, 0=enemy) */
void bullet_fire_ex(GameData *gd, fix16 x, fix16 y,
                    fix16 vx, fix16 vy, BulletType type, u8 owner)
{
    bullet_fire(gd, x, y, vx, vy, type);
    /* Find the bullet we just created (last active player bullet) and set owner */
    for (s8 i = MAX_BULLETS - 1; i >= 0; i--)
    {
        Bullet *b = &gd->bullets[i];
        if (b->active && b->is_player) { b->owner = owner; break; }
    }
}

void bullets_update(GameData *gd)
{
    for (u8 i = 0; i < MAX_BULLETS; i++)
    {
        Bullet *b = &gd->bullets[i];
        if (!b->active) continue;
        b->x = fix16Add(b->x, b->vx);
        b->y = fix16Add(b->y, b->vy);
        /* Boundary handling: Bounce powerup reflects player bullets off walls */
        s16 bx = fix16ToInt(b->x), by = fix16ToInt(b->y);
        if (bx < 0 || bx >= WORLD_W || by < HUD_HEIGHT || by >= WORLD_H)
        {
            if (b->is_player && powerup_active(gd, PU_BOUNCE))
            {
                /* Reflect: flip the velocity component that caused the exit */
                if (bx < 0)        { b->x = FIX16(1);             b->vx = fix16Abs(b->vx); }
                else if (bx >= WORLD_W) { b->x = FIX16(WORLD_W-1); b->vx = -fix16Abs(b->vx); }
                if (by < HUD_HEIGHT)    { b->y = FIX16(HUD_HEIGHT); b->vy = fix16Abs(b->vy); }
                else if (by >= WORLD_H) { b->y = FIX16(WORLD_H-1); b->vy = -fix16Abs(b->vy); }
                bx = fix16ToInt(b->x); by = fix16ToInt(b->y);
            }
            else
            {
                b->active = FALSE;
                if (b->spr) { SPR_releaseSprite(b->spr); b->spr = NULL; }
                continue;
            }
        }
        /* Wall tile: Bounce reflects player bullets, others are destroyed */
        {
            u8 btx, bty;
            tilemap_cell_at_pixel(bx, by, &btx, &bty);
            if (tilemap_is_solid(gd, btx, bty))
            {
                if (b->is_player && powerup_active(gd, PU_BOUNCE))
                {
                    /* Reflect on the axis that caused the collision:
                     * if the tile above/below is clear → horizontal wall → flip vy.
                     * if the tile left/right is clear  → vertical wall  → flip vx.
                     * If both solid (corner), flip both. */
                    u8 tx2, ty2;
                    tilemap_cell_at_pixel(bx, by - (s16)fix16ToInt(b->vy), &tx2, &ty2);
                    u8 vert_clear = !tilemap_is_solid(gd, tx2, ty2);
                    tilemap_cell_at_pixel(bx - (s16)fix16ToInt(b->vx), by, &tx2, &ty2);
                    u8 horiz_clear = !tilemap_is_solid(gd, tx2, ty2);
                    if (vert_clear)  b->vy = -b->vy;
                    if (horiz_clear) b->vx = -b->vx;
                    if (!vert_clear && !horiz_clear) { b->vx = -b->vx; b->vy = -b->vy; }
                }
                else
                {
                    b->active = FALSE;
                    if (b->spr) { SPR_releaseSprite(b->spr); b->spr = NULL; }
                    continue;
                }
            }
        }
        SPR_setPosition(b->spr, bx - 4 - gd->cam_x, by - 4 - gd->cam_y);
    }
}

void bullets_draw(GameData *gd) { (void)gd; }

/* ============================================================
 * mine.c
 * ============================================================ */
void mine_place(GameData *gd, fix16 x, fix16 y)
{
    for (u8 i = 0; i < MAX_MINES; i++)
    {
        Mine *m = &gd->mines[i];
        if (m->active) continue;
        m->x = x;  m->y = y;
        m->active    = TRUE;
        m->triggered = FALSE;
        m->spr = SPR_addSprite(&spr_mine,
                               fix16ToInt(x)-8, fix16ToInt(y)-8,
                               TILE_ATTR(PAL_ACTIVE, TRUE, FALSE, FALSE));
        if (!m->spr) { m->active = FALSE; return; }
        return;
    }
}

void mines_update(GameData *gd)
{
    for (u8 i = 0; i < MAX_MINES; i++)
    {
        Mine *m = &gd->mines[i];
        if (!m->active) continue;
        if (m->spr) SPR_setPosition(m->spr,
            fix16ToInt(m->x) - 8 - gd->cam_x,
            fix16ToInt(m->y) - 8 - gd->cam_y);
    }
}

void mines_draw(GameData *gd) { (void)gd; }

void powercharges_update(GameData *gd)
{
    for (u8 i = 0; i < MAX_POWERCHARGES; i++)
    {
        PowerCharge *pc = &gd->powercharges[i];
        if (!pc->active) continue;
        if (pc->spr) SPR_setPosition(pc->spr,
            fix16ToInt(pc->x) - 6 - gd->cam_x,
            fix16ToInt(pc->y) - 6 - gd->cam_y);
    }
}
/* ============================================================
 * explosions_update — animate one-shot explosion sprites
 * ============================================================ */
void explosions_update(GameData *gd)
{
    for (u8 i = 0; i < MAX_EXPLOSIONS; i++)
    {
        Explosion *ex = &gd->explosions[i];
        if (!ex->active) continue;

        /* Spawn sprite on first frame */
        if (!ex->spr)
        {
            ex->spr = SPR_addSprite(&spr_explosion,
                                    fix16ToInt(ex->x) - 11 - gd->cam_x,
                                    fix16ToInt(ex->y) - 11 - gd->cam_y,
                                    TILE_ATTR(PAL_ENEMY, TRUE, FALSE, FALSE));
            if (ex->spr) SPR_setFrame(ex->spr, 0);
        }

        /* Advance frame every 6 game frames (roughly matches original speed) */
        ex->frame++;
        u8 anim_frame = ex->frame / 6;

        if (anim_frame >= 6)   /* spr_explosion has 6 frames, then disappear */
        {
            ex->active = FALSE;
            if (ex->spr) { SPR_releaseSprite(ex->spr); ex->spr = NULL; }
            continue;
        }

        if (ex->spr)
        {
            SPR_setFrame(ex->spr, anim_frame);
            SPR_setPosition(ex->spr,
                            fix16ToInt(ex->x) - 11 - gd->cam_x,
                            fix16ToInt(ex->y) - 11 - gd->cam_y);
        }
    }
}


/* ============================================================
 * smartbomb.c
 * ============================================================ */
void smartbomb_activate(GameData *gd)
{
    /* Destroy all enemies on screen */
    for (u8 i = 0; i < MAX_ENEMIES; i++)
        if (gd->enemies[i].active)
            enemy_die(&gd->enemies[i], gd);

    /* Destroy all enemy bullets */
    for (u8 i = 0; i < MAX_BULLETS; i++)
    {
        Bullet *b = &gd->bullets[i];
        if (b->active && !b->is_player)
        {
            b->active = FALSE;
            if (b->spr) { SPR_releaseSprite(b->spr); b->spr = NULL; }
        }
    }

    /* Flash screen white */
    sfx_play(SFX_SMARTBOMB);
    PAL_setColor(0, 0x0EEE);
    SYS_doVBlankProcess();
    PAL_setColor(0, 0x0000);
}

/* ============================================================
 * level.c
 * ============================================================ */
void level_generate(GameData *gd, u16 level_num)
{
    /* Look up level data (clamp to table, then cycle 1-based) */
    u16 li = (level_num > 0) ? ((level_num - 1) % MAX_LEVEL_DATA) : 0;
    const LevelDef *ld = &g_levels[li];

    /* Clear tilemap - all floor */
    memset(gd->tilemap, 0, sizeof(gd->tilemap));

    /* Border walls only — the original XQuest has an open playfield with
     * just a decorative border. No interior walls exist in the original. */
    for (u8 x = 0; x < MAP_TILES_W; x++)
    {
        gd->tilemap[0][x] = TILE_WALL;
        gd->tilemap[MAP_TILES_H-1][x] = TILE_WALL;
    }
    for (u8 y = 0; y < MAP_TILES_H; y++)
    {
        gd->tilemap[y][0] = TILE_WALL;
        gd->tilemap[y][MAP_TILES_W-1] = TILE_WALL;
    }

    /* Apply difficulty scaling */
    const DifficultySettings *diff = screen_get_difficulty();
    s16 gem_adj = diff ? diff->gem_count_add   : 0;

    /* Gem count from level table (+ difficulty adjustment) */
    s16 gem_count_raw = (s16)ld->num_crystals + gem_adj;
    u8 gem_count = (u8)MAX(2, MIN(gem_count_raw, (s16)MAX_GEMS));
    gems_init(gd, gem_count);

    /* Mines from level table */
    {
        u8 mine_count = ld->num_mines;
        for (u8 i = 0; i < mine_count && i < MAX_MINES; i++)
        {
            fix16 mx, my;
            u8 attempts = 0;
            do {
                mx = FIX16(16 + (s16)(random() % (WORLD_W - 32)));
                my = FIX16(HUD_HEIGHT + 16 + (s16)(random() % (WORLD_H - HUD_HEIGHT - 32)));
                attempts++;
            } while (attempts < 30 &&
                     tilemap_is_solid(gd,
                         (u8)(fix16ToInt(mx) / TILE_W),
                         (u8)((fix16ToInt(my) - HUD_HEIGHT) / TILE_H)));
            mine_place(gd, mx, my);
        }
    }

    /* ---- Smartbomb pickups (PowerCharges) ----
     * Original: "smart" objects placed on the level floor.
     * smartprob=0.2 chance per roll, maxsmart=1 (levels 1-10) or 2 (levels 11+).
     * Pickup uses spr_powercharge (the attractor sprite from xquest.gfx).
     * Collecting one always gives +1 smartbomb (handled in collision_check_all). */
    {
        /* Release any leftover sprites from the previous level */
        for (u8 i = 0; i < MAX_POWERCHARGES; i++)
        {
            if (gd->powercharges[i].spr)
            {
                SPR_releaseSprite(gd->powercharges[i].spr);
                gd->powercharges[i].spr = NULL;
            }
            gd->powercharges[i].active = FALSE;
        }

        /* Determine count: roll random < 0.2 up to maxsmart times */
        u8 maxsmart  = (level_num >= 11) ? 2 : 1;
        u8 num_smarts = 0;
        while (num_smarts < maxsmart && (random() & 0xFFFF) < 13107u) /* 13107/65535 ≈ 0.2 */
            num_smarts++;

        for (u8 i = 0; i < num_smarts && i < MAX_POWERCHARGES; i++)
        {
            fix16 pcx, pcy;
            u8 attempts = 0;
            do {
                pcx = FIX16(20 + (s16)(random() % (WORLD_W - 40)));
                pcy = FIX16(HUD_HEIGHT + 20 + (s16)(random() % (WORLD_H - HUD_HEIGHT - 40)));
                attempts++;
            } while (attempts < 40 && (
                tilemap_is_solid(gd,
                    (u8)(fix16ToInt(pcx) / TILE_W),
                    (u8)((fix16ToInt(pcy) - HUD_HEIGHT) / TILE_H)) ||
                /* Stay away from player start position (world centre) */
                (abs(fix16ToInt(pcx) - WORLD_W/2) + abs(fix16ToInt(pcy) - WORLD_H/2) < 60)
            ));

            PowerCharge *pc = &gd->powercharges[i];
            pc->x      = pcx;
            pc->y      = pcy;
            pc->active = TRUE;
            pc->spr    = SPR_addSprite(&spr_powercharge,
                                       fix16ToInt(pcx) - 6 - gd->cam_x,
                                       fix16ToInt(pcy) - 6 - gd->cam_y,
                                       TILE_ATTR(PAL_COLLECT, TRUE, FALSE, FALSE));
        }
    }

    /* Initialise variant enemy palette */
    ev_init();

    /* ---- Gate sprite ---- */
    /* Release old gate sprite if present (level restart) */
    if (gd->gate_spr)
    {
        if (gd->gate_spr) { SPR_releaseSprite(gd->gate_spr); gd->gate_spr = NULL; }
    }
    gd->gate_open        = FALSE;
    gd->gate_anim_frame  = 0;
    gd->gate_anim_timer  = 0;
    gd->gate_x           = WORLD_W / 2;    /* start at world horizontal centre */
    gd->gate_move_dir    = 1;              /* initially moving right */
    gd->gate_move_accum  = 0;

    /* Place gate sprite at top-centre, just below HUD */
    /* Gate is centred on world width */
    gd->gate_spr = SPR_addSprite(&spr_gate,
                                 WORLD_W / 2 - 8 - gd->cam_x,
                                 HUD_HEIGHT,
                                 TILE_ATTR(PAL_COLLECT, TRUE, FALSE, FALSE));
    if (gd->gate_spr)
    {
        SPR_setFrame(gd->gate_spr, 0);   /* frame 0 = closed */
        SPR_setVisibility(gd->gate_spr, VISIBLE);
    }

    /* ---- Portal sprites ---- */
    /* Release old portal sprites if present */
    if (gd->portal_left_spr)
    {
        if (gd->portal_left_spr) { SPR_releaseSprite(gd->portal_left_spr); gd->portal_left_spr = NULL; }
    }
    if (gd->portal_right_spr)
    {
        if (gd->portal_right_spr) { SPR_releaseSprite(gd->portal_right_spr); gd->portal_right_spr = NULL; }
    }

    /* Left portal: unique left-facing sprite from xquest.gfx (portal_left, 20x20, 6fr).
     * World-fixed at the left wall, vertically centred. */
    gd->portal_left_spr = SPR_addSprite(&spr_portal,
                                        0 - gd->cam_x,
                                        (HUD_HEIGHT + WORLD_H / 2) - gd->cam_y - 10,
                                        TILE_ATTR(PAL_COLLECT, TRUE, FALSE, FALSE));
    if (gd->portal_left_spr)
    {
        SPR_setFrame(gd->portal_left_spr, 0);
        SPR_setVisibility(gd->portal_left_spr, VISIBLE);
    }

    /* Right portal: its own unique right-facing sprite (portal_right, 20x20, 6fr).
     * No horizontal flip needed — the sprite already faces the correct direction. */
    gd->portal_right_spr = SPR_addSprite(&spr_portal_right,
                                         WORLD_W - 20 - gd->cam_x,
                                         (HUD_HEIGHT + WORLD_H / 2) - gd->cam_y - 10,
                                         TILE_ATTR(PAL_COLLECT, TRUE, FALSE, FALSE));
    if (gd->portal_right_spr)
    {
        SPR_setFrame(gd->portal_right_spr, 0);
        SPR_setVisibility(gd->portal_right_spr, VISIBLE);
    }

    /* ---- Portal state ---- */
    gd->portal_left_cd    = -1;   /* -1 = idle */
    gd->portal_right_cd   = -1;
    gd->portal_left_type  = ENEMY_GRUNGER;
    gd->portal_right_type = ENEMY_GRUNGER;

    gd->level_timer = 0;
}

/* ============================================================
 * PORTAL HELPER: pick a weighted random enemy type for this level
 * ============================================================ */
static EnemyType portal_pick_type(u16 level_num)
{
    u16 li = (level_num > 0) ? ((level_num - 1) % MAX_LEVEL_DATA) : 0;
    u16 total = 0;
    for (u8 t = 0; t < LEVEL_PROB_COUNT; t++)
        total += g_level_probs[li][t];
    if (total == 0) return ENEMY_GRUNGER;
    u16 roll = (u16)(random() % total);
    u16 acc  = 0;
    for (u8 t = 0; t < LEVEL_PROB_COUNT; t++)
    {
        acc += g_level_probs[li][t];
        if (roll < acc) return (EnemyType)t;
    }
    return ENEMY_GRUNGER;
}

/* Count active enemies on screen */
static u8 count_active_enemies(const GameData *gd)
{
    u8 n = 0;
    for (u8 i = 0; i < MAX_ENEMIES; i++)
        if (gd->enemies[i].active) n++;
    return n;
}

/* Find a free enemy slot */
static s8 find_free_enemy(const GameData *gd)
{
    for (u8 i = 0; i < MAX_ENEMIES; i++)
        if (!gd->enemies[i].active) return (s8)i;
    return -1;
}

/* Entry velocity given to each enemy type as it exits the spawn portal.
 * Matches the enemy's own base movement speed so slow types don't burst
 * across screen and fast types don't crawl.  Sign is applied at use-site
 * (positive = rightward from left portal, negated = leftward from right). */
static const fix16 ENEMY_ENTRY_VX[ENEMY_TYPE_COUNT] = {
    FIX16(0.50),  /* GRUNGER     */
    FIX16(1.10),  /* ZIPPO       */
    FIX16(0.55),  /* ZINGER      */
    FIX16(0.75),  /* VINCE       */
    FIX16(0.40),  /* MINER       */
    FIX16(0.50),  /* MEEBY       */
    FIX16(0.45),  /* RETALIATOR  */
    FIX16(0.50),  /* TERRIER     */
    FIX16(0.50),  /* DOINGER     */
    FIX16(0.20),  /* SNIPE       */
    FIX16(0.55),  /* TRIBBLER    */
    FIX16(0.90),  /* BUCKSHOT    */
    FIX16(0.30),  /* CLUSTER     */
    FIX16(0.45),  /* STICKTIGHT  */
    FIX16(0.35),  /* REPULSOR    */
};

void level_check_complete(GameData *gd)
{
    /* Level timer increments every frame */
    gd->level_timer++;

    /* ---- Time-based game speed ramp ---- 
     * Original: once TimeOnLevel exceeds par * FrameRate, speed increases by
     * BaseGameSpeed every 32 seconds: +BaseGameSpeed/32 per extra second.
     * We scale g_game_speed (FIX16(1) = normal) upward continuously. */
    {
        u16 li = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
        u32 par_frames = (u32)g_levels[li].time_par * 60u;
        if (gd->level_timer > par_frames)
        {
            /* Add FIX16(1)/(32*60) = ~FIX16(0.00052) per frame over par */
            u32 over = gd->level_timer - par_frames;
            /* ramp: +1.0 per 1920 frames (32 seconds) → FIX16(1)/1920 per frame */
            fix16 ramp = FIX16_FROM_FRAC(1, 1920);
            (void)over;   /* applied incrementally each frame */
            g_game_speed = fix16Add(g_game_speed, ramp);
            /* Cap at 3× normal speed */
            if (g_game_speed > FIX16(3)) g_game_speed = FIX16(3);
        }
    }

    /* ---- Gate animation ---- */
    if (!gd->gate_open && gd->gems_remaining == 0)
    {
        /* All gems collected: start opening animation */
        gd->gate_open = TRUE;
        gd->gate_anim_frame = 0;
        gd->gate_anim_timer = 0;
        sfx_play(SFX_GATE_OPEN);
        /* Restore PAL2 to gem/gate colours (was overridden by variant enemy palette) */
        ev_restore_collect_palette();
    }

    if (gd->gate_open && gd->gate_spr)
    {
        /* Advance gate open animation (9 frames, one step every 4 game frames) */
        gd->gate_anim_timer++;
        if (gd->gate_anim_timer >= 4)
        {
            gd->gate_anim_timer = 0;
            if (gd->gate_anim_frame < 8)
            {
                gd->gate_anim_frame++;
                SPR_setFrame(gd->gate_spr, gd->gate_anim_frame);
            }
        }
    }

    /* ---- Moving gate (levels 33+) ----
     * Original: GateMove is a fixed-point increment added to GateMoveCount
     * each frame; when count exceeds 63 the gate moves 1 pixel.
     * We replicate this with an 8:8 accumulator:
     *   gate_move_accum += gate_move (from level table)
     *   when accum >= 64, shift gate_x by 1 pixel
     * Gate bounces between x=20 and x=WORLD_W-20. */
    if (gd->gate_spr)
    {
        u16 li = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
        u8 gate_move = g_levels[li].gate_move;

        if (gate_move > 0)
        {
            gd->gate_move_accum += gate_move;
            while (gd->gate_move_accum >= 64)
            {
                gd->gate_move_accum -= 64;
                gd->gate_x += gd->gate_move_dir;

                /* Bounce at screen edges (original: MinGateX=20, MaxGateX=PageWidth-30) */
                if (gd->gate_x >= WORLD_W - 20)
                {
                    gd->gate_x = WORLD_W - 20;
                    gd->gate_move_dir = -1;
                    /* Occasional random direction flip (original GateChangeDirProb) */
                }
                else if (gd->gate_x <= 20)
                {
                    gd->gate_x = 20;
                    gd->gate_move_dir = 1;
                }
            }

            /* Apply GateChangeDirProb: small random chance to reverse */
            /* Original: random < GateChangeDirProb per frame.
             * Levels 41+ have this; we map it as: if accum==0 roll 1/2048. */
            if ((random() & 0x7FF) == 0)
                gd->gate_move_dir = -gd->gate_move_dir;
        }

        /* Update sprite position every frame */
        SPR_setPosition(gd->gate_spr, gd->gate_x - 8 - gd->cam_x, HUD_HEIGHT);
    }

    /* Check if player has flown through the open gate (fully open = frame 8) */
    if (gd->gate_open && gd->gate_anim_frame >= 8 && gd->player.active)
    {
        fix16 gate_x_f = FIX16(gd->gate_x);
        fix16 gate_y   = FIX16(HUD_HEIGHT + 8);

        fix16 dx = fix16Abs(fix16Sub(gd->player.x, gate_x_f));
        fix16 dy = fix16Abs(fix16Sub(gd->player.y, gate_y));

        if (dx < FIX16(24) && dy < FIX16(24))
        {
            /* Time bonus: 500 pts per second under par, capped at 5000 */
            u16 li = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
            u32 par_frames  = (u32)g_levels[li].time_par * 60u;
            u32 time_bonus  = 0;
            if (gd->level_timer < par_frames)
            {
                u32 secs_under = (par_frames - gd->level_timer) / 60u;
                time_bonus = secs_under * 500u;
                /* Original: no cap on time bonus (par - taken) * 500 */
            }
            gd->player.score += time_bonus;
            sfx_play(SFX_LEVEL_CLEAR);
            screen_level_clear(gd, time_bonus);   /* 2-second fanfare overlay */
            level_next(gd);
            return;   /* gd is now reset; don't touch it further this frame */
        }
    }

    /* ---- Continuous enemy spawning via side portals ---- */
    {
        u16 li       = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
        const LevelDef *ld = &g_levels[li];
        const DifficultySettings *diff = screen_get_difficulty();
        s16 enm_adj  = diff ? diff->enemy_count_add : 0;
        u8  max_on   = (u8)MIN((s16)ld->max_enemies + enm_adj, (s16)MAX_ENEMIES);
        u8  on_screen = count_active_enemies(gd);

        /* Spawn probability per portal per frame.
         *
         * The original Pascal rolls once per frame:
         *   if random < erelease * enemyfrequency then spawn one enemy.
         * erelease is stored as a float (e.g. 0.005); we have it scaled ×65535.
         *
         * The port tests TWO portals per frame — that would double the spawn
         * rate vs. the original.  We compensate by using half the threshold
         * per portal, so the combined probability over both portals stays
         * faithful to the original single roll.
         *
         * Additionally, we enforce a minimum inter-spawn cooldown (stored in
         * portal_left_cd / portal_right_cd): once a portal has just closed
         * (-1 → idle) it must wait at least PORTAL_COOLDOWN_FRAMES before
         * it can be triggered again.  This prevents back-to-back spam on high
         * erelease levels.
         *
         * Grace period: the original's AddEnemy() checked if NumEnemies was
         * below MaxEnemies, but more importantly the player always got a few
         * seconds to orient before the first enemy appeared.  We enforce a
         * 180-frame (~3 sec) no-spawn window at the start of each level.
         */
#define PORTAL_COOLDOWN_FRAMES  90   /* ~1.5 sec guaranteed gap per portal */
#define PORTAL_GRACE_FRAMES    180   /* ~3 sec no-spawn window at level start */

        /* No spawning during the grace period; only animate active portals */
        if (gd->level_timer >= PORTAL_GRACE_FRAMES)
        {
            u32 roll_limit = (u32)ld->erelease_prob / 2;   /* halved: two portals */
            if (diff && diff->enemy_count_add > 0)
                roll_limit = roll_limit * 12 / 10;          /* +20% on harder */

            /* Left portal */
            if (on_screen < max_on && gd->portal_left_cd < 0)
            {
                /* portal_left_cd == -1 means idle but might still be cooling down.
                 * We repurpose values in [-PORTAL_COOLDOWN_FRAMES .. -1] as cooldown:
                 * -1 = ready,  negative = counting up to -1. */
                if (gd->portal_left_cd == -1 &&
                    (u32)(random() & 0xFFFF) < roll_limit)
                {
                    gd->portal_left_cd   = PORTAL_ANIM_FRAMES;
                    gd->portal_left_type = (u8)portal_pick_type(gd->level);
                    on_screen++;   /* count the incoming enemy against the cap */
                }
            }

            /* Right portal */
            if (on_screen < max_on && gd->portal_right_cd < 0)
            {
                if (gd->portal_right_cd == -1 &&
                    (u32)(random() & 0xFFFF) < roll_limit)
                {
                    gd->portal_right_cd   = PORTAL_ANIM_FRAMES;
                    gd->portal_right_type = (u8)portal_pick_type(gd->level);
                }
            }
        } /* end grace-period guard */

        /* ---- Animate and resolve LEFT portal ---- */
        if (gd->portal_left_cd >= 0)
        {
            gd->portal_left_cd--;

            /* Map countdown to animation frame (0=closed → 4=open).
             * The portal opens during the first half of the countdown,
             * then stays open until the enemy enters at cd==0. */
            u8 anim_step;
            s16 cd = gd->portal_left_cd;
            if (cd >= PORTAL_ANIM_FRAMES / 2)
            {
                /* Opening: map [FRAMES..FRAMES/2] → [0..PORTAL_ANIM_STEPS-1] */
                u16 elapsed = (u16)(PORTAL_ANIM_FRAMES - cd);
                anim_step = (u8)(elapsed * PORTAL_ANIM_STEPS / (PORTAL_ANIM_FRAMES / 2));
                if (anim_step >= PORTAL_ANIM_STEPS) anim_step = PORTAL_ANIM_STEPS - 1;
            }
            else
            {
                /* Fully open while enemy is "inside" the portal */
                anim_step = PORTAL_ANIM_STEPS - 1;
            }
            if (gd->portal_left_spr)
                SPR_setFrame(gd->portal_left_spr, anim_step);

            if (gd->portal_left_cd == 0)
            {
                /* Enemy enters — reset portal to closed */
                if (gd->portal_left_spr)
                    SPR_setFrame(gd->portal_left_spr, 0);

                s8 slot = find_free_enemy(gd);
                if (slot >= 0)
                {
                    /* Spawn at world Y corresponding to screen midpoint */
                    EnemyType ltype = (EnemyType)gd->portal_left_type;
                    enemy_spawn(&gd->enemies[(u8)slot],
                                ltype,
                                FIX16(PORTAL_LEFT_X + 8),
                                FIX16(HUD_HEIGHT + WORLD_H / 2));
                    /* Give initial rightward velocity equal to the enemy's own
                     * base speed so slow enemies don't rocket off the portal
                     * and fast enemies don't crawl across the screen. */
                    gd->enemies[(u8)slot].vx = ENEMY_ENTRY_VX[ltype];
                    sfx_play(SFX_ENEMY_ENTER);
                }
                gd->portal_left_cd = -PORTAL_COOLDOWN_FRAMES;  /* start cooldown */
            }
        }

        /* ---- Animate and resolve RIGHT portal ---- */
        if (gd->portal_right_cd >= 0)
        {
            gd->portal_right_cd--;

            u8 anim_step;
            s16 cd = gd->portal_right_cd;
            if (cd >= PORTAL_ANIM_FRAMES / 2)
            {
                u16 elapsed = (u16)(PORTAL_ANIM_FRAMES - cd);
                anim_step = (u8)(elapsed * PORTAL_ANIM_STEPS / (PORTAL_ANIM_FRAMES / 2));
                if (anim_step >= PORTAL_ANIM_STEPS) anim_step = PORTAL_ANIM_STEPS - 1;
            }
            else
            {
                anim_step = PORTAL_ANIM_STEPS - 1;
            }
            if (gd->portal_right_spr)
                SPR_setFrame(gd->portal_right_spr, anim_step);

            if (gd->portal_right_cd == 0)
            {
                /* Enemy enters — reset portal to closed */
                if (gd->portal_right_spr)
                    SPR_setFrame(gd->portal_right_spr, 0);

                s8 slot = find_free_enemy(gd);
                if (slot >= 0)
                {
                    EnemyType rtype = (EnemyType)gd->portal_right_type;
                    enemy_spawn(&gd->enemies[(u8)slot],
                                rtype,
                                FIX16(PORTAL_RIGHT_X - 8),
                                FIX16(HUD_HEIGHT + WORLD_H / 2));
                    /* Give initial leftward velocity at the enemy's own base speed */
                    gd->enemies[(u8)slot].vx = -ENEMY_ENTRY_VX[rtype];
                    sfx_play(SFX_ENEMY_ENTER);
                }
                gd->portal_right_cd = -PORTAL_COOLDOWN_FRAMES;  /* start cooldown */
            }
        }

        /* Advance cooldown counters: count negative values up toward -1 (ready). */
        if (gd->portal_left_cd < -1)  gd->portal_left_cd++;
        if (gd->portal_right_cd < -1) gd->portal_right_cd++;
    }
}

/* ============================================================
 * sfx.c
 * ============================================================ */

/* SFX pointer table - maps sfx IDs to rescomp-generated arrays */
static const u8 *SFX_TABLE[] = {
    sfx_0, sfx_1, sfx_2, sfx_3, sfx_4,
    sfx_5, sfx_6, sfx_7, sfx_8
};

#define SFX_COUNT 9

/* sfx_N_size are extern variables, not compile-time constants, so we
 * cannot use them in a static initializer. Look them up inline instead. */
static u32 sfx_get_size(u8 id)
{
    switch (id)
    {
        case 0: return sizeof(sfx_0);
        case 1: return sizeof(sfx_1);
        case 2: return sizeof(sfx_2);
        case 3: return sizeof(sfx_3);
        case 4: return sizeof(sfx_4);
        case 5: return sizeof(sfx_5);
        case 6: return sizeof(sfx_6);
        case 7: return sizeof(sfx_7);
        case 8: return sizeof(sfx_8);
        default: return 0;
    }
}

void sfx_init(void)
{
    /* Z80 PCM driver initialised by SGDK automatically */
}

void sfx_play(u8 sfx_id)
{
    /* SND_startPlay_PCM(sample, len, rate, pan, loop)
     * SOUND_RATE_8000 matches our WAV declaration (0 8000 in resources.res) */
    if (sfx_id >= SFX_COUNT) return;
    SND_startPlay_PCM(SFX_TABLE[sfx_id], sfx_get_size(sfx_id),
                      SOUND_RATE_8000, SOUND_PAN_CENTER, FALSE);
}

void sfx_play_sustained(u8 sfx_id)
{
    if (sfx_id >= SFX_COUNT) return;
    SND_startPlay_PCM(SFX_TABLE[sfx_id], sfx_get_size(sfx_id),
                      SOUND_RATE_8000, SOUND_PAN_CENTER, FALSE);
}

void sfx_stop(void)
{
    SND_stopPlay_PCM();
}

/* ============================================================
 * camera.c  — scroll the viewport to follow the player
 *
 * The world is WORLD_W x WORLD_H (392x320).
 * The viewport is SCREEN_W x PLAYFIELD_H (320x208).
 * cam_x/cam_y are the world coords of the top-left of the viewport.
 *
 * Scrolling rule (same as original CheckWallCollisions):
 *   if (player_screen_x > viewport_right - BORDER)  scroll right
 *   if (player_screen_x < viewport_left  + BORDER)  scroll left
 *   same for Y, chase by (overshoot / 20 + 1) px per frame.
 *
 * Hardware scroll: VDP_setHorizontalScroll(BG_B, -cam_x)
 *                  VDP_setVerticalScroll  (BG_B,  cam_y)
 * (H-scroll is negative because the plane moves left when cam moves right)
 * ============================================================ */
void camera_update(GameData *gd)
{
    s16 px = fix16ToInt(gd->player.x);
    s16 py = fix16ToInt(gd->player.y) - HUD_HEIGHT;  /* playfield-relative */

    /* Horizontal */
    s16 right_edge = gd->cam_x + SCREEN_W - CAM_BORDER_H;
    s16 left_edge  = gd->cam_x + CAM_BORDER_H;
    if (px > right_edge)
    {
        s16 delta = (px - right_edge) / 20 + 1;
        gd->cam_x += delta;
        if (gd->cam_x > CAM_MAX_X) gd->cam_x = CAM_MAX_X;
    }
    else if (px < left_edge)
    {
        s16 delta = (left_edge - px) / 20 + 1;
        gd->cam_x -= delta;
        if (gd->cam_x < 0) gd->cam_x = 0;
    }

    /* Vertical */
    s16 bottom_edge = gd->cam_y + PLAYFIELD_H - CAM_BORDER_V;
    s16 top_edge    = gd->cam_y + CAM_BORDER_V;
    if (py > bottom_edge)
    {
        s16 delta = (py - bottom_edge) / 20 + 1;
        gd->cam_y += delta;
        if (gd->cam_y > CAM_MAX_Y) gd->cam_y = CAM_MAX_Y;
    }
    else if (py < top_edge)
    {
        s16 delta = (top_edge - py) / 20 + 1;
        gd->cam_y -= delta;
        if (gd->cam_y < 0) gd->cam_y = 0;
    }

    /* Apply to VDP hardware scrolling.
     * H-scroll: negative value shifts plane left (cam moves right = plane shifts left).
     * V-scroll: positive value shifts plane down (cam moves down = plane shifts up). */
    VDP_setHorizontalScroll(BG_B, -gd->cam_x);
    VDP_setVerticalScroll(BG_B, gd->cam_y);

    /* Portal sprites are screen-fixed: always at the left/right wall edges,
     * vertically centred on the viewport. Reposition every frame so they
     * don't drift with vertical camera scroll. */
    /* Portal sprites are world-fixed: their world Y is WORLD_H/2+HUD_HEIGHT.
     * Subtract cam offsets to get screen position, like all other world objects.
     * X stays at screen edges (no horizontal offset needed — portals are at x=0
     * and x=WORLD_W-16 in world space, and cam_x max is only 72px so they are
     * always at or near the screen edge). */
    {
        s16 portal_screen_y = (HUD_HEIGHT + WORLD_H / 2) - gd->cam_y - 12;
        if (gd->portal_left_spr)
            SPR_setPosition(gd->portal_left_spr,
                            0 - gd->cam_x, portal_screen_y);
        if (gd->portal_right_spr)
            SPR_setPosition(gd->portal_right_spr,
                            WORLD_W - 16 - gd->cam_x, portal_screen_y);
    }
}

/* ============================================================
 * hud.c
 * ============================================================ */
void hud_draw(GameData *gd)
{
    char buf[40];

    if (g_two_player && player2_is_active())
    {
        /* Two-player HUD: P1 left, P2 right */
        Player *p2 = player2_get();

        /* P1 */
        sprintf(buf, "1:%08lu L%d B%d",
                gd->player.score,
                gd->player.lives,
                gd->player.smartbombs);
        VDP_clearText(0, 0, 20);
        VDP_drawText(buf, 0, 0);

        /* Level + crystals + timer (centred) */
        {
            u16 li2 = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
            u32 pf2 = (u32)g_levels[li2].time_par * 60u;
            u16 tl2 = (gd->level_timer < pf2)
                      ? (u16)((pf2 - gd->level_timer) / 60u) : 0;
            sprintf(buf, "L%02d C%02d T%03d", gd->level, gd->gems_remaining, tl2);
        }
        VDP_clearText(17, 0, 9);
        VDP_drawText(buf, 17, 0);

        /* P2 */
        sprintf(buf, "2:%08lu L%d B%d",
                p2->score,
                p2->lives,
                p2->smartbombs);
        VDP_clearText(22, 0, 18);
        VDP_drawText(buf, 22, 0);
    }
    else
    {
        /* Single-player HUD: SCORE / LEVEL / CRYSTALS / SHIPS / BOMBS / TIMER
         * Matches original: score, level, crystals remaining, lives, bombs, time. */
        u16 li_hud  = (gd->level > 0) ? ((gd->level - 1) % MAX_LEVEL_DATA) : 0;
        u32 par_f   = (u32)g_levels[li_hud].time_par * 60u;
        u16 t_left  = (gd->level_timer < par_f)
                      ? (u16)((par_f - gd->level_timer) / 60u) : 0;
        sprintf(buf, "%08lu L%02d C%02d S%d B%d T%03d",
                gd->player.score,
                gd->level,
                gd->gems_remaining,
                gd->player.lives,
                gd->player.smartbombs,
                t_left);
        VDP_clearText(0, 0, 40);
        VDP_drawText(buf, 0, 0);
    }
}

void hud_update_score(u32 score)
{
    /* Called when score changes for efficiency */
    (void)score;
}

/* ============================================================
 * title.c
 * ============================================================ */
void title_show(void)
{
    /* Clear display */
    SPR_reset();
    VDP_clearPlane(BG_A, TRUE);
    VDP_clearPlane(BG_B, TRUE);

    /* Load the title screen's own 16-color palette into PAL0 */
    PAL_setPalette(PAL_BG, pal_title.data, CPU);

    /* Draw title image to plane B */
    VDP_drawImageEx(BG_B, &img_title, TILE_ATTR_FULL(PAL_BG, FALSE, FALSE, FALSE, TILE_USERINDEX),
                    0, 0, FALSE, CPU);

    /* Overlay text */
    VDP_drawText("PRESS START", 10, 26);

    /* Wait for START */
    while (TRUE)
    {
        SYS_doVBlankProcess();
        u16 joy = JOY_readJoypad(JOY_1);
        if (joy & BUTTON_START) break;
    }

    /* Restore game palettes */
    PAL_setPalette(PAL_BG,      pal_bg.data,      CPU);
    PAL_setPalette(PAL_ACTIVE,  pal_active.data,  CPU);
    PAL_setPalette(PAL_COLLECT, pal_collect.data, CPU);
    PAL_setPalette(PAL_ENEMY,   pal_enemy.data,   CPU);

    VDP_clearPlane(BG_B, TRUE);
    VDP_clearPlane(BG_A, TRUE);
}

/* ============================================================
 * level_next()
 * Advance to the next level: generate map, redraw tilemap,
 * re-spawn enemies. Called from level_check_complete() when
 * the player steps through the open gate.
 * ============================================================ */
void level_next(GameData *gd)
{
    gd->level++;

    /* Reset time-based speed ramp for the new level */
    g_game_speed = FIX16(1);

    /* SPR_reset() releases ALL sprites. Null our tracked pointers first so
     * level_generate() doesn't attempt a double-release. */
    gd->gate_spr         = NULL;
    gd->portal_left_spr  = NULL;
    gd->portal_right_spr = NULL;

    /* Clear all active entities */
    SPR_reset();

    /* Reposition player at centre for new level, preserving score/lives/bombs.
     * We do NOT call player_init (that would reset everything).
     * Instead: re-create the sprite and reset only movement state. */
    {
        Player *p = &gd->player;
        p->x             = FIX16(WORLD_W / 2);
        p->y             = FIX16(WORLD_H / 2);
        p->vx            = FIX16(0);
        p->vy            = FIX16(0);
        p->dir           = DIR_RIGHT;
        p->shoot_cooldown = 0;
        p->invincible    = 60;   /* brief grace period on level entry */
        p->active        = TRUE;
        /* SPR_reset() already freed the old sprite — create a new one */
        p->spr = SPR_addSprite(&spr_ship,
                               fix16ToInt(p->x) - 8,
                               fix16ToInt(p->y) - 8,
                               TILE_ATTR(PAL_ACTIVE, TRUE, FALSE, FALSE));
        if (p->spr) SPR_setAnim(p->spr, 0);
    }

    /* Also null enemy/mine/gem/bullet sprite handles — SPR_reset freed them */
    for (u8 i = 0; i < MAX_ENEMIES;    i++) { gd->enemies[i].active = FALSE;    gd->enemies[i].spr    = NULL; }
    for (u8 i = 0; i < MAX_BULLETS;    i++) { gd->bullets[i].active = FALSE;    gd->bullets[i].spr    = NULL; }
    for (u8 i = 0; i < MAX_GEMS;       i++) { gd->gems[i].active    = FALSE;    gd->gems[i].spr       = NULL; }
    for (u8 i = 0; i < MAX_MINES;      i++) { gd->mines[i].active   = FALSE;    gd->mines[i].spr      = NULL; }
    for (u8 i = 0; i < MAX_EXPLOSIONS; i++) { gd->explosions[i].active = FALSE; gd->explosions[i].spr = NULL; }
    for (u8 i = 0; i < MAX_POWERCHARGES; i++) { gd->powercharges[i].active = FALSE; gd->powercharges[i].spr = NULL; }
    /* Supercrystals: release sprites (SPR_reset freed them), clear state */
    for (u8 i = 0; i < MAX_SUPERCRYSTALS; i++) { gd->supercrystals[i].active = FALSE; gd->supercrystals[i].spr = NULL; }
    /* Powerup timers persist across levels (original keeps powerups active) */

    /* Generate new level layout (also creates gate_spr and resets portals) */
    level_generate(gd, gd->level);

    /* Redraw background */
    tilemap_draw(gd);
}
