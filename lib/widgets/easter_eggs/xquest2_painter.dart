// XQuest 2 — Painter (CustomPainter)
// Renders: tilemap, all entities, HUD, screen overlays.
// All sprites drawn pixel-by-pixel via canvas.drawRect() at scaled pixel size.

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'xquest2_types.dart';
import 'xquest2_powerup.dart';
import 'xquest2_sprites.dart';

// ─── Sprite helper ────────────────────────────────────────────────────────────

void _drawSprite(Canvas canvas, List<int> pixels, int w, int h,
    double cx, double cy, double ps) {
  final paint = Paint()..isAntiAlias = false;
  final left = cx - w * ps / 2;
  final top = cy - h * ps / 2;
  for (int i = 0; i < pixels.length; i++) {
    final argb = pixels[i];
    if (argb == 0) continue;
    final col = i % w, row = i ~/ w;
    paint.color = Color(argb);
    canvas.drawRect(
      Rect.fromLTWH(left + col * ps, top + row * ps, ps, ps),
      paint,
    );
  }
}

void _drawSpriteFrame(Canvas canvas, List<List<int>> frames, int frame, int w, int h,
    double cx, double cy, double ps) {
  final f = frame.clamp(0, frames.length - 1);
  _drawSprite(canvas, frames[f], w, h, cx, cy, ps);
}

// ─── Tilemap palette ──────────────────────────────────────────────────────────

int _tileHash(int tx, int ty) => (tx * 7 + ty * 13) & 0xFF;

const _floorColors = <Color>[
  Color(0xFF000828),
  Color(0xFF00082C),
  Color(0xFF000830),
  Color(0xFF001030),
];
const _wallColor = Color(0xFF2244AA);
const _wallEdgeColor = Color(0xFF4466CC);
const _wallBorderColor = Color(0xFF1133AA);

// ─── Main Painter ─────────────────────────────────────────────────────────────

class XQuest2Painter extends CustomPainter {
  final GameData gd;
  final double pixelSize;

  XQuest2Painter(this.gd, this.pixelSize);

  @override
  void paint(Canvas canvas, Size size) {
    final ps = pixelSize;
    final camX = gd.camX;
    final camY = gd.camY;

    // Background fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF000820),
    );

    // Starfield (world-space, scrolls with camera)
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (int i = 0; i < gd.starX.length; i++) {
      final sx = (gd.starX[i] - camX) * ps;
      final sy = (gd.starY[i] - camY) * ps;
      if (sx < 0 || sx > size.width || sy < 0 || sy > size.height) continue;
      canvas.drawRect(Rect.fromLTWH(sx, sy, ps, ps), starPaint);
    }

    // ── World layer (offset by camera) ─────────────────────────────────────
    canvas.save();
    canvas.translate(-camX * ps, -camY * ps);

    _drawTilemap(canvas, gd, ps);
    _drawGems(canvas, gd, ps);
    _drawMines(canvas, gd, ps);
    _drawPowerCharges(canvas, gd, ps);
    _drawPowerUpDrops(canvas, gd, ps);
    _drawExplosions(canvas, gd, ps);
    _drawEnemies(canvas, gd, ps);
    _drawBullets(canvas, gd, ps);
    _drawPlayer(canvas, gd, ps);
    _drawGate(canvas, gd, ps);

    canvas.restore();

