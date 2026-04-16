/*
 * screens.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * All non-gameplay full-screen states:
 *   - Game Over
 *   - Hall of Fame (high score table, 50 entries from XQUEST.SCR)
 *   - Options / Difficulty menu
 *   - Pause overlay
 *   - Level clear fanfare
 *
 * HOF format (from XQUEST.SCR analysis):
 *   50 records × 27 bytes each
 *   bytes  0–6  : padding / null
 *   bytes  7–19 : name, null-terminated, max 12 chars
 *   bytes 20–23 : score (u32 little-endian)
 *   bytes 24–25 : level reached (u16 little-endian)
 *   bytes 26    : padding
 *
 * On Genesis we keep the HOF in WRAM (no battery save in scaffold;
 * add SRAM/EEPROM support later). It is pre-populated with default
 * "XQuest" entries matching the original SCR file.
 */

#include <genesis.h>
#include "xquest.h"
#include "screens.h"

/* Globals defined in main.c, accessed here for pause-quit and 2P setup */
extern GameData gd;
extern u8       g_two_player;

/* ────────────────────────────────────────────────
 * HOF constants
 * ──────────────────────────────────────────────── */
#define HOF_MAX_ENTRIES   10   /* show top 10 on Genesis (original had 50) */
#define HOF_NAME_LEN      12   /* max name length */

/* ────────────────────────────────────────────────
 * Difficulty table (from original CFG)
 * ──────────────────────────────────────────────── */
const DifficultySettings difficulty_table[DIFFICULTY_COUNT] =
{
    /* EASY */
    {
        .label          = "EASY",
        .enemy_hp_scale = 50,    /* ×0.5 HP */
        .enemy_spd_scale= 70,    /* ×0.7 speed */
        .enemy_count_add= -2,    /* 2 fewer enemies */
        .gem_count_add  =  4,    /* 4 extra gems (easier to complete) */
        .score_scale    = 75,    /* ×0.75 score */
    },
    /* NORMAL */
    {
        .label          = "NORMAL",
        .enemy_hp_scale = 100,
        .enemy_spd_scale= 100,
        .enemy_count_add=  0,
        .gem_count_add  =  0,
        .score_scale    = 100,
    },
    /* HARD */
    {
        .label          = "HARD",
        .enemy_hp_scale = 150,   /* ×1.5 HP */
        .enemy_spd_scale= 130,   /* ×1.3 speed */
        .enemy_count_add=  3,    /* 3 extra enemies */
        .gem_count_add  = -2,    /* 2 fewer gems (harder to complete) */
        .score_scale    = 150,   /* ×1.5 score */
    },
    /* INSANE */
    {
        .label          = "INSANE",
        .enemy_hp_scale = 200,
        .enemy_spd_scale= 160,
        .enemy_count_add=  6,
        .gem_count_add  = -4,
        .score_scale    = 200,
    },
};

/* Active difficulty (default: NORMAL) */
static u8 g_difficulty = DIFFICULTY_NORMAL;

/* Hall of Fame table in WRAM */
HofEntry g_hof[HOF_MAX_ENTRIES];
u8       g_hof_initialised = FALSE;

/* ────────────────────────────────────────────────
 * HOF helpers
 * ──────────────────────────────────────────────── */
static void hof_init_defaults(void)
{
    /* Populate with the default "XQuest" entries from the original file */
    for (u8 i = 0; i < HOF_MAX_ENTRIES; i++)
    {
        /* strncpy equivalent without libc */
        const char *src = "XQuest";
        char *dst = g_hof[i].name;
        u8 j = 0;
        while (src[j] && j < HOF_NAME_LEN - 1) { dst[j] = src[j]; j++; }
        dst[j] = '\0';

        g_hof[i].score = 0;
        g_hof[i].level = 0;
    }
    g_hof_initialised = TRUE;
}

