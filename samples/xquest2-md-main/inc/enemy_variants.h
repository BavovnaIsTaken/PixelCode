/*
 * enemy_variants.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Visual differentiation for shared-sprite enemy types
 */

#ifndef ENEMY_VARIANTS_H
#define ENEMY_VARIANTS_H

#include <genesis.h>
#include "xquest.h"

/**
 * ev_init()
 * Load pal_enemy2 into PAL_COLLECT (PAL2) at level start.
 * This tints gems slightly until ev_restore_collect_palette() is called.
 */
void ev_init(void);

/**
 * ev_restore_collect_palette()
 * Restore PAL_COLLECT to gem/gate colours once all gems are collected.
 * Call from level_check_complete() when gd->gate_open first becomes TRUE.
 */
void ev_restore_collect_palette(void);

/**
 * ev_apply_to_sprite()
 * Apply variant-specific palette + flip + frame offset to a sprite.
 * Call immediately after SPR_addSprite() for any enemy type that
 * ev_is_variant() returns TRUE for.
 */
void ev_apply_to_sprite(EnemyType type, Sprite *spr);

/**
 * ev_is_variant()
 * Returns TRUE if this enemy type reuses another type's sprite graphics.
 */
u8 ev_is_variant(EnemyType type);

/**
 * ev_get_anim_offset()
 * Starting animation frame for variant enemies (prevents sync with host sprite).
 */
u8 ev_get_anim_offset(EnemyType type);

#endif /* ENEMY_VARIANTS_H */
