/*
 * sram.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Hall of Fame persistence via cartridge SRAM (battery-backed save)
 *
 * Most Genesis cartridges with save support use a small SRAM region
 * mapped at 0x200000–0x20FFFF (even bytes only) or via a mapper.
 * SGDK exposes this via SRAM_enable() / SRAM_disable() / SRAM_readByte()
 * / SRAM_writeByte(). The cart must have battery-backed SRAM.
 *
 * Save layout (512 bytes total — well within any SRAM budget)
 * ──────────────────────────────────────────────────────────────
 * Offset  Size  Content
 *      0     4  Magic "XQ2!" (0x58 0x51 0x32 0x21) — validates save
 *      4     1  Version byte (currently 1)
 *      5     1  Difficulty last used (0-3)
 *      6     2  Padding
 *      8   270  HOF data: 10 entries × 27 bytes
 *                  entry: 13 bytes name (null-term) + 4 bytes score + 2 bytes level
 *                         + 8 bytes padding = 27 bytes per entry
 *    278   234  Reserved / future use
 *
 * If the magic is missing or the version doesn't match, the HOF is
 * re-initialised to default values and the SRAM is rewritten.
 *
 * On carts without battery SRAM the writes are harmless (the
 * data just doesn't persist), and reads return 0xFF (unprogrammed).
 * The magic check catches this gracefully.
 */

#include <genesis.h>
#include "sram.h"
#include "screens.h"

/* ────────────────────────────────────────────────
 * Save layout constants
 * ──────────────────────────────────────────────── */
#define SAVE_MAGIC_0   0x58   /* 'X' */
#define SAVE_MAGIC_1   0x51   /* 'Q' */
#define SAVE_MAGIC_2   0x32   /* '2' */
#define SAVE_MAGIC_3   0x21   /* '!' */
#define SAVE_VERSION   1

#define SAVE_OFF_MAGIC      0
#define SAVE_OFF_VERSION    4
#define SAVE_OFF_DIFFICULTY 5
#define SAVE_OFF_PAD        6
#define SAVE_OFF_HOF        8
#define SAVE_HOF_ENTRY_SIZE 27
#define SAVE_HOF_ENTRIES    10
#define SAVE_HOF_TOTAL      (SAVE_HOF_ENTRIES * SAVE_HOF_ENTRY_SIZE)   /* 270 */
#define SAVE_TOTAL_SIZE     512

/* ────────────────────────────────────────────────
 * Internal: SRAM byte read/write wrappers
 * SGDK SRAM addresses are byte-addressed (even addresses on real hw)
 * ──────────────────────────────────────────────── */
static void sram_wr(u16 offset, u8 val)
{
    SRAM_writeByte(offset, val);
}

static u8 sram_rd(u16 offset)
{
    return (u8)SRAM_readByte(offset);
}

static void sram_wr_u32(u16 offset, u32 val)
{
    sram_wr(offset + 0, (u8)(val >> 24));
    sram_wr(offset + 1, (u8)(val >> 16));
    sram_wr(offset + 2, (u8)(val >>  8));
    sram_wr(offset + 3, (u8)(val      ));
}

static u32 sram_rd_u32(u16 offset)
{
    return ((u32)sram_rd(offset    ) << 24) |
           ((u32)sram_rd(offset + 1) << 16) |
           ((u32)sram_rd(offset + 2) <<  8) |
           ((u32)sram_rd(offset + 3)      );
}

static void sram_wr_u16(u16 offset, u16 val)
{
    sram_wr(offset,     (u8)(val >> 8));
    sram_wr(offset + 1, (u8)(val     ));
}

static u16 sram_rd_u16(u16 offset)
{
    return ((u16)sram_rd(offset) << 8) | sram_rd(offset + 1);
}

static void sram_wr_str(u16 offset, const char *s, u8 maxlen)
{
    u8 i = 0;
    while (s[i] && i < maxlen - 1) { sram_wr(offset + i, (u8)s[i]); i++; }
    sram_wr(offset + i, 0);
    /* Zero-pad remaining */
    while (i < maxlen) { sram_wr(offset + i, 0); i++; }
}

static void sram_rd_str(u16 offset, char *dst, u8 maxlen)
{
    u8 i = 0;
    while (i < maxlen - 1)
    {
        u8 c = sram_rd(offset + i);
        dst[i] = (c >= 32 && c < 128) ? (char)c : '\0';
        if (!c) { i++; break; }
        i++;
    }
    dst[i] = '\0';
}

/* ────────────────────────────────────────────────
 * sram_validate()
 * Returns TRUE if the SRAM contains a valid XQ2 save.
 * ──────────────────────────────────────────────── */
