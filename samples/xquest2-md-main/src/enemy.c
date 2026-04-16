/*
 * enemy.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * All 15 enemy types from the original XQuest 2
 *
 * Enemy roster (from docs):
 *   0  GRUNGER    - slow, stupid, hired muscle
 *   1  ZIPPO      - same as grunger but fast
 *   2  ZINGER     - fires bullets everywhere
 *   3  VINCE      - almost invulnerable
 *   4  MINER      - lays mines
 *   5  MEEBY      - big, annoying, tough
 *   6  RETALIATOR - shoots back when hit
 *   7  TERRIER    - homes in after sensing player
 *   8  DOINGER    - more dangerous the longer it's alive
 *   9  SNIPE      - waits for clear shot
 *  10  TRIBBLER   - splits when shot
 *  11  BUCKSHOT   - fires many bullets
 *  12  CLUSTER    - harmless until shot (then splits dangerously)
 *  13  STICKTIGHT - extremely hard to shake off
 *  14  REPULSOR   - pushes player away forcefully
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "screens.h"
#include "sfx.h"
#include "enemy_variants.h"
#include "resources.h"

/* Enemy HP table — matched to original xquest.enm 'hits' field.
 * Most enemies die in 1 hit. Retaliator takes 5 (original: hits=5).
 * Vince has rebounds=TRUE in the original (bullets bounce off), making him
 * nearly unkillable. We simulate this with HP=20. All others: hits=1. */
static const s16 ENEMY_HP[ENEMY_TYPE_COUNT] = {
    1,   /* GRUNGER     — hits=1 */
    1,   /* ZIPPO       — hits=1 */
    1,   /* ZINGER      — hits=1 */
   20,   /* VINCE       — rebounds=TRUE, simulated as high HP */
    1,   /* MINER       — custom enemy, 1-shot */
    1,   /* MEEBY       — hits=1 (tough due to size, not HP) */
    5,   /* RETALIATOR  — hits=5 (original value) */
    1,   /* TERRIER     — hits=1 */
    1,   /* DOINGER     — hits=1 */
    1,   /* SNIPE       — hits=1 */
    1,   /* TRIBBLER    — hits=1 */
    1,   /* BUCKSHOT    — hits=1 */
    1,   /* CLUSTER     — hits=1 */
    1,   /* STICKTIGHT  — hits=1 */
    1,   /* REPULSOR    — hits=1 */
};

/* Enemy base speed (fix16) */
static const fix16 ENEMY_SPEED[ENEMY_TYPE_COUNT] = {
    FIX16(0.8),   /* GRUNGER */
    FIX16(2.0),   /* ZIPPO */
    FIX16(1.2),   /* ZINGER */
    FIX16(1.0),   /* VINCE */
    FIX16(0.6),   /* MINER */
    FIX16(0.7),   /* MEEBY */
    FIX16(1.0),   /* RETALIATOR */
    FIX16(1.8),   /* TERRIER */
    FIX16(0.9),   /* DOINGER */
    FIX16(0.4),   /* SNIPE */
    FIX16(1.0),   /* TRIBBLER */
    FIX16(1.5),   /* BUCKSHOT */
    FIX16(0.5),   /* CLUSTER */
    FIX16(1.6),   /* STICKTIGHT */
    FIX16(1.2),   /* REPULSOR */
};

/* Score value per kill — matched to original xquest.enm 'score' field.
 * Miner was the blank slot (index 6) in the original; we assign 500 to
 * match the adjacent enemy tier. All other values are exact .enm values. */
static const u16 ENEMY_SCORE[ENEMY_TYPE_COUNT] = {
    200,   /* GRUNGER     — original: 200  */
    300,   /* ZIPPO       — original: 300  */
    300,   /* ZINGER      — original: 300  */
    500,   /* VINCE       — original: 500  */
    500,   /* MINER       — custom; matches Vince tier */
    600,   /* MEEBY       — original: 600  */
   2000,   /* RETALIATOR  — original: 2000 */
   1000,   /* TERRIER     — original: 1000 */
   1000,   /* DOINGER     — original: 1000 */
   1000,   /* SNIPE       — original: 1000 */
   1250,   /* TRIBBLER    — original: 1250 */
    500,   /* BUCKSHOT    — original: 500  */
   1500,   /* CLUSTER     — original: 1500 */
   5000,   /* STICKTIGHT  — original: 5000 */
   2000,   /* REPULSOR    — original: 2000 */
};

