# XQuest 2 → Sega Genesis Port
### SGDK 1.70 Project Scaffold

> Original game by Mark Mackey (1996, MS-DOS)  
> Genesis port scaffold generated from full binary asset extraction

---

## Project Structure

```
xquest2_sgdk/
├── Makefile
├── README.md
├── inc/
│   └── xquest.h          ← All types, constants, function prototypes
├── src/
│   ├── main.c            ← Entry point, game loop, VBlank
│   ├── player.c          ← Ship movement, firing, smartbomb, death
│   ├── enemy.c           ← All 15 enemy AI behaviours
│   └── game.c            ← collision, level gen, gem, bullet, mine,
│                            smartbomb, hud, title, sfx (scaffold)
└── res/
    ├── resources.res     ← SGDK resource declarations
    ├── palettes/         ← 4× Genesis 16-color palette PNGs
    ├── sprites/          ← 125 Genesis-remapped 16×16 sprite PNGs
    ├── screens/          ← Title screen PNG (320×240 → crop to 320×224)
    └── sounds/           ← 9 WAV files (8000 Hz, 8-bit unsigned PCM)
```

---

## Build Requirements

| Tool | Version | Notes |
|---|---|---|
| SGDK | 1.70 | Set `export SGDK=/opt/sgdk` |
| Java | 11+ | For `rescomp.jar` |
| m68k-elf-gcc | 6.3+ | Motorola 68000 cross-compiler |
| BlastEm | any | Recommended emulator for testing |

```bash
# Build
make

# Build + run in BlastEm
make run

# Clean
make clean
```

---

## Asset Summary

### Sprites (125 total, 16×16 px)
All sprites extracted from `XQUEST.GFX` and remapped to 4 Genesis palettes.

| Category | Count | Palette | Key sprites |
|---|---|---|---|
| Background tiles | 34 | PAL0 | Wall (8), Floor (18), Cyan floor (4), Edge (4) |
| Player ship | 8 | PAL1 | 2 body frames, 3 thrust, 2 diagonal, 1 dir |
| Mine | 5 | PAL1 | 5-frame animation |
| Bullets | 5 | PAL1/3 | Player (red), enemy green, enemy yellow |
| Gems | 4 | PAL2 | 1 base + 3 sparkle animation frames |
| Exit gate | 9 | PAL2 | 9-frame open animation |
| PowerCharge | 1 | PAL2 | Pickup item |
| SmartBomb fx | 2 | PAL3 | Screen-clear effect |
| Explosion fx | 3 | PAL3 | 3-frame death animation |
| Enemies | 54 | PAL3 | 10 identified types (see below) |

### Enemies (15 types from docs → 10 sprite groups)
| Type | Sprites | AI behaviour |
|---|---|---|
| Meeby | 000–023 | Large, 24-frame rotation, charges player |
| Grunger | 026–031 | Slow random walk toward player |
| Tribbler | 035–044 | Moves toward player, splits when shot |
| Zippo | 050–053 | Like grunger but 2.5× faster |
| Retaliator | 024 | Fires back when hit, fires in 4 dirs on death |
| Terrier | 070–072 | Ignores player until close, then relentless |
| Sticktight | 073–075 | Fast homing, orbits player when close |
| Doinger | 076 | Gets faster + fires more bullets over time |
| Vince | 077 | 10 HP, near-invulnerable |
| Miner | 123 | Drops mines periodically |
| Zinger* | shared | Fires 4-direction bullet bursts |
| Buckshot* | shared | Fires 8-direction bullet bursts |
| Snipe* | shared | Stays still, accurate long-range shot |
| Cluster* | shared | Splits into 3 Zippos when destroyed |
| Repulsor* | shared | Pushes player away with force field |
\* These 5 types share sprite graphics with other enemies; differentiated by palette swap or behavior only.

