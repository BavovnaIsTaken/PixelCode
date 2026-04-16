/*
 * main.c - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Entry point and main game loop
 */

#include <genesis.h>
#include "xquest.h"
#include "tilemap.h"
#include "screens.h"
#include "player2.h"
#include "sram.h"
#include "resources.h"

/* ============================================================
 * GLOBAL STATE
 * ============================================================ */
GameData gd;           /* global (accessed by screens.c pause quit) */
u32 g_frame_count;     /* global frame counter, used by AI in enemy.c */
u8 g_two_player = FALSE;   /* defined here, declared extern in player2.h */
fix16 g_game_speed = FIX16(1);  /* game speed scalar, reset each level */

/* ============================================================
 * FORWARD DECLARATIONS
 * ============================================================ */
static void sys_init(void);
static void palettes_load(void);
static void vblank_callback(void);

/* ============================================================
 * ENTRY POINT
 * ============================================================ */
int main(bool hard_reset)
{
    sys_init();
    palettes_load();

    /* ---- Load SRAM save (HOF + difficulty) ---- */
    sram_startup();

    /* ---- Title screen ---- */
    title_show();

    /* ---- Main game loop: title -> options -> game -> game over -> repeat ---- */
    while (TRUE)
    {
        /* Options menu (difficulty + 2P) */
        screen_options();

        /* Init and run one full game session */
        game_init();
        game_run();

        /* Game over screen + HOF check (may update HOF) */
        screen_game_over(&gd);

        /* Persist HOF to SRAM after each game */
        sram_save_hof();
    }

    return 0;
}

/* ============================================================
 * SYSTEM INITIALISATION
 * ============================================================ */
static void sys_init(void)
{
    /* Set VDP plane size to 64×64 tiles (512×512 px) BEFORE SPR_initEx.
     * This must happen first — SPR_initEx sets up internal VRAM layout
     * that depends on the plane size already being configured.
     * We need 512×512 to hold the 392×320 world with hardware scrolling. */
    VDP_setPlaneSize(64, 64, TRUE);

    /* Initialise SGDK sprite engine with 512 VRAM tiles reserved */
    /* 768 tiles: ship(216) + 15 enemy types(~300) + effects(~100) + bullets(~5)
     * 512 was too small — bullet/effect sprites silently became transparent. */
    SPR_initEx(768);

    /* Set display to hi-res mode (320×224) */
    VDP_setScreenWidth320();

    /* Full-screen horizontal scroll mode (one scroll value for whole screen) */
    VDP_setScrollingMode(HSCROLL_PLANE, VSCROLL_PLANE);

    /* Enable vertical interrupt for frame timing */
    SYS_setVIntCallback(vblank_callback);

    /* Set background colour to black */
    VDP_setBackgroundColor(0);

    /* Random seed from VDP counter */
    setRandomSeed(GET_VCOUNTER);

    g_frame_count = 0;
}

/* ============================================================
 * PALETTE LOADING
 * ============================================================ */
static void palettes_load(void)
{
    PAL_setPalette(PAL_BG,      pal_bg.data,      CPU);
    PAL_setPalette(PAL_ACTIVE,  pal_active.data,  CPU);
    PAL_setPalette(PAL_COLLECT, pal_collect.data, CPU);
    PAL_setPalette(PAL_ENEMY,   pal_enemy.data,   CPU);
}

/* ============================================================
 * GAME INIT  (called at start of each life/run)
 * ============================================================ */
void game_init(void)
{
    /* Release all sprites from prior screens (title, options, etc.).
     * Must happen before memset so SPR_addSprite calls in player_init
     * and level_generate find a clean sprite engine. */
    SPR_reset();

    /* Zero the game state */
    memset(&gd, 0, sizeof(GameData));

    /* Portal idle sentinel: -1 means no portal animation running.
     * memset gives 0 which would immediately trigger — set explicitly. */
    gd.portal_left_cd  = -1;
    gd.portal_right_cd = -1;

    /* Camera starts centred on the world */
    gd.cam_x = CAM_MAX_X / 2;  /* start viewport centred on world */
    gd.cam_y = CAM_MAX_Y / 2;

    /* Reload palettes — screens (title, options, game_over) may have
     * modified individual palette entries. */
    PAL_setPalette(PAL_BG,      pal_bg.data,      CPU);
    PAL_setPalette(PAL_ACTIVE,  pal_active.data,  CPU);
    PAL_setPalette(PAL_COLLECT, pal_collect.data, CPU);
    PAL_setPalette(PAL_ENEMY,   pal_enemy.data,   CPU);

    /* Reset game speed ramp */
    g_game_speed = FIX16(1);

    /* Initial player positions */
    player_init(&gd.player,
                FIX16(WORLD_W / 2),
                FIX16(WORLD_H / 2));
    /* Player 2 starts at offset position */
    player2_init(FIX16(WORLD_W / 4), FIX16(WORLD_H / 2));

    gd.level  = 1;
    gd.state  = STATE_GAME;
    gd.difficulty = screen_get_difficulty_index();

    sfx_init();

    /* Load background tileset into VRAM, configure plane size */
    tilemap_init();

    /* Generate first level (populates gd.tilemap[][]) */
    level_generate(&gd, gd.level);

    /* Render the level tilemap to VDP plane B */
    tilemap_draw(&gd);

    /* Clear plane A (HUD + sprite overlay) */
    VDP_clearPlane(BG_A, TRUE);

    hud_draw(&gd);
}

/* ============================================================
 * MAIN GAME LOOP
 * ============================================================ */
void game_run(void)
{
    while (gd.state == STATE_GAME || gd.state == STATE_PAUSED)
    {
        SYS_doVBlankProcess();
        g_frame_count++;

        u16 joy = JOY_readJoypad(JOY_1);

        /* Pause: START button opens pause overlay */
        if (joy & BUTTON_START)
        {
            gd.state = STATE_PAUSED;
            screen_pause();          /* blocks until resumed or quit */
            if (gd.state != STATE_GAME_OVER)
                gd.state = STATE_GAME;
            continue;
        }

        if (gd.state == STATE_PAUSED) continue;

        /* ---- Update ---- */
        player_update(&gd.player, &gd);
        player2_update(&gd);            /* no-op if g_two_player == FALSE */
        enemies_update(&gd);
        bullets_update(&gd);
        gems_update(&gd);
        mines_update(&gd);
        powercharges_update(&gd);
        explosions_update(&gd);
        supercrystals_update(&gd);
        powerup_tick(&gd);
        collision_check_all(&gd);
        player2_collision(&gd);         /* no-op if g_two_player == FALSE */
        level_check_complete(&gd);

        /* ---- Draw ---- */
        camera_update(&gd);
        SPR_update();
        hud_draw(&gd);

        /* ---- End check ---- */
        u8 p1_dead = (!gd.player.active || gd.player.lives == 0);
        u8 p2_dead = (!player2_is_active());
        if (p1_dead && (!g_two_player || p2_dead))
            gd.state = STATE_GAME_OVER;
    }
}

/* ============================================================
 * VBLANK CALLBACK
 * ============================================================ */
static void vblank_callback(void)
{
    /* SGDK handles DMA here automatically */
}