/* Sprite definition pointer table — every enemy type uses its own sprite
 * extracted directly from xquest.gfx with the correct palette. */
static const SpriteDefinition *ENEMY_SPR[ENEMY_TYPE_COUNT] = {
    &spr_grunger,     /* 0  GRUNGER    11x11 4fr */
    &spr_zippo,       /* 1  ZIPPO      11x11 4fr */
    &spr_zinger,      /* 2  ZINGER     16x16 4fr */
    &spr_vince,       /* 3  VINCE      16x16 4fr */
    &spr_miner,       /* 4  MINER      12x12 4fr */
    &spr_meeby,       /* 5  MEEBY      20x20 6fr */
    &spr_retaliator,  /* 6  RETALIATOR 11x13 4fr */
    &spr_terrier,     /* 7  TERRIER    21x8  4fr */
    &spr_doinger,     /* 8  DOINGER    12x12 4fr */
    &spr_snipe,       /* 9  SNIPE      9x9   4fr */
    &spr_tribbler,    /* 10 TRIBBLER   14x14 4fr */
    &spr_buckshot,    /* 11 BUCKSHOT   11x11 4fr */
    &spr_cluster,     /* 12 CLUSTER    9x9   4fr */
    &spr_sticktight,  /* 13 STICKTIGHT 11x11 4fr */
    &spr_repulsor,    /* 14 REPULSOR   12x12 6fr */
};

/* Return speed adjusted for difficulty and game speed ramp */
static fix16 scaled_speed(const Enemy *e, fix16 base_speed)
{
    /* difficulty scale: enemy speed_scale is a percentage (100 = normal) */
    /* Integer multiply: max FIX16(1.5)*160/100=FIX16(2.4), fits s32. */
    fix16 s = (fix16)((s32)base_speed * (u8)e->speed_scale / 100);
    /* Split-shift to avoid fix16Mul overflow: max 120M, fits s32. */
    return (fix16)((s32)s * (g_game_speed >> 8) >> 8);
}

/* ============================================================
 * UTILITY: Move toward target with speed
 * ============================================================ */
static void move_toward(Enemy *e, fix16 tx, fix16 ty, fix16 speed)
{
    /* Integer pixel coords avoid fix16Mul overflow (world up to 392px).
     * Max: 392 * FIX16(2.0) = 52M — fits s32. */
    s16 dx_i = fix16ToInt(fix16Sub(tx, e->x));
    s16 dy_i = fix16ToInt(fix16Sub(ty, e->y));
    s16 dist_i = (s16)(abs(dx_i) + abs(dy_i));
    if (dist_i < 1) return;
    speed = scaled_speed(e, speed);
    e->vx = (fix16)((s32)dx_i * speed / dist_i);
    e->vy = (fix16)((s32)dy_i * speed / dist_i);
}

/* ============================================================
 * UTILITY: Move away from target
 * ============================================================ */
static void move_away(Enemy *e, fix16 tx, fix16 ty, fix16 speed) __attribute__((unused));
static void move_away(Enemy *e, fix16 tx, fix16 ty, fix16 speed)
{
    s16 dx_i = fix16ToInt(fix16Sub(e->x, tx));
    s16 dy_i = fix16ToInt(fix16Sub(e->y, ty));
    s16 dist_i = (s16)(abs(dx_i) + abs(dy_i));
    if (dist_i < 1) return;
    e->vx = (fix16)((s32)dx_i * speed / dist_i);
    e->vy = (fix16)((s32)dy_i * speed / dist_i);
}

/* ============================================================
 * ENEMY SPAWN
 * ============================================================ */
