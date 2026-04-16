/*
 * xquest.h - XQuest 2 for Sega Genesis (SGDK 1.70)
 * Global definitions, types and constants
 */

#ifndef XQUEST_H
#define XQUEST_H

#include <genesis.h>

/* ============================================================
 * SCREEN / DISPLAY
 * ============================================================ */
#define SCREEN_W            320
#define SCREEN_H            224     /* Genesis native (cropped from original 240) */
#define PLAYFIELD_W         320
#define PLAYFIELD_H         208     /* minus HUD bar top+bottom */
#define HUD_HEIGHT           16

/* World dimensions (logical play area, larger than viewport — same as original).
 * Original: PageWidth=392, PageHeight=320, PhysicalPageWidth=320,
 *           SplitScreenLine=217 (our PLAYFIELD_H=208, close enough).
 * Scroll range: H = WORLD_W - SCREEN_W = 72 px
 *               V = WORLD_H - PLAYFIELD_H = 112 px */
#define WORLD_W             392
#define WORLD_H             320

/* Camera scroll limits */
#define CAM_MAX_X           (WORLD_W - SCREEN_W)    /* 72  */
#define CAM_MAX_Y           (WORLD_H - PLAYFIELD_H) /* 112 */

/* Scroll border: how close the player gets to the viewport edge before the
 * camera starts following. Matches original ScreenHBorder/ScreenVBorder. */
#define CAM_BORDER_H        140     /* original: PhysicalPageWidth/2 - 20 */
#define CAM_BORDER_V        104     /* original: SplitScrnScanLine/2     */

/* Tile dimensions */
#define TILE_W               16
#define TILE_H               16
#define MAP_TILES_W          25     /* WORLD_W / 16  (ceil(392/16)=25)   */
#define MAP_TILES_H          20     /* WORLD_H / 16  (ceil(320/16)=20)   */

/* ============================================================
 * GAME CONSTANTS (preserved from original)
 * ============================================================ */
#define MAX_GEMS             64
#define MAX_ENEMIES          24
#define MAX_BULLETS          32
#define MAX_MINES            20
#define MAX_POWERCHARGES      4
#define MAX_EXPLOSIONS       16

#define SCORE_EXTRA_LIFE_BASE  15000   /* first extra life at 15k pts */
#define INITIAL_LIVES            3
#define MAX_SMARTBOMBS           9

/* Ship physics (8-direction, inertia-based) */
#define SHIP_ACCEL             (FIX16(0.156))  /* original: 10/64 px per frame */
#define SHIP_MAX_SPEED         (FIX16(3.0))    /* original: 640/64 = 10; we cap at 6 for Genesis screen */
#define SHIP_FRICTION          (FIX16(0.82))   /* applied only when no key held */
#define SHIP_ACCEL_FRAMES      8               /* frames to reach ~63% of max speed */
#define SHIP_FIRE_COOLDOWN      6    /* frames between shots */
#define BULLET_SPEED           (FIX16(8.0))    /* 8 px/frame — fast, crosses 320px screen in ~0.67s */

/* Enemy counts grow with level */
#define DIFFICULTY_SCALE(lvl)  (MIN((lvl) / 5, 4))

/* ============================================================
 * PALETTE INDICES
 * ============================================================ */
#define PAL_BG        PAL0    /* background tiles */
#define PAL_ACTIVE    PAL1    /* player, bullets, mines */
#define PAL_COLLECT   PAL2    /* gems, gate, powerups */
#define PAL_ENEMY     PAL3    /* enemies, fx */

/* ============================================================
 * SPRITE TILE INDICES (set by rescomp) - forward declarations
 * All sprites extracted directly from xquest.gfx with correct palette.
 * ============================================================ */

/* Player & objects */
extern const SpriteDefinition spr_ship;           /* 16x16, 24 frames (8-dir × 3 anim) */
extern const SpriteDefinition spr_mine;           /* 11x11, 1 frame  */
extern const SpriteDefinition spr_enemy_mine;     /* 7x7,   1 frame  */
extern const SpriteDefinition spr_bullet_player;  /* 2x2,   1 frame  */
extern const SpriteDefinition spr_smartbomb;      /* 11x11, 1 frame  */

