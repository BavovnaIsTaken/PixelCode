/// Procedural pixel-art drawing for the galley office environment.
///
/// All rendering uses canvas.drawRect only — no PNG assets, no paths.
library;

import 'package:flutter/material.dart';

// ─── Palette ─────────────────────────────────────────────────────────────────

// Wood
const _oakDark = Color(0xFF1E1408);
const _oakMid = Color(0xFF3D2B14);
const _oakSeam = Color(0xFF2A1E0C);

// Iron
const _ironDark = Color(0xFF1A1C1E);
const _ironBand = Color(0xFF2E3135);
const _ironRust = Color(0xFF4A2A1A);

// Bronze
const _bronzeRim = Color(0xFF5C4A2A);
const _bronzePatina = Color(0xFF3A5C4A);
const _bronzeHi = Color(0xFF8B6A3A);

// Linen
const _linenBase = Color(0xFFB8A882);
const _linenShadow = Color(0xFF6E5C3A);

// Rope
const _ropeBeige = Color(0xFF7A6848);

// Terracotta / red
const _terracotta = Color(0xFF7A3820);
const _accentRed = Color(0xFF8B1A1A);

// Amber glow
const _amberGlow = Color(0xFFC8841A);

// Sea (night)
const _seaDeep = Color(0xFF0D1B2A);
const _seaMid = Color(0xFF1A3A52);
const _seaCrest = Color(0xFF2A6070);
const _foamWhite = Color(0xFFC8DDE8);
const _reflectGold = Color(0xFF3A3018);

// ─── Sea ─────────────────────────────────────────────────────────────────────

/// Draws animated sea tiles filling [bounds], skipping any tile that falls
/// inside [deckRect]. Pass the full visible viewport (in painter coords) as
/// [bounds] so the sea fills the entire area around the galley — not just a
/// narrow strip past the hull. The tile grid is aligned to the global origin
/// so the pattern stays continuous as the user pans the canvas.
void drawGalleySea({
  required Canvas canvas,
  required Rect bounds,
  required Rect deckRect,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  const ts = 16.0;
  final frame = (tick ~/ 8) % 4;

  final startX = (bounds.left / ts).floor() * ts;
  final startY = (bounds.top / ts).floor() * ts;
  final endX = (bounds.right / ts).ceil() * ts;
  final endY = (bounds.bottom / ts).ceil() * ts;

  for (double ty = startY; ty < endY; ty += ts) {
    for (double tx = startX; tx < endX; tx += ts) {
      final tileRect = Rect.fromLTWH(tx, ty, ts, ts);

      if (tileRect.right <= deckRect.left ||
          tileRect.bottom <= deckRect.top ||
          tileRect.left >= deckRect.right ||
          tileRect.top >= deckRect.bottom) {
        final col = (tx / ts).round();
        final row = (ty / ts).round();
        // Modulo-then-add-modulo keeps phase positive for negative tile coords.
        final phase = ((col + row) % 2 + 2) % 2;
        _drawSeaTile(canvas, tx, ty, ts, frame, phase, p);
      }
    }
  }
}

void _drawSeaTile(
  Canvas canvas,
  double x,
  double y,
  double s,
  int frame,
  int phase,
  Paint p,
) {
  // Base deep water.
  p.color = _seaDeep;
  canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);

  // Mid-water band — shifts vertically each frame to simulate swell.
  final midY = y + (phase == 0 ? _seaWaveMidOffset[frame] : _seaWaveMidOffset[(frame + 2) % 4]);
  p.color = _seaMid;
  canvas.drawRect(Rect.fromLTWH(x, midY, s, 5), p);

  // Crest highlight on top of the swell.
  final crestY = midY - 2;
  p.color = _seaCrest;
  canvas.drawRect(Rect.fromLTWH(x + 2, crestY, s - 4, 2), p);

  // Amber moonlight reflection — sparse, only on phase-0 tile at certain frames.
  if (phase == 0 && frame == 1) {
    p.color = _reflectGold;
    canvas.drawRect(Rect.fromLTWH(x + s / 2 - 1, midY + 1, 3, 1), p);
  }
}

// Wave mid-band Y offsets relative to tile top (0-indexed frame).
const _seaWaveMidOffset = [5.0, 7.0, 9.0, 7.0];

// ─── Hull cap ────────────────────────────────────────────────────────────────