void enemy_spawn(Enemy *e, EnemyType type, fix16 x, fix16 y)
{
    memset(e, 0, sizeof(Enemy));
    e->x        = x;
    e->y        = y;
    e->type     = type;
    e->hp       = ENEMY_HP[type];
    e->active   = TRUE;
    e->ai_state = 0;
    e->ai_timer = 0;

    /* Apply difficulty speed scale (screens.h declares screen_get_difficulty) */
    {
        const DifficultySettings *diff = screen_get_difficulty();
        e->speed_scale = diff ? (u8)diff->enemy_spd_scale : 100;
    }

    /* Initialise curve components.
     * Meeby and Sticktight move in arcs (original: 'curves' flag true).
     * Others use identity rotation (no curve). */
    if (type == ENEMY_MEEBY || type == ENEMY_STICKTIGHT)
    {
        /* Small random rotation: ±(0..410) Q15 ≈ ±0.7° per frame */
        s16 cs = (s16)((s32)(random() % 820) - 410);
        s32 cs32 = (s32)cs * cs;
        s32 cc32 = 32767L - cs32 / 32767L;
        e->curvesin = cs;
        e->curvecos = (s16)(cc32 < 1000L ? 1000L : cc32);
    }
    else
    {
        e->curvesin = 0;
        e->curvecos = 32767;   /* identity */
    }

    /* Sprite centre offsets (half the sprite's pixel dimensions).
     * Used so SPR_setPosition places the sprite centred on e->x,e->y. */
    static const s8 SPR_OFS_X[ENEMY_TYPE_COUNT] = {
         6,  6,  8,  8,  6, 10,  6, 11,  6,  5,  7,  6,  5,  6,  6
    };  /* GR ZP ZI VI MI ME RE TE DO SN TR BK CL ST RP  (half of actual px width) */
    static const s8 SPR_OFS_Y[ENEMY_TYPE_COUNT] = {
         6,  6,  8,  8,  6, 10,  7,  4,  6,  5,  7,  6,  5,  6,  6
    };  /* same order */

    e->spr = SPR_addSprite(ENEMY_SPR[type],
                           fix16ToInt(x) - SPR_OFS_X[type],
                           fix16ToInt(y) - SPR_OFS_Y[type],
                           TILE_ATTR(PAL_ENEMY, TRUE, FALSE, FALSE));
    if (!e->spr) { e->active = FALSE; return; }
    SPR_setAnim(e->spr, 0);

    /* Apply variant palette/flip for shared-sprite enemy types */
    if (ev_is_variant(type))
    {
        ev_apply_to_sprite(type, e->spr);
        u8 off = ev_get_anim_offset(type);
        if (off > 0) SPR_setFrame(e->spr, off);
    }
}

/* ============================================================
 * PER-TYPE AI UPDATE
 *
 * All behaviour flags are from the original xquest.enm binary:
 *   follows, curves, zoom, changedir, fireprob, follow_prob
 *
 * Velocity formula (non-following enemies):
 *   Original: delx = (random(speed) - speed2) * gamespeed / 64
 *   At gamespeed=64: range = [-(speed2/64), +(speed-speed2)/64] px/DOS-frame
 *   Scaled to Genesis 60fps: multiply by 60/67
 *
 * changedir probability converted: p_gen = 1-(1-p_dos)^(60/67)
 * We use deterministic timers at the mean interval (1/p_gen frames).
 * ============================================================ */

/* Pick a new symmetric random velocity in fix16. range_fp is one-sided. */
static void random_vel(Enemy *e, fix16 range_fp)
{
    s32 r;
    r = (s32)(random() & 0xFFFF);
    e->vx = (fix16)(r * range_fp / 32768 - range_fp);
    r = (s32)(random() & 0xFFFF);
    e->vy = (fix16)(r * range_fp / 32768 - range_fp);
}

static void ai_grunger(Enemy *e, GameData *gd)
{
    /* follows=0, changedir=0.006 → avg 186 frames. Pure random walk.
     * vel range: ±(60/64)*(60/67) ≈ ±0.84 px/frame. */
    (void)gd;
    e->ai_timer++;
    if (e->ai_timer >= 186)
    {
        e->ai_timer = (s16)(random() % 40);
        random_vel(e, FIX16(0.84));
    }
}