/* Gems / gate / portals / powerups */
extern const SpriteDefinition spr_gem;            /* crystal 11x11, 1 frame  */
extern const SpriteDefinition spr_supercrystal;   /* 16x16,  6 frames        */
extern const SpriteDefinition spr_gate;           /* gate_left  16x14, 1 fr  */
extern const SpriteDefinition spr_gate_right;     /* gate_right 16x14, 1 fr  */
extern const SpriteDefinition spr_portal;         /* portal_left  20x20, 6 fr */
extern const SpriteDefinition spr_portal_right;   /* portal_right 20x20, 6 fr */
extern const SpriteDefinition spr_powercharge;    /* attractor 13x13, 1 frame */
extern const SpriteDefinition spr_corner_tl;      /* gate corners 10x10       */
extern const SpriteDefinition spr_corner_tr;
extern const SpriteDefinition spr_corner_bl;
extern const SpriteDefinition spr_corner_br;

/* FX */
extern const SpriteDefinition spr_explosion;      /* 23x23, 6 frames */

/* Enemy bullets */
extern const SpriteDefinition spr_bullet_green;    /* Zinger/Doinger 3x3 */
extern const SpriteDefinition spr_bullet_yellow;   /* Snipe 3x3          */
extern const SpriteDefinition spr_bullet_purple;   /* Retaliator 4x4     */
extern const SpriteDefinition spr_bullet_buckshot; /* Buckshot 4x4       */

/* Enemies — every type now has its own unique sprite */
extern const SpriteDefinition spr_grunger;         /* 11x11, 4 fr */
extern const SpriteDefinition spr_zippo;           /* 11x11, 4 fr */
extern const SpriteDefinition spr_zinger;          /* 16x16, 4 fr */
extern const SpriteDefinition spr_vince;           /* 16x16, 4 fr */
extern const SpriteDefinition spr_miner;           /* 12x12, 4 fr */
extern const SpriteDefinition spr_meeby;           /* 20x20, 6 fr */
extern const SpriteDefinition spr_retaliator;      /* 11x13, 4 fr */
extern const SpriteDefinition spr_terrier;         /* 21x8,  4 fr */
extern const SpriteDefinition spr_doinger;         /* 12x12, 4 fr */
extern const SpriteDefinition spr_snipe;           /* 9x9,   4 fr */
extern const SpriteDefinition spr_tribbler;        /* 14x14, 4 fr */
extern const SpriteDefinition spr_tribble_frag;    /* 6x6,   4 fr */
extern const SpriteDefinition spr_buckshot;        /* 11x11, 4 fr */
extern const SpriteDefinition spr_cluster;         /* 9x9,   4 fr */
extern const SpriteDefinition spr_sticktight;      /* 11x11, 4 fr */
extern const SpriteDefinition spr_repulsor;        /* 12x12, 6 fr */

/* SFX data arrays and sizes (generated by rescomp WAV) */
extern const u8 sfx_0[];  extern u32 sfx_0_size;
extern const u8 sfx_1[];  extern u32 sfx_1_size;
extern const u8 sfx_2[];  extern u32 sfx_2_size;
extern const u8 sfx_3[];  extern u32 sfx_3_size;
extern const u8 sfx_4[];  extern u32 sfx_4_size;
extern const u8 sfx_5[];  extern u32 sfx_5_size;
extern const u8 sfx_6[];  extern u32 sfx_6_size;
extern const u8 sfx_7[];  extern u32 sfx_7_size;
extern const u8 sfx_8[];  extern u32 sfx_8_size;

/* ============================================================
 * UTILITY MACROS
 * ============================================================ */
#ifndef MIN
#define MIN(a, b)   ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b)   ((a) > (b) ? (a) : (b))
#endif

/* fix16Abs - SGDK 1.70 does not expose this name directly */
#ifndef fix16Abs
#define fix16Abs(v)  ((v) < 0 ? -(v) : (v))
#endif