/// Draws the bronze rim and cap along the top edge of the outer wall ring.
void drawGalleyHullCap({
  required Canvas canvas,
  required Rect outerWallRect,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Outer bronze rim strip.
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.left, outerWallRect.top, outerWallRect.width, 4), p);

  // Highlight on very top edge.
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.left + 2, outerWallRect.top, outerWallRect.width - 4, 1), p);

  // Patina shadow band just below.
  p.color = _bronzePatina;
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.left, outerWallRect.top + 4, outerWallRect.width, 2), p);

  // Iron band bolts — evenly spaced every 16 px.
  p.color = _ironBand;
  final boltCount = (outerWallRect.width / 16).floor();
  for (int i = 0; i < boltCount; i++) {
    final bx = outerWallRect.left + 8 + i * 16.0;
    canvas.drawRect(Rect.fromLTWH(bx, outerWallRect.top + 1, 2, 4), p);
  }

  // Side caps (left and right).
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.left, outerWallRect.top, 4, outerWallRect.height), p);
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.right - 4, outerWallRect.top, 4, outerWallRect.height), p);

  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.left + 1, outerWallRect.top + 2, 1, outerWallRect.height - 4), p);
  canvas.drawRect(Rect.fromLTWH(
      outerWallRect.right - 2, outerWallRect.top + 2, 1, outerWallRect.height - 4), p);
}

// ─── Foam rim ────────────────────────────────────────────────────────────────

/// Draws the animated foam strip where hull meets sea, on all four outer edges.
/// 3-frame animation driven by [tick].
void drawGalleyFoamRim({
  required Canvas canvas,
  required Rect outerWallRect,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  final frame = (tick ~/ 12) % 3;

  // Foam intensity ramps: frame 0 = light, 1 = full, 2 = fade.
  final foamAlpha = const [0.45, 0.85, 0.55][frame];
  p.color = _foamWhite.withValues(alpha: foamAlpha);

  const foamH = 3.0;
  const foamW = 3.0;

  // Top edge.
  _drawFoamStrip(canvas, outerWallRect.left, outerWallRect.top - foamH,
      outerWallRect.width, foamH, horizontal: true, frame: frame, p: p);
  // Bottom edge.
  _drawFoamStrip(canvas, outerWallRect.left, outerWallRect.bottom,
      outerWallRect.width, foamH, horizontal: true, frame: frame, p: p);
  // Left edge.
  _drawFoamStrip(canvas, outerWallRect.left - foamW, outerWallRect.top,
      foamW, outerWallRect.height, horizontal: false, frame: frame, p: p);
  // Right edge.
  _drawFoamStrip(canvas, outerWallRect.right, outerWallRect.top,
      foamW, outerWallRect.height, horizontal: false, frame: frame, p: p);
}

void _drawFoamStrip(
  Canvas canvas,
  double x,
  double y,
  double length,
  double thickness, {
  required bool horizontal,
  required int frame,
  required Paint p,
}) {
  canvas.drawRect(Rect.fromLTWH(x, y, horizontal ? length : thickness,
      horizontal ? thickness : length), p);

  // Sparse bright speckles that shift position per frame.
  p.color = _foamWhite;
  final step = 10.0;
  final count = (length / step).floor();
  for (int i = 0; i < count; i++) {
    final offset = (frame * 3.0);
    final sx = horizontal ? x + i * step + offset : x;
    final sy = horizontal ? y : y + i * step + offset;
    canvas.drawRect(Rect.fromLTWH(sx, sy, 2, 1), p);
  }
}

// ─── Mast and sail ───────────────────────────────────────────────────────────

/// Draws the central mast, square sail, yardarm, and rope rigging.
/// Sail animates in 3-frame pingpong (FULL / SLACK / BACK) at 1 frame per
/// 90 ticks. Render this layer AFTER all characters.
void drawGalleyMastAndSail({
  required Canvas canvas,
  required int mastCol,
  required int mastBaseRow,
  required int mastTopRow,
  required int sailWidthTiles,
  required int sailHeightTiles,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  const ts = 16.0;

  final mastX = mastCol * ts + ts / 2 - 1;
  final baseY = mastBaseRow * ts;
  final topY = mastTopRow * ts;
  final mastH = baseY - topY;

  // Mast pole — dark oak core with highlight.
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(mastX, topY, 3, mastH), p);
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(mastX + 1, topY + 2, 1, mastH - 4), p);

  // Iron bands on the mast every ~20px.
  p.color = _ironBand;
  int bandCount = (mastH / 20).floor();
  for (int i = 1; i <= bandCount; i++) {
    final by = topY + i * (mastH / (bandCount + 1));
    canvas.drawRect(Rect.fromLTWH(mastX - 1, by, 5, 2), p);
  }

  // Yardarm — horizontal spar from which sail hangs.
  final yardY = topY + mastH * 0.18;
  final sailW = sailWidthTiles * ts;
  final sailH = sailHeightTiles * ts;
  final yardX = mastX + 1.5 - sailW / 2;
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(yardX - 2, yardY, sailW + 4, 2), p);
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(yardX - 2, yardY + 2, sailW + 4, 1), p);

  // Sail — 3 frames pingpong: 0=full belly, 1=slack, 2=back belly.
  final rawFrame = (tick ~/ 90) % 4;
  // Pingpong: 0→1→2→1→0…  indices 0,1,2,1
  final sailFrame = const [0, 1, 2, 1][rawFrame];
  _drawSail(canvas, yardX, yardY + 2, sailW, sailH, sailFrame, p);

  // Flag at mast top.
  drawGalleyFlag(
    canvas: canvas,
    mastTopX: mastX + 1,
    mastTopY: topY,
    tick: tick,
  );

  // Forestay rope — diagonal from mast top to bow-side bottom corner.
  _drawRopeLine(canvas, mastX + 1, topY, yardX - 2, yardY + sailH + 4, p);

  // Backstay — symmetric.
  _drawRopeLine(
      canvas, mastX + 2, topY, yardX + sailW + 4, yardY + sailH + 4, p);
}