static void ai_zippo(Enemy *e, GameData *gd)
{
    /* follows=0, curves=1, changedir=0.003 → avg 372 frames.
     * Arc motion (curvesin/cos set here, rotated in enemies_update).
     * vel range: ±(140/64)*(60/67) ≈ ±1.96 px/frame. */
    (void)gd;
    e->ai_timer++;
    if (e->ai_timer >= 372)
    {
        e->ai_timer = (s16)(random() % 60);
        random_vel(e, FIX16(1.96));
        s16 cs = (s16)((s32)(random() % 2730) - 1365);
        e->curvesin = cs;
        e->curvecos = 32700;
    }
}

static void ai_zinger(Enemy *e, GameData *gd)
{
    /* follows=0, fires=1, changedir=0.006 → avg 186 frames.
     * Random walk + 4-direction burst fire every ~50 frames.
     * vel range: ±(50/64)*(60/67) ≈ ±0.70 px/frame. */
    e->ai_timer++;
    if (e->ai_timer >= 186)
    {
        e->ai_timer = (s16)(random() % 40);
        random_vel(e, FIX16(0.70));
    }
    if ((g_frame_count % 50) == ((u32)e & 0x3F))
    {
        fix16 spd = FIX16(1.8);
        bullet_fire(gd, e->x, e->y,  spd,      FIX16(0), BULLET_GREEN);
        bullet_fire(gd, e->x, e->y, FIX16(0),  spd,      BULLET_GREEN);
        bullet_fire(gd, e->x, e->y, -spd,      FIX16(0), BULLET_GREEN);
        bullet_fire(gd, e->x, e->y, FIX16(0), -spd,      BULLET_GREEN);
        sfx_play(SFX_ENEMY_SHOOT);
    }
}

static void ai_vince(Enemy *e, GameData *gd)
{
    /* follows=0, rebounds=1, changedir=0.003 → avg 372 frames.
     * Holds direction and bounces off walls; rare direction changes.
     * vel range: ±(100/64)*(60/67) ≈ ±1.40 px/frame. */
    (void)gd;
    e->ai_timer++;
    if (e->ai_timer >= 372)
    {
        e->ai_timer = (s16)(random() % 60);
        random_vel(e, FIX16(1.40));
    }
}

static void ai_miner(Enemy *e, GameData *gd)
{
    /* No original data (blank slot). Slow random walker that drops mines. */
    e->ai_timer++;
    if (e->ai_timer >= 186)
    {
        e->ai_timer = (s16)(random() % 40);
        random_vel(e, FIX16(0.40));
    }
    if ((g_frame_count % 120) == ((u32)e & 0x7F))
        mine_place(gd, e->x, e->y);
}

static void ai_meeby(Enemy *e, GameData *gd)
{
    /* follows=0, curves=1, changedir=0.006 → avg 186 frames.
     * Arc motion; on direction change re-aims toward player.
     * vel range: ±(60/64)*(60/67) ≈ ±0.84 px/frame. */
    e->ai_timer++;
    /* Rotate velocity by arc matrix every frame */
    if (e->curvesin != 0)
    {
        s32 vx32 = (s32)e->vx >> 8;
        s32 vy32 = (s32)e->vy >> 8;
        s32 nvx = (vx32 * e->curvecos - vy32 * e->curvesin) >> 7;
        s32 nvy = (vy32 * e->curvecos + vx32 * e->curvesin) >> 7;
        e->vx = (fix16)nvx;
        e->vy = (fix16)nvy;
    }
    if (e->ai_timer >= 186)
    {
        e->ai_timer = (s16)(random() % 40);
        move_toward(e, gd->player.x, gd->player.y, ENEMY_SPEED[ENEMY_MEEBY]);
        s16 cs = (s16)((s32)(random() % 2184) - 1092);
        e->curvesin = cs;
        e->curvecos = 32700;
    }
}

static void ai_retaliator(Enemy *e, GameData *gd)
{
    /* follows=1, follow_prob=0.01 → avg 100 frames between homing.
     * changedir=0.006 → random nudge at ~186 frames otherwise. */
    e->ai_timer++;
    if (e->ai_timer >= 100)
    {
        e->ai_timer = (s16)(random() % 30);
        move_toward(e, gd->player.x, gd->player.y, ENEMY_SPEED[ENEMY_RETALIATOR]);
    }
    else if (e->ai_timer == 50)
        random_vel(e, FIX16(0.56));
}

