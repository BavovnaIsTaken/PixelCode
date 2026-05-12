# Arkanoid easter-egg roadmap

> Focus: **make level 1 look genuinely good** before any new mechanics or
> levels. Visual polish first, content second.

## Where we are (2026-05-11)

- Switched from gradient/shape rendering to a **text-sprite catalog**
  (`lib/widgets/canvas/arkanoid_sprites.dart`) so every visual element can
  be hand-tuned per-pixel.
- Six brick types map to office-themed sprites (monitor variants, glass
  partition, cracked glass, trophy, fire extinguisher, filing cabinet).
- Eight powerup capsules, desk paddle, coffee-cup ball, fire-extinguisher
  blast ball.
- Smoke-tested via `test/widgets/canvas/arkanoid_sprites_test.dart`
  (rectangularity + complete glyph→color coverage).

The painter and color resolver are minimum-viable: shapes are recognisable
but flat and lack the hierarchy of the old gradient renderer.

## Phase 0 — baseline (DONE)

- [x] `arkanoid_sprites.dart` with full catalog
- [x] painter migration (`_drawSingleBrick`, `_drawPaddle`, `_drawSingleBall`,
      `_drawFallingPowerUps`)
- [x] aspect-correct `min(rectW/sw, rectH/sh)` fit math
- [x] catalog smoke tests

## Phase 1 — level 1 visual polish

The goal of this phase: open the easter egg, see level 1, and want to keep
playing because it looks like a real game.

### 1.1 Sprite art quality pass

Each row is *one focused art session* — don't bundle. After each, run the
game and stare at it until it stops feeling flat.

- [ ] **Monitor bricks** — add bezel notches, power-LED dot, subtle
      scanline pattern on the screen, distinct screen content per variant
      (code lines / chart / chat bubble / loading bar)
- [ ] **Glass partition** — make the highlight diagonal (45°) instead of
      scattered, add a thin top/bottom rail
- [ ] **Cracked glass** — make cracks branch from a single impact point,
      not random scatter
- [ ] **Trophy** — pedestal needs depth (sides darker than face), gold
      cup needs a clearer cup shape (bowl + handles)
- [ ] **Fire extinguisher (brick)** — clear pin/handle, larger label
      patch, base ring
- [ ] **Filing cabinet** — drawer handles need to look like handles, not
      stripes; top edge needs a lip
- [ ] **Desk paddle** — currently 3 rows of flat wood. Try 5-row design
      with leg shadow underneath, drawer outline, monitor stand bump on top
- [ ] **Coffee ball** — needs a steam wisp glyph above (animated separately
      in painter — single sprite isn't enough)
- [ ] **Powerup icons** — current `i` glyph blobs don't read. Replace each
      with a recognisable mini-icon (↔ for expand, two dots for multiball,
      etc.)

### 1.2 Color palette tightening

- [ ] Audit `resolveArkanoidSpriteColor` against the rest of PixelCode's
      pixel art (`furniture_sprites.dart`, sprite_system specs). Shift hues
      so the easter-egg feels like the same world, not a separate game.
- [ ] Add a third (mid-tone) color per material — currently most surfaces
      use only `XX/xx` (light/dark) pairs and read as 2-bit. 3 tones per
      brick adds visible depth at brick size.

### 1.3 Background + frame

- [ ] Replace the flat dark blue background with a subtle office scene:
      far-back wall + ceiling lights at top, hint of carpet at bottom.
      Must stay low-contrast so bricks pop.
- [ ] Side walls: vertical pin-stripe or panel detail instead of flat fill.
- [ ] Top border: a "shelf" with mini-decor (plant, lamp) so the ball
      bounces off something that feels physical.

### 1.4 Level 1 layout

Level 1 currently uses the same procedural row of normal bricks. After 1.1
lands, redesign:

- [ ] Hand-draw a **pixel-art arrangement** for level 1 (e.g. spell
      "PIXELCODE" in monitor bricks across the top, glass partition wall in
      the middle, two filing cabinets as side anchors).
- [ ] Drop one trophy somewhere as a reward target.
- [ ] No fire extinguishers in level 1 — save the explosion for level 2+.

### 1.5 Motion & juice

- [ ] **Brick break** — current frame just disappears. Add a 4-frame
      shatter (8 sprite-pixels flying outward) using the brick's main
      palette.
- [ ] **Ball trail** — half-alpha ghost of the previous 2 positions while
      moving.
- [ ] **Paddle hit** — squash by 1 sprite-row for 80 ms on impact.
- [ ] **Powerup collect** — small flash of capsule color around the paddle
      when picked up.
- [x] **Sticky-catch landing** — radial 8-direction pixel-burst, paddle
      squish, animated glue strand, pulsing halo, dashed aim arrow
      following paddle. (`arkanoid_catch_helpers.dart` + painter
      overlays; tests in `test/widgets/easter_eggs/arkanoid_catch_helpers_test.dart`.)

## Phase 2 — beyond level 1 (deferred)

Only start once Phase 1 has been signed-off as "I like opening this".

- Level 2–10 hand-drawn layouts
- Boss brick (multi-hit, custom large sprite)
- Music + sound effects
- Score persistence beyond high-score-per-level

## Out of scope (don't drift)

- Level editor / user-generated content
- Online leaderboards
- Multiplayer
- Theme variants (Halloween, etc.)

## How to work on this

1. Pick **one** unchecked item from Phase 1.
2. Open the easter egg in the running app (`/menu → office → arkanoid`).
3. Iterate on the sprite/painter/color until the *specific thing in that
   bullet* looks right at gameplay zoom.
4. Add a test to `arkanoid_sprites_test.dart` if you introduce new glyph
   keys or new sprites.
5. Commit and tick the box. **Do not** batch multiple items into one
   commit — small commits let us revert a sprite that looked great in
   isolation but clashes with the rest.

## File map

| Concern                | File                                              |
| ---------------------- | ------------------------------------------------- |
| Sprite art             | `lib/widgets/canvas/arkanoid_sprites.dart`        |
| Color resolver         | `resolveArkanoidSpriteColor` (same file)          |
| Painter / game loop    | `lib/widgets/easter_eggs/arkanoid_game.dart`      |
| Catalog smoke tests    | `test/widgets/canvas/arkanoid_sprites_test.dart`  |
| This roadmap           | `docs/ARKANOID_ROADMAP.md`                        |