/* FIX16_FROM_FLOAT - scale a small integer expression to fix16.
 * SGDK targets the M68000 which has no FPU. We avoid runtime floats entirely.
 * Usage: FIX16_FROM_INT_SCALED(numerator, denominator)
 * e.g.  FIX16_FROM_INT_SCALED(n, 1000) converts n/1000 to fix16.
 * For the random-velocity pattern used in enemy.c:
 *   (random() % 200 - 100) * 0.015  =>  (random() % 200 - 100) * 15 / 1000
 */
#define FIX16_FROM_FRAC(num, den)   ((fix16)((s32)(num) * 65536L / (den)))

/* ============================================================
 * ENEMY SPAWN PORTAL CONSTANTS
 * ============================================================ */
/* Portal animation length (frames).  Enemy enters at countdown == 0. */
#define PORTAL_ANIM_FRAMES   80
/* Number of animation steps drawn (1 frame image per step) */
#define PORTAL_ANIM_STEPS     5
/* Horizontal X position of the two portals (pixel centres) */
#define PORTAL_LEFT_X        10
#define PORTAL_RIGHT_X      (SCREEN_W - 10)
/* Vertical Y position of portals (screen vertical midpoint) */
/* Portal screen Y: fixed at viewport vertical midpoint (screen pixels, not world) */
#define PORTAL_SCREEN_Y     (HUD_HEIGHT + PLAYFIELD_H / 2)  /* 16+104 = 120 px from top */

/* ============================================================
 * LEVEL DEFINITIONS  (mirrored from original xqvars.pas)
 * Max 50 levels; values beyond MAX_LEVEL_DATA cycle from level 1.
 * ============================================================ */
#define MAX_LEVEL_DATA   50

typedef struct {
    u8   num_crystals;   /* gems to collect */
    u8   num_mines;
    u8   max_enemies;    /* max simultaneous on-screen */
    u16  erelease_prob;  /* spawn probability × 65536 per frame per type */
                         /* (original float × 65535, clamped to u16)      */
    u16  gate_width;     /* width of the exit gap in pixels (unused in    */
                         /* tile-based port but kept for future use)       */
    u8   gate_move;      /* 0=static gate, >0=moving gate speed           */
    u16  time_par;       /* par time in seconds for bonus                 */
    u32  newman_score;   /* score threshold for extra life                */
} LevelDef;

/* Per-level enemy type probability weights [0..ENEMY_TYPE_COUNT-1].
 * Index maps to EnemyType enum.  Sum need not equal 100.
 * Derived from original xqvars.pas probs[][] table (index 0=supercrystal
 * skipped; index 1=explosion skipped; real enemies start at index 2).
 * We store only the 15 enemy types matching EnemyType enum order. */
#define LEVEL_PROB_COUNT   15   /* == ENEMY_TYPE_COUNT */
extern const u8 g_level_probs[MAX_LEVEL_DATA][LEVEL_PROB_COUNT];
extern const LevelDef g_levels[MAX_LEVEL_DATA];

/* ============================================================
 * GLOBAL FRAME COUNTER
 * Incremented once per frame in main.c game_run().
 * ============================================================ */
extern u32 g_frame_count;

/* Game speed scalar (fix16).  FIX16(1) = normal.  Increases when the player
 * exceeds the level par time, matching the original speed-ramp mechanic. */
extern fix16 g_game_speed;

/* ============================================================
 * 8-DIRECTION VELOCITY TABLES
 * Defined in player.c, shared with enemy.c via this extern.
 * ============================================================ */
extern const fix16 DIR_DVX[8];
extern const fix16 DIR_DVY[8];

/* ============================================================
 * TYPES
 * ============================================================ */

typedef enum {
    DIR_RIGHT = 0,
    DIR_UP_RIGHT,
    DIR_UP,
    DIR_UP_LEFT,
    DIR_LEFT,
    DIR_DOWN_LEFT,
    DIR_DOWN,
    DIR_DOWN_RIGHT,
    DIR_NONE = -1
} Direction;