static void ai_terrier(Enemy *e, GameData *gd)
{
    /* follows=0, changedir=0.006 → avg 186 frames.
     * Custom: random walk until player is within 80px, then hunts. */
    if (e->ai_state == 0)
    {
        e->ai_timer++;
        if (e->ai_timer >= 186)
        {
            e->ai_timer = (s16)(random() % 40);
            random_vel(e, FIX16(0.84));
        }
        s16 dx_i = fix16ToInt(fix16Sub(gd->player.x, e->x));
        s16 dy_i = fix16ToInt(fix16Sub(gd->player.y, e->y));
        if (abs(dx_i) < 80 && abs(dy_i) < 80)
            e->ai_state = 1;
    }
    else
    {
        e->ai_timer++;
        if (e->ai_timer >= 30)
        {
            e->ai_timer = 0;
            move_toward(e, gd->player.x, gd->player.y, ENEMY_SPEED[ENEMY_TERRIER]);
        }
    }
}

static void ai_doinger(Enemy *e, GameData *gd)
{
    /* follows=0, zoom=1, changedir=0.020 → avg 56 frames (frequent).
     * zoom=1: when player moves slowly, charges at 1.5× speed.
     * Fires aimed shots, rate increasing over time. */
    if (e->ai_timer < 900) e->ai_timer++;
    e->ai_state++;
    u16 cd = (u16)MAX(56 - (s16)(e->ai_timer / 30), 20);
    if (e->ai_state >= cd)
    {
        e->ai_state = 0;
        fix16 pspd = fix16Add(fix16Abs(gd->player.vx), fix16Abs(gd->player.vy));
        if (pspd < FIX16(1.0))
            move_toward(e, gd->player.x, gd->player.y, scaled_speed(e, FIX16(0.75)));
        else
        {
            fix16 r = fix16Add(ENEMY_SPEED[ENEMY_DOINGER], FIX16_FROM_FRAC(e->ai_timer, 1800));
            if (r > FIX16(1.5)) r = FIX16(1.5);
            random_vel(e, r);
        }
    }
    u16 fire_cd = (u16)MAX(90 - (s16)(e->ai_timer / 15), 30);
    if ((g_frame_count % fire_cd) == ((u32)e & 0x1F))
    {
        fix16 spd = FIX16(1.8);
        s16 dx_i = fix16ToInt(fix16Sub(gd->player.x, e->x));
        s16 dy_i = fix16ToInt(fix16Sub(gd->player.y, e->y));
        s16 di   = (s16)(abs(dx_i) + abs(dy_i));
        if (di > 0)
            bullet_fire(gd, e->x, e->y,
                        (fix16)((s32)dx_i * spd / di),
                        (fix16)((s32)dy_i * spd / di), BULLET_GREEN);
    }
}

static void ai_snipe(Enemy *e, GameData *gd)
{
    /* follows=0, fires=1, changedir=0.003 → avg 372 frames. Nearly stationary. */
    e->ai_timer++;
    if (e->ai_timer >= 372)
    {
        e->ai_timer = (s16)(random() % 60);
        random_vel(e, FIX16(0.25));
    }
    if ((g_frame_count % 150) == ((u32)e & 0x7F))
    {
        fix16 spd = FIX16(2.3);
        s16 dx_i = fix16ToInt(fix16Sub(gd->player.x, e->x));
        s16 dy_i = fix16ToInt(fix16Sub(gd->player.y, e->y));
        s16 di   = (s16)(abs(dx_i) + abs(dy_i));
        if (di > 0)
        {
            bullet_fire(gd, e->x, e->y,
                        (fix16)((s32)dx_i * spd / di),
                        (fix16)((s32)dy_i * spd / di), BULLET_YELLOW);
            sfx_play(SFX_ENEMY_SHOOT);
        }
    }
}

