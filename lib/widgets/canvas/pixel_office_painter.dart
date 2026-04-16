/// CustomPainter that renders the pixel-art office scene with Z-sorted entities.
///
/// Uses PNG sprite sheets from pixel-agents for characters (16×32) and
/// furniture. Falls back to text-based sprites when images aren't loaded yet.
///
/// Supports resource packs: [RoomTheme] for environment colors,
/// [ComputerType] for monitor sprites, and [CharacterSkin] for agent palettes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/agent_message.dart';
import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';
import 'character_skins.dart';
import 'character_sprites.dart';
import 'computer_sprites.dart';
import 'office_game_state.dart';
import 'pixel_sprites.dart';
import 'room_themes.dart';

// ─── Z-sortable drawable ────────────────────────────────────────────────────

class _Drawable {
  final double zY;
  final void Function(Canvas canvas) draw;
  _Drawable(this.zY, this.draw);
}

// ─── Paint for pixel-perfect image rendering ────────────────────────────────

final _pixelPaint = Paint()..filterQuality = FilterQuality.none;

// ─── Painter ────────────────────────────────────────────────────────────────

class PixelOfficePainter extends CustomPainter {
  final OfficeGameState gameState;
  final SpriteManager? sprites;
  final String? selectedAgentId;
  final String? hoveredAgentId;
  final int tick;
  final OfficeLevel officeLevel;
  final CharacterSkin? skin;

  PixelOfficePainter({
    required this.gameState,
    this.sprites,
    this.selectedAgentId,
    this.hoveredAgentId,
    this.tick = 0,
    this.officeLevel = OfficeLevel.garage,
    this.skin,
  });

  bool get _hasImages => sprites != null && sprites!.isLoaded;