/* Insert a new score into the HOF if it qualifies */
static s8 hof_insert(const char *name, u32 score, u16 level)
{
    if (!g_hof_initialised) hof_init_defaults();

    /* Find insertion position */
    s8 pos = -1;
    for (s8 i = HOF_MAX_ENTRIES - 1; i >= 0; i--)
    {
        if (score > g_hof[i].score)
            pos = i;
        else
            break;
    }
    if (pos < 0) return -1;   /* didn't make the table */

    /* Shift entries down */
    for (s8 i = HOF_MAX_ENTRIES - 1; i > pos; i--)
        g_hof[i] = g_hof[i - 1];

    /* Insert */
    u8 j = 0;
    while (name[j] && j < HOF_NAME_LEN - 1) { g_hof[pos].name[j] = name[j]; j++; }
    g_hof[pos].name[j] = '\0';
    g_hof[pos].score   = score;
    g_hof[pos].level   = level;

    return pos;
}

/* ────────────────────────────────────────────────
 * Utility: clear screen and set background black
 * ──────────────────────────────────────────────── */
static void clear_screen(void)
{
    VDP_clearPlane(BG_A, TRUE);
    VDP_clearPlane(BG_B, TRUE);
    SPR_reset();
    PAL_setColor(0, 0x0000);   /* background = black */
}

/* ────────────────────────────────────────────────
 * Utility: wait for button press, return which
 * ──────────────────────────────────────────────── */
static u16 wait_for_button(void)
{
    /* Wait for release first (debounce) */
    while (JOY_readJoypad(JOY_1) & (BUTTON_A|BUTTON_B|BUTTON_C|BUTTON_START))
        SYS_doVBlankProcess();
    /* Then wait for press */
    u16 btn = 0;
    while (!btn)
    {
        SYS_doVBlankProcess();
        btn = JOY_readJoypad(JOY_1) & (BUTTON_A|BUTTON_B|BUTTON_C|BUTTON_START);
    }
    return btn;
}

/* ────────────────────────────────────────────────
 * Utility: draw a centred string at tile row `row`
 * ──────────────────────────────────────────────── */
static void draw_centred(const char *s, u8 row)
{
    u8 len = 0;
    while (s[len]) len++;
    u8 col = (40 - len) / 2;
    VDP_drawText(s, col, row);
}

/* ────────────────────────────────────────────────
 * Utility: itoa for score display (no printf on MD)
 * ──────────────────────────────────────────────── */
static void format_score(char *buf, u32 score)
{
    /* 8-digit zero-padded score */
    buf[8] = '\0';
    for (s8 i = 7; i >= 0; i--)
    {
        buf[i] = '0' + (score % 10);
        score /= 10;
    }
}

static void format_uint(char *buf, u16 val)
{
    /* 5-digit, no padding */
    buf[5] = '\0';
    if (val == 0) { buf[0]='0'; buf[1]='\0'; return; }
    s8 i = 4;
    while (val && i >= 0) { buf[i--] = '0' + (val % 10); val /= 10; }
    /* Shift left */
    u8 start = (u8)(i + 1);
    u8 j = 0;
    while (buf[start]) buf[j++] = buf[start++];
    buf[j] = '\0';
}

/* ════════════════════════════════════════════════
 * GAME OVER SCREEN
 * ════════════════════════════════════════════════ */