void _drawSail(
  Canvas canvas,
  double x,
  double y,
  double w,
  double h,
  int frame,
  Paint p,
) {
  // Sail belly: frame 0 = full bow-side curve, 1 = flat, 2 = back-curve.
  // Approximated as three vertical columns with hue-shifted shading.

  final third = w / 3;

  // Shared base: linen shadow for depth panels.
  p.color = _linenShadow;
  canvas.drawRect(Rect.fromLTWH(x, y, w, h), p);

  if (frame == 0) {
    // Full belly — bright centre, shadow on trailing edge.
    p.color = _linenBase;
    canvas.drawRect(Rect.fromLTWH(x + third * 0.5, y + 2, third * 1.5, h - 4), p);
    // Warm highlight strip — hue shift toward cream.
    p.color = const Color(0xFFD4C49A);
    canvas.drawRect(Rect.fromLTWH(x + third * 0.7, y + 3, third * 0.6, h - 6), p);
  } else if (frame == 1) {
    // Slack — subtle centre band, rest stays shadow.
    p.color = _linenBase.withValues(alpha: 0.7);
    canvas.drawRect(Rect.fromLTWH(x + third, y + 4, third, h - 8), p);
  } else {
    // Back — belly on far side.
    p.color = _linenBase;
    canvas.drawRect(Rect.fromLTWH(x + third, y + 2, third * 1.5, h - 4), p);
    p.color = const Color(0xFFD4C49A);
    canvas.drawRect(Rect.fromLTWH(x + third * 1.7, y + 3, third * 0.6, h - 6), p);
  }

  // Horizontal reef lines — dark seams across the sail.
  p.color = _linenShadow.withValues(alpha: 0.6);
  final lineCount = (h / 8).floor();
  for (int i = 1; i < lineCount; i++) {
    final ly = y + i * (h / lineCount);
    canvas.drawRect(Rect.fromLTWH(x + 2, ly, w - 4, 1), p);
  }

  // Bolt-rope hem on left and right edges.
  p.color = _ropeBeige;
  canvas.drawRect(Rect.fromLTWH(x, y, 2, h), p);
  canvas.drawRect(Rect.fromLTWH(x + w - 2, y, 2, h), p);
  // Bottom hem.
  canvas.drawRect(Rect.fromLTWH(x, y + h - 2, w, 2), p);
}

/// Draws a rope line as a series of 1×1 pixel steps (Bresenham-lite using
/// rect stepping) — only for short decorative rigging runs.
void _drawRopeLine(
  Canvas canvas,
  double x1,
  double y1,
  double x2,
  double y2,
  Paint p,
) {
  p.color = _ropeBeige.withValues(alpha: 0.7);
  final dx = x2 - x1;
  final dy = y2 - y1;
  final steps = (dx.abs() > dy.abs() ? dx.abs() : dy.abs()).toInt();
  if (steps == 0) return;
  final sx = dx / steps;
  final sy = dy / steps;
  // Draw every 2nd step to keep it visually sparse (rope, not filled line).
  for (int i = 0; i < steps; i += 2) {
    canvas.drawRect(Rect.fromLTWH(x1 + sx * i, y1 + sy * i, 1, 1), p);
  }
}

// ─── Stern platform ───────────────────────────────────────────────────────────

