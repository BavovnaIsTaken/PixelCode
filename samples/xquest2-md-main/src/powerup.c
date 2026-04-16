/*
 * powerup.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 *
 * Implements the 7 powerup types from the original XQuest 2:
 *   Shield    — invincibility (walls and enemies don't kill)
 *   RapidFire — fire rate doubled
 *   MultiFire — 3-way spread shot (±10° extra bullets)
 *   AssFire   — simultaneous rear shot
 *   AimedFire — bullets home toward nearest enemy
 *   HeavyFire — bullets pierce through enemies (1-shot all)
 *   Bounce    — bullets bounce off walls
 *
 * Powerups are awarded by collecting Supercrystals (the animated floating
 * pickups that appear periodically on the level).  They time out after a
 * duration derived from the original's TimeMin + random(TimeRan) formula,
 * converted from DOS FrameRate=67 to Genesis 60fps.
 *
 * Effects are applied in player.c (firing, invincibility) and
 * collision_check_all (bullet pierce, wall bounce).
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "sfx.h"
#include "resources.h"

/* ============================================================
 * POWERUP QUERY / AWARD / TICK
 * ============================================================ */

u8 powerup_active(const GameData *gd, PowerUpId id)
{
    return gd->powerup_timer[id] > 0;
}

void powerup_award(GameData *gd, PowerUpId id)
{
    /* Add duration: TimeMin + random(TimeRan), matching original. */
    u16 duration = PU_DUR_MIN[id] + (u16)(random() % PU_DUR_RAN[id]);
    /* Stack on top of any remaining time (original behaviour) */
    if ((u32)gd->powerup_timer[id] + duration > 0xFFFF)
        gd->powerup_timer[id] = 0xFFFF;
    else
        gd->powerup_timer[id] = (u16)(gd->powerup_timer[id] + duration);
}

void powerup_tick(GameData *gd)
{
    /* Decrement all active powerup timers once per frame */
    for (u8 i = 0; i < PU_COUNT; i++)
        if (gd->powerup_timer[i] > 0)
            gd->powerup_timer[i]--;
}

/* ============================================================
 * SUPERCRYSTAL UPDATE
 *
 * Supercrystals spawn periodically (every ~300 frames on average),
 * float with a gentle vertical sine-bob, and expire after 5-10 seconds
 * if not collected.  Collecting one awards a random powerup.
 *
 * Original: type-0 enemy spawned from portals with weight 5-10 in the
 * probs[] table.  We handle them separately as floor pickups so they
 * don't interfere with the enemy cap.
 * ============================================================ */

/* Sine table (256 entries, amplitude 4px) for vertical bob */
static const s8 SC_BOB[16] = { 0,1,2,3,3,3,2,1,0,-1,-2,-3,-3,-3,-2,-1 };