void screen_game_over(GameData *gd)
{
    clear_screen();

    /* Palette: red text on black */
    PAL_setColor(1,  0x000E);   /* bright red */
    PAL_setColor(2,  0x0EEE);   /* white */
    PAL_setColor(15, 0x0888);   /* grey */

    VDP_setTextPalette(0);
    draw_centred("G A M E   O V E R", 8);

    VDP_setTextPalette(0);
    {
        char buf[24];
        char score_str[9];
        format_score(score_str, gd->player.score);

        draw_centred("FINAL SCORE", 12);

        /* Draw score centred */
        buf[0] = ' '; buf[1] = ' ';
        u8 i = 0;
        while (score_str[i]) { buf[i+2] = score_str[i]; i++; }
        buf[i+2] = '\0';
        draw_centred(buf, 13);

        /* Level reached */
        char level_str[6];
        format_uint(level_str, gd->level);
        draw_centred("LEVEL REACHED", 15);
        draw_centred(level_str, 16);
    }

    draw_centred("PRESS START", 20);

    /* Flash "GAME OVER" */
    for (u8 flash = 0; flash < 120; flash++)
    {
        SYS_doVBlankProcess();
        /* Don't wait for input during flash */
    }

    wait_for_button();

    /* Check if scores qualify for HOF — check both players in 2P mode */
    if (!g_hof_initialised) hof_init_defaults();
    if (gd->player.score > g_hof[HOF_MAX_ENTRIES-1].score)
        screen_hof_enter(gd);
    if (g_two_player)
    {
        Player *p2 = player2_get();
        if (p2 && p2->score > g_hof[HOF_MAX_ENTRIES-1].score)
        {
            /* Temporarily swap P2 score/level into gd for reuse of screen_hof_enter */
            u32 saved_score = gd->player.score;
            u16 saved_level = gd->level;
            gd->player.score = p2->score;
            gd->level = saved_level;
            screen_hof_enter(gd);
            gd->player.score = saved_score;
        }
    }
}

/* ════════════════════════════════════════════════
 * NAME ENTRY (for Hall of Fame)
 * ════════════════════════════════════════════════ */