/// Draws the raised stern deck with helm wheel at its centre.
void drawGalleySternPlatform({
  required Canvas canvas,
  required Rect platformRect,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Deck planking — two alternating oak tones, hue-shifted.
  final plankCount = (platformRect.width / 8).floor();
  for (int i = 0; i < plankCount; i++) {
    p.color = i % 2 == 0 ? _oakMid : _oakSeam;
    canvas.drawRect(
        Rect.fromLTWH(platformRect.left + i * 8, platformRect.top,
            8, platformRect.height), p);
    // Plank highlight — cool amber stripe near top of each plank.
    p.color = const Color(0xFF4A3418);
    canvas.drawRect(Rect.fromLTWH(platformRect.left + i * 8 + 1,
        platformRect.top + 1, 5, 1), p);
  }

  // Raised edge — iron-bound step.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(
      platformRect.left, platformRect.top, platformRect.width, 2), p);
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(
      platformRect.left + 1, platformRect.top, platformRect.width - 2, 1), p);

  // Helm wheel.
  final hwx = platformRect.center.dx - 12;
  final hwy = platformRect.top + 4;
  _drawHelmWheel(canvas, hwx, hwy, tick, p);
}

void _drawHelmWheel(
  Canvas canvas,
  double x,
  double y,
  int tick,
  Paint p,
) {
  // 24×24 helm wheel — hub + 8 spokes + rim, all rects.
  const s = 24.0;

  // Outer rim — bronze ring (top, bottom, left, right bands).
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(x, y + 4, s, 4), p);          // top band
  canvas.drawRect(Rect.fromLTWH(x, y + s - 8, s, 4), p);      // bottom band
  canvas.drawRect(Rect.fromLTWH(x + 4, y, 4, s), p);          // left band
  canvas.drawRect(Rect.fromLTWH(x + s - 8, y, 4, s), p);      // right band

  // Rim highlight.
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 4, s - 2, 1), p);

  // Hub — centre square.
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(x + 9, y + 9, 6, 6), p);
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(x + 10, y + 10, 2, 2), p);

  // Spokes rotate 1 frame per 30 ticks (4 visual positions).
  final rot = (tick ~/ 30) % 4;
  p.color = _oakDark;

  // Horizontal and vertical spokes (always present — only visual offset rotates).
  final offsets = const [
    [0.0, 0.0],
    [1.0, 0.0],
    [2.0, 0.0],
    [1.0, 1.0],
  ];
  final o = offsets[rot];
  // Horizontal spoke.
  canvas.drawRect(Rect.fromLTWH(x + 2 + o[0], y + 11, s - 4, 2), p);
  // Vertical spoke.
  canvas.drawRect(Rect.fromLTWH(x + 11, y + 2 + o[1], 2, s - 4), p);
  // Diagonal spokes (lighter, simulated with shorter rects).
  p.color = _oakSeam;
  canvas.drawRect(Rect.fromLTWH(x + 4 + o[0], y + 4, 4, 4), p);
  canvas.drawRect(Rect.fromLTWH(x + s - 8 + o[0], y + 4, 4, 4), p);
  canvas.drawRect(Rect.fromLTWH(x + 4 + o[0], y + s - 8, 4, 4), p);
  canvas.drawRect(Rect.fromLTWH(x + s - 8 + o[0], y + s - 8, 4, 4), p);
}

// ─── Bow ──────────────────────────────────────────────────────────────────────

/// Draws the bronze bow ram and optional decorative figurehead at the prow.
void drawGalleyBow({
  required Canvas canvas,
  required Rect bowRect,
  required bool figureheadEnabled,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Ram body — tapers from hull width to point.
  // Three descending bands simulating the taper.
  final bw = bowRect.width;
  final bh = bowRect.height;
  final bx = bowRect.left;
  final by = bowRect.top;

  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(bx, by, bw, bh * 0.4), p);
  p.color = _bronzePatina;
  canvas.drawRect(Rect.fromLTWH(bx + 2, by + bh * 0.4, bw - 4, bh * 0.3), p);
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(bx + 4, by + bh * 0.7, bw - 8, bh * 0.15), p);
  // Ram tip.
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(bx + bw * 0.35, by + bh * 0.85, bw * 0.3, bh * 0.15), p);

  // Patina scratch marks on ram.
  p.color = _bronzePatina;
  canvas.drawRect(Rect.fromLTWH(bx + 3, by + 3, bw - 6, 1), p);
  canvas.drawRect(Rect.fromLTWH(bx + 5, by + 5, bw - 10, 1), p);

  if (!figureheadEnabled) return;

  // Figurehead — abstract angular form above the ram (not referencing any IP).
  // Geometric bird-wing silhouette in terracotta.
  p.color = _terracotta;
  canvas.drawRect(Rect.fromLTWH(bx + bw * 0.2, by - bh * 0.4, bw * 0.6, bh * 0.35), p);
  p.color = _accentRed;
  canvas.drawRect(Rect.fromLTWH(bx + bw * 0.35, by - bh * 0.55, bw * 0.3, bh * 0.2), p);
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(bx + bw * 0.42, by - bh * 0.5, bw * 0.16, bh * 0.08), p);
}