    // ── HUD (fixed, no camera offset) ──────────────────────────────────────
    _drawHud(canvas, gd, ps, size);
  }

  // ── Tilemap ────────────────────────────────────────────────────────────────

  void _drawTilemap(Canvas canvas, GameData gd, double ps) {
    final paint = Paint()..isAntiAlias = false;
    for (int ty = 0; ty < mapTilesH; ty++) {
      for (int tx = 0; tx < mapTilesW; tx++) {
        final cell = gd.tilemap[ty][tx];
        final worldX = tx * tileW * ps;
        final worldY = (ty * tileH + hudHeight) * ps;
        final rect = Rect.fromLTWH(worldX, worldY, tileW * ps, tileH * ps);

        if (cell == 1) {
          // Wall — check for border vs interior
          final isBorder = tx == 0 || tx == mapTilesW - 1 || ty == 0 || ty == mapTilesH - 1;
          // Edge detection: wall adjacent to floor
          final openN = ty == 0 || gd.tilemap[ty - 1][tx] == 0;
          final openS = ty == mapTilesH - 1 || gd.tilemap[ty + 1][tx] == 0;
          final openW = tx == 0 || gd.tilemap[ty][tx - 1] == 0;
          final openE = tx == mapTilesW - 1 || gd.tilemap[ty][tx + 1] == 0;
          final isEdge = openN || openS || openW || openE;

          paint.color = isBorder
              ? _wallBorderColor
              : isEdge
                  ? _wallEdgeColor
                  : _wallColor;
          canvas.drawRect(rect, paint);

          // Highlight edge pixels
          if (isEdge) {
            paint.color = const Color(0xFF6688EE);
            if (openN) canvas.drawRect(Rect.fromLTWH(worldX, worldY, tileW * ps, ps), paint);
            if (openS) canvas.drawRect(Rect.fromLTWH(worldX, worldY + (tileH - 1) * ps, tileW * ps, ps), paint);
            if (openW) canvas.drawRect(Rect.fromLTWH(worldX, worldY, ps, tileH * ps), paint);
            if (openE) canvas.drawRect(Rect.fromLTWH(worldX + (tileW - 1) * ps, worldY, ps, tileH * ps), paint);
          }
        } else {
          // Floor — hash-based variant
          final hash = _tileHash(tx, ty);
          final colorIdx = ((hash & 0x07) == 0)
              ? 3
              : hash % (_floorColors.length - 1);
          paint.color = _floorColors[colorIdx];
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  // ── Gate ───────────────────────────────────────────────────────────────────

  void _drawGate(Canvas canvas, GameData gd, double ps) {
    if (!gd.gateOpen && gd.gateAnimFrame == 0) {
      // Gate is closed — it's just the wall (already drawn)
      return;
    }

    // Draw gate opening indicator at gateX, top border
    final gx = gd.gateX * ps;
    final gy = hudHeight * ps;
    final openFrac = gd.gateAnimFrame / 8.0;
    final openW = (32 * openFrac).clamp(4, 32.0) * ps;

    final paint = Paint()
      ..color = gd.gateOpen
          ? const Color(0xFF00FF88)
          : const Color(0xFF00AA66);
    canvas.drawRect(
      Rect.fromLTWH(gx - openW / 2, gy - ps, openW, tileH * ps),
      paint,
    );

    // Pulsing glow when fully open
    if (gd.gateOpen && gd.gateAnimFrame >= 8) {
      final glowPaint = Paint()
        ..color = const Color(0x4000FF88)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRect(
        Rect.fromLTWH(gx - openW / 2 - 4, gy - 4, openW + 8, tileH * ps + 8),
        glowPaint,
      );
    }
  }

  // ── Gems ───────────────────────────────────────────────────────────────────

  void _drawGems(Canvas canvas, GameData gd, double ps) {
    for (final g in gd.gems) {
      if (!g.active || g.collected) continue;
      _drawSprite(canvas, xq2Crystal, xq2CrystalW, xq2CrystalH,
          g.x * ps, g.y * ps, ps);
    }
  }

  // ── Mines ──────────────────────────────────────────────────────────────────

  void _drawMines(Canvas canvas, GameData gd, double ps) {
    final blink = (gd.frameCount ~/ 15) % 2 == 0;
    for (final m in gd.mines) {
      if (!m.active) continue;
      if (!blink) {
        _drawSprite(canvas, xq2Mine, xq2MineW, xq2MineH,
            m.x * ps, m.y * ps, ps);
      } else {
        // Blink: draw smaller glow
        final p = Paint()..color = const Color(0xFFFF3333);
        canvas.drawCircle(Offset(m.x * ps, m.y * ps), 4 * ps, p);
      }
    }
  }

  // ── PowerCharges ───────────────────────────────────────────────────────────

  void _drawPowerCharges(Canvas canvas, GameData gd, double ps) {
    for (final pc in gd.powerCharges) {
      if (!pc.active) continue;
      _drawSprite(canvas, xq2Attractor, xq2AttractorW, xq2AttractorH,
          pc.x * ps, pc.y * ps, ps);
    }
  }

  // ── PowerUp drops ──────────────────────────────────────────────────────────

  void _drawPowerUpDrops(Canvas canvas, GameData gd, double ps) {
    for (final d in gd.powerUpDrops) {
      if (!d.active) continue;
      // Coloured box with letter
      final color = _powerUpColor(d.type);
      final boxPaint = Paint()..color = color;
      canvas.drawRect(
        Rect.fromLTWH(d.x * ps - 6 * ps, d.y * ps - 6 * ps, 12 * ps, 12 * ps),
        boxPaint,
      );
      final tp = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontSize: 10 * ps,
        textAlign: TextAlign.center,
      ))
        ..pushStyle(ui.TextStyle(color: Colors.black, fontWeight: FontWeight.bold))
        ..addText(d.letter);
      final para = tp.build()..layout(ui.ParagraphConstraints(width: 12 * ps));
      canvas.drawParagraph(para, Offset(d.x * ps - 6 * ps, d.y * ps - 5 * ps));
    }
  }

  // ── Explosions ─────────────────────────────────────────────────────────────

  void _drawExplosions(Canvas canvas, GameData gd, double ps) {
    for (final ex in gd.explosions) {
      if (!ex.active) continue;
      _drawSpriteFrame(canvas, xq2ExplosionFrames, ex.frame,
          xq2ExplosionW, xq2ExplosionH, ex.x * ps, ex.y * ps, ps);
    }
  }

  // ── Enemies ────────────────────────────────────────────────────────────────

  void _drawEnemies(Canvas canvas, GameData gd, double ps) {
    for (final e in gd.enemies) {
      if (!e.active) continue;
      final (frames, w, h) = _enemySprite(e.type);
      _drawSpriteFrame(canvas, frames, e.animFrame, w, h,
          e.x * ps, e.y * ps, ps);
    }
  }

  // ── Bullets ────────────────────────────────────────────────────────────────

  void _drawBullets(Canvas canvas, GameData gd, double ps) {
    for (final b in gd.bullets) {
      if (!b.active) continue;
      final paint = Paint()..color = _bulletColor(b.bulletType);
      final r = b.isPlayer ? 1.5 * ps : 2.0 * ps;
      canvas.drawCircle(Offset(b.x * ps, b.y * ps), r, paint);
    }
  }

  // ── Player ─────────────────────────────────────────────────────────────────

  void _drawPlayer(Canvas canvas, GameData gd, double ps) {
    final p = gd.player;
    if (!p.active) return;
    if (p.dying > 0) return;

    // Invincibility flash every 6 frames
    if (p.invincible > 0 && (p.invincible ~/ 6) % 2 == 0) return;

    // Ship sprite — 24 rotation frames
    final frame = p.direction.clamp(0, xq2ShipFrames.length - 1);
    _drawSpriteFrame(canvas, xq2ShipFrames, frame,
        xq2ShipW, xq2ShipH, p.x * ps, p.y * ps, ps);

    // Shield glow
    if (powerupActive(gd, PowerUpId.shield)) {
      final glowPaint = Paint()
        ..color = const Color(0x5500FFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(p.x * ps, p.y * ps), 12 * ps, glowPaint);
    }
  }

  // ── HUD ────────────────────────────────────────────────────────────────────

  void _drawHud(Canvas canvas, GameData gd, double ps, Size size) {
    final p = gd.player;

    // HUD background bar
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, hudHeight * ps),
      Paint()..color = const Color(0xFF0A0A18),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, hudHeight * ps - ps, size.width, ps),
      Paint()..color = const Color(0xFF2244AA),
    );

    // Score (left)
    _drawText(canvas, 'SCORE: ${p.score}', 4 * ps, 3 * ps, 7 * ps,
        const Color(0xFFFFFFCC));

    // Level (centre)
    _drawText(canvas, 'LVL ${gd.level}', size.width / 2, 3 * ps, 7 * ps,
        const Color(0xFF88CCFF), center: true);

    // Crystals remaining (right of centre)
    _drawText(canvas, '◆ ${gd.gemsRemaining}', size.width / 2 + 40 * ps, 3 * ps, 7 * ps,
        const Color(0xFFFFCC00));

    // Lives (top-right area)
    _drawText(canvas, '♥ ${p.lives}', size.width - 60 * ps, 3 * ps, 7 * ps,
        const Color(0xFFFF4444));

    // Smartbombs
    _drawText(canvas, '✦ ${p.smartbombs}', size.width - 30 * ps, 3 * ps, 7 * ps,
        const Color(0xFF44AAFF));

    // Active powerup indicators (bottom strip)
    _drawPowerupBar(canvas, gd, ps, size);
  }

  void _drawPowerupBar(Canvas canvas, GameData gd, double ps, Size size) {
    const letters = ['S', 'R', 'M', 'F', 'A', 'H', 'B'];
    double xOff = 4 * ps;
    final barY = size.height - 10 * ps;

    for (int i = 0; i < PowerUpId.values.length; i++) {
      if (gd.powerupTimer[i] > 0) {
        final color = _powerUpColor(PowerUpId.values[i]);
        canvas.drawRect(
          Rect.fromLTWH(xOff, barY, 8 * ps, 8 * ps),
          Paint()..color = color.withValues(alpha: 0.8),
        );
        _drawText(canvas, letters[i], xOff + 4 * ps, barY + 1 * ps, 6 * ps,
            Colors.black, center: true);
        xOff += 10 * ps;
      }
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, double fontSize,
      Color color, {bool center = false}) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: fontSize,
      textAlign: center ? TextAlign.center : TextAlign.left,
    ))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: 'monospace',
        fontWeight: FontWeight.bold,
      ))
      ..addText(text);
    final para = pb.build()
      ..layout(ui.ParagraphConstraints(width: 200));
    canvas.drawParagraph(para, Offset(center ? x - 100 : x, y));
  }

  @override
  bool shouldRepaint(XQuest2Painter old) => true;
}