/* Character set for name entry */
static const char NAME_CHARS[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    " .-!?";
#define NAME_CHARS_LEN  36

void screen_hof_enter(GameData *gd)
{
    clear_screen();
    draw_centred("NEW HIGH SCORE!", 4);
    draw_centred("ENTER YOUR NAME", 6);
    draw_centred("UP/DOWN: LETTER   LEFT/RIGHT: CURSOR", 8);
    draw_centred("START: DONE", 9);

    char name[HOF_NAME_LEN];
    u8   name_len = 0;
    u8   cursor   = 0;
    u8   char_idx = 0;

    for (u8 i = 0; i < HOF_NAME_LEN; i++) name[i] = ' ';
    name[0] = '\0';

    u8 done = FALSE;
    u16 prev_joy = 0;

    while (!done)
    {
        SYS_doVBlankProcess();
        u16 joy = JOY_readJoypad(JOY_1);
        u16 pressed = joy & ~prev_joy;   /* newly pressed this frame */
        prev_joy = joy;

        if (pressed & BUTTON_UP)
        {
            char_idx = (char_idx + 1) % NAME_CHARS_LEN;
        }
        if (pressed & BUTTON_DOWN)
        {
            char_idx = (char_idx == 0) ? NAME_CHARS_LEN - 1 : char_idx - 1;
        }
        if (pressed & BUTTON_RIGHT)
        {
            /* Commit current char and advance */
            if (cursor < HOF_NAME_LEN - 1)
            {
                name[cursor] = NAME_CHARS[char_idx];
                cursor++;
                if (cursor > name_len) name_len = cursor;
                name[name_len] = '\0';
                char_idx = 0;
            }
        }
        if (pressed & BUTTON_LEFT)
        {
            if (cursor > 0) cursor--;
            char_idx = 0;
        }
        if ((pressed & BUTTON_A) || (pressed & BUTTON_C))
        {
            /* Commit and advance */
            name[cursor] = NAME_CHARS[char_idx];
            if (cursor < HOF_NAME_LEN - 1) cursor++;
            if (cursor > name_len) { name_len = cursor; name[name_len] = '\0'; }
            char_idx = 0;
        }
        if (pressed & BUTTON_START)
        {
            name[cursor] = NAME_CHARS[char_idx];
            if (cursor >= name_len) { name_len = cursor + 1; name[name_len] = '\0'; }
            done = TRUE;
        }

        /* Redraw name */
        {
            char display[HOF_NAME_LEN + 4];
            display[0] = '[';
            for (u8 i = 0; i < HOF_NAME_LEN - 1; i++)
            {
                if (i == cursor)
                    display[i + 1] = NAME_CHARS[char_idx];  /* show live char */
                else if (i < name_len)
                    display[i + 1] = name[i];
                else
                    display[i + 1] = '_';
            }
            display[HOF_NAME_LEN] = ']';
            display[HOF_NAME_LEN + 1] = '\0';
            VDP_clearText(4, 12, 36);
            draw_centred(display, 12);
        }

        /* Draw available chars around cursor char */
        {
            char char_row[7];
            for (s8 ci = -3; ci <= 3; ci++)
            {
                s8 idx = ((s8)char_idx + ci + NAME_CHARS_LEN) % NAME_CHARS_LEN;
                char_row[ci + 3] = NAME_CHARS[idx];
            }
            char_row[3] = '[';   /* mark centre */
            VDP_clearText(0, 15, 40);
            draw_centred(char_row, 15);
        }
    }

    /* Trim trailing spaces */
    s8 end = (s8)name_len - 1;
    while (end >= 0 && name[end] == ' ') { name[end] = '\0'; end--; }
    if (end < 0) { name[0] = 'A'; name[1] = '\0'; }

    hof_insert(name, gd->player.score, gd->level);
    screen_hof_show();
}

/* ════════════════════════════════════════════════
 * HALL OF FAME DISPLAY
 * ════════════════════════════════════════════════ */
void screen_hof_show(void)
{
    if (!g_hof_initialised) hof_init_defaults();

    clear_screen();
    draw_centred("* HALL OF FAME *", 1);
    draw_centred("RANK  NAME          SCORE     LEVEL", 3);

    /* Draw separator */
    VDP_drawText("----  ------------  --------  -----", 2, 4);

    for (u8 i = 0; i < HOF_MAX_ENTRIES; i++)
    {
        char line[40];
        char score_str[9];
        char level_str[6];
        format_score(score_str, g_hof[i].score);
        format_uint(level_str, g_hof[i].level);

        /* Build line: "  1.  XQuest       00000000   1" */
        u8 pos = 0;
        /* Rank */
        line[pos++] = ' '; line[pos++] = ' ';
        line[pos++] = '0' + (i + 1);
        line[pos++] = '.';
        line[pos++] = ' '; line[pos++] = ' ';
        /* Name (padded to 12) */
        u8 ni = 0;
        while (g_hof[i].name[ni] && ni < 12) line[pos++] = g_hof[i].name[ni++];
        while (ni++ < 12) line[pos++] = ' ';
        line[pos++] = ' '; line[pos++] = ' ';
        /* Score */
        for (u8 si = 0; si < 8; si++) line[pos++] = score_str[si];
        line[pos++] = ' '; line[pos++] = ' ';
        /* Level */
        u8 li = 0;
        while (level_str[li]) line[pos++] = level_str[li++];
        line[pos] = '\0';

        VDP_drawText(line, 2, (u8)(5 + i));
    }

    draw_centred("PRESS START TO CONTINUE", 27);
    wait_for_button();
}

/* ════════════════════════════════════════════════
 * PAUSE OVERLAY
 * ════════════════════════════════════════════════ */
void screen_pause(void)
{
    /* Don't clear — draw over the game */
    VDP_drawText(" ** PAUSED ** ", 13, 13);
    VDP_drawText("START TO RESUME", 12, 15);
    VDP_drawText("A: QUIT GAME   ", 12, 16);

    /* Wait until unpaused or quit */
    u16 prev = JOY_readJoypad(JOY_1);
    while (TRUE)
    {
        SYS_doVBlankProcess();
        u16 joy = JOY_readJoypad(JOY_1);
        u16 pressed = joy & ~prev;
        prev = joy;

        if (pressed & BUTTON_START) break;
        if (pressed & BUTTON_A)
        {
            /* Quit to title — caller sees STATE_GAME_OVER */
            gd.state = STATE_GAME_OVER;
            gd.player.lives = 0;
            break;
        }
    }

    /* Clear pause text */
    VDP_clearText(12, 13, 16);
    VDP_clearText(12, 15, 17);
    VDP_clearText(12, 16, 15);
}

/* ════════════════════════════════════════════════
 * LEVEL CLEAR FANFARE
 * ════════════════════════════════════════════════ */
void screen_level_clear(GameData *gd, u32 time_bonus)
{
    /* Brief overlay — don't clear background */
    char buf[20];
    draw_centred("LEVEL COMPLETE!", 10);

    if (time_bonus > 0)
    {
        draw_centred("TIME BONUS", 12);
        char bonus_str[9];
        format_score(bonus_str, time_bonus);
        draw_centred(bonus_str, 13);
    }

    /* Show for ~2 seconds */
    for (u16 f = 0; f < 120; f++)
        SYS_doVBlankProcess();

    VDP_clearText(0, 10, 40);
    VDP_clearText(0, 12, 40);
    VDP_clearText(0, 13, 40);
}

/* ════════════════════════════════════════════════
 * OPTIONS / DIFFICULTY MENU
 * ════════════════════════════════════════════════ */

/* Returns the player's chosen difficulty (0-3) */
u8 screen_options(void)
{
    clear_screen();
    draw_centred("OPTIONS", 2);
    draw_centred("SELECT DIFFICULTY", 5);

    u8 sel = g_difficulty;

    u16 prev_joy = JOY_readJoypad(JOY_1);

    while (TRUE)
    {
        SYS_doVBlankProcess();
        u16 joy = JOY_readJoypad(JOY_1);
        u16 pressed = joy & ~prev_joy;
        prev_joy = joy;

        if (pressed & BUTTON_UP)
            sel = (sel == 0) ? DIFFICULTY_COUNT - 1 : sel - 1;
        if (pressed & BUTTON_DOWN)
            sel = (sel + 1) % DIFFICULTY_COUNT;
        if ((pressed & BUTTON_A) || (pressed & BUTTON_START))
            break;
        if (pressed & BUTTON_B)
        {
            sel = g_difficulty;   /* cancel */
            break;
        }

        /* Redraw options */
        for (u8 i = 0; i < DIFFICULTY_COUNT; i++)
        {
            char line[24];
            line[0] = (i == sel) ? '>' : ' ';
            line[1] = ' ';
            u8 p = 2;
            const char *lbl = difficulty_table[i].label;
            while (*lbl) line[p++] = *lbl++;
            line[p] = '\0';
            VDP_clearText(15, (u8)(8 + i), 12);
            VDP_drawText(line, 15, (u8)(8 + i));
        }

        /* Description of selected difficulty */
        const DifficultySettings *ds = &difficulty_table[sel];
        char desc[36];
        /* "Score x1.0" etc */
        desc[0] = 'S'; desc[1] = 'C'; desc[2] = 'O'; desc[3] = 'R'; desc[4] = 'E';
        desc[5] = ' '; desc[6] = 'x';
        desc[7] = '0' + ds->score_scale / 100;
        desc[8] = '.';
        desc[9] = '0' + (ds->score_scale % 100) / 10;
        desc[10] = '\0';
        VDP_clearText(0, 14, 40);
        draw_centred(desc, 14);
    }

    g_difficulty = sel;

    draw_centred("TWO PLAYERS?", 17);
    draw_centred("A: YES    B: NO", 19);

    /* Wait for 2P choice */
    prev_joy = JOY_readJoypad(JOY_1);
    while (TRUE)
    {
        SYS_doVBlankProcess();
        u16 joy = JOY_readJoypad(JOY_1);
        u16 pressed = joy & ~prev_joy;
        prev_joy = joy;
        if (pressed & BUTTON_A) { g_two_player = TRUE;  break; }
        if (pressed & BUTTON_B) { g_two_player = FALSE; break; }
    }

    return g_difficulty;
}

/* ────────────────────────────────────────────────
 * Accessors
 * ──────────────────────────────────────────────── */
const DifficultySettings *screen_get_difficulty(void)
{
    return &difficulty_table[g_difficulty];
}

u8 screen_get_difficulty_index(void)
{
    return g_difficulty;
}