// ─── Lantern ─────────────────────────────────────────────────────────────────

/// Draws a hung bronze lantern (8×12) with slow 2-frame amber flicker.
void drawGalleyLantern({
  required Canvas canvas,
  required double x,
  required double y,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  final lit = (tick ~/ 24) % 2 == 0;

  // Hanging chain — 3 link dots.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x + 3, y, 2, 2), p);
  canvas.drawRect(Rect.fromLTWH(x + 3, y + 3, 2, 1), p);

  // Body — bronze cage.
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(x, y + 4, 8, 8), p);

  // Glass panel — warm amber or dim when flickering off.
  p.color = lit ? _amberGlow : const Color(0xFF3A2A0A);
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 5, 6, 6), p);

  // Cage bars.
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(x + 3, y + 5, 2, 6), p);   // vertical bar
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 7, 6, 1), p);   // horizontal bar

  // Cap and base.
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(x, y + 4, 8, 1), p);
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(x, y + 12, 8, 1), p);

  // Glow halo — faint amber rect below when lit.
  if (lit) {
    p.color = _amberGlow.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(x - 3, y + 6, 14, 10), p);
  }
}

// ─── Barrel ──────────────────────────────────────────────────────────────────

/// Draws a single 12×12 barrel or stacked 12×16 pair.
void drawGalleyBarrel({
  required Canvas canvas,
  required double x,
  required double y,
  bool stacked = false,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  _drawSingleBarrel(canvas, x, y + (stacked ? 4 : 0), p);
  if (stacked) {
    _drawSingleBarrel(canvas, x, y, p);
  }
}

void _drawSingleBarrel(Canvas canvas, double x, double y, Paint p) {
  // Stave body — warm oak with hue-shifted seams.
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(x + 1, y, 10, 12), p);
  // Highlight — cool amber facing viewer.
  p.color = const Color(0xFF4A3418);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 1, 4, 10), p);
  // Shadow side.
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(x + 8, y + 1, 3, 10), p);

  // Iron hoops.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x, y + 2, 12, 1), p);
  canvas.drawRect(Rect.fromLTWH(x, y + 6, 12, 1), p);
  canvas.drawRect(Rect.fromLTWH(x, y + 9, 12, 1), p);

  // Top cap.
  p.color = _oakSeam;
  canvas.drawRect(Rect.fromLTWH(x + 1, y, 10, 2), p);
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x, y, 1, 12), p);
  canvas.drawRect(Rect.fromLTWH(x + 11, y, 1, 12), p);
}

// ─── Amphora ─────────────────────────────────────────────────────────────────

/// Draws a terracotta amphora (8×14).
void drawGalleyAmphora({
  required Canvas canvas,
  required double x,
  required double y,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Body — wider in middle.
  p.color = _terracotta;
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 3, 4, 9), p);   // slim neck→body
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 5, 6, 6), p);   // wide belly
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 11, 4, 2), p);  // base taper

  // Rim highlight — hue-shifted to warm ochre.
  p.color = const Color(0xFF9A5030);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 5, 2, 5), p);

  // Neck and lip.
  p.color = _terracotta;
  canvas.drawRect(Rect.fromLTWH(x + 3, y, 2, 3), p);
  p.color = const Color(0xFF5A2810);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 3, 4, 1), p);

  // Handles — small lateral tabs.
  p.color = _terracotta;
  canvas.drawRect(Rect.fromLTWH(x, y + 5, 2, 4), p);
  canvas.drawRect(Rect.fromLTWH(x + 6, y + 5, 2, 4), p);

  // Base point.
  canvas.drawRect(Rect.fromLTWH(x + 3, y + 13, 2, 1), p);
}

// ─── Rope coil ───────────────────────────────────────────────────────────────

