# ============================================================
# XQuest 2 for Sega Genesis - SGDK 1.70 Resource Declarations
# Sprites extracted directly from xquest.gfx with correct palette
# ============================================================

# --- PALETTES ---
PALETTE pal_bg          "palettes/pal_bg.png"
PALETTE pal_active      "palettes/pal_active.png"
PALETTE pal_collect     "palettes/pal_collect.png"
PALETTE pal_enemy       "palettes/pal_enemy.png"

# --- TITLE SCREEN ---
IMAGE   img_title       "screens/title_screen.png"  BEST
PALETTE pal_title       "screens/title_screen.png"

# --- BACKGROUND TILES ---

# --- PLAYER & OBJECTS ---
# Ship: 24 frames, 16x16 (2x2 tiles), 8 directions x 3 anim frames
SPRITE  spr_ship            "sprites/ship.png"          2 2 NONE
# Mine (player-laid): 11x11 -> fits in 16x16 cell (2x2 tiles), 1 frame
SPRITE  spr_mine            "sprites/mine.png"          2 2 NONE
# Enemy-laid mine: 7x7 -> 8x8 = 1x1 tile
SPRITE  spr_enemy_mine      "sprites/enemy_mine.png"    1 1 NONE
# Player bullet: 2x2 px -> 1x1 tile
SPRITE  spr_bullet_player   "sprites/missile_player.png" 1 1 NONE
# SmartBomb effect: 11x11 -> 2x2 tiles
SPRITE  spr_smartbomb       "sprites/smartbomb.png"     2 2 NONE

# --- GEMS / GATE / PORTALS / POWERUPS ---
# Crystal (gem): 11x11 -> 2x2 tiles, 1 frame
SPRITE  spr_gem             "sprites/crystal.png"       2 2 NONE
# Supercrystal (special gem): 16x16, 6 anim frames
SPRITE  spr_supercrystal    "sprites/supercrystal.png"  2 2 NONE
# Exit gate: left 16x14, right 16x14, each 1 frame (shown together)
SPRITE  spr_gate            "sprites/gate_left.png"     2 2 NONE
SPRITE  spr_gate_right      "sprites/gate_right.png"    2 2 NONE
# Enemy spawn portal: left + right, 20x20, 6 anim frames each (3x3 tiles)
SPRITE  spr_portal          "sprites/portal_left.png"   3 3 NONE
SPRITE  spr_portal_right    "sprites/portal_right.png"  3 3 NONE
# PowerCharge (attractor): 13x13 -> 2x2 tiles
SPRITE  spr_powercharge     "sprites/attractor.png"     2 2 NONE
# Gate frame corners: 10x10 -> 2x2 tiles
SPRITE  spr_corner_tl       "sprites/corner_tl.png"     2 2 NONE
SPRITE  spr_corner_tr       "sprites/corner_tr.png"     2 2 NONE
SPRITE  spr_corner_bl       "sprites/corner_bl.png"     2 2 NONE
SPRITE  spr_corner_br       "sprites/corner_br.png"     2 2 NONE

# --- FX ---
# Explosion: 23x23 -> 3x3 tiles, 6 frames
SPRITE  spr_explosion       "sprites/explosion.png"     3 3 NONE

# --- ENEMY BULLETS ---
# Green missile (Zinger/Doinger): 3x3 -> 1x1 tile
SPRITE  spr_bullet_green    "sprites/missile_green.png"      1 1 NONE
# Yellow missile (Snipe): 3x3 -> 1x1 tile
SPRITE  spr_bullet_yellow   "sprites/missile_yellow.png"     1 1 NONE
# Purple missile (Retaliator): 4x4 -> 1x1 tile
SPRITE  spr_bullet_purple   "sprites/missile_purple.png"     1 1 NONE
# Buckshot missile: 4x4 -> 1x1 tile
SPRITE  spr_bullet_buckshot "sprites/missile_buckshot.png"   1 1 NONE

# --- ENEMIES ---
# Grunger: 11x11 -> 2x2 tiles, 4 frames
SPRITE  spr_grunger         "sprites/grunger.png"       2 2 NONE
# Zippo: 11x11 -> 2x2 tiles, 4 frames
SPRITE  spr_zippo           "sprites/zippo.png"         2 2 NONE
# Zinger: 16x16, 4 frames
SPRITE  spr_zinger          "sprites/zinger.png"        2 2 NONE
# Vince: 16x16, 4 frames
SPRITE  spr_vince           "sprites/vince.png"         2 2 NONE
# Miner: 12x12 -> 2x2 tiles, 4 frames
SPRITE  spr_miner           "sprites/miner.png"         2 2 NONE
# Meeby: 20x20 -> 3x3 tiles, 6 frames
SPRITE  spr_meeby           "sprites/meeby.png"         3 3 NONE
# Retaliator: 11x13 -> 2x2 tiles, 4 frames
SPRITE  spr_retaliator      "sprites/retaliator.png"    2 2 NONE
# Terrier: 21x8 -> 3x1 tiles, 4 frames
SPRITE  spr_terrier         "sprites/terrier.png"       2 1 NONE
# Doinger: 12x12 -> 2x2 tiles, 4 frames
SPRITE  spr_doinger         "sprites/doinger.png"       2 2 NONE
# Snipe: 9x9 -> 2x2 tiles, 4 frames
SPRITE  spr_snipe           "sprites/snipe.png"         2 2 NONE
# Tribbler: 14x14 -> 2x2 tiles, 4 frames
SPRITE  spr_tribbler        "sprites/tribbler.png"      2 2 NONE
# Tribble fragment: 6x6 -> 1x1 tile, 4 frames
SPRITE  spr_tribble_frag    "sprites/tribble_frag.png"  1 1 NONE
# Buckshot: 11x11 -> 2x2 tiles, 4 frames
SPRITE  spr_buckshot        "sprites/buckshot.png"      2 2 NONE
# Cluster: 9x9 -> 2x2 tiles, 4 frames
SPRITE  spr_cluster         "sprites/cluster.png"       2 2 NONE
# Sticktight: 11x11 -> 2x2 tiles, 4 frames
SPRITE  spr_sticktight      "sprites/sticktight.png"    2 2 NONE
# Repulsor: 12x12 -> 2x2 tiles, 6 frames
SPRITE  spr_repulsor        "sprites/repulsor.png"      2 2 NONE

# --- SOUND EFFECTS ---
WAV     sfx_0   "sounds/snd_00_music_intro.wav"   0 8000
WAV     sfx_1   "sounds/snd_01_music_loop_a.wav"  0 8000
WAV     sfx_2   "sounds/snd_02_music_loop_b.wav"  0 8000
WAV     sfx_3   "sounds/snd_03_music_loop_c.wav"  0 8000
WAV     sfx_4   "sounds/snd_04_music_loop_d.wav"  0 8000
WAV     sfx_5   "sounds/snd_05_sfx_burst_a.wav"   0 8000
WAV     sfx_6   "sounds/snd_06_sfx_burst_b.wav"   0 8000
WAV     sfx_7   "sounds/snd_07_sfx_sweep.wav"     0 8000
WAV     sfx_8   "sounds/snd_08_sfx_short_a.wav"   0 8000

# --- BACKGROUND TILESET ---
TILESET bg_tileset      "tiles/bg_tileset.png"   NONE

# --- CUSTOM FONT ---
TILESET xquest_font     "font/xquest_font.png"    NONE

# --- ENEMY VARIANT PALETTE ---
PALETTE pal_enemy2      "palettes/pal_enemy2.png"