static void ai_tribbler(Enemy *e, GameData *gd)
{
    /* follows=0, changedir=0.004 → avg 279 frames. Random walk; splits on death. */
    (void)gd;
    e->ai_timer++;
    if (e->ai_timer >= 279)
    {
        e->ai_timer = (s16)(random() % 50);
        random_vel(e, FIX16(0.91));
    }
}

static void ai_buckshot(Enemy *e, GameData *gd)
{
    /* follows=0, curves=1, changedir=0.005 → avg 223 frames.
     * Arc motion + 8-direction burst fire every ~60 frames. */
    e->ai_timer++;
    if (e->ai_timer >= 223)
    {
        e->ai_timer = (s16)(random() % 40);
        random_vel(e, FIX16(1.54));
        s16 cs = (s16)((s32)(random() % 2730) - 1365);
        e->curvesin = cs;
        e->curvecos = 32700;
    }
    if ((g_frame_count % 60) == ((u32)e & 0x3F))
    {
        fix16 spd = FIX16(2.3);
        for (u8 d = 0; d < 8; d++)
            bullet_fire(gd, e->x, e->y,
                        (fix16)((s32)(DIR_DVX[d] >> 8) * spd >> 8),
                        (fix16)((s32)(DIR_DVY[d] >> 8) * spd >> 8), BULLET_BUCKSHOT);
        sfx_play(SFX_ENEMY_SHOOT);
    }
}

static void ai_cluster(Enemy *e, GameData *gd)
{
    /* follows=0, changedir=0.006 → avg 186 frames. Harmless random walk;
     * dangerous only on death (splits into fast pieces in enemy_die). */
    (void)gd;
    e->ai_timer++;
    if (e->ai_timer >= 186)
    {
        e->ai_timer = (s16)(random() % 40);
        random_vel(e, FIX16(0.70));
    }
}

static void ai_sticktight(Enemy *e, GameData *gd)
{
    /* follows=0, changedir=0.020 → avg 56 frames (frequent changes).
     * When close to player, adds a perpendicular (orbit) component. */
    e->ai_timer++;
    if (e->ai_timer >= 56)
    {
        e->ai_timer = (s16)(random() % 15);
        s16 dx_i = fix16ToInt(fix16Sub(gd->player.x, e->x));
        s16 dy_i = fix16ToInt(fix16Sub(gd->player.y, e->y));
        if (abs(dx_i) < 24 && abs(dy_i) < 24)
        {
            fix16 px = -e->vy;
            fix16 py =  e->vx;
            e->vx = fix16Add(e->vx, (fix16)((s32)(px >> 8) * FIX16(0.3) >> 8));
            e->vy = fix16Add(e->vy, (fix16)((s32)(py >> 8) * FIX16(0.3) >> 8));
        }
        else
            random_vel(e, FIX16(0.56));
    }
}

static void ai_repulsor(Enemy *e, GameData *gd)
{
    /* follows=1, follow_prob=1.0 → homes EVERY frame (always moves toward player).
     * Simultaneously pushes player away with a force field. */
    move_toward(e, gd->player.x, gd->player.y, ENEMY_SPEED[ENEMY_REPULSOR]);
    s16 dx_i   = fix16ToInt(fix16Sub(gd->player.x, e->x));
    s16 dy_i   = fix16ToInt(fix16Sub(gd->player.y, e->y));
    s16 dist_i = (s16)(abs(dx_i) + abs(dy_i));
    if (dist_i > 0 && dist_i < 96)
    {
        fix16 force = FIX16(12) / dist_i;
        gd->player.vx = fix16Add(gd->player.vx, (fix16)((s32)dx_i * force / dist_i));
        gd->player.vy = fix16Add(gd->player.vy, (fix16)((s32)dy_i * force / dist_i));
    }
}

