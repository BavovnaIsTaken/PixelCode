/*
 * screens.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Declarations for non-gameplay screen states and difficulty system
 */

#ifndef SCREENS_H
#define SCREENS_H

#include <genesis.h>
#include "xquest.h"

/* ────────────────────────────────────────────────
 * Difficulty levels
 * ──────────────────────────────────────────────── */
#define DIFFICULTY_EASY    0
#define DIFFICULTY_NORMAL  1
#define DIFFICULTY_HARD    2
#define DIFFICULTY_INSANE  3
#define DIFFICULTY_COUNT   4

typedef struct {
    const char *label;
    s16  enemy_hp_scale;    /* percentage: 100 = normal */
    s16  enemy_spd_scale;   /* percentage: 100 = normal */
    s8   enemy_count_add;   /* additive adjustment to enemy count */
    s8   gem_count_add;     /* additive adjustment to gem count */
    u16  score_scale;       /* percentage: 100 = normal */
} DifficultySettings;

extern const DifficultySettings difficulty_table[DIFFICULTY_COUNT];

/* ────────────────────────────────────────────────
 * Hall of Fame entry
 * ──────────────────────────────────────────────── */
#ifndef HOF_ENTRY_FWD
#define HOF_ENTRY_FWD
typedef struct {
    char name[13];   /* null-terminated, max 12 chars */
    u32  score;
    u16  level;
} HofEntry;
#endif

/* ────────────────────────────────────────────────
 * Two-player flag (set by options screen)
 * ──────────────────────────────────────────────── */
extern u8 g_two_player;

/* ────────────────────────────────────────────────
 * Screen functions
 * ──────────────────────────────────────────────── */

/** Show "GAME OVER", final score, then check HOF qualification */
void screen_game_over(GameData *gd);

/** Name-entry screen for a new high score; calls screen_hof_show() after */
void screen_hof_enter(GameData *gd);

/** Display the full Hall of Fame table */
void screen_hof_show(void);

/** Pause overlay drawn on top of gameplay; handles resume/quit */
void screen_pause(void);

/** Brief "LEVEL COMPLETE" banner with optional time bonus */
void screen_level_clear(GameData *gd, u32 time_bonus);

/** Difficulty + 2-player options menu; returns chosen difficulty index */
u8 screen_options(void);

/** Get active DifficultySettings */
const DifficultySettings *screen_get_difficulty(void);
u8 screen_get_difficulty_index(void);

#endif /* SCREENS_H */