/// Draws a coiled rope on the deck (12×6 footprint).
void drawGalleyRopeCoil({
  required Canvas canvas,
  required double x,
  required double y,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Outer loop.
  p.color = _ropeBeige;
  canvas.drawRect(Rect.fromLTWH(x, y + 2, 12, 2), p);       // top run
  canvas.drawRect(Rect.fromLTWH(x, y + 2, 2, 4), p);         // left side
  canvas.drawRect(Rect.fromLTWH(x + 10, y + 2, 2, 4), p);    // right side
  canvas.drawRect(Rect.fromLTWH(x, y + 4, 12, 2), p);        // bottom run

  // Inner loop — darker strand.
  p.color = const Color(0xFF5A4A30);
  canvas.drawRect(Rect.fromLTWH(x + 3, y + 3, 6, 1), p);

  // Loose end.
  p.color = _ropeBeige;
  canvas.drawRect(Rect.fromLTWH(x + 6, y, 2, 3), p);

  // Shadow under coil.
  p.color = _oakDark.withValues(alpha: 0.4);
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 6, 11, 1), p);
}

// ─── Anchor ──────────────────────────────────────────────────────────────────

/// Draws a 16×20 anchor in iron with bronze chain link.
void drawGalleyAnchor({
  required Canvas canvas,
  required double x,
  required double y,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Ring at top.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x + 5, y, 6, 2), p);
  canvas.drawRect(Rect.fromLTWH(x + 5, y + 2, 2, 2), p);
  canvas.drawRect(Rect.fromLTWH(x + 9, y + 2, 2, 2), p);

  // Shank — vertical bar.
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(x + 7, y + 2, 2, 12), p);
  // Highlight on shank.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x + 7, y + 3, 1, 10), p);

  // Cross-stock — horizontal.
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 5, 14, 2), p);
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 5, 12, 1), p);

  // Arms — two flukes.
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 14, 4, 4), p);  // left fluke
  canvas.drawRect(Rect.fromLTWH(x + 10, y + 14, 4, 4), p); // right fluke
  // Fluke tips — narrower.
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 16, 2, 3), p);
  canvas.drawRect(Rect.fromLTWH(x + 13, y + 16, 2, 3), p);

  // Iron rust patches.
  p.color = _ironRust;
  canvas.drawRect(Rect.fromLTWH(x + 3, y + 15, 2, 2), p);
  canvas.drawRect(Rect.fromLTWH(x + 11, y + 15, 2, 2), p);
}

// ─── War drum ────────────────────────────────────────────────────────────────

/// Draws a 16×14 war drum with accent blink every 45 ticks.
void drawGalleyWarDrum({
  required Canvas canvas,
  required double x,
  required double y,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  final accent = (tick ~/ 45) % 2 == 0;

  // Shell body — terracotta with hue shift to dark red shadow.
  p.color = _terracotta;
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 3, 14, 9), p);
  p.color = _accentRed;
  canvas.drawRect(Rect.fromLTWH(x + 12, y + 3, 3, 9), p);  // shadow side

  // Drum head — linen stretched skin.
  p.color = _linenBase;
  canvas.drawRect(Rect.fromLTWH(x, y + 2, 16, 3), p);
  // Skin crease.
  p.color = _linenShadow;
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 2, 12, 1), p);

  // Bottom head.
  p.color = _linenBase;
  canvas.drawRect(Rect.fromLTWH(x, y + 10, 16, 3), p);
  p.color = _linenShadow;
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 12, 12, 1), p);

  // Iron tension bands.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x, y + 5, 16, 1), p);
  canvas.drawRect(Rect.fromLTWH(x, y + 8, 16, 1), p);

  // Mallet — visible resting on top when no accent beat.
  if (!accent) {
    p.color = _oakMid;
    canvas.drawRect(Rect.fromLTWH(x + 5, y - 3, 2, 5), p);
    p.color = _linenBase;
    canvas.drawRect(Rect.fromLTWH(x + 4, y - 5, 4, 3), p);
  } else {
    // Accent: mallet strike — shifted down, blink of amber on skin.
    p.color = _oakMid;
    canvas.drawRect(Rect.fromLTWH(x + 5, y - 1, 2, 4), p);
    p.color = _amberGlow.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, 6, 2), p);
  }
}

// ─── Shield on rail ──────────────────────────────────────────────────────────

/// Draws a round shield hanging on the outboard rail (16×14 sprite).
void drawGalleyShieldOnRail({
  required Canvas canvas,
  required double x,
  required double y,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Rail bar behind shield.
  p.color = _oakSeam;
  canvas.drawRect(Rect.fromLTWH(x - 1, y + 5, 18, 2), p);

  // Shield body — round approximated as three stacked bands.
  p.color = _accentRed;
  canvas.drawRect(Rect.fromLTWH(x + 2, y, 12, 14), p);     // main field
  canvas.drawRect(Rect.fromLTWH(x, y + 2, 16, 10), p);     // wide band

  // Rim — bronze.
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(x, y + 2, 2, 10), p);
  canvas.drawRect(Rect.fromLTWH(x + 14, y + 2, 2, 10), p);
  canvas.drawRect(Rect.fromLTWH(x + 2, y, 12, 2), p);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 12, 12, 2), p);

  // Rim highlight.
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 2, 1, 10), p);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 1, 12, 1), p);

  // Boss — central iron dome approximated as nested rects.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x + 5, y + 4, 6, 6), p);
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(x + 6, y + 5, 4, 4), p);
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x + 7, y + 6, 2, 2), p);
}