### Sound Effects (9 segments @ 8000 Hz, 8-bit unsigned PCM)
| ID | File | Duration | Suspected use |
|---|---|---|---|
| 0 | `snd_00_music_intro.wav` | 5.19s | Title / attract SFX |
| 1 | `snd_01_music_loop_a.wav` | 3.95s | In-game SFX bank A |
| 2 | `snd_02_music_loop_b.wav` | 3.98s | In-game SFX bank B |
| 3 | `snd_03_music_loop_c.wav` | 3.22s | In-game SFX bank C |
| 4 | `snd_04_music_loop_d.wav` | 3.21s | In-game SFX bank D |
| 5 | `snd_05_sfx_burst_a.wav` | 4.54s | Explosion / smartbomb |
| 6 | `snd_06_sfx_burst_b.wav` | 0.93s | Secondary explosion |
| 7 | `snd_07_sfx_sweep.wav` | 0.04s | Shoot / gem collect blip |
| 8 | `snd_08_sfx_short_a.wav` | 2.10s | Level complete / extra life |

**SGDK note:** Convert unsigned PCM to signed before use:  
`XOR each sample byte with 0x80` — or pass `signed=TRUE` in rescomp.

### Screen Images
| File | Size | Use |
|---|---|---|
| `title_screen.png` | 320×240 | Title screen (crop 8px top/bottom for 320×224) |
| `startpic.png` | 320×40 | "XQUEST" logo banner |
| `title0.png` | 160×45 | "ATOMJACK PRESENTS" |

---

## Genesis Hardware Constraints vs Original

| Feature | DOS Original | Genesis Port |
|---|---|---|
| Resolution | 320×240 (Mode X) | 320×224 (16px less height) |
| Colors | 256 simultaneous | 64 (4 palettes × 16) |
| Sprites | Software rendered | Hardware sprites, 80 max / 20 per line |
| Sprite size | Any (software) | 8×8 to 32×32 hardware tiles |
| Sound | SB 8-bit PCM, 4 ch | Z80 PCM driver, 2 PCM channels |
| Input | Mouse/Joystick/KB | 3-button or 6-button Genesis pad |

### Input Mapping
| Original | Genesis |
|---|---|
| Mouse/Joystick move | D-pad (8-way) |
| Fire button | A or C |
| Smartbomb button | B |
| Pause | Start |
| Menu navigate | D-pad |
| Menu select | A |
| Menu back | B |

---

## Implementation Status

- [x] Asset extraction (sprites, screens, sounds, palettes)
- [x] Genesis palette quantization (256→4×16)
- [x] Sprite remapping to Genesis palettes
- [x] SGDK project structure + Makefile
- [x] `xquest.h` — all types, constants, prototypes
- [x] `main.c` — init, game loop, VBlank
- [x] `player.c` — 8-dir movement, inertia, fire, smartbomb, death, respawn
- [x] `enemy.c` — all 15 enemy AI behaviours
- [x] `game.c` — collision, gems, bullets, mines, level gen, HUD, title, SFX
- [x] `tilemap.c/h` — tile map renderer (wall/floor to VDP plane B, auto-edge detection)
- [x] `screens.c/h` — game over, HOF entry (name input), HOF display, level clear fanfare
- [x] `player2.c/h` — full two-player support (JOY_2, independent lives/scores/bombs)
- [x] Difficulty scaling (Easy/Normal/Hard/Insane, affects HP/speed/counts/score)
- [ ] Demo playback (XQUEST.DMO)
- [ ] Font rendering (XQUEST.FNT, XQUEST2.FNT)
- [x] `sfx.h` — named SFX constants, all sfx_play() calls updated
- [ ] Enemy palettes for 5 remaining unidentified types

---

## Gameplay Preservation Notes

The port preserves all core XQuest 2 mechanics:
- **Inertia physics**: ship accelerates/decelerates with friction (same constants scaled to 60Hz)
- **Screen wrap**: player and enemies wrap at all 4 edges
- **Pixel collision**: hitboxes match original (10×10 ship, 12×12 enemies, 6×6 bullets, 10×10 mines/gems)
- **Scoring**: 50pts/gem, per-enemy scores, time bonus on level clear
- **Extra lives**: every 15,000pts base, scaling with level
- **SmartBomb**: destroys all enemies + enemy bullets on screen
- **Tribbler split**: spawns additional enemies on death
- **Cluster split**: spawns 3 fast Zippos on death
- **Retaliator**: fires in 4 directions when hit AND when destroyed
- **Doinger**: speed and fire rate increase with time alive
- **Vince**: 10 HP (near-invulnerable)
- **Repulsor**: applies push force to player (force-field effect)

---

*Based on XQuest 2 by Mark Mackey (1996). Genesis port scaffold by asset extraction.*
