/*
 * sfx.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Sound effect ID definitions
 *
 * Sound bank contents (from XQUEST.SND analysis):
 * ─────────────────────────────────────────────────
 *  ID   File                       Dur    Contents (identified by context)
 *  0    snd_00_music_intro.wav     5.19s  Title/attract complex SFX sequence
 *  1    snd_01_music_loop_a.wav    3.95s  Gameplay ambient/SFX bank A
 *  2    snd_02_music_loop_b.wav    3.98s  Gameplay ambient/SFX bank B
 *  3    snd_03_music_loop_c.wav    3.22s  Gameplay ambient/SFX bank C
 *  4    snd_04_music_loop_d.wav    3.21s  Gameplay ambient/SFX bank D
 *  5    snd_05_sfx_burst_a.wav     4.54s  Large explosion / smartbomb
 *  6    snd_06_sfx_burst_b.wav     0.93s  Small explosion / enemy destroyed
 *  7    snd_07_sfx_sweep.wav       0.04s  Shoot bullet / gem collect blip
 *  8    snd_08_sfx_short_a.wav     2.10s  Level complete / powerup / extra life
 *
 * Usage mapping:
 * ─────────────────────────────────────────────────
 *  SFX_SHOOT         → snd_07  (tiny blip on every player shot)
 *  SFX_GEM_COLLECT   → snd_07  (same tiny blip, distinct enough)
 *  SFX_ENEMY_SHOOT   → snd_07  (enemy fire blip)
 *  SFX_EXPLOSION_SM  → snd_06  (small enemy death)
 *  SFX_EXPLOSION_LG  → snd_05  (player death / smartbomb)
 *  SFX_SMARTBOMB     → snd_05  (full screen clear)
 *  SFX_POWERUP       → snd_08  (powercharge collected)
 *  SFX_EXTRA_LIFE    → snd_08  (1UP awarded)
 *  SFX_LEVEL_CLEAR   → snd_08  (all gems collected, gate opens)
 *  SFX_TITLE         → snd_00  (plays on title screen)
 *  SFX_AMBIENT_A     → snd_01  (in-game ambient, cycled per level)
 *  SFX_AMBIENT_B     → snd_02
 *  SFX_AMBIENT_C     → snd_03
 *  SFX_AMBIENT_D     → snd_04
 */

#ifndef SFX_H
#define SFX_H

#include <genesis.h>

/* ────────────────────────────────────────────────
 * Raw WAV bank IDs (direct indices into sfx_0[]…sfx_8[])
 * ──────────────────────────────────────────────── */
#define SFX_BANK_TITLE        0
#define SFX_BANK_AMBIENT_A    1
#define SFX_BANK_AMBIENT_B    2
#define SFX_BANK_AMBIENT_C    3
#define SFX_BANK_AMBIENT_D    4
#define SFX_BANK_EXPLOSION_LG 5
#define SFX_BANK_EXPLOSION_SM 6
#define SFX_BANK_BLIP         7
#define SFX_BANK_FANFARE      8
#define SFX_BANK_COUNT        9

/* ────────────────────────────────────────────────
 * Named event → bank mapping
 * ──────────────────────────────────────────────── */
#define SFX_SHOOT          SFX_BANK_BLIP
#define SFX_GEM_COLLECT    SFX_BANK_BLIP
#define SFX_ENEMY_SHOOT    SFX_BANK_BLIP
#define SFX_MINE_LAY       SFX_BANK_BLIP
#define SFX_EXPLOSION_SM   SFX_BANK_EXPLOSION_SM
#define SFX_EXPLOSION_LG   SFX_BANK_EXPLOSION_LG
#define SFX_PLAYER_DIE     SFX_BANK_EXPLOSION_LG
#define SFX_SMARTBOMB      SFX_BANK_EXPLOSION_LG
#define SFX_POWERUP        SFX_BANK_FANFARE
#define SFX_EXTRA_LIFE     SFX_BANK_FANFARE
#define SFX_LEVEL_CLEAR    SFX_BANK_FANFARE
#define SFX_GATE_OPEN      SFX_BANK_FANFARE
#define SFX_ENEMY_ENTER    SFX_BANK_BLIP      /* portal opens, enemy enters */
#define SFX_TITLE          SFX_BANK_TITLE

/* ────────────────────────────────────────────────
 * PCM playback channels
 * SGDK Z80 driver provides 2 PCM channels.
 * We use CH1 for short one-shots, CH2 for sustained.
 * ──────────────────────────────────────────────── */
#define SFX_CH_ONESHOT   SOUND_PCM_CH1
#define SFX_CH_SUSTAINED SOUND_PCM_CH2

/* ────────────────────────────────────────────────
 * API
 * ──────────────────────────────────────────────── */

/**
 * sfx_init()
 * Initialise the sound system. Call once at game start.
 */
void sfx_init(void);

/**
 * sfx_play(id)
 * Play a named SFX bank on the one-shot channel.
 * id = one of the SFX_* named constants above.
 */
void sfx_play(u8 id);

/**
 * sfx_play_sustained(id)
 * Play on the sustained channel (for longer sounds).
 */
void sfx_play_sustained(u8 id);

/**
 * sfx_stop()
 * Stop all PCM playback immediately.
 */
void sfx_stop(void);

#endif /* SFX_H */
