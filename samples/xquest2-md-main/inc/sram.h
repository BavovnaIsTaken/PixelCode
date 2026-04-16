/*
 * sram.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Battery-backed SRAM save/load for Hall of Fame
 */

#ifndef SRAM_H
#define SRAM_H

#include <genesis.h>
#include "screens.h"   /* HofEntry, DIFFICULTY_* */

/**
 * sram_load()
 * Attempt to load HOF entries and last-used difficulty from SRAM.
 * Returns TRUE if a valid XQ2 save was found; FALSE if SRAM is blank/corrupt.
 * If FALSE, the caller should use default values.
 *
 * @param hof        Output buffer for HOF entries (must hold `entries` items)
 * @param entries    Number of HOF entries to read (max 10)
 * @param difficulty Output for last-used difficulty (may be NULL)
 */
u8 sram_load(HofEntry *hof, u8 entries, u8 *difficulty);

/**
 * sram_save()
 * Write HOF and difficulty to SRAM with magic header.
 * Safe to call on carts without SRAM (writes go nowhere).
 *
 * @param hof        HOF entries to save
 * @param entries    Number of HOF entries
 * @param difficulty Current difficulty index
 */
void sram_save(const HofEntry *hof, u8 entries, u8 difficulty);

/**
 * sram_erase()
 * Wipe SRAM (clears magic, all data becomes 0).
 * Call when player selects "ERASE DATA" in options.
 */
void sram_erase(void);

/** Called at boot: loads HOF + difficulty from SRAM */
void sram_startup(void);

/** Called after game over: saves HOF + difficulty to SRAM */
void sram_save_hof(void);

#endif /* SRAM_H */