typedef enum {
    ENEMY_GRUNGER = 0,
    ENEMY_ZIPPO,
    ENEMY_ZINGER,
    ENEMY_VINCE,
    ENEMY_MINER,
    ENEMY_MEEBY,
    ENEMY_RETALIATOR,
    ENEMY_TERRIER,
    ENEMY_DOINGER,
    ENEMY_SNIPE,
    ENEMY_TRIBBLER,
    ENEMY_BUCKSHOT,
    ENEMY_CLUSTER,
    ENEMY_STICKTIGHT,
    ENEMY_REPULSOR,
    ENEMY_TYPE_COUNT
} EnemyType;

typedef enum {
    STATE_TITLE,
    STATE_GAME,
    STATE_PAUSED,
    STATE_LEVEL_CLEAR,
    STATE_GAME_OVER,
    STATE_HALL_OF_FAME
} GameState;

typedef struct {
    fix16 x, y;            /* position (fixed-point) */
    fix16 vx, vy;          /* velocity */
    Direction dir;         /* current movement direction */
    u8    lives;
    u8    smartbombs;
    u32   score;
    u16   shoot_cooldown;
    u8    invincible;      /* frames of post-death invincibility */
    u8    active;
    u32   next_life_score; /* score at which next extra life is awarded */
    Sprite *spr;
} Player;

typedef struct {
    fix16 x, y;
    fix16 vx, vy;
    EnemyType type;
    s16   hp;
    u8    active;
    u8    anim_frame;
    u16   anim_timer;
    u16   ai_timer;        /* general-purpose AI state counter */
    u8    ai_state;
    /* Curved motion (Meeby / moth enemies): rotation matrix components.
     * Stored as signed fixed-point ×32767.  0 = no curve. */
    s16   curvesin;        /* sin component of curve rotation */
    s16   curvecos;        /* cos component (32767 = 1.0)     */
    /* Per-enemy speed scale applied at spawn from difficulty settings.
     * 100 = 100% = normal speed. Stored here so AI functions can use it. */
    u8    speed_scale;     /* difficulty speed % (default 100) */
    u8    last_hit_by;     /* 1=P1, 2=P2 — set on bullet hit, used by enemy_die */
    Sprite *spr;
} Enemy;

typedef enum {
    BULLET_PLAYER = 0,   /* player's shot     — spr_bullet_player, PAL1 */
    BULLET_GREEN,        /* Zinger / Doinger  — spr_bullet_green,  PAL3 */
    BULLET_YELLOW,       /* Snipe             — spr_bullet_yellow, PAL3 */
    BULLET_PURPLE,       /* Retaliator        — spr_bullet_purple, PAL3 */
    BULLET_BUCKSHOT,     /* Buckshot          — spr_bullet_buckshot,PAL3*/
} BulletType;

typedef struct {
    fix16 x, y;
    fix16 vx, vy;
    u8         active;
    u8         is_player;   /* TRUE = player bullet, FALSE = enemy bullet */
    u8         owner;        /* 1 = P1, 2 = P2, 0 = enemy */
    BulletType bullet_type; /* selects sprite */
    Sprite *spr;
} Bullet;

typedef struct {
    fix16 x, y;
    u8    active;
    u8    collected;
    Sprite *spr;
} Gem;

typedef struct {
    fix16 x, y;
    u8    active;
    u8    triggered;
    Sprite *spr;
} Mine;

typedef struct {
    fix16 x, y;
    u8    active;
    u16   lifetime;
    Sprite *spr;
} PowerCharge;

typedef struct {
    fix16 x, y;
    u8    active;
    u8    frame;
    Sprite *spr;
} Explosion;

/* ============================================================
 * POWERUP SYSTEM
 * Derived from original xqvars.pas PowerUpType enum and timing.
 * Durations converted from DOS FrameRate=67 to Genesis 60fps.
 * ============================================================ */