// ─── Sprite / Color lookups ───────────────────────────────────────────────────

(List<List<int>>, int, int) _enemySprite(EnemyType t) {
  switch (t) {
    case EnemyType.grunger:    return (xq2GrungerFrames, xq2GrungerW, xq2GrungerH);
    case EnemyType.zippo:      return (xq2ZippoFrames, xq2ZippoW, xq2ZippoH);
    case EnemyType.zinger:     return (xq2ZingerFrames, xq2ZingerW, xq2ZingerH);
    case EnemyType.vince:      return (xq2VinceFrames, xq2VinceW, xq2VinceH);
    case EnemyType.miner:      return (xq2MinerFrames, xq2MinerW, xq2MinerH);
    case EnemyType.meeby:      return (xq2MeebyFrames, xq2MeebyW, xq2MeebyH);
    case EnemyType.retaliator: return (xq2RetaliatorFrames, xq2RetaliatorW, xq2RetaliatorH);
    case EnemyType.terrier:    return (xq2TerrierFrames, xq2TerrierW, xq2TerrierH);
    case EnemyType.doinger:    return (xq2DoingerFrames, xq2DoingerW, xq2DoingerH);
    case EnemyType.snipe:      return (xq2SnipeFrames, xq2SnipeW, xq2SnipeH);
    case EnemyType.tribbler:   return (xq2TribblerFrames, xq2TribblerW, xq2TribblerH);
    case EnemyType.buckshot:   return (xq2BuckshotFrames, xq2BuckshotW, xq2BuckshotH);
    case EnemyType.cluster:    return (xq2ClusterFrames, xq2ClusterW, xq2ClusterH);
    case EnemyType.sticktight: return (xq2SticktightFrames, xq2SticktightW, xq2SticktightH);
    case EnemyType.repulsor:   return (xq2RepulsorFrames, xq2RepulsorW, xq2RepulsorH);
  }
}

Color _bulletColor(BulletType t) {
  switch (t) {
    case BulletType.player:   return const Color(0xFFFFFFFF);
    case BulletType.green:    return const Color(0xFF00FF44);
    case BulletType.yellow:   return const Color(0xFFFFFF00);
    case BulletType.purple:   return const Color(0xFFCC44FF);
    case BulletType.buckshot: return const Color(0xFFFF8800);
  }
}

Color _powerUpColor(PowerUpId id) {
  switch (id) {
    case PowerUpId.shield:    return const Color(0xFF00FFFF);
    case PowerUpId.aimedFire: return const Color(0xFFFFFF00);
    case PowerUpId.rapidFire: return const Color(0xFFFF8800);
    case PowerUpId.multiFire: return const Color(0xFF00FF00);
    case PowerUpId.assFire:   return const Color(0xFFAA44FF);
    case PowerUpId.heavyFire: return const Color(0xFFFF2222);
    case PowerUpId.bounce:    return const Color(0xFFFFFFFF);
  }
}