// ─── Cargo crate ─────────────────────────────────────────────────────────────

/// Draws a wooden cargo crate (~14×12 footprint) with iron banding —
/// designed to slot into furniture placement on the deck.
void drawGalleyCrate({
  required Canvas canvas,
  required double x,
  required double y,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // Outer wood — dark oak base.
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(x, y, 14, 12), p);

  // Plank face — mid oak fill.
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, 12, 10), p);

  // Horizontal plank seams.
  p.color = _oakSeam;
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 4, 12, 1), p);
  canvas.drawRect(Rect.fromLTWH(x + 1, y + 8, 12, 1), p);

  // Iron corner brackets (top corners).
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(x, y, 2, 3), p);
  canvas.drawRect(Rect.fromLTWH(x + 12, y, 2, 3), p);
  // Bottom corners.
  canvas.drawRect(Rect.fromLTWH(x, y + 9, 2, 3), p);
  canvas.drawRect(Rect.fromLTWH(x + 12, y + 9, 2, 3), p);

  // Iron band across the middle (highlight on top edge).
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x, y + 5, 14, 2), p);
  p.color = _ironDark;
  canvas.drawRect(Rect.fromLTWH(x, y + 6, 14, 1), p);

  // Nail dots on band.
  p.color = _ironRust;
  canvas.drawRect(Rect.fromLTWH(x + 3, y + 5, 1, 1), p);
  canvas.drawRect(Rect.fromLTWH(x + 10, y + 5, 1, 1), p);
}

// ─── Oar ─────────────────────────────────────────────────────────────────────

/// Draws a single oar (6 wide × 40 tall) protruding from the hull.
/// [direction]: -1 = left side (oar angles left), +1 = right side.
/// 2-frame gentle bob every 60 ticks.
void drawGalleyOar({
  required Canvas canvas,
  required double x,
  required double y,
  required int direction,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  final bob = (tick ~/ 60) % 2 == 0 ? 0.0 : 1.0;
  final bobY = y + bob;

  // Loom (handle shaft) — dark oak.
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(x + 1, bobY, 3, 28), p);
  // Shaft highlight — warm amber seam.
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(x + 2, bobY + 1, 1, 26), p);

  // Collar band at pivot.
  p.color = _ironBand;
  canvas.drawRect(Rect.fromLTWH(x, bobY + 24, 6, 2), p);

  // Blade — wider, hue-shifted to lighter oak.
  final bladeX = direction == -1 ? x - 2 : x + 1;
  p.color = const Color(0xFF4A3418);
  canvas.drawRect(Rect.fromLTWH(bladeX, bobY + 26, 6, 12), p);
  // Blade tip — shadow.
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(bladeX + 1, bobY + 34, 4, 4), p);
  // Blade highlight.
  p.color = const Color(0xFF6A4E28);
  canvas.drawRect(Rect.fromLTWH(bladeX + 1, bobY + 27, 2, 10), p);
}