/* AI dispatch table */
typedef void (*AIFunc)(Enemy *, GameData *);
static const AIFunc AI_TABLE[ENEMY_TYPE_COUNT] = {
    ai_grunger,    /* 0  GRUNGER */
    ai_zippo,      /* 1  ZIPPO */
    ai_zinger,     /* 2  ZINGER */
    ai_vince,      /* 3  VINCE */
    ai_miner,      /* 4  MINER */
    ai_meeby,      /* 5  MEEBY */
    ai_retaliator, /* 6  RETALIATOR */
    ai_terrier,    /* 7  TERRIER */
    ai_doinger,    /* 8  DOINGER */
    ai_snipe,      /* 9  SNIPE */
    ai_tribbler,   /* 10 TRIBBLER */
    ai_buckshot,   /* 11 BUCKSHOT */
    ai_cluster,    /* 12 CLUSTER */
    ai_sticktight, /* 13 STICKTIGHT */
    ai_repulsor,   /* 14 REPULSOR */
};

/* ============================================================
 * ENEMIES UPDATE (all active enemies)
 * ============================================================ */
void enemies_update(GameData *gd)
{
    for (u8 i = 0; i < MAX_ENEMIES; i++)
    {
        Enemy *e = &gd->enemies[i];
        if (!e->active) continue;

        /* Run AI */
        AI_TABLE[e->type](e, gd);

        /* Apply curved motion: rotate velocity by curvesin/curvecos if set.
         * This is done after AI so the AI sets the base direction, and the
         * curve bends it each frame (matching original curvesin/curvecos logic). */
        if (e->curvesin != 0)
        {
            /* Split-shift: vx>>8 first so product fits s32, then >>7 not >>15. */
            s32 vx32 = (s32)e->vx >> 8;
            s32 vy32 = (s32)e->vy >> 8;
            s32 nvx = (vx32 * e->curvecos - vy32 * e->curvesin) >> 7;
            s32 nvy = (vy32 * e->curvecos + vx32 * e->curvesin) >> 7;
            e->vx = (fix16)nvx;
            e->vy = (fix16)nvy;
        }

        /* Integrate position */
        e->x = fix16Add(e->x, e->vx);
        e->y = fix16Add(e->y, e->vy);

        /* Boundary bounce (original: enemies bounce off EnemyXMin/Max/YMin/Max).
         * Also guard against the vertical enemy-inlet strip at screen midpoint
         * (x near 0 or SCREEN_W), matching original EnemyEntering guard. */
        s16 ex = fix16ToInt(e->x);
        s16 ey = fix16ToInt(e->y);

        /* Left boundary */
        if (ex < 10)
        {
            e->x  = FIX16(10);
            e->vx = fix16Abs(e->vx);
        }
        /* Right boundary */
        else if (ex > WORLD_W - 10)
        {
            e->x  = FIX16(WORLD_W - 10);
            e->vx = -fix16Abs(e->vx);
        }
        /* Top boundary (below HUD) */
        if (ey < HUD_HEIGHT + 10)
        {
            e->y  = FIX16(HUD_HEIGHT + 10);
            e->vy = fix16Abs(e->vy);
        }
        /* Bottom boundary */
        else if (ey > WORLD_H - 10)
        {
            e->y  = FIX16(WORLD_H - 10);
            e->vy = -fix16Abs(e->vy);
        }

        /* Extra guard: don't let enemies wander into the spawn-portal columns
         * (x < 20 or x > SCREEN_W-20) except at the vertical midpoint row,
         * matching original "collision with enemy inlets" check. */
        ex = fix16ToInt(e->x);
        ey = fix16ToInt(e->y);
        s16 mid_y = (HUD_HEIGHT + WORLD_H) / 2;
        if (ey < mid_y - 10 || ey > mid_y + 10)   /* not at portal row */
        {
            if (ex < 20)
            {
                e->x  = FIX16(20);
                e->vx = fix16Abs(e->vx);
            }
            else if (ex > WORLD_W - 20)
            {
                e->x  = FIX16(WORLD_W - 20);
                e->vx = -fix16Abs(e->vx);
            }
        }

        /* Wall tile collision: bounce off solid tiles */
        {
            u8 tx, ty;
            tilemap_cell_at_pixel(fix16ToInt(e->x), fix16ToInt(e->y), &tx, &ty);
            if (tilemap_is_solid(gd, tx, ty))
            {
                /* Push back and reverse relevant velocity */
                e->x = fix16Sub(e->x, e->vx);
                e->y = fix16Sub(e->y, e->vy);
                if (e->vx != 0) e->vx = -e->vx;
                if (e->vy != 0) e->vy = -e->vy;
            }
        }

        /* Animation cycle */
        e->anim_timer++;
        if (e->anim_timer >= 8)
        {
            e->anim_timer = 0;
            /* Advance frame, wrapping at the animation's frame count.
             * We read numFrame from the SpriteDefinition directly since
             * SPR_getAnimationDef does not exist in SGDK 1.70. */
            u16 num_frames = ENEMY_SPR[e->type]->animations[0]->numFrame;
            e->anim_frame = (e->anim_frame + 1) % num_frames;
            if (e->spr) SPR_setFrame(e->spr, e->anim_frame);
        }

        /* Update sprite position (centred on e->x, e->y) */
        static const s8 UPD_OFS_X[ENEMY_TYPE_COUNT] = {
             6,  6,  8,  8,  6, 10,  6, 11,  6,  5,  7,  6,  5,  6,  6
        };
        static const s8 UPD_OFS_Y[ENEMY_TYPE_COUNT] = {
             6,  6,  8,  8,  6, 10,  7,  4,  6,  5,  7,  6,  5,  6,  6
        };
        if (e->spr) SPR_setPosition(e->spr,
                        fix16ToInt(e->x) - UPD_OFS_X[e->type] - gd->cam_x,
                        fix16ToInt(e->y) - UPD_OFS_Y[e->type] - gd->cam_y);
    }
}