void supercrystals_update(GameData *gd)
{
    /* ---- Spawn check ---- */
    /* Try to spawn a new supercrystal every ~300 frames on average.
     * Original: weight 5-10 out of ~65-70 total = ~8-15% of enemy spawns
     * at erelease ~0.005/frame → ~1 supercrystal per 285 frames.
     * We use a simpler direct roll: 1/300 chance per frame. */
    u8 sc_count = 0;
    for (u8 i = 0; i < MAX_SUPERCRYSTALS; i++)
        if (gd->supercrystals[i].active) sc_count++;

    if (sc_count < MAX_SUPERCRYSTALS && (random() % 300) == 0)
    {
        for (u8 i = 0; i < MAX_SUPERCRYSTALS; i++)
        {
            if (!gd->supercrystals[i].active)
            {
                Supercrystal *sc = &gd->supercrystals[i];
                /* Random position on open floor, away from player start */
                fix16 sx, sy;
                u8 attempts = 0;
                do {
                    sx = FIX16(24 + (s16)(random() % (WORLD_W - 48)));
                    sy = FIX16(HUD_HEIGHT + 24 + (s16)(random() % (WORLD_H - HUD_HEIGHT - 48)));
                    attempts++;
                } while (attempts < 40 && (
                    tilemap_is_solid(gd,
                        (u8)(fix16ToInt(sx) / TILE_W),
                        (u8)((fix16ToInt(sy) - HUD_HEIGHT) / TILE_H)) ||
                    (abs(fix16ToInt(sx) - WORLD_W/2) +
                     abs(fix16ToInt(sy) - WORLD_H/2) < 50)
                ));

                sc->x          = sx;
                sc->y          = sy;
                /* 5-10 seconds lifetime: 300 + random(300) frames */
                sc->lifetime   = 300 + (u16)(random() % 300);
                sc->active     = TRUE;
                sc->anim_frame = 0;
                sc->anim_timer = 0;
                sc->spr = SPR_addSprite(&spr_supercrystal,
                                        fix16ToInt(sx) - 8 - gd->cam_x,
                                        fix16ToInt(sy) - 8 - gd->cam_y,
                                        TILE_ATTR(PAL_COLLECT, TRUE, FALSE, FALSE));
                if (!sc->spr) { sc->active = FALSE; }
                break;
            }
        }
    }

    /* ---- Update active supercrystals ---- */
    for (u8 i = 0; i < MAX_SUPERCRYSTALS; i++)
    {
        Supercrystal *sc = &gd->supercrystals[i];
        if (!sc->active) continue;

        /* Lifetime countdown */
        if (sc->lifetime > 0) sc->lifetime--;
        if (sc->lifetime == 0)
        {
            sc->active = FALSE;
            if (sc->spr) { SPR_releaseSprite(sc->spr); sc->spr = NULL; }
            continue;
        }

        /* Animation — 6 frames, cycle every 8 game frames */
        sc->anim_timer++;
        if (sc->anim_timer >= 8)
        {
            sc->anim_timer = 0;
            sc->anim_frame = (sc->anim_frame + 1) % 6;
            if (sc->spr) SPR_setFrame(sc->spr, sc->anim_frame);
        }

        /* Vertical bob using small sine table */
        s8 bob = SC_BOB[(g_frame_count >> 1) & 0x0F];

        /* Sprite position (with camera scroll and bob) */
        if (sc->spr)
            SPR_setPosition(sc->spr,
                            fix16ToInt(sc->x) - 8 - gd->cam_x,
                            fix16ToInt(sc->y) - 8 + bob - gd->cam_y);

        /* ---- Player collection check ---- */
        s16 dx = fix16ToInt(sc->x) - fix16ToInt(gd->player.x);
        s16 dy = fix16ToInt(sc->y) - fix16ToInt(gd->player.y);
        if (abs(dx) < 14 && abs(dy) < 14)
        {
            /* Award a random powerup — weights match original probs[22]:
             * RapidFire 0..2 (3), MultiFire 3..5 (3), HeavyFire 6..8 (3),
             * AssFire 9..11 (3), AimedFire 12..13 (2), Bounce 14..15 (2),
             * Shield 18 (1) = 17 cases total that give a weapon/shield.
             * We use the same relative weights. */
            static const PowerUpId AWARD_TABLE[17] = {
                PU_RAPIDFIRE, PU_RAPIDFIRE, PU_RAPIDFIRE,
                PU_MULTIFIRE, PU_MULTIFIRE, PU_MULTIFIRE,
                PU_HEAVYFIRE, PU_HEAVYFIRE, PU_HEAVYFIRE,
                PU_ASSFIRE,   PU_ASSFIRE,   PU_ASSFIRE,
                PU_AIMEDFIRE, PU_AIMEDFIRE,
                PU_BOUNCE,    PU_BOUNCE,
                PU_SHIELD
            };
            PowerUpId awarded = AWARD_TABLE[random() % 17];
            powerup_award(gd, awarded);
            sfx_play(SFX_POWERUP);

            sc->active = FALSE;
            if (sc->spr) { SPR_releaseSprite(sc->spr); sc->spr = NULL; }
        }
    }
}