  RoomTheme get _theme => roomThemeForLevel(officeLevel);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / kCanvasWidth,
      size.height / kCanvasHeight,
    );
    final offsetX = (size.width - kCanvasWidth * scale) / 2;
    final offsetY = (size.height - kCanvasHeight * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    _drawFloorAndWalls(canvas);
    _drawScene(canvas);
    _drawBubbles(canvas);
    _drawVignette(canvas);

    canvas.restore();
  }

  // ─── Floor & walls ──────────────────────────────────────────────────────

  void _drawFloorAndWalls(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;
    final tileMap = gameState.tileMap;
    final theme = _theme;

    for (int r = 0; r < kGridRows; r++) {
      for (int c = 0; c < kGridCols; c++) {
        final tx = c * kTileSize;
        final ty = r * kTileSize;
        final tile = tileMap[r][c];

        if (tile == TileType.wall) {
          paint.color = theme.wallBase;
          canvas.drawRect(
            Rect.fromLTWH(tx, ty, kTileSize + 0.5, kTileSize + 0.5), paint);

          if (r > 0 && tileMap[r - 1][c] == TileType.floor) {
            paint.color = theme.wallTop;
            canvas.drawRect(Rect.fromLTWH(tx, ty, kTileSize + 0.5, 2), paint);
          }
          if (r < kGridRows - 1 && tileMap[r + 1][c] == TileType.floor) {
            paint.color = theme.wallInner;
            canvas.drawRect(
              Rect.fromLTWH(tx, ty + kTileSize - 2, kTileSize + 0.5, 2), paint);
          }
        } else {
          paint.color = (c + r) % 2 == 0 ? theme.floorDark : theme.floorLight;
          canvas.drawRect(
            Rect.fromLTWH(tx, ty, kTileSize + 0.5, kTileSize + 0.5), paint);
        }
      }
    }

    // Subtle grid
    paint
      ..color = theme.floorGrid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3;
    for (int c = 1; c < kGridCols; c++) {
      canvas.drawLine(
        Offset(c * kTileSize, kTileSize),
        Offset(c * kTileSize, (kGridRows - 1) * kTileSize),
        paint,
      );
    }
    for (int r = 1; r < kGridRows; r++) {
      canvas.drawLine(
        Offset(kTileSize, r * kTileSize),
        Offset((kGridCols - 1) * kTileSize, r * kTileSize),
        paint,
      );
    }
  }

  // ─── Z-sorted scene ─────────────────────────────────────────────────────

  void _drawScene(Canvas canvas) {
    final drawables = <_Drawable>[];

    // Furniture per station: desk, PC, chair (only for hired agents)
    for (final station in kStations) {
      final ch = gameState.characters[station.agentId];
      if (ch == null || !ch.isHired) continue;
      final isActive = ch.isActive;
      _addStationFurniture(drawables, station, isActive, ch);
    }

    // Coffee machine
    _addCoffeeMachine(drawables);

    // Decorative plants in corners (not in garage)
    if (officeLevel != OfficeLevel.garage) {
      _addPlants(drawables);
    }

    // Characters (only hired)
    for (final ch in gameState.characters.values) {
      if (!ch.isHired) continue;
      _addCharacter(drawables, ch);
    }

    // Office cat
    _addCat(drawables);

    drawables.sort((a, b) => a.zY.compareTo(b.zY));
    for (final d in drawables) {
      d.draw(canvas);
    }
  }

  void _addStationFurniture(
    List<_Drawable> drawables,
    DeskStation station,
    bool isActive,
    GameCharacter ch,
  ) {
    final deskTileX = station.deskCol * kTileSize;
    final deskTileY = station.deskRow * kTileSize;
    final deskZY = (station.deskRow + 1) * kTileSize.toDouble();
    final theme = _theme;

    // ── Desk surface (programmatic or PNG) ──
    final deskImg = sprites?.furniture('DESK_FRONT');
    if (_hasImages && deskImg != null) {
      final dw = 48.0;
      final dh = 32.0;
      final dx = deskTileX + kTileSize / 2 - dw / 2;
      final dy = deskTileY + kTileSize * 2 - dh;
      drawables.add(_Drawable(deskZY, (c) {
        c.drawImageRect(
          deskImg,
          Rect.fromLTWH(0, 0, deskImg.width.toDouble(), deskImg.height.toDouble()),
          Rect.fromLTWH(dx, dy, dw, dh),
          _pixelPaint,
        );
      }));
    } else {
      // Fallback: colored rectangle using theme desk colors
      drawables.add(_Drawable(deskZY, (c) {
        final p = Paint()..style = PaintingStyle.fill;
        p.color = theme.deskSurface;
        c.drawRect(Rect.fromLTWH(deskTileX + 1, deskTileY + 10, 14, 5), p);
        p.color = theme.deskEdge;
        c.drawRect(Rect.fromLTWH(deskTileX + 1, deskTileY + 15, 14, 1), p);
      }));
    }

    // ── PC / Monitor ──
    // Determine computer type from agent's hardware tier
    final compType = computerForHardware(ch.hardware);

    final pcName = isActive
        ? 'PC_FRONT_ON_${(tick % 3) + 1}'
        : 'PC_FRONT_OFF';
    final pcImg = sprites?.furniture(pcName);
    if (_hasImages && pcImg != null) {
      final px = deskTileX.toDouble();
      final py = deskTileY - kTileSize;
      drawables.add(_Drawable(deskZY + 0.5, (c) {
        c.drawImageRect(
          pcImg,
          Rect.fromLTWH(0, 0, pcImg.width.toDouble(), pcImg.height.toDouble()),
          Rect.fromLTWH(px, py, kSpriteW.toDouble(), kSpriteH.toDouble()),
          _pixelPaint,
        );
      }));
    } else {
      // Fallback: text sprite monitor from computer type
      final frame = isActive
          ? (tick % 2 == 0 ? compType.monitorOn0 : compType.monitorOn1)
          : compType.monitorOff;
      drawables.add(_Drawable(deskZY + 0.5, (c) {
        drawSprite(c, frame, deskTileX + 4, deskTileY + 4, 1.0,
            (k) => compType.resolveKey(k, active: isActive));
      }));
    }

    // ── Monitor glow on desk ──
    if (isActive) {
      final glowColor = compType.monitorGlow;
      drawables.add(_Drawable(deskZY + 0.3, (c) {
        c.drawRect(
          Rect.fromLTWH(deskTileX + 2, deskTileY + 10, 12, 6),
          Paint()
            ..color = glowColor.withValues(alpha: 0.08)
            ..style = PaintingStyle.fill,
        );
      }));
    }

    // ── Chair (behind character) ──
    final chairImg = sprites?.furniture('CUSHIONED_CHAIR_BACK');
    if (_hasImages && chairImg != null) {
      final cx = station.seatCol * kTileSize.toDouble();
      final cy = station.seatRow * kTileSize.toDouble();
      final chairZY = (station.seatRow + 1) * kTileSize - 0.5;
      drawables.add(_Drawable(chairZY, (c) {
        c.drawImageRect(
          chairImg,
          Rect.fromLTWH(
            0, 0, chairImg.width.toDouble(), chairImg.height.toDouble()),
          Rect.fromLTWH(cx, cy, kTileSize, kTileSize),
          _pixelPaint,
        );
      }));
    }
  }

  void _addPlants(List<_Drawable> drawables) {
    final plantImg = sprites?.furniture('PLANT');
    if (!_hasImages || plantImg == null) return;
    final plantTimers = gameState.plantEasterEgg.activeTimers;

    for (int i = 0; i < kPlantPositions.length; i++) {
      final pos = kPlantPositions[i];
      final px = pos.$1 * kTileSize.toDouble();
      final basePy = pos.$2 * kTileSize - kTileSize;
      final zY = (pos.$2 + 1) * kTileSize.toDouble();

      final timer = plantTimers[i];
      final bouncing = timer != null && timer > 0;

      drawables.add(_Drawable(zY, (c) {
        double py = basePy;
        double scaleX = 1.0;
        double scaleY = 1.0;

        if (bouncing) {
          final phase = (kPlantAnimDuration - timer) * kPlantBounceSpeed;
          // Smooth fade-out envelope so animation settles before timer expires
          final envelope = (timer / kPlantAnimDuration).clamp(0.0, 1.0);
          // Bounce: squash/stretch + hop
          final bounce = math.sin(phase) * 2.0 * envelope;
          final squash = math.sin(phase * 2) * 0.08 * envelope;
          py = basePy - bounce.abs();
          scaleX = 1.0 + squash;
          scaleY = 1.0 - squash;
        }

        if (bouncing) {
          final cx = px + kTileSize / 2;
          final cy = basePy + kSpriteH.toDouble();
          c.save();
          c.translate(cx, cy);
          c.scale(scaleX, scaleY);
          c.translate(-cx, -cy);
        }

        c.drawImageRect(
          plantImg,
          Rect.fromLTWH(
            0, 0, plantImg.width.toDouble(), plantImg.height.toDouble()),
          Rect.fromLTWH(px, py, kTileSize, kSpriteH.toDouble()),
          _pixelPaint,
        );

        if (bouncing) c.restore();

        // Sparkle particles when bouncing
        if (bouncing) {
          final sparkPaint = Paint()..style = PaintingStyle.fill;
          final t = (kPlantAnimDuration - timer) / kPlantAnimDuration;
          for (int s = 0; s < 4; s++) {
            final angle = t * 6.28 + s * 1.57;
            final radius = 6.0 + t * 8.0;
            final sx = px + kTileSize / 2 + math.cos(angle) * radius;
            final sy = basePy + kTileSize / 2 + math.sin(angle) * radius;
            final alpha = (1.0 - t).clamp(0.0, 1.0);
            sparkPaint.color = const Color(0xFF44FF88).withValues(alpha: alpha * 0.7);
            c.drawRect(Rect.fromCenter(center: Offset(sx, sy), width: 1.5, height: 1.5), sparkPaint);
          }
        }
      }));
    }
  }

  // Amber outline paint: turns all opaque pixels into amber.
  static final _outlinePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..colorFilter =
        const ColorFilter.mode(Color(0xFFFFC107), BlendMode.srcATop);

  void _addCharacter(List<_Drawable> drawables, GameCharacter ch) {
    final sittingOffset =
        ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
    final charZY = ch.y + kTileSize / 2 + kCharZSortOffset;

    final isSelected = selectedAgentId == ch.agentId;
    final isHovered = hoveredAgentId == ch.agentId;
    final glowColor = agentAccentColor(ch.agentId);

    // Active glow under feet
    if (ch.isActive) {
      drawables.add(_Drawable(charZY - 0.003, (c) {
        c.drawOval(
          Rect.fromCenter(
            center: Offset(ch.x, ch.y + sittingOffset + 1),
            width: 14,
            height: 4,
          ),
          Paint()
            ..color = glowColor.withValues(alpha: 0.15)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }));
    }

    // Selection / hover glow under feet
    if (isSelected || isHovered) {
      const outlineColor = Color(0xFFFFC107);
      final outlineAlpha = isSelected ? 0.35 : 0.25;
      drawables.add(_Drawable(charZY - 0.002, (c) {
        c.drawOval(
          Rect.fromCenter(
            center: Offset(ch.x, ch.y + sittingOffset + 1),
            width: 18,
            height: 6,
          ),
          Paint()
            ..color = outlineColor.withValues(alpha: outlineAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }));
    }

    // ── Character sprite (PNG or fallback text) ──
    final sheet = sprites?.charSheet(ch.paletteIndex);
    if (_hasImages && sheet != null) {
      final info = charSpriteFrame(ch);
      final srcRect = charFrameRect(info.col, info.row);
      final drawX = ch.x - kSpriteW / 2;
      final drawY = ch.y + sittingOffset - kSpriteH;
      final sw = kSpriteW.toDouble();
      final sh = kSpriteH.toDouble();

      // Amber 1px outline: draw sprite shifted in 4 directions
      if (isHovered || isSelected) {
        drawables.add(_Drawable(charZY - 0.001, (c) {
          void drawShifted(double dx, double dy, bool flip) {
            if (flip) {
              c.save();
              c.translate(drawX + dx + sw, drawY + dy);
              c.scale(-1, 1);
              c.drawImageRect(
                  sheet, srcRect, Rect.fromLTWH(0, 0, sw, sh), _outlinePaint);
              c.restore();
            } else {
              c.drawImageRect(sheet, srcRect,
                  Rect.fromLTWH(drawX + dx, drawY + dy, sw, sh), _outlinePaint);
            }
          }

          for (final d in const [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)]) {
            drawShifted(d.$1, d.$2, info.mirror);
          }
        }));
      }

      // Normal sprite
      drawables.add(_Drawable(charZY, (c) {
        if (info.mirror) {
          c.save();
          c.translate(drawX + sw, drawY);
          c.scale(-1, 1);
          c.drawImageRect(
              sheet, srcRect, Rect.fromLTWH(0, 0, sw, sh), _pixelPaint);
          c.restore();
        } else {
          c.drawImageRect(
              sheet, srcRect, Rect.fromLTWH(drawX, drawY, sw, sh), _pixelPaint);
        }
      }));
    } else {
      // Fallback: text sprite with skin palette support
      final activeSkin = skin ?? skinDefault;
      final skinPalette = activeSkin.palettes[ch.agentId];
      final fallbackPalette =
          agentPalettes[ch.agentId] ?? agentPalettes['manager']!;

      Color resolveColor(String key) =>
          skinPalette?.resolve(key) ?? fallbackPalette.resolve(key);

      final (sprite, mirrored) = getCharacterSprite(ch);
      final sw = sprite[0].length;
      final shh = sprite.length;
      final drawX = ch.x - (sw / 2);
      final drawY = ch.y + sittingOffset - shh;

      drawables.add(_Drawable(charZY, (c) {
        if (mirrored) {
          drawSpriteMirrored(c, sprite, drawX, drawY, 1.0, resolveColor);
        } else {
          drawSprite(c, sprite, drawX, drawY, 1.0, resolveColor);
        }
      }));
    }

    // ── Skateboard ──
    if (ch.isOnSkateboard && ch.state == CharState.walk) {
      drawables.add(_Drawable(charZY - 0.004, (c) {
        final boardX = ch.x;
        final boardY = ch.y + sittingOffset + 1;
        // Deck
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(boardX, boardY), width: 12, height: 3),
            const Radius.circular(1.5),
          ),
          Paint()..color = skateboardDeck,
        );
        // Wheels
        final wp = Paint()..color = skateboardWheels;
        c.drawRect(Rect.fromCenter(center: Offset(boardX - 4, boardY + 1.5), width: 2, height: 1.5), wp);
        c.drawRect(Rect.fromCenter(center: Offset(boardX + 4, boardY + 1.5), width: 2, height: 1.5), wp);
        // Speed trail
        final trailPaint = Paint()
          ..color = agentAccentColor(ch.agentId).withValues(alpha: 0.2)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;
        final trailDir = ch.dir == CharDirection.right || ch.dir == CharDirection.down ? -1.0 : 1.0;
        for (int i = 0; i < 3; i++) {
          final offset = (i + 1) * 3.0 * trailDir;
          c.drawLine(
            Offset(boardX + offset, boardY - 1),
            Offset(boardX + offset + trailDir * 2, boardY - 1),
            trailPaint,
          );
        }
      }));
    }
  }

  // ─── Coffee machine ────────────────────────────────────────────────────

  void _addCoffeeMachine(List<_Drawable> drawables) {
    final brewing = gameState.coffeeMachineBrewing;
    final sprite = brewing
        ? (tick % 2 == 0 ? coffeeMachineBrew0 : coffeeMachineBrew1)
        : coffeeMachineIdle;
    final px = kCoffeeMachineCol * kTileSize + (kTileSize - sprite[0].length) / 2;
    final py = kCoffeeMachineRow * kTileSize + (kTileSize - sprite.length) / 2;
    final zY = (kCoffeeMachineRow + 1) * kTileSize.toDouble();

    drawables.add(_Drawable(zY, (c) {
      drawSprite(c, sprite, px, py, 1.0,
          (k) => CoffeeMachinePalette.resolve(k, brewing: brewing));

      // Steam particles when brewing
      if (brewing) {
        final steamPaint = Paint()..style = PaintingStyle.fill;
        final t = tick.toDouble();
        for (int i = 0; i < 3; i++) {
          final sx = px + 3.0 + i * 2.0 + math.sin(t + i * 1.5) * 1.5;
          final sy = py - 2.0 - (t * 0.5 + i).remainder(4.0);
          final alpha = (0.4 - (t * 0.5 + i).remainder(4.0) / 10.0).clamp(0.0, 0.4);
          steamPaint.color = Colors.white.withValues(alpha: alpha);
          c.drawRect(Rect.fromCenter(center: Offset(sx, sy), width: 1, height: 1), steamPaint);
        }
      }
    }));
  }

  // ─── Office cat ─────────────────────────────────────────────────────────

  void _addCat(List<_Drawable> drawables) {
    final cat = gameState.cat;
    final (sprite, mirrored) = getCatSprite(cat);
    final sw = sprite[0].length.toDouble();
    final sh = sprite.length.toDouble();

    // When sleeping on desk, draw on desk surface
    final isSleeping = cat.state == CatAction.sleep;
    final drawX = cat.x - sw / 2;
    final drawY = isSleeping ? cat.y - sh + 4 : cat.y - sh + 2;
    final catZY = isSleeping
        ? cat.y + kTileSize / 2 + 0.6 // just above desk surface
        : cat.y + kTileSize / 2 + 0.3;

    // Tiny shadow
    drawables.add(_Drawable(catZY - 0.001, (c) {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(cat.x, cat.y + (isSleeping ? 2 : 3)),
          width: 8,
          height: 3,
        ),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }));

    // Cat sprite
    drawables.add(_Drawable(catZY, (c) {
      if (mirrored) {
        drawSpriteMirrored(c, sprite, drawX, drawY, 1.0, CatPalette.resolve);
      } else {
        drawSprite(c, sprite, drawX, drawY, 1.0, CatPalette.resolve);
      }
    }));

    // Zzz bubble when sleeping
    if (isSleeping) {
      drawables.add(_Drawable(catZY + 0.001, (c) {
        final zx = cat.x + 5;
        final zy = drawY - 2;
        final phase = tick % 3;
        final zPaint = Paint()..style = PaintingStyle.fill;
        final sizes = [1.0, 1.5, 2.0];
        for (int i = 0; i <= phase; i++) {
          zPaint.color = CatPalette.fur.withValues(alpha: 0.5 - i * 0.1);
          final tp = TextPainter(
            text: TextSpan(
              text: 'z',
              style: TextStyle(
                color: zPaint.color,
                fontSize: sizes[i],
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, Offset(zx + i * 2.5, zy - i * 2.5));
        }
      }));
    }
  }

  // ─── Speech bubbles ─────────────────────────────────────────────────────

  void _drawBubbles(Canvas canvas) {
    for (final ch in gameState.characters.values) {
      if (!ch.isHired || !ch.isActive || ch.displayStatus == AgentStatus.idle) {
        continue;
      }
      _drawBubble(canvas, ch);
    }
  }

  void _drawBubble(Canvas canvas, GameCharacter ch) {
    final sittingOffset =
        ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
    final bx = ch.x;
    final by = ch.y + sittingOffset - kSpriteH - 2;
    final color = agentAccentColor(ch.agentId);

    // Background pill
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(bx, by), width: 13, height: 8),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF1E1E2E).withValues(alpha: 0.92),
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(bx, by), width: 13, height: 8),
        const Radius.circular(2),
      ),
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Tail
    final tail = Path()
      ..moveTo(bx - 1, by + 4)
      ..lineTo(bx, by + 6)
      ..lineTo(bx + 1, by + 4);
    canvas.drawPath(
      tail,
      Paint()..color = const Color(0xFF1E1E2E).withValues(alpha: 0.92),
    );

    // Content
    if (ch.displayStatus == AgentStatus.thinking) {
      final dp = Paint()..style = PaintingStyle.fill;
      for (int i = 0; i < 3; i++) {
        dp.color = color.withValues(alpha: (tick + i) % 3 == 0 ? 0.9 : 0.3);
        canvas.drawRect(
          Rect.fromLTWH(bx - 3 + i * 3, by - 0.5, 1, 1), dp);
      }
    } else {
      canvas.drawCircle(
        Offset(bx, by), 1.5,
        Paint()..color = color.withValues(alpha: 0.8),
      );
    }
  }

  // ─── Vignette ───────────────────────────────────────────────────────────

  void _drawVignette(Canvas canvas) {
    final center = Offset(kCanvasWidth / 2, kCanvasHeight / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: kCanvasWidth,
      height: kCanvasHeight,
    );
    final theme = _theme;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, kCanvasWidth, kCanvasHeight),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.9,
          colors: [
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: theme.vignetteAlpha),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // Tech hub: subtle cyan ambient glow from below
    if (officeLevel == OfficeLevel.techHub) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, kCanvasWidth, kCanvasHeight),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              theme.accentColor.withValues(alpha: 0.03),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }

    // Campus: warm ambient glow
    if (officeLevel == OfficeLevel.campus) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, kCanvasWidth, kCanvasHeight),
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: 0.8,
            colors: [
              theme.accentColor.withValues(alpha: 0.02),
              Colors.transparent,
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(PixelOfficePainter oldDelegate) => true;
}