static u8 sram_validate(void)
{
    SRAM_enable();
    u8 ok = (sram_rd(SAVE_OFF_MAGIC    ) == SAVE_MAGIC_0 &&
             sram_rd(SAVE_OFF_MAGIC + 1) == SAVE_MAGIC_1 &&
             sram_rd(SAVE_OFF_MAGIC + 2) == SAVE_MAGIC_2 &&
             sram_rd(SAVE_OFF_MAGIC + 3) == SAVE_MAGIC_3 &&
             sram_rd(SAVE_OFF_VERSION  ) == SAVE_VERSION);
    SRAM_disable();
    return ok;
}

/* ────────────────────────────────────────────────
 * sram_load()
 * Load HOF and difficulty from SRAM.
 * Returns TRUE if valid data was found and loaded.
 * ──────────────────────────────────────────────── */
u8 sram_load(HofEntry *hof, u8 entries, u8 *difficulty)
{
    if (!sram_validate()) return FALSE;

    SRAM_enable();

    /* Load difficulty */
    u8 diff = sram_rd(SAVE_OFF_DIFFICULTY);
    if (diff >= DIFFICULTY_COUNT) diff = DIFFICULTY_NORMAL;
    if (difficulty) *difficulty = diff;

    /* Load HOF entries */
    for (u8 i = 0; i < entries && i < SAVE_HOF_ENTRIES; i++)
    {
        u16 base = SAVE_OFF_HOF + i * SAVE_HOF_ENTRY_SIZE;
        sram_rd_str(base, hof[i].name, 13);
        hof[i].score = sram_rd_u32(base + 13);
        hof[i].level = sram_rd_u16(base + 17);
    }

    SRAM_disable();
    return TRUE;
}

/* ────────────────────────────────────────────────
 * sram_save()
 * Write the current HOF and difficulty to SRAM.
 * ──────────────────────────────────────────────── */
void sram_save(const HofEntry *hof, u8 entries, u8 difficulty)
{
    SRAM_enable();

    /* Write magic and version */
    sram_wr(SAVE_OFF_MAGIC,     SAVE_MAGIC_0);
    sram_wr(SAVE_OFF_MAGIC + 1, SAVE_MAGIC_1);
    sram_wr(SAVE_OFF_MAGIC + 2, SAVE_MAGIC_2);
    sram_wr(SAVE_OFF_MAGIC + 3, SAVE_MAGIC_3);
    sram_wr(SAVE_OFF_VERSION,   SAVE_VERSION);
    sram_wr(SAVE_OFF_DIFFICULTY, difficulty);
    sram_wr(SAVE_OFF_PAD,       0);
    sram_wr(SAVE_OFF_PAD + 1,   0);

    /* Write HOF */
    for (u8 i = 0; i < entries && i < SAVE_HOF_ENTRIES; i++)
    {
        u16 base = SAVE_OFF_HOF + i * SAVE_HOF_ENTRY_SIZE;
        sram_wr_str(base,      hof[i].name, 13);
        sram_wr_u32(base + 13, hof[i].score);
        sram_wr_u16(base + 17, hof[i].level);
        /* Pad remaining bytes */
        for (u8 p = 19; p < SAVE_HOF_ENTRY_SIZE; p++)
            sram_wr(base + p, 0);
    }

    /* Zero reserved area */
    for (u16 off = SAVE_OFF_HOF + SAVE_HOF_TOTAL; off < SAVE_TOTAL_SIZE; off++)
        sram_wr(off, 0);

    SRAM_disable();
}

/* ────────────────────────────────────────────────
 * sram_erase()
 * Wipe the SRAM save (called from options/reset).
 * ──────────────────────────────────────────────── */
void sram_erase(void)
{
    SRAM_enable();
    for (u16 i = 0; i < SAVE_TOTAL_SIZE; i++)
        sram_wr(i, 0);
    SRAM_disable();
}

/* ────────────────────────────────────────────────
 * High-level bridge functions called from main.c
 * These access the HOF table that lives in screens.c
 * via the exposed screen_hof_get/set API.
 * ──────────────────────────────────────────────── */

/* Forward declarations for screens.c internal HOF */
extern HofEntry g_hof[];         /* defined in screens.c */
extern u8       g_hof_initialised;

/**
 * sram_startup()
 * Called once at boot. Loads HOF + difficulty from SRAM.
 * If no valid save, defaults are used.
 */
void sram_startup(void)
{
    u8 diff = DIFFICULTY_NORMAL;

    if (sram_load(g_hof, 10, &diff))
    {
        g_hof_initialised = TRUE;
        /* Apply loaded difficulty as the default */
        /* screen_set_difficulty(diff); */   /* add this accessor if needed */
    }
    /* If load failed, g_hof stays zero-initialised
     * and hof_init_defaults() will be called on first HOF access */
}

/**
 * sram_save_hof()
 * Write current HOF and difficulty to SRAM.
 * Called after each game over.
 */
void sram_save_hof(void)
{
    if (!g_hof_initialised) return;
    sram_save(g_hof, 10, screen_get_difficulty_index());
}