typedef enum {
    PU_SHIELD    = 0,  /* invincible: walls & enemies don't kill        */
    PU_RAPIDFIRE = 1,  /* fire rate doubled                             */
    PU_MULTIFIRE = 2,  /* 3-way spread shot (±10° extra bullets)        */
    PU_ASSFIRE   = 3,  /* simultaneous rear shot (+ with MultiFire: 5)  */
    PU_AIMEDFIRE = 4,  /* bullets home toward nearest enemy             */
    PU_HEAVYFIRE = 5,  /* bullets pierce through enemies                */
    PU_BOUNCE    = 6,  /* bullets bounce off walls                      */
    PU_COUNT     = 7
} PowerUpId;

/* Duration ranges (Genesis 60fps frames), matching original timing:
 * Shield:    10-25s  (600-1500f)
 * AimedFire: 30-90s  (1800-5400f)
 * RapidFire, MultiFire, AssFire, HeavyFire: 60-150s (3600-9000f)
 * Bounce:    30-90s  (1800-5400f) */
static const u16 PU_DUR_MIN[PU_COUNT] = { 600,3600,3600,3600,1800,3600,1800 };
static const u16 PU_DUR_RAN[PU_COUNT] = { 900,5400,5400,5400,3600,5400,3600 };

/* ============================================================
 * SUPERCRYSTAL  — floating pickup that awards a random powerup
 * Original: type-0 enemy, spawned ~1 per 5 seconds, lasts 5-10s.
 * ============================================================ */
#define MAX_SUPERCRYSTALS  2

typedef struct {
    fix16  x, y;
    u16    lifetime;   /* frames remaining before auto-despawn */
    u8     active;
    u8     anim_frame;
    u8     anim_timer;
    Sprite *spr;
} Supercrystal;

typedef struct {
    Player      player;
    Enemy       enemies[MAX_ENEMIES];
    Bullet      bullets[MAX_BULLETS];
    Gem         gems[MAX_GEMS];
    Mine        mines[MAX_MINES];
    PowerCharge powercharges[MAX_POWERCHARGES];
    Explosion   explosions[MAX_EXPLOSIONS];

    u16  level;
    u8   gems_remaining;
    u8   gate_open;
    u8   gate_anim_frame;    /* current frame of gate open animation (0-8) */
    u8   gate_anim_timer;    /* frames since last gate anim step */
    Sprite *gate_spr;        /* gate sprite (NULL until level init) */
    /* Moving gate (levels 33+): gate slides left/right when gate_move > 0 */
    s16  gate_x;             /* current pixel X of gate centre */
    s16  gate_move_dir;      /* +1 = moving right, -1 = moving left */
    u16  gate_move_accum;    /* sub-pixel accumulator (fixed-point 8:8) */
    u16  level_timer;
    u8   difficulty;       /* 0=easy, 1=normal, 2=hard, 3=insane */
    GameState state;

    /* Camera scroll position (top-left of viewport in world space) */
    s16  cam_x;   /* 0 .. CAM_MAX_X (72)  */
    s16  cam_y;   /* 0 .. CAM_MAX_Y (112) */

    /* Enemy spawn portals (left and right side inlets).
     * countdown > 0 means a portal is animating open/closed.
     * At countdown==0 the enemy enters. enemy_type holds the type queued. */
    s16  portal_left_cd;    /* countdown frames (80..0) */
    s16  portal_right_cd;
    u8   portal_left_type;
    u8   portal_right_type;
    Sprite *portal_left_spr;   /* left wall portal sprite  */
    Sprite *portal_right_spr;  /* right wall portal sprite */

    /* Active powerup remaining durations (0 = inactive) */
    u16  powerup_timer[PU_COUNT];

    /* Supercrystal pickups */
    Supercrystal supercrystals[MAX_SUPERCRYSTALS];

    /* Tile map */
    u8   tilemap[MAP_TILES_H][MAP_TILES_W];   /* 0=floor, 1=wall */
} GameData;

/* ============================================================
 * FUNCTION DECLARATIONS (implemented in respective .c files)
 * ============================================================ */

/* main.c / game loop */
void game_init(void);
void game_run(void);

/* title.c */
void title_show(void);