/// Draws a horizontal oar that crosses the hull at [pivotX], [pivotY]:
/// the handle ([handleLen] px) extends inboard along the deck, the blade
/// extends outboard into the water. [direction]: -1 = oar points left
/// (left-side bank), +1 = oar points right (right-side bank). 4-frame
/// rowing cycle every [rowTicks] ticks pivots the blade slightly up/down,
/// simulating the catch-pull-recover stroke of a rowing crew.
void drawGalleyOarThroughHull({
  required Canvas canvas,
  required double pivotX,
  required double pivotY,
  required int direction,
  required int tick,
  double handleLen = 18,
  double bladeLen = 26,
  int rowTicks = 40,
}) {
  final p = Paint()..style = PaintingStyle.fill;

  // 4-frame rowing pivot: 0 catch (blade tip slightly down), 1 pull (level),
  // 2 release (blade tip slightly up), 3 recover (level). Cycle pingpong by
  // remapping 0→0, 1→1, 2→2, 3→1 — gives uneven dwell on level positions.
  final phase = (tick ~/ rowTicks) % 4;
  final tip = switch (phase) {
    0 => 1.5,   // catch — blade tip dips toward water
    1 => 0.0,   // pull — horizontal
    2 => -1.5,  // release — blade tip lifts
    _ => 0.0,   // recover
  };

  // Handle extends inboard (toward deck centre).
  final handleStartX = direction == -1 ? pivotX : pivotX - handleLen;
  // Vertical offset along the blade (slope from pivot to tip).
  final tipSlope = tip / bladeLen; // px per outboard px

  // Handle loom — flat horizontal shaft on deck.
  p.color = _oakDark;
  canvas.drawRect(Rect.fromLTWH(handleStartX, pivotY - 1, handleLen, 3), p);
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(handleStartX, pivotY - 1, handleLen, 1), p);

  // Pivot collar (bronze oarlock at hull).
  p.color = _bronzeRim;
  canvas.drawRect(Rect.fromLTWH(pivotX - 1, pivotY - 2, 3, 5), p);
  p.color = _bronzeHi;
  canvas.drawRect(Rect.fromLTWH(pivotX, pivotY - 2, 1, 1), p);

  // Blade shaft — outboard, sloped per rowing phase.
  // Render in 1px-wide segments stepping outboard so the slope reads as
  // pixels even though we only use drawRect.
  final stepDir = direction.toDouble();
  for (int step = 0; step < bladeLen.toInt(); step++) {
    final sx = direction == -1
        ? pivotX - 1 - step
        : pivotX + 1 + step;
    // Slope: shaft for first ~70%, blade widens at outboard end.
    final shaftPortion = bladeLen * 0.65;
    final isBlade = step >= shaftPortion;
    final yOff = step * tipSlope * stepDir.abs();
    final colY = pivotY + yOff;

    if (!isBlade) {
      // Thin shaft 3px tall.
      p.color = _oakDark;
      canvas.drawRect(Rect.fromLTWH(sx, colY - 1, 1, 3), p);
      p.color = _oakMid;
      canvas.drawRect(Rect.fromLTWH(sx, colY - 1, 1, 1), p);
    } else {
      // Blade — taller, hue-shifted. Widens toward tip.
      final progress = (step - shaftPortion) / (bladeLen - shaftPortion);
      final h = (3 + progress * 6).toDouble();
      p.color = const Color(0xFF4A3418);
      canvas.drawRect(Rect.fromLTWH(sx, colY - h / 2, 1, h), p);
      // Highlight along the upper edge of the blade.
      p.color = const Color(0xFF6A4E28);
      canvas.drawRect(Rect.fromLTWH(sx, colY - h / 2, 1, 1), p);
    }
  }

  // Tiny foam splash where the blade meets the water — only on catch phase.
  if (phase == 0) {
    final splashX = direction == -1
        ? pivotX - bladeLen
        : pivotX + bladeLen - 4;
    p.color = _foamWhite.withValues(alpha: 0.55);
    canvas.drawRect(Rect.fromLTWH(splashX, pivotY + tip - 1, 4, 1), p);
  }
}

// ─── Flag ─────────────────────────────────────────────────────────────────────

/// Draws a 16×10 pennant at the mast top with 4-frame fast wave animation.
void drawGalleyFlag({
  required Canvas canvas,
  required double mastTopX,
  required double mastTopY,
  required int tick,
}) {
  final p = Paint()..style = PaintingStyle.fill;
  final frame = (tick ~/ 6) % 4;

  // Flag staff extension above mast.
  p.color = _oakMid;
  canvas.drawRect(Rect.fromLTWH(mastTopX, mastTopY - 6, 2, 6), p);

  // Flag body — 4 wave shapes simulate the banner snapping in the breeze.
  // Each frame offsets the ripple by 4px to the right.
  final waveOffset = frame * 4.0;

  // Shadow layer — terracotta banner base.
  p.color = _accentRed;
  canvas.drawRect(Rect.fromLTWH(mastTopX + 2, mastTopY - 5, 14, 9), p);

  // Mid highlight — brighter on the leading belly.
  p.color = const Color(0xFFAA2020);
  final hiX = mastTopX + 2 + waveOffset;
  final hiW = (14.0 - waveOffset).clamp(0.0, 14.0);
  if (hiW > 0) {
    canvas.drawRect(Rect.fromLTWH(hiX, mastTopY - 4, hiW, 7), p);
  }

  // Trailing shadow — dark fold where flag folds back.
  if (frame > 0) {
    p.color = _accentRed.withValues(alpha: 0.6);
    canvas.drawRect(
        Rect.fromLTWH(mastTopX + 2, mastTopY - 5, (frame * 3.0).toDouble(), 9), p);
  }

  // Horizontal line divider on flag (golden band).
  p.color = _amberGlow;
  canvas.drawRect(Rect.fromLTWH(mastTopX + 3, mastTopY - 1, 11, 1), p);
}
