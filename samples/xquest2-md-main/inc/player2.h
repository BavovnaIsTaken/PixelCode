/*
 * player2.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Two-player support declarations
 */

#ifndef PLAYER2_H
#define PLAYER2_H

#include <genesis.h>
#include "xquest.h"

/** Global two-player flag — set TRUE by the options screen */
extern u8 g_two_player;

/** Initialise player 2 at position (x, y) */
void player2_init(fix16 x, fix16 y);

/** Update player 2 each frame (reads JOY_2) */
void player2_update(GameData *gd);

/** Collision checks for player 2 against enemies/mines/gems/bullets */
void player2_collision(GameData *gd);

/** Called when player 2 is hit */
void player2_die(GameData *gd);

/** Returns TRUE if P2 is in play and alive */
u8 player2_is_active(void);

/** Direct access to P2 state (for HUD display) */
Player *player2_get(void);

/** P2 score (0 if not in play) */
u32 player2_get_score(void);

#endif /* PLAYER2_H */