/* player.c */
void player_init(Player *p, fix16 x, fix16 y);
void player_update(Player *p, GameData *gd);
void player_draw(Player *p, GameData *gd);
void player_die(Player *p, GameData *gd);

/* enemy.c */
void enemy_spawn(Enemy *e, EnemyType type, fix16 x, fix16 y);
void enemies_update(GameData *gd);
void enemies_draw(GameData *gd);
void enemy_die(Enemy *e, GameData *gd);

/* gem.c */
void gems_init(GameData *gd, u8 count);
void gems_update(GameData *gd);
void gems_draw(GameData *gd);

/* bullet.c */
void bullet_fire(GameData *gd, fix16 x, fix16 y, fix16 vx, fix16 vy, BulletType type);
/* Owner variant: 1=P1, 2=P2, 0=enemy (bullet_fire defaults owner=1 for player, 0 for enemy) */
void bullet_fire_ex(GameData *gd, fix16 x, fix16 y, fix16 vx, fix16 vy, BulletType type, u8 owner);
void bullets_update(GameData *gd);
void bullets_draw(GameData *gd);

/* mine.c */
void mine_place(GameData *gd, fix16 x, fix16 y);
void mines_update(GameData *gd);
void mines_draw(GameData *gd);
void powercharges_update(GameData *gd);
void explosions_update(GameData *gd);
void supercrystals_update(GameData *gd);

/* powerup.c — active powerup query helpers */
u8   powerup_active(const GameData *gd, PowerUpId id);
void powerup_award(GameData *gd, PowerUpId id);
void powerup_tick(GameData *gd);

/* smartbomb.c */
void smartbomb_activate(GameData *gd);

/* level.c */
void level_generate(GameData *gd, u16 level_num);
void level_check_complete(GameData *gd);
void level_next(GameData *gd);

/* collision.c */
void collision_check_all(GameData *gd);
u8   rects_overlap(fix16 ax, fix16 ay, u8 aw, u8 ah,
                   fix16 bx, fix16 by, u8 bw, u8 bh);

/* sfx.c */
void sfx_init(void);
void sfx_play(u8 sfx_id);

/* camera */
void camera_update(GameData *gd);

/* hud.c */
void hud_draw(GameData *gd);
void hud_update_score(u32 score);

/* ============================================================
 * player2.c
 * ============================================================ */
void    player2_init(fix16 x, fix16 y);
void    player2_update(GameData *gd);
void    player2_collision(GameData *gd);
void    player2_die(GameData *gd);
u8      player2_is_active(void);
Player *player2_get(void);
u32     player2_get_score(void);

/* ============================================================
 * screens.c
 * ============================================================ */
void screen_game_over(GameData *gd);
void screen_hof_enter(GameData *gd);
void screen_hof_show(void);
void screen_pause(void);
void screen_level_clear(GameData *gd, u32 time_bonus);
u8   screen_options(void);
u8   screen_get_difficulty_index(void);

/* ============================================================
 * sram.c
 * HofEntry is defined in screens.h; forward-declared here to
 * avoid a circular include (screens.h already includes xquest.h).
 * ============================================================ */
#ifndef HOF_ENTRY_FWD
#define HOF_ENTRY_FWD
typedef struct { char name[13]; u32 score; u16 level; } HofEntry;
#endif
u8   sram_load(HofEntry *hof, u8 entries, u8 *difficulty);
void sram_save(const HofEntry *hof, u8 entries, u8 difficulty);
void sram_erase(void);
void sram_startup(void);
void sram_save_hof(void);

/* tilemap.c — declared in tilemap.h (included by files that need it) */

/* ============================================================
 * enemy_variants.c
 * ============================================================ */
void ev_init(void);
void ev_restore_collect_palette(void);
void ev_apply_to_sprite(EnemyType type, Sprite *spr);
u8   ev_is_variant(EnemyType type);
u8   ev_get_anim_offset(EnemyType type);

/* ============================================================
 * sfx sustained / stop (game.c)
 * ============================================================ */
void sfx_play_sustained(u8 sfx_id);
void sfx_stop(void);

#endif /* XQUEST_H */