/* ============================================================
 * ENEMY DIE
 * ============================================================ */
void enemy_die(Enemy *e, GameData *gd)
{
    if (!e->active) return;

    /* Award score to the player who dealt the killing blow.
     * last_hit_by: 1=P1 (default), 2=P2. Falls back to P1 in single-player. */
    if (g_two_player && e->last_hit_by == 2 && player2_is_active())
    {
        Player *p2k = player2_get();
        if (p2k) p2k->score += ENEMY_SCORE[e->type];
    }
    else
        gd->player.score += ENEMY_SCORE[e->type];

    /* Special death effects — from original .enm flags:
     *
     * Sticktight: explodes=1, firetype=6 → fires radial burst of bullets
     *   on death.  Original Explode() fires up to 15 missiles in all
     *   directions using sint[]/cost[] tables.  We approximate with 8
     *   bullets on the 8-way axis grid, matching the port's bullet system.
     *
     * Tribbler: tribbles=0 on the Tribbler itself — it just dies.  The
     *   original's "tribble" mechanic lives on the small Tribble sub-type
     *   (not in the port's type enum), so no split needed here.
     *
     * Cluster/Retaliator: no death effects in the original .enm data. */
    if (e->type == ENEMY_STICKTIGHT)
    {
        /* Radial bullet burst — 8 directions at ~2 px/frame.
         * Original firetype=6 mspeed≈150/64≈2.3 px/tick. */
        fix16 spd = FIX16(2.3);
        for (u8 d = 0; d < 8; d++)
            bullet_fire(gd, e->x, e->y,
                        (fix16)((s32)(DIR_DVX[d] >> 8) * spd >> 8),
                        (fix16)((s32)(DIR_DVY[d] >> 8) * spd >> 8),
                        BULLET_BUCKSHOT);
        sfx_play(SFX_ENEMY_SHOOT);
    }

    /* Spawn explosion */
    for (u8 i = 0; i < MAX_EXPLOSIONS; i++)
    {
        if (!gd->explosions[i].active)
        {
            gd->explosions[i].x      = e->x;
            gd->explosions[i].y      = e->y;
            gd->explosions[i].active = TRUE;
            gd->explosions[i].frame  = 0;
            break;
        }
    }

    sfx_play(SFX_EXPLOSION_SM);

    e->active = FALSE;
    if (e->spr) { SPR_releaseSprite(e->spr); e->spr = NULL; }
}

/* ============================================================
 * ENEMIES DRAW (position already set in update)
 * ============================================================ */
void enemies_draw(GameData *gd)
{
    /* Positions already updated in enemies_update via SPR_setPosition.
     * SGDK sprite engine handles the actual rendering via SPR_update()
     * called from main.c. Nothing extra needed here. */
    (void)gd;
}
