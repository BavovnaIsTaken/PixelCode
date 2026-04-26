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
import 'character_accessories.dart';
import 'character_skins.dart';
import 'room_sprites.dart';
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
  final List<FurniturePlacement> placedFurniture;
  final List<PlacedRoom> placedRooms;
  final bool editMode;
  final String? selectedFurnitureId;
  final bool buildMode;
  final RoomType? ghostRoomType;
  final int? ghostRoomCol;
  final int? ghostRoomRow;
  final int ghostRoomRotation;
  final bool ghostIsValid;

  PixelOfficePainter({
    required this.gameState,
    this.sprites,
    this.selectedAgentId,
    this.hoveredAgentId,
    this.tick = 0,
    this.officeLevel = OfficeLevel.garage,
    this.skin,
    this.placedFurniture = const [],
    this.placedRooms = const [],
    this.editMode = false,
    this.selectedFurnitureId,
    this.buildMode = false,
    this.ghostRoomType,
    this.ghostRoomCol,
    this.ghostRoomRow,
    this.ghostRoomRotation = 0,
    this.ghostIsValid = true,
  });

  bool get _hasImages => sprites != null && sprites!.isLoaded;

  RoomTheme get _theme => roomThemeForLevel(officeLevel);

  /// True when (col, row) is inside the inner playable area of the current
  /// grid. Used to skip rendering canonical props that were sized for a
  /// larger office than the one currently in play.
  bool _fitsInGrid(int col, int row) {
    return col >= 1 &&
        row >= 1 &&
        col < gameState.gridCols - 1 &&
        row < gameState.gridRows - 1;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / gameState.canvasWidth,
      size.height / gameState.canvasHeight,
    );
    final offsetX = (size.width - gameState.canvasWidth * scale) / 2;
    final offsetY = (size.height - gameState.canvasHeight * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    _drawFloorAndWalls(canvas);
    _drawPlacedRooms(canvas);
    _drawScene(canvas);
    _drawBubbles(canvas);
    _drawVignette(canvas);
    if (editMode) _drawEditOverlay(canvas);
    if (buildMode) _drawBuildOverlay(canvas);

    canvas.restore();
  }

  // ─── Floor & walls ──────────────────────────────────────────────────────

  void _drawFloorAndWalls(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;
    final tileMap = gameState.tileMap;
    final theme = _theme;
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;

    for (int r = 0; r < gRows; r++) {
      for (int c = 0; c < gCols; c++) {
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
          if (r < gRows - 1 && tileMap[r + 1][c] == TileType.floor) {
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
    for (int c = 1; c < gCols; c++) {
      canvas.drawLine(
        Offset(c * kTileSize, kTileSize),
        Offset(c * kTileSize, (gRows - 1) * kTileSize),
        paint,
      );
    }
    for (int r = 1; r < gRows; r++) {
      canvas.drawLine(
        Offset(kTileSize, r * kTileSize),
        Offset((gCols - 1) * kTileSize, r * kTileSize),
        paint,
      );
    }
  }

  // ─── Z-sorted scene ─────────────────────────────────────────────────────

  void _drawScene(Canvas canvas) {
    final drawables = <_Drawable>[];

    // Furniture per station: desk, PC, chair.
    // Canonical stations show up when any instance of that role is hired.
    // Extra (workstation) stations show up when any character is seated there.
    for (final station in gameState.allStations) {
      // Skip stations whose desk OR seat falls outside the current grid —
      // keeps props from drifting into the void for small offices.
      if (!_fitsInGrid(station.deskCol, station.deskRow) ||
          !_fitsInGrid(station.seatCol, station.seatRow)) {
        continue;
      }
      GameCharacter? seated;
      GameCharacter? anyHired;
      for (final c in gameState.characters.values) {
        if (!c.isHired) continue;
        final matches = station.isExtra
            ? c.seat == station
            : c.roleType == station.agentId;
        if (!matches) continue;
        anyHired ??= c;
        if (c.seat != null) {
          seated = c;
          break;
        }
      }
      final ch = seated ?? anyHired;
      if (ch == null) continue;
      _addStationFurniture(drawables, station, ch.isActive, ch);
    }

    // Coffee machine & snack table — only when their canonical tile fits the
    // current grid. Garage is too small to host them.
    if (_fitsInGrid(kCoffeeMachineCol2, kCoffeeMachineRow)) {
      _addCoffeeMachine(drawables);
    }
    if (_fitsInGrid(kSnackTableCol, kSnackTableRow)) {
      _addSnackTable(drawables);
    }

    // Placed furniture items (plants are now purchasable furniture — no
    // auto-placed decorative corner plants).
    _addPlacedFurniture(drawables);

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

  // Amber outline paint: turns all opaque pixels into amber.
  static final _outlinePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..colorFilter =
        const ColorFilter.mode(Color(0xFFFFC107), BlendMode.srcATop);

  void _addCharacter(List<_Drawable> drawables, GameCharacter ch) {
    final sittingOffset =
        ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
    final charZY = ch.y + kTileSize / 2 + kCharZSortOffset;

    final isSelected = selectedAgentId == ch.instanceId;
    final isHovered = hoveredAgentId == ch.instanceId;
    final glowColor = agentAccentColor(ch.roleType);

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
        // Hair tint + accessory overlay — keeps instances of the same role
        // visually distinct without extra sprite sheets.
        final headX = ch.x;
        final headY = drawY;
        drawHairTint(c, ch.cosmetics, headX, headY, ch.dir);
        drawAccessory(c, ch.cosmetics, headX, headY, ch.dir);
      }));
    } else {
      // Fallback: text sprite with skin palette support
      final activeSkin = skin ?? skinDefault;
      final skinPalette = activeSkin.palettes[ch.roleType];
      final fallbackPalette =
          agentPalettes[ch.roleType] ?? agentPalettes['manager']!;

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
        drawHairTint(c, ch.cosmetics, ch.x, drawY, ch.dir);
        drawAccessory(c, ch.cosmetics, ch.x, drawY, ch.dir);
      }));
    }

    // ── Skateboard ──
    final showBoard = ch.isOnSkateboard &&
        (ch.state == CharState.walk ||
         ch.state == CharState.skateMount ||
         ch.state == CharState.skateDismount);
    if (showBoard) {
      drawables.add(_Drawable(charZY - 0.004, (c) {
        final boardX = ch.x;
        final boardY = ch.y + 1;

        // During mount: board fades in (scale up). During dismount: fades out.
        double boardScale = 1.0;
        double boardAlpha = 1.0;
        if (ch.state == CharState.skateMount) {
          final progress = (ch.frameTimer / kSkateMountDuration).clamp(0.0, 1.0);
          boardScale = 0.3 + 0.7 * progress;
          boardAlpha = progress;
        } else if (ch.state == CharState.skateDismount) {
          final progress = (ch.frameTimer / kSkateDismountDuration).clamp(0.0, 1.0);
          boardScale = 1.0 - 0.7 * progress;
          boardAlpha = 1.0 - progress;
        }

        final deckW = 12.0 * boardScale;
        final deckH = 3.0 * boardScale;

        // Deck
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(boardX, boardY), width: deckW, height: deckH),
            Radius.circular(1.5 * boardScale),
          ),
          Paint()..color = skateboardDeck.withValues(alpha: boardAlpha),
        );
        // Wheels
        final wp = Paint()..color = skateboardWheels.withValues(alpha: boardAlpha);
        c.drawRect(
          Rect.fromCenter(center: Offset(boardX - 4 * boardScale, boardY + 1.5 * boardScale), width: 2, height: 1.5),
          wp,
        );
        c.drawRect(
          Rect.fromCenter(center: Offset(boardX + 4 * boardScale, boardY + 1.5 * boardScale), width: 2, height: 1.5),
          wp,
        );
        // Speed trail only while riding
        if (ch.state == CharState.walk) {
          final trailPaint = Paint()
            ..color = agentAccentColor(ch.roleType).withValues(alpha: 0.2)
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
        }
      }));
    }

    // ── Coffee cup in hand ──
    if (ch.hasCoffee) {
      drawables.add(_Drawable(charZY + 0.001, (c) {
        _drawCoffeeCup(c, ch.x, ch.y + sittingOffset, ch.dir);
      }));
    }
  }

  /// Draw a tiny coffee cup at the character's hand position.
  void _drawCoffeeCup(Canvas c, double cx, double cy, CharDirection dir) {
    final cupPaint = Paint()..color = const Color(0xFF6B4226);
    final rimPaint = Paint()..color = const Color(0xFFE8E0D8);
    final steamPaint = Paint()..color = Colors.white.withValues(alpha: 0.35);

    // Offset cup position based on facing direction
    double cupX, cupY;
    switch (dir) {
      case CharDirection.down:
        cupX = cx + 3.5;
        cupY = cy - 4;
      case CharDirection.up:
        cupX = cx - 3.5;
        cupY = cy - 6;
      case CharDirection.right:
        cupX = cx + 4;
        cupY = cy - 5;
      case CharDirection.left:
        cupX = cx - 4;
        cupY = cy - 5;
    }

    // Cup body (brown)
    c.drawRect(Rect.fromLTWH(cupX, cupY, 3, 3), cupPaint);
    // Rim (white)
    c.drawRect(Rect.fromLTWH(cupX, cupY, 3, 1), rimPaint);
    // Handle
    c.drawRect(Rect.fromLTWH(cupX + 3, cupY + 1, 1, 1), cupPaint);
    // Steam wisps (animated via tick)
    final t = tick.toDouble();
    for (int i = 0; i < 2; i++) {
      final sx = cupX + 0.5 + i * 1.5 + math.sin(t * 0.7 + i * 2.0) * 0.8;
      final sy = cupY - 1.0 - i * 1.0;
      final alpha = (0.3 - i * 0.1).clamp(0.0, 0.3);
      steamPaint.color = Colors.white.withValues(alpha: alpha);
      c.drawRect(Rect.fromCenter(center: Offset(sx, sy), width: 1, height: 1), steamPaint);
    }
  }

  // ─── Coffee machine (large, 2 tiles) ────────────────────────────────────

  void _addCoffeeMachine(List<_Drawable> drawables) {
    final brewing = gameState.coffeeMachineBrewing;
    final theme = _theme;
    final baseX = kCoffeeMachineCol * kTileSize;
    final baseY = kCoffeeMachineRow * kTileSize;
    final zY = (kCoffeeMachineRow + 1) * kTileSize.toDouble();
    final p = Paint()..style = PaintingStyle.fill;

    drawables.add(_Drawable(zY, (c) {
      // ── Counter / table (spans 2 tiles) ──
      p.color = theme.deskSurface;
      c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 10, 30, 5), p);
      p.color = theme.deskEdge;
      c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 15, 30, 1), p);

      // ── Coffee machine body (left tile, bigger) ──
      const machX = 3.0;
      final mx = baseX + machX;
      final my = baseY + 1.0;

      // Main body
      p.color = const Color(0xFF3A3A40);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mx, my, 12, 9),
          const Radius.circular(1),
        ),
        p,
      );

      // Top panel
      p.color = const Color(0xFF2A2A30);
      c.drawRect(Rect.fromLTWH(mx, my, 12, 2), p);

      // Indicator lights
      p.color = brewing ? const Color(0xFF44FF44) : const Color(0xFF884444);
      c.drawRect(Rect.fromLTWH(mx + 2, my + 0.5, 2, 1), p);
      c.drawRect(Rect.fromLTWH(mx + 5, my + 0.5, 2, 1), p);

      // Dispenser nozzle
      p.color = const Color(0xFF2A2A30);
      c.drawRect(Rect.fromLTWH(mx + 4, my + 4, 4, 2), p);

      // Coffee drip when brewing
      if (brewing) {
        p.color = const Color(0xFF6B4226);
        final dripY = my + 6 + (tick % 2 == 0 ? 0.0 : 1.0);
        c.drawRect(Rect.fromLTWH(mx + 5.5, dripY, 1, 1.5), p);
      }

      // Cup on counter
      p.color = const Color(0xFFE8E0D8);
      c.drawRect(Rect.fromLTWH(mx + 4, my + 7, 4, 3), p);
      p.color = const Color(0xFF6B4226);
      if (brewing) {
        c.drawRect(Rect.fromLTWH(mx + 4.5, my + 7.5, 3, 1.5), p);
      }

      // ── Water tank (right side of machine) ──
      p.color = const Color(0xFF4A4A55);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(mx + 13, my + 1, 5, 8),
          const Radius.circular(1),
        ),
        p,
      );
      // Water level
      p.color = const Color(0xFF5588AA).withValues(alpha: 0.4);
      c.drawRect(Rect.fromLTWH(mx + 14, my + 3, 3, 5), p);

      // ── Extra cups stack (right of water tank) ──
      p.color = const Color(0xFFE8E0D8).withValues(alpha: 0.7);
      for (int i = 0; i < 3; i++) {
        c.drawRect(Rect.fromLTWH(mx + 20 + i * 1.5, my + 6.5 - i * 0.5, 3, 3.5 + i * 0.5), p);
      }

      // ── Steam when brewing ──
      if (brewing) {
        final steamPaint = Paint()..style = PaintingStyle.fill;
        final t = tick.toDouble();
        for (int i = 0; i < 5; i++) {
          final sx = mx + 4.0 + i * 2.5 + math.sin(t + i * 1.2) * 1.5;
          final sy = my - 1.5 - (t * 0.5 + i).remainder(5.0);
          final alpha = (0.35 - (t * 0.5 + i).remainder(5.0) / 12.0).clamp(0.0, 0.35);
          steamPaint.color = Colors.white.withValues(alpha: alpha);
          c.drawRect(Rect.fromCenter(center: Offset(sx, sy), width: 1.5, height: 1.5), steamPaint);
        }
      }
    }));
  }

  // ─── Snack table ──────────────────────────────────────────────────────────

  void _addSnackTable(List<_Drawable> drawables) {
    final theme = _theme;
    final baseX = kSnackTableCol * kTileSize;
    final baseY = kSnackTableRow * kTileSize;
    final zY = (kSnackTableRow + 1) * kTileSize.toDouble();
    final p = Paint()..style = PaintingStyle.fill;

    drawables.add(_Drawable(zY, (c) {
      // ── Table surface ──
      p.color = theme.deskSurface;
      c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 10, 14, 5), p);
      p.color = theme.deskEdge;
      c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 15, 14, 1), p);

      // ── Plate of cookies ──
      // Plate (light grey circle-ish)
      p.color = const Color(0xFFD0D0D0);
      c.drawOval(Rect.fromLTWH(baseX + 2, baseY + 11, 6, 3), p);
      // Cookies (brown dots)
      p.color = const Color(0xFF8B6914);
      c.drawRect(Rect.fromLTWH(baseX + 3, baseY + 11.5, 1.5, 1.5), p);
      c.drawRect(Rect.fromLTWH(baseX + 5, baseY + 11.5, 1.5, 1.5), p);
      p.color = const Color(0xFFA07B28);
      c.drawRect(Rect.fromLTWH(baseX + 4, baseY + 12.5, 1.5, 1), p);

      // ── Sugar bowl ──
      p.color = const Color(0xFFEEEEEE);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(baseX + 9, baseY + 11, 4, 3),
          const Radius.circular(1),
        ),
        p,
      );
      // Sugar cubes inside
      p.color = const Color(0xFFF8F8F8);
      c.drawRect(Rect.fromLTWH(baseX + 10, baseY + 11.5, 1, 1), p);
      c.drawRect(Rect.fromLTWH(baseX + 11.5, baseY + 11.5, 1, 1), p);

      // ── Napkin holder ──
      p.color = const Color(0xFF8B4513);
      c.drawRect(Rect.fromLTWH(baseX + 7, baseY + 3, 3, 7), p);
      // Napkins (white)
      p.color = const Color(0xFFF5F5F5);
      c.drawRect(Rect.fromLTWH(baseX + 7.5, baseY + 3.5, 2, 6), p);
    }));
  }

  // ─── Placed furniture ──────────────────────────────────────────────────

  static const _furnitureColors = <FurnitureType, Color>{
    FurnitureType.coffeeTable: Color(0xFF6B4226),
    FurnitureType.snackTable: Color(0xFF8B6914),
    FurnitureType.decoration: Color(0xFF44AA55),
    FurnitureType.storage: Color(0xFF5566AA),
    FurnitureType.lounge: Color(0xFFAA5566),
  };

  void _addPlacedFurniture(List<_Drawable> drawables) {
    final theme = _theme;
    for (final placement in placedFurniture) {
      final item = furnitureById(placement.itemId);
      if (item == null) continue;

      if (item.id == 'plant_small' || item.id == 'plant_large') {
        _addPlantSprite(drawables, placement, isLarge: item.id == 'plant_large');
        continue;
      }

      final baseX = placement.col * kTileSize;
      final baseY = placement.row * kTileSize;
      final w = item.widthTiles * kTileSize;
      final zY = (placement.row + 1) * kTileSize.toDouble();
      final accent = _furnitureColors[item.type] ?? const Color(0xFF888888);

      drawables.add(_Drawable(zY, (c) {
        final p = Paint()..style = PaintingStyle.fill;

        // Table/surface
        p.color = theme.deskSurface;
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(baseX + 1, baseY + 8, w - 2, 7),
            const Radius.circular(1),
          ),
          p,
        );
        p.color = theme.deskEdge;
        c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 15, w - 2, 1), p);

        // Item visual on top (small colored element)
        p.color = accent.withValues(alpha: 0.8);
        final itemW = (w - 6).clamp(4.0, 12.0);
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(baseX + (w - itemW) / 2, baseY + 3, itemW, 6),
            const Radius.circular(1.5),
          ),
          p,
        );

        // Highlight dot
        p.color = accent.withValues(alpha: 0.4);
        c.drawRect(
          Rect.fromLTWH(baseX + (w - itemW) / 2 + 1, baseY + 4, 2, 1),
          p,
        );
      }));
    }
  }

  // ─── Plant sprite (purchasable decoration with bounce easter egg) ────

  void _addPlantSprite(
    List<_Drawable> drawables,
    FurniturePlacement placement, {
    required bool isLarge,
  }) {
    final col = placement.col;
    final row = placement.row;
    final baseX = col * kTileSize.toDouble();
    // Large plant sprite (16×32) extends one tile up from its footprint.
    // Small plant sits within the footprint tile.
    final baseY = isLarge
        ? row * kTileSize - kTileSize.toDouble()
        : row * kTileSize.toDouble();
    final zY = (row + 1) * kTileSize.toDouble();
    final timer = gameState.plantEasterEgg.activeTimers['$col,$row'];
    final bouncing = timer != null && timer > 0;
    final plantImg = sprites?.furniture('PLANT');

    drawables.add(_Drawable(zY, (c) {
      double py = baseY;
      double scaleX = 1.0;
      double scaleY = 1.0;

      if (bouncing) {
        final phase = (kPlantAnimDuration - timer) * kPlantBounceSpeed;
        final envelope = (timer / kPlantAnimDuration).clamp(0.0, 1.0);
        final bounce = math.sin(phase) * 2.0 * envelope;
        final squash = math.sin(phase * 2) * 0.08 * envelope;
        py = baseY - bounce.abs();
        scaleX = 1.0 + squash;
        scaleY = 1.0 - squash;

        final cx = baseX + kTileSize / 2;
        final cy = baseY + (isLarge ? kSpriteH.toDouble() : kTileSize);
        c.save();
        c.translate(cx, cy);
        c.scale(scaleX, scaleY);
        c.translate(-cx, -cy);
      }

      if (_hasImages && plantImg != null) {
        if (isLarge) {
          c.drawImageRect(
            plantImg,
            Rect.fromLTWH(
                0, 0, plantImg.width.toDouble(), plantImg.height.toDouble()),
            Rect.fromLTWH(baseX, py, kTileSize, kSpriteH.toDouble()),
            _pixelPaint,
          );
        } else {
          // Small plant: draw only the bottom half of the sprite (pot/base)
          // at the footprint tile, so it reads as a desk-top plant.
          final srcTop = plantImg.height / 2.0;
          c.drawImageRect(
            plantImg,
            Rect.fromLTWH(
                0, srcTop, plantImg.width.toDouble(), plantImg.height - srcTop),
            Rect.fromLTWH(baseX, py, kTileSize, kTileSize),
            _pixelPaint,
          );
        }
      } else {
        // Fallback: colored pot + foliage blob.
        final p = Paint()..style = PaintingStyle.fill;
        final potY = py + (isLarge ? kSpriteH - 8 : kTileSize - 6);
        p.color = const Color(0xFF6B4226);
        c.drawRect(Rect.fromLTWH(baseX + 4, potY, 8, 6), p);
        p.color = const Color(0xFF44AA55);
        final leafH = isLarge ? 20.0 : 8.0;
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(baseX + 2, potY - leafH, 12, leafH),
            const Radius.circular(3),
          ),
          p,
        );
      }

      if (bouncing) {
        c.restore();

        // Sparkles
        final sparkPaint = Paint()..style = PaintingStyle.fill;
        final t = (kPlantAnimDuration - timer) / kPlantAnimDuration;
        final centerY = baseY + (isLarge ? kSpriteH / 2 : kTileSize / 2);
        for (int s = 0; s < 4; s++) {
          final angle = t * 6.28 + s * 1.57;
          final radius = 6.0 + t * 8.0;
          final sx = baseX + kTileSize / 2 + math.cos(angle) * radius;
          final sy = centerY + math.sin(angle) * radius;
          final alpha = (1.0 - t).clamp(0.0, 1.0);
          sparkPaint.color =
              const Color(0xFF44FF88).withValues(alpha: alpha * 0.7);
          c.drawRect(
              Rect.fromCenter(
                  center: Offset(sx, sy), width: 1.5, height: 1.5),
              sparkPaint);
        }
      }
    }));
  }

  // ─── Edit mode overlay ────────────────────────────────────────────────

  void _drawPlacedRooms(Canvas canvas) {
    for (final room in placedRooms) {
      drawRoom(canvas, room, _theme, tick, showWorkstationFurniture: false);
    }
  }

  void _drawBuildOverlay(Canvas canvas) {
    final blocked = gameState.blockedTiles;
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;
    final p = Paint()..style = PaintingStyle.fill;

    // Tile highlights: green = free, red = blocked
    for (int r = 1; r < gRows - 1; r++) {
      for (int c = 1; c < gCols - 1; c++) {
        final isBlocked = blocked.contains('$c,$r');
        p.color = isBlocked
            ? const Color(0xFFFF4444).withValues(alpha: 0.10)
            : const Color(0xFF44FF88).withValues(alpha: 0.05);
        canvas.drawRect(
            Rect.fromLTWH(c * kTileSize, r * kTileSize, kTileSize, kTileSize),
            p);
      }
    }

    // Grid lines
    p
      ..color = const Color(0xFF44FF88).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int c = 1; c < gCols; c++) {
      canvas.drawLine(Offset(c * kTileSize, kTileSize),
          Offset(c * kTileSize, (gRows - 1) * kTileSize), p);
    }
    for (int r = 1; r < gRows; r++) {
      canvas.drawLine(Offset(kTileSize, r * kTileSize),
          Offset((gCols - 1) * kTileSize, r * kTileSize), p);
    }

    // Ghost room preview (single room OR preset bundle)
    final gc = ghostRoomCol;
    final gr = ghostRoomRow;
    if (gc != null && gr != null) {
      final ghostColor =
          ghostIsValid ? const Color(0xFF44FF88) : const Color(0xFFFF4444);

      // Overall ghost footprint (for corridor routing) — accounts for rotation.
      int footLeft = gc, footTop = gr, footRight = gc, footBottom = gr;
      final gtForFoot = ghostRoomType;
      if (gtForFoot != null) {
        final rotated = ghostRoomRotation == 90 || ghostRoomRotation == 270;
        footRight = gc + (rotated ? gtForFoot.heightTiles : gtForFoot.widthTiles);
        footBottom = gr + (rotated ? gtForFoot.widthTiles : gtForFoot.heightTiles);
      }

      // Corridor preview: connect the ghost footprint to the nearest existing
      // room with an L-shaped 1-tile strip. Skip if no rooms yet or ghost
      // overlaps (handled as invalid).
      if (ghostIsValid && placedRooms.isNotEmpty && gtForFoot != null) {
        final gcx = (footLeft + footRight) / 2.0;
        final gcy = (footTop + footBottom) / 2.0;
        PlacedRoom? nearest;
        double nearestDist = double.infinity;
        for (final room in placedRooms) {
          final rcx =
              room.col + room.type.widthTiles / 2.0;
          final rcy =
              room.row + room.type.heightTiles / 2.0;
          final d = (rcx - gcx).abs() + (rcy - gcy).abs();
          if (d < nearestDist) {
            nearestDist = d;
            nearest = room;
          }
        }
        if (nearest != null) {
          final nrLeft = nearest.col;
          final nrTop = nearest.row;
          final nrRight = nearest.col + nearest.type.widthTiles;
          final nrBottom = nearest.row + nearest.type.heightTiles;

          // Pick corridor midline at a tile that lies within the vertical
          // overlap (or nearest edge) and horizontal overlap of both rects.
          final yMid = ((math.max(footTop, nrTop) +
                      math.min(footBottom, nrBottom) -
                      1) /
                  2)
              .floor();
          final xMid = ((math.max(footLeft, nrLeft) +
                      math.min(footRight, nrRight) -
                      1) /
                  2)
              .floor();

          // Horizontal segment at yMid between the two rects' x-extents.
          int hx1, hx2;
          if (footRight <= nrLeft) {
            hx1 = footRight;
            hx2 = nrLeft;
          } else if (nrRight <= footLeft) {
            hx1 = nrRight;
            hx2 = footLeft;
          } else {
            hx1 = hx2 = 0; // already horizontally overlapping
          }

          // Vertical segment at xMid between the two rects' y-extents.
          int vy1, vy2;
          if (footBottom <= nrTop) {
            vy1 = footBottom;
            vy2 = nrTop;
          } else if (nrBottom <= footTop) {
            vy1 = nrBottom;
            vy2 = footTop;
          } else {
            vy1 = vy2 = 0;
          }

          final corridorFill = Paint()
            ..color = const Color(0xFFFFD700).withValues(alpha: 0.18)
            ..style = PaintingStyle.fill;
          final corridorStroke = Paint()
            ..color = const Color(0xFFFFD700).withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;

          if (hx2 > hx1) {
            final safeY = yMid
                .clamp(1, gameState.gridRows - 2)
                .toInt();
            final rect = Rect.fromLTWH(
              hx1 * kTileSize,
              safeY * kTileSize,
              (hx2 - hx1) * kTileSize,
              kTileSize,
            );
            canvas.drawRect(rect, corridorFill);
            canvas.drawRect(rect, corridorStroke);
          }
          if (vy2 > vy1) {
            final safeX = xMid
                .clamp(1, gameState.gridCols - 2)
                .toInt();
            final rect = Rect.fromLTWH(
              safeX * kTileSize,
              vy1 * kTileSize,
              kTileSize,
              (vy2 - vy1) * kTileSize,
            );
            canvas.drawRect(rect, corridorFill);
            canvas.drawRect(rect, corridorStroke);
          }
        }
      }

      void drawGhostRect(double rx, double ry, double rw, double rh) {
        canvas.drawRect(
            Rect.fromLTWH(rx, ry, rw, rh),
            Paint()
              ..color = ghostColor.withValues(alpha: 0.25)
              ..style = PaintingStyle.fill);
        canvas.drawRect(
            Rect.fromLTWH(rx + 0.5, ry + 0.5, rw - 1, rh - 1),
            Paint()
              ..color = ghostColor.withValues(alpha: 0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }

      final gt = ghostRoomType;
      if (gt != null) {
        drawGhostRect(
          gc * kTileSize,
          gr * kTileSize,
          gt.widthTiles * kTileSize,
          gt.heightTiles * kTileSize,
        );
      }
    }

    // Existing room outlines
    for (final room in placedRooms) {
      final rx = room.col * kTileSize;
      final ry = room.row * kTileSize;
      final rw = room.type.widthTiles * kTileSize;
      final rh = room.type.heightTiles * kTileSize;
      canvas.drawRect(
          Rect.fromLTWH(rx + 0.5, ry + 0.5, rw - 1, rh - 1),
          Paint()
            ..color = const Color(0xFFFFD700).withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
  }

  void _drawEditOverlay(Canvas canvas) {
    final blocked = gameState.blockedTiles;
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;
    final p = Paint()..style = PaintingStyle.fill;

    // Semi-transparent tile highlights
    for (int r = 1; r < gRows - 1; r++) {
      for (int c = 1; c < gCols - 1; c++) {
        final tx = c * kTileSize;
        final ty = r * kTileSize;
        final isBlocked = blocked.contains('$c,$r');

        p.color = isBlocked
            ? const Color(0xFFFF4444).withValues(alpha: 0.08)
            : const Color(0xFF44FF44).withValues(alpha: 0.06);
        canvas.drawRect(Rect.fromLTWH(tx, ty, kTileSize, kTileSize), p);
      }
    }

    // Grid lines (more visible in edit mode)
    p
      ..color = const Color(0xFF44FF44).withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int c = 1; c < gCols; c++) {
      canvas.drawLine(
        Offset(c * kTileSize, kTileSize),
        Offset(c * kTileSize, (gRows - 1) * kTileSize),
        p,
      );
    }
    for (int r = 1; r < gRows; r++) {
      canvas.drawLine(
        Offset(kTileSize, r * kTileSize),
        Offset((gCols - 1) * kTileSize, r * kTileSize),
        p,
      );
    }

    // Highlight placed furniture outlines
    for (int i = 0; i < placedFurniture.length; i++) {
      final placement = placedFurniture[i];
      final item = furnitureById(placement.itemId);
      if (item == null) continue;

      final fx = placement.col * kTileSize;
      final fy = placement.row * kTileSize;
      final fw = item.widthTiles * kTileSize;
      final fh = item.heightTiles * kTileSize;

      canvas.drawRect(
        Rect.fromLTWH(fx + 0.5, fy + 0.5, fw - 1, fh - 1),
        Paint()
          ..color = const Color(0xFFFFD700).withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
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
      if (!ch.isHired) continue;
      if (ch.isChatting) {
        _drawChatBubble(canvas, ch);
        continue;
      }
      if (!ch.isActive || ch.displayStatus == AgentStatus.idle) continue;
      _drawBubble(canvas, ch);
    }
  }

  /// Speech bubble shown while two characters are having a casual chat.
  /// Wider than the agent-status bubble and animates between three dots
  /// and a simple chat glyph so the scene reads as a real conversation.
  void _drawChatBubble(Canvas canvas, GameCharacter ch) {
    final bx = ch.x;
    final by = ch.y - kSpriteH - 1;
    final color = agentAccentColor(ch.roleType);

    final rect = Rect.fromCenter(center: Offset(bx, by), width: 16, height: 9);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2.5)),
      Paint()..color = const Color(0xFF1E1E2E).withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2.5)),
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );

    // Tail
    final tail = Path()
      ..moveTo(bx - 1.5, by + 4.5)
      ..lineTo(bx, by + 7)
      ..lineTo(bx + 1.5, by + 4.5);
    canvas.drawPath(
      tail,
      Paint()..color = const Color(0xFF1E1E2E).withValues(alpha: 0.92),
    );

    // Animated content: three dots that light up in sequence.
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final phase = tick % 4;
    for (int i = 0; i < 3; i++) {
      final on = phase == i || phase == 3;
      dotPaint.color = color.withValues(alpha: on ? 0.95 : 0.3);
      canvas.drawRect(
        Rect.fromLTWH(bx - 4 + i * 3, by - 0.5, 1.5, 1.5),
        dotPaint,
      );
    }
  }

  void _drawBubble(Canvas canvas, GameCharacter ch) {
    final sittingOffset =
        ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
    final bx = ch.x;
    final by = ch.y + sittingOffset - kSpriteH - 2;
    final color = agentAccentColor(ch.roleType);

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
