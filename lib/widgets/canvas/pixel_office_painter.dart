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
import 'package:collection/collection.dart';

import '../../models/agent_message.dart';
import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';
import 'character_accessories.dart';
import 'character_skins.dart';
import 'room_sprites.dart';
import 'character_sprites.dart';
import 'galley_sprites.dart';
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

// ─── Cached Paint objects for character glows ──────────────────────────────
// These are reused across frames to avoid allocation overhead during painting.
final _charActivePaint = Paint()
  ..style = PaintingStyle.fill
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

final _charHoverPaint = Paint()
  ..style = PaintingStyle.fill
  ..color = const Color(0xFFFFC107)
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

final _charSelectionPaint = Paint()
  ..style = PaintingStyle.fill
  ..color = const Color(0xFFFFC107)
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

// ─── Cached Paint for fill operations ──────────────────────────────────────
final _fillPaint = Paint()..style = PaintingStyle.fill;

final _floorGridPaint = Paint()
  ..style = PaintingStyle.stroke
  ..color = const Color(0xFF404050)
  ..strokeWidth = 0.5;

// ─── Universal cached Paint objects (avoid 50+ allocs/frame) ─────────────────
// These are reused & their color/alpha/filter updated dynamically each use.
// Eliminates allocation pressure from closures in paint() callback.

final Paint glowPaint = Paint()
  ..style = PaintingStyle.fill
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

final Paint shadowPaint = Paint()
  ..style = PaintingStyle.fill
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);

final Paint strokePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.0;

final Paint outlinePaint = Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 0.5;

final Paint gridTilePaint = Paint()
  ..style = PaintingStyle.stroke
  ..color = const Color(0xFF555555)
  ..strokeWidth = 0.3;

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

  /// Index into [placedFurniture] of an item the player has picked up to
  /// move. Drawn with a pulsing outline in the edit overlay so the player
  /// sees what's "in hand". Null when nothing is held.
  final int? heldPlacedFurnitureIndex;
  final bool buildMode;
  final RoomType? ghostRoomType;
  final int? ghostRoomCol;
  final int? ghostRoomRow;
  final int ghostRoomRotation;
  final bool ghostIsValid;

  /// True when the ghost is in the foundation-buffer outside the currently
  /// owned grid but inside the tier's max expansion capacity — placement is
  /// allowed but will purchase the needed expansion step(s).
  final bool ghostPendingExpand;

  /// Number of buffer tiles to render past each office edge in build mode.
  /// Drawn as a "foundation grid" (subtle amber fill + L-corner lot markers)
  /// so the player can preview attaching rooms outside the current owned area.
  final int buildBufferCols;
  final int buildBufferRows;

  /// Cost of the next expansion step at the current tier — surfaced as a
  /// single "₲N розширення" hint near the buffer boundary corner. Null when
  /// the tier is fully expanded (no buffer drawn in that case anyway).
  final int? nextExpansionCost;

  /// Foundation-buffer tile the pointer is currently over (null when outside
  /// the buffer). Painted with a per-tile green/red wash so the player gets
  /// affordance feedback on "can I buy this?".
  final int? hoveredBufferCol;
  final int? hoveredBufferRow;

  /// 0..1 fade alpha applied to the hover wash. Driven by a 150 ms
  /// AnimationController on the canvas side so enter/exit feel smooth instead
  /// of binary.
  final double bufferHoverAlpha;

  /// True when the player can currently afford the next expansion step. Drives
  /// the hover wash colour (green = affordable, red = not).
  final bool bufferHoverAffordable;

  /// True while the pointer is pressed down on the hovered buffer tile. Adds
  /// an extra inner stroke so the press reads as a deliberate click, not just
  /// a hover.
  final bool bufferHoverPressed;

  /// Whether to actually PAINT the foundation-buffer lot. The buffer area is
  /// always reserved in the canvas fit (stable layout), but the amber lot
  /// markers + price only appear while the player is positioning a room at the
  /// edge (or hovering the lot) — so idle build mode isn't littered with
  /// mystery gold tiles.
  final bool showFoundationBuffer;

  /// Adjacency bonus label rendered over the ghost (e.g. "+5%" or "−5%").
  /// Null when there is no adjacency effect for the current ghost position.
  final String? adjacencyLabel;

  final List<PlacedCorridor> placedCorridors;

  /// Free auto-connect corridor preview for the active room ghost — the exact
  /// path that gets built on commit (computed once in the widget). Drawn in
  /// gold so the player sees the connection they're about to get.
  final List<({int col, int row})> connectingCorridorTiles;

  /// First tile of a corridor being drawn — null when no corridor is in-flight.
  final int? corridorAnchorCol;
  final int? corridorAnchorRow;

  /// instanceId → set of earned specialization topic keys (C.1).
  /// Used to draw a micro-glyph above specialized agents on the canvas.
  final Map<String, Set<String>> agentSpecializations;

  /// Translucent "drop preview" footprint for the furniture edit flow. The
  /// painter draws this rectangle at (col,row) sized to the item's tile
  /// footprint, tinted green when [ghostFurnitureValid] is true and red
  /// otherwise. Mirrors the buy-mode ghost so a held / selected item visibly
  /// follows the cursor. Null fields mean "no ghost" (empty hand or pointer
  /// outside the canvas).
  final FurnitureItem? ghostFurnitureItem;
  final int? ghostFurnitureCol;
  final int? ghostFurnitureRow;
  final bool ghostFurnitureValid;

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
    this.heldPlacedFurnitureIndex,
    this.buildMode = false,
    this.ghostRoomType,
    this.ghostRoomCol,
    this.ghostRoomRow,
    this.ghostRoomRotation = 0,
    this.ghostIsValid = true,
    this.ghostPendingExpand = false,
    this.buildBufferCols = 0,
    this.buildBufferRows = 0,
    this.nextExpansionCost,
    this.hoveredBufferCol,
    this.hoveredBufferRow,
    this.bufferHoverAlpha = 0.0,
    this.bufferHoverAffordable = true,
    this.bufferHoverPressed = false,
    this.showFoundationBuffer = true,
    this.adjacencyLabel,
    this.placedCorridors = const [],
    this.connectingCorridorTiles = const [],
    this.corridorAnchorCol,
    this.corridorAnchorRow,
    this.agentSpecializations = const {},
    this.ghostFurnitureItem,
    this.ghostFurnitureCol,
    this.ghostFurnitureRow,
    this.ghostFurnitureValid = true,
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

  /// Canvas width including any active build-mode buffer past the right wall.
  /// When [buildBufferCols] > 0 the painter draws extra tiles past the owned
  /// grid, so the on-screen area needs to grow accordingly — otherwise the
  /// buffer renders past the clip region and is invisible.
  double get effectiveCanvasWidth =>
      gameState.canvasWidth + buildBufferCols * kTileSize;

  double get effectiveCanvasHeight =>
      gameState.canvasHeight + buildBufferRows * kTileSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Guard a degenerate startup-layout frame: a zero/non-finite size makes
    // `scale` 0, and `canvas.scale(0)` collapses the whole office to a single
    // point — a blank frame. Skip until we have a real size to draw into.
    if (size.width <= 0 || size.height <= 0) return;
    final scale = math.min(
      size.width / effectiveCanvasWidth,
      size.height / effectiveCanvasHeight,
    );
    if (!scale.isFinite || scale <= 0) return;
    final offsetX = (size.width - effectiveCanvasWidth * scale) / 2;
    final offsetY = (size.height - effectiveCanvasHeight * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    final isGalley = officeLevel == OfficeLevel.galley;
    if (isGalley) {
      // Sea fills the FULL visible viewport, not just the painter's
      // effective canvas — so empty space around the galley is open ocean,
      // not the black void of an unpainted canvas. Compute the viewport in
      // painter-local coords (post translate+scale) and feed that as bounds.
      final visibleBounds = Rect.fromLTWH(
        -offsetX / scale,
        -offsetY / scale,
        size.width / scale,
        size.height / scale,
      );
      drawGalleySea(
        canvas: canvas,
        bounds: visibleBounds,
        deckRect: Rect.fromLTWH(
          0,
          0,
          gameState.canvasWidth,
          gameState.canvasHeight,
        ),
        tick: tick,
      );
    }

    _drawFloorAndWalls(canvas);
    if (isGalley) _drawGalleyHullDecor(canvas);
    _drawPlacedRooms(canvas);
    _drawCorridors(canvas);
    _drawScene(canvas);
    if (isGalley) _drawGalleyTopLayer(canvas);
    _drawBubbles(canvas);
    _drawVignette(canvas);
    if (editMode) _drawEditOverlay(canvas);
    if (buildMode) _drawBuildOverlay(canvas);

    canvas.restore();
  }

  // ─── Galley environment ─────────────────────────────────────────────────

  /// Hull cap + foam rim drawn directly after the wall ring. Painted in the
  /// translated grid-space (origin at the top-left of the wall ring), so the
  /// outerWallRect is the full grid rect.
  void _drawGalleyHullDecor(Canvas canvas) {
    final outerWallRect = Rect.fromLTWH(
      0,
      0,
      gameState.canvasWidth,
      gameState.canvasHeight,
    );
    drawGalleyHullCap(canvas: canvas, outerWallRect: outerWallRect);

    // Static deck decor: barrels, anchor, drum, rope coils, amphorae.
    // Positioned along the inner edges of the deck so they read as ship
    // gear without obstructing agent pathing in the centre.
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;
    final innerLeftPx = kTileSize.toDouble();
    final innerTopPx = kTileSize.toDouble();
    final innerRightPx = (gCols - 1) * kTileSize - 1;
    final innerBottomPx = (gRows - 1) * kTileSize - 1;

    // Structural fixtures only — barrels/amphorae/rope coils are now
    // purchasable furniture so the player decorates the deck themselves.
    // Drum + anchor stay as ship-iconography props.
    drawGalleyAnchor(
      canvas: canvas,
      x: innerRightPx - 18,
      y: innerBottomPx - 22,
    );
    drawGalleyWarDrum(
      canvas: canvas,
      x: innerLeftPx + 4,
      y: innerTopPx + 4,
      tick: tick,
    );

    // Hanging lanterns on the long sides (mid-points)
    drawGalleyLantern(
      canvas: canvas,
      x: innerLeftPx + (innerRightPx - innerLeftPx) * 0.25 - 4,
      y: innerTopPx + 2,
      tick: tick,
    );
    drawGalleyLantern(
      canvas: canvas,
      x: innerLeftPx + (innerRightPx - innerLeftPx) * 0.75 - 4,
      y: innerTopPx + 2,
      tick: tick,
    );

    // Through-hull oars: handle on the deck, blade out in the water. Count
    // scales with the galley length (every ~3 tiles along the bulwark) so a
    // longer ship gets a longer rowing bank. Reserve 4 tiles at each end for
    // bow/stern clearance. Staggered tick offsets desynchronise the rowing
    // cycle for organic motion.
    final gRowsLocal = gameState.gridRows;
    final reservedEndTiles = 4;
    final bankSpan = gRowsLocal - 2 * reservedEndTiles;
    final oarCount = (bankSpan / 3).floor().clamp(2, 14);
    final leftPivotX = kTileSize.toDouble();
    final rightPivotX = (gameState.gridCols - 1) * kTileSize.toDouble();
    for (int i = 0; i < oarCount; i++) {
      final t = (i + 0.5) / oarCount;
      final pivotY = reservedEndTiles * kTileSize + bankSpan * kTileSize * t;
      drawGalleyOarThroughHull(
        canvas: canvas,
        pivotX: leftPivotX,
        pivotY: pivotY,
        direction: -1,
        tick: tick + i * 7,
      );
      drawGalleyOarThroughHull(
        canvas: canvas,
        pivotX: rightPivotX,
        pivotY: pivotY,
        direction: 1,
        tick: tick + i * 11,
      );
    }
  }

  /// Galley structural features drawn after the z-sorted scene so they
  /// read as foreground silhouettes: bow ram + forecastle at the front,
  /// stern platform + lantern + shields along the back.
  void _drawGalleyTopLayer(Canvas canvas) {
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;
    final innerCols = gCols - 2;

    // Bow ram extending past the top wall — pointed prow read.
    final bowWidthTiles = (innerCols - 1).clamp(2, innerCols);
    final bowWidth = kTileSize * bowWidthTiles;
    final bowRect = Rect.fromLTWH(
      (gCols * kTileSize - bowWidth) / 2,
      -kTileSize * 0.75,
      bowWidth,
      kTileSize,
    );
    drawGalleyBow(canvas: canvas, bowRect: bowRect, figureheadEnabled: true);

    // Stern platform near the back of the ship — captain's deck.
    final sternWidthTiles = (innerCols - 1).clamp(2, innerCols);
    final sternWidth = kTileSize * sternWidthTiles;
    final sternRect = Rect.fromLTWH(
      (gCols * kTileSize - sternWidth) / 2,
      (gRows - 2) * kTileSize - 2,
      sternWidth,
      kTileSize * 1.2,
    );
    drawGalleySternPlatform(
      canvas: canvas,
      platformRect: sternRect,
      tick: tick,
    );

    // Stern lantern post on the rear corner of the platform.
    drawGalleyLantern(
      canvas: canvas,
      x: sternRect.right - 10,
      y: sternRect.top - 10,
      tick: tick,
    );
    drawGalleyLantern(
      canvas: canvas,
      x: sternRect.left + 2,
      y: sternRect.top - 10,
      tick: tick + 13,
    );

    // Shields lining the long bulwarks — alternating sides, evenly spaced.
    // Skip the first/last two rows so they don't clash with bow/stern.
    final shieldCount = ((gRows - 6) / 4).floor().clamp(2, 12);
    for (int i = 0; i < shieldCount; i++) {
      final t = (i + 1) / (shieldCount + 1);
      final y = 2 * kTileSize + (gRows - 4) * kTileSize * t;
      final leftSide = i.isEven;
      final x = leftSide ? kTileSize.toDouble() - 4 : (gCols - 1) * kTileSize - 8;
      drawGalleyShieldOnRail(canvas: canvas, x: x, y: y);
    }
  }

  // ─── Floor & walls ──────────────────────────────────────────────────────

  void _drawFloorAndWalls(Canvas canvas) {
    final tileMap = gameState.tileMap;
    final theme = _theme;
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;

    // Reuse _fillPaint for all tile rendering
    _fillPaint.style = PaintingStyle.fill;

    for (int r = 0; r < gRows; r++) {
      for (int c = 0; c < gCols; c++) {
        final tx = c * kTileSize;
        final ty = r * kTileSize;
        final tile = tileMap[r][c];

        if (tile == TileType.wall) {
          _fillPaint.color = theme.wallBase;
          canvas.drawRect(
            Rect.fromLTWH(tx, ty, kTileSize + 0.5, kTileSize + 0.5), _fillPaint);

          if (r > 0 && tileMap[r - 1][c] == TileType.floor) {
            _fillPaint.color = theme.wallTop;
            canvas.drawRect(Rect.fromLTWH(tx, ty, kTileSize + 0.5, 2), _fillPaint);
          }
          if (r < gRows - 1 && tileMap[r + 1][c] == TileType.floor) {
            _fillPaint.color = theme.wallInner;
            canvas.drawRect(
              Rect.fromLTWH(tx, ty + kTileSize - 2, kTileSize + 0.5, 2), _fillPaint);
          }
        } else {
          _fillPaint.color = (c + r) % 2 == 0 ? theme.floorDark : theme.floorLight;
          canvas.drawRect(
            Rect.fromLTWH(tx, ty, kTileSize + 0.5, kTileSize + 0.5), _fillPaint);
        }
      }
    }

    // Subtle grid using cached paint
    _floorGridPaint.color = theme.floorGrid;
    for (int c = 1; c < gCols; c++) {
      canvas.drawLine(
        Offset(c * kTileSize, kTileSize),
        Offset(c * kTileSize, (gRows - 1) * kTileSize),
        _floorGridPaint,
      );
    }
    for (int r = 1; r < gRows; r++) {
      canvas.drawLine(
        Offset(kTileSize, r * kTileSize),
        Offset((gCols - 1) * kTileSize, r * kTileSize),
        _floorGridPaint,
      );
    }
  }

  // ─── Z-sorted scene ─────────────────────────────────────────────────────

  void _drawScene(Canvas canvas) {
    // Collect drawables by category — allows batch-sorting later.
    final stationFurniture = <_Drawable>[];
    final coffeeMachine = <_Drawable>[];
    final snackTable = <_Drawable>[];
    final placedFurniture = <_Drawable>[];
    final characters = <_Drawable>[];
    final cat = <_Drawable>[];

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
      _addStationFurniture(stationFurniture, station, ch.isActive, ch);
    }

    // Coffee machine & snack table — only when their canonical tile fits the
    // current grid. Garage is too small to host them.
    if (_fitsInGrid(kCoffeeMachineCol2, kCoffeeMachineRow)) {
      _addCoffeeMachine(coffeeMachine);
    }
    if (_fitsInGrid(kSnackTableCol, kSnackTableRow)) {
      _addSnackTable(snackTable);
    }

    // Placed furniture items (plants are now purchasable furniture — no
    // auto-placed decorative corner plants).
    _addPlacedFurniture(placedFurniture);

    // Characters (only hired)
    for (final ch in gameState.characters.values) {
      if (!ch.isHired) continue;
      _addCharacter(characters, ch);
    }

    // Office cat
    _addCat(cat);

    // ─────────────────────────────────────────────────────────────────────────
    // Z-sort via merge — O(n) amortized instead of O(n log n) full sort.
    // Rationale: Most elements persist frame-to-frame (only state/position changes).
    // Pre-sorting by category means we only merge K sorted streams (K small).
    // ─────────────────────────────────────────────────────────────────────────

    // Sort each category individually (small lists, negligible cost)
    stationFurniture.sort((a, b) => a.zY.compareTo(b.zY));
    coffeeMachine.sort((a, b) => a.zY.compareTo(b.zY));
    snackTable.sort((a, b) => a.zY.compareTo(b.zY));
    placedFurniture.sort((a, b) => a.zY.compareTo(b.zY));
    characters.sort((a, b) => a.zY.compareTo(b.zY));
    cat.sort((a, b) => a.zY.compareTo(b.zY));

    // Merge all sorted streams into final render order — O(n) merge.
    // This is far faster than sorting a single large list when element count is high.
    final sortedDrawables = _mergeMultipleSorted([
      stationFurniture,
      coffeeMachine,
      snackTable,
      placedFurniture,
      characters,
      cat,
    ]);

    for (final d in sortedDrawables) {
      d.draw(canvas);
    }
  }

  /// Merge K sorted lists of drawables into single Z-sorted output.
  /// Time: O(n) where n = total drawable count. Space: O(n) for output.
  static List<_Drawable> _mergeMultipleSorted(List<List<_Drawable>> streams) {
    final result = <_Drawable>[];
    final iterators = streams.map((s) => s.iterator).toList();
    final heads = <_Drawable?>[for (final it in iterators) (it.moveNext() ? it.current : null)];

    while (heads.any((h) => h != null)) {
      // Find stream with minimum zY
      int minIdx = -1;
      double minZ = double.infinity;
      for (int i = 0; i < heads.length; i++) {
        if (heads[i] != null && heads[i]!.zY < minZ) {
          minZ = heads[i]!.zY;
          minIdx = i;
        }
      }

      if (minIdx >= 0) {
        result.add(heads[minIdx]!);
        heads[minIdx] = iterators[minIdx].moveNext() ? iterators[minIdx].current : null;
      }
    }

    return result;
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

    // Agents now sit at the SAME procedural workstation used by an empty
    // workstation room — the old PNG DESK_FRONT/PC desk is retired from
    // stations (it becomes a placeable furniture item). Drawn at the desk-row
    // zY so the agent (seat row, higher zY) renders in front of the desk+chair.
    drawables.add(_Drawable(deskZY, (c) {
      drawWorkstation(c, deskTileX, deskTileY, _theme, active: isActive);
    }));
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
        _charActivePaint.color = glowColor.withValues(alpha: 0.15);
        c.drawOval(
          Rect.fromCenter(
            center: Offset(ch.x, ch.y + sittingOffset + 1),
            width: 14,
            height: 4,
          ),
          _charActivePaint,
        );
      }));
    }

    // Selection / hover glow under feet
    if (isSelected || isHovered) {
      final outlineAlpha = isSelected ? 0.35 : 0.25;
      final targetPaint = isSelected ? _charSelectionPaint : _charHoverPaint;
      drawables.add(_Drawable(charZY - 0.002, (c) {
        targetPaint.color = const Color(0xFFFFC107).withValues(alpha: outlineAlpha);
        c.drawOval(
          Rect.fromCenter(
            center: Offset(ch.x, ch.y + sittingOffset + 1),
            width: 18,
            height: 6,
          ),
          targetPaint,
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

    // ── Specialization micro-glyph (C.1) ──
    // A 2px amber square in the top-right corner of the sprite head area,
    // visible only when the agent has at least one earned specialization.
    final specs = agentSpecializations[ch.instanceId];
    if (specs != null && specs.isNotEmpty) {
      final headX = ch.x + kSpriteW / 2 - 1;
      final headY = ch.y + sittingOffset - kSpriteH + 1;
      drawables.add(_Drawable(charZY + 0.002, (c) {
        c.drawRect(
          Rect.fromLTWH(headX, headY, 2, 2),
          Paint()..color = const Color(0xFFF59E0B),
        );
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
        final t = tick.toDouble();
        for (int i = 0; i < 5; i++) {
          final sx = mx + 4.0 + i * 2.5 + math.sin(t + i * 1.2) * 1.5;
          final sy = my - 1.5 - (t * 0.5 + i).remainder(5.0);
          final alpha = (0.35 - (t * 0.5 + i).remainder(5.0) / 12.0).clamp(0.0, 0.35);
          _fillPaint.color = Colors.white.withValues(alpha: alpha);
          _fillPaint.style = PaintingStyle.fill;
          c.drawRect(Rect.fromCenter(center: Offset(sx, sy), width: 1.5, height: 1.5), _fillPaint);
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
    FurnitureType.desk: Color(0xFF5C4033),
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

      if (item.id == 'desk_workstation') {
        _addWorkDeskSprite(drawables, placement, item);
        continue;
      }

      if (_addGalleyCargoSprite(drawables, placement, item)) {
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

  // ─── Galley cargo sprites (purchasable ship-themed furniture) ────────

  /// Returns true when [item] is a galley cargo prop and a sprite was added;
  /// the caller then skips the generic furniture fallback. Always anchored
  /// inside the placement's footprint so move/sell/edit gestures keep working
  /// through the existing furniture system unchanged.
  bool _addGalleyCargoSprite(
    List<_Drawable> drawables,
    FurniturePlacement placement,
    FurnitureItem item,
  ) {
    final baseX = placement.col * kTileSize.toDouble();
    final baseY = placement.row * kTileSize.toDouble();
    final zY = (placement.row + 1) * kTileSize.toDouble();

    switch (item.id) {
      case 'ship_barrel':
        drawables.add(_Drawable(zY, (c) {
          drawGalleyBarrel(canvas: c, x: baseX + 2, y: baseY + 3, stacked: false);
        }));
        return true;
      case 'ship_barrel_stack':
        drawables.add(_Drawable(zY, (c) {
          drawGalleyBarrel(canvas: c, x: baseX, y: baseY, stacked: true);
        }));
        return true;
      case 'ship_crate':
        drawables.add(_Drawable(zY, (c) {
          drawGalleyCrate(canvas: c, x: baseX + 1, y: baseY + 2);
        }));
        return true;
      case 'ship_amphora':
        drawables.add(_Drawable(zY, (c) {
          drawGalleyAmphora(canvas: c, x: baseX + 4, y: baseY + 1);
        }));
        return true;
      case 'ship_rope_coil':
        drawables.add(_Drawable(zY, (c) {
          drawGalleyRopeCoil(canvas: c, x: baseX + 2, y: baseY + 4);
        }));
        return true;
    }
    return false;
  }

  // ─── Work desk sprite (the default workstation desk, now purchasable) ──
  //
  // Mirrors the desk-with-monitor that spawns under each hired agent
  // (see [_addStationFurniture]) so a placed `desk_workstation` matches the
  // office's built-in desks instead of the generic furniture block.
  void _addWorkDeskSprite(
    List<_Drawable> drawables,
    FurniturePlacement placement,
    FurnitureItem item,
  ) {
    final theme = _theme;
    final baseX = placement.col * kTileSize.toDouble();
    final baseY = placement.row * kTileSize.toDouble();
    final w = item.widthTiles * kTileSize.toDouble();
    final zY = (placement.row + 1) * kTileSize.toDouble();
    final cx = baseX + w / 2;

    drawables.add(_Drawable(zY, (c) {
      final p = Paint()..style = PaintingStyle.fill;

      // Desk surface + front edge (theme-tinted, like the built-in desks).
      p.color = theme.deskSurface;
      c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 9, w - 2, 6), p);
      p.color = theme.deskEdge;
      c.drawRect(Rect.fromLTWH(baseX + 1, baseY + 15, w - 2, 1), p);

      // Monitor stand.
      p.color = const Color(0xFF2A2A35);
      c.drawRect(Rect.fromLTWH(cx - 1, baseY + 7, 2, 2), p);

      // Monitor frame.
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 4, baseY + 2, 8, 6),
          const Radius.circular(1),
        ),
        p,
      );

      // Screen — animated like the agents' live monitors: a cyan glow with
      // dim "code" scanlines that scroll one row per tick (a 2-frame flicker
      // on the same `tick` cadence as the built-in PCs).
      final on0 = tick % 2 == 0;
      p.color = const Color(0xFF00C0D1);
      c.drawRect(Rect.fromLTWH(cx - 3, baseY + 3, 6, 4), p);
      p.color = const Color(0xFF007A84);
      c.drawRect(Rect.fromLTWH(cx - 3, baseY + (on0 ? 4 : 5), 6, 1), p);
      c.drawRect(Rect.fromLTWH(cx - 3, baseY + (on0 ? 6 : 3), 4, 1), p);

      // Faint screen glow spilling onto the desk, pulsing with the flicker.
      p.color = const Color(0xFF00C0D1).withValues(alpha: on0 ? 0.10 : 0.06);
      c.drawRect(Rect.fromLTWH(baseX + 2, baseY + 9, w - 4, 3), p);
    }));
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

  // ─── Corridors ────────────────────────────────────────────────────────

  void _drawCorridors(Canvas canvas) {
    // Placed corridors are REAL floor structures connecting rooms — render in
    // every mode. Build neighbour sets so walls appear only on OPEN sides (not
    // where a corridor continues or meets a room — those edges are doorways).
    final corridorSet = <String>{};
    for (final c in placedCorridors) {
      for (final t in c.tiles) {
        corridorSet.add('${t.col},${t.row}');
        if (c.wide) corridorSet.add('${t.col + 1},${t.row}'); // wide right cell
      }
    }
    final roomSet = <String>{};
    for (final r in placedRooms) {
      for (var rc = r.col; rc < r.col + r.footprintWidth; rc++) {
        for (var rr = r.row; rr < r.row + r.footprintHeight; rr++) {
          roomSet.add('$rc,$rr');
        }
      }
    }
    for (final corridor in placedCorridors) {
      for (final tile in corridor.tiles) {
        _drawCorridorTile(
            canvas, tile.col, tile.row, corridor.wide, corridorSet, roomSet);
      }
    }

    // The corridor anchor dot is a build/edit affordance only.
    if (!buildMode && !editMode) return;

    // Anchor dot — first tap when drawing a corridor.
    final ac = corridorAnchorCol;
    final ar = corridorAnchorRow;
    if (ac != null && ar != null) {
      canvas.drawCircle(
        Offset((ac + 0.5) * kTileSize, (ar + 0.5) * kTileSize),
        3.5,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFFFFD700).withValues(alpha: 0.9),
      );
    }
  }

  /// Carpet body colour: tier [theme.floorDark] blended ~12% toward the tier
  /// accent — a distinct hallway runner that still belongs to the office.
  static Color _carpetBody(RoomTheme theme) =>
      Color.lerp(theme.floorDark, theme.accentColor, 0.12)!;

  /// Paints one corridor tile as a CARPETED hallway with neighbour-aware walls.
  /// The carpet is a woven accent-tinted runner; thin top-lit walls are drawn
  /// only on edges that border neither another corridor tile nor a room (those
  /// edges are doorways), so connected runs read continuous. [wide] doubles the
  /// width to two tiles.
  void _drawCorridorTile(Canvas canvas, int col, int row, bool wide,
      Set<String> corridorSet, Set<String> roomSet) {
    final theme = _theme;
    final tx = col * kTileSize;
    final ty = row * kTileSize;
    final w = wide ? kTileSize * 2 : kTileSize;
    final p = Paint()..style = PaintingStyle.fill;

    // ── Carpet runner: border stripes → pile field → directional weave ───────
    p.color = _carpetBody(theme);
    canvas.drawRect(Rect.fromLTWH(tx, ty, w, kTileSize), p);
    // Border stripes (read as a woven hem, not a smear).
    p.color = theme.wallBase.withValues(alpha: 0.65);
    canvas.drawRect(Rect.fromLTWH(tx, ty + 2, w, 2), p);
    canvas.drawRect(Rect.fromLTWH(tx, ty + kTileSize - 4, w, 2), p);
    // Thin bevel highlight just inside each stripe.
    p.color = theme.wallTop.withValues(alpha: 0.18);
    canvas.drawRect(Rect.fromLTWH(tx, ty + 4, w, 1), p);
    canvas.drawRect(Rect.fromLTWH(tx, ty + kTileSize - 5, w, 1), p);
    // Directional pile — two staggered rows of 1px dots (diagonal weave read).
    p.color = theme.wallBase.withValues(alpha: 0.25);
    for (var wx = tx + 1; wx < tx + w - 1; wx += 4) {
      canvas.drawRect(Rect.fromLTWH(wx, ty + 6, 1, 1), p);
    }
    for (var wx = tx + 3; wx < tx + w - 1; wx += 4) {
      canvas.drawRect(Rect.fromLTWH(wx, ty + 8, 1, 1), p);
    }
    // Center accent lane ties the runner to the tier.
    p.color = theme.accentColor.withValues(alpha: 0.09);
    canvas.drawRect(Rect.fromLTWH(tx + 4, ty + 5, w - 8, 6), p);

    // ── Walls on open sides — 3-layer cap (highlight + body + base shadow) ────
    bool open(int c, int r) =>
        !corridorSet.contains('$c,$r') && !roomSet.contains('$c,$r');
    final rightCol = wide ? col + 2 : col + 1;

    if (open(col, row - 1)) {
      p.color = theme.wallTop; // cap highlight
      canvas.drawRect(Rect.fromLTWH(tx, ty, w, 1), p);
      p.color = theme.wallBase; // body
      canvas.drawRect(Rect.fromLTWH(tx, ty + 1, w, 2), p);
      p.color = theme.wallInner.withValues(alpha: 0.80); // base shadow
      canvas.drawRect(Rect.fromLTWH(tx, ty + 3, w, 1), p);
    }
    if (open(col, row + 1)) {
      // Far edge — a receding shadow face (no top highlight from above).
      p.color = theme.wallBase.withValues(alpha: 0.75);
      canvas.drawRect(Rect.fromLTWH(tx, ty + kTileSize - 3, w, 2), p);
      p.color = theme.wallInner.withValues(alpha: 0.90);
      canvas.drawRect(Rect.fromLTWH(tx, ty + kTileSize - 1, w, 1), p);
    }
    if (open(col - 1, row)) {
      p.color = theme.wallTop;
      canvas.drawRect(Rect.fromLTWH(tx, ty, 1, kTileSize), p);
      p.color = theme.wallBase;
      canvas.drawRect(Rect.fromLTWH(tx + 1, ty, 2, kTileSize), p);
      p.color = theme.wallInner.withValues(alpha: 0.80);
      canvas.drawRect(Rect.fromLTWH(tx + 3, ty, 1, kTileSize), p);
    }
    if (open(rightCol, row)) {
      p.color = theme.wallInner.withValues(alpha: 0.80);
      canvas.drawRect(Rect.fromLTWH(tx + w - 4, ty, 1, kTileSize), p);
      p.color = theme.wallBase;
      canvas.drawRect(Rect.fromLTWH(tx + w - 3, ty, 2, kTileSize), p);
      p.color = theme.wallTop;
      canvas.drawRect(Rect.fromLTWH(tx + w - 1, ty, 1, kTileSize), p);
    }
  }

  // ─── Edit mode overlay ────────────────────────────────────────────────

  /// Builds a theme for [room] by applying any per-room wall/floor skin
  /// overrides on top of the tier default [_theme].
  RoomTheme _themeForRoom(PlacedRoom room) {
    final base = _theme;
    final wallPack = room.wallSkinId != null
        ? wallSkinPackById(room.wallSkinId!)
        : null;
    final floorPack = room.floorSkinId != null
        ? floorSkinPackById(room.floorSkinId!)
        : null;
    if (wallPack == null && floorPack == null) return base;
    return RoomTheme(
      id: base.id,
      name: base.name,
      nameEn: base.nameEn,
      tier: base.tier,
      wallBase: wallPack != null ? Color(wallPack.wallBase) : base.wallBase,
      wallTop: wallPack != null ? Color(wallPack.wallTop) : base.wallTop,
      wallInner:
          wallPack != null ? Color(wallPack.wallInner) : base.wallInner,
      floorDark:
          floorPack != null ? Color(floorPack.floorDark) : base.floorDark,
      floorLight:
          floorPack != null ? Color(floorPack.floorLight) : base.floorLight,
      floorGrid:
          floorPack != null ? Color(floorPack.floorGrid) : base.floorGrid,
      deskSurface: base.deskSurface,
      deskEdge: base.deskEdge,
      accentColor: base.accentColor,
      vignetteAlpha: base.vignetteAlpha,
    );
  }

  void _drawPlacedRooms(Canvas canvas) {
    // Workstation rooms whose extra station has a seated agent — those draw
    // their own PNG desk+PC via _addStationFurniture, so the room must NOT add
    // an ambient desk on top (else it doubles up). Extra stations carry the
    // room id as 'ws_<roomId>' (office_game_state._buildExtraStations).
    final occupiedWorkstationIds = <String>{};
    for (final station in gameState.allStations) {
      if (!station.isExtra || !station.agentId.startsWith('ws_')) continue;
      final roomId = station.agentId.substring(3);
      for (final ch in gameState.characters.values) {
        if (ch.isHired && ch.seat == station) {
          occupiedWorkstationIds.add(roomId);
          break;
        }
      }
    }

    for (final room in placedRooms) {
      drawRoom(
        canvas,
        room,
        _themeForRoom(room),
        tick,
        showWorkstationFurniture: false,
        workstationOccupied: occupiedWorkstationIds.contains(room.id),
        neighborRooms: placedRooms,
        neighborCorridors: placedCorridors,
      );
    }
  }

  void _drawBuildOverlay(Canvas canvas) {
    final blocked = gameState.blockedTiles;
    final gCols = gameState.gridCols;
    final gRows = gameState.gridRows;
    final p = Paint()..style = PaintingStyle.fill;

    // Foundation buffer past the owned grid — tiles where placement triggers
    // an expansion-step purchase. Painted FIRST so room overlays land on top.
    if (showFoundationBuffer &&
        (buildBufferCols > 0 || buildBufferRows > 0)) {
      _drawFoundationBuffer(
          canvas, gCols, gRows, buildBufferCols, buildBufferRows);
    }

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
      final ghostColor = ghostIsValid
          ? (ghostPendingExpand
              ? const Color(0xFFFFB020) // amber — fits, but needs expansion
              : const Color(0xFF44FF88)) // green — fits in owned grid
          : const Color(0xFFFF4444); // red — invalid

      // Auto-connect corridor preview — a GHOST of the SAME carpet the commit
      // builds: a faint carpet body + edge bands + an accent outline so it
      // reads as "the corridor that will appear here", not a committed path.
      if (connectingCorridorTiles.isNotEmpty) {
        final theme = _theme;
        final body = Paint()
          ..style = PaintingStyle.fill
          ..color = _carpetBody(theme).withValues(alpha: 0.28);
        final band = Paint()
          ..style = PaintingStyle.fill
          ..color = theme.wallBase.withValues(alpha: 0.22);
        final outline = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = theme.accentColor.withValues(alpha: 0.60);
        for (final t in connectingCorridorTiles) {
          final tx = t.col * kTileSize;
          final ty = t.row * kTileSize;
          canvas.drawRect(Rect.fromLTWH(tx, ty, kTileSize, kTileSize), body);
          canvas.drawRect(Rect.fromLTWH(tx, ty, kTileSize, 1), band);
          canvas.drawRect(
              Rect.fromLTWH(tx, ty + kTileSize - 1, kTileSize, 1), band);
          canvas.drawRect(
              Rect.fromLTWH(tx + 0.5, ty + 0.5, kTileSize - 1, kTileSize - 1),
              outline);
        }
      }

      void drawGhostRect(double rx, double ry, double rw, double rh,
          {bool dashed = false}) {
        canvas.drawRect(
            Rect.fromLTWH(rx, ry, rw, rh),
            Paint()
              ..color = ghostColor.withValues(alpha: 0.25)
              ..style = PaintingStyle.fill);
        final strokePaint = Paint()
          ..color = ghostColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        if (!dashed) {
          canvas.drawRect(
              Rect.fromLTWH(rx + 0.5, ry + 0.5, rw - 1, rh - 1), strokePaint);
        } else {
          // Dashed border signals Zone (open feature area without walls).
          const dash = 3.0;
          const gap = 2.0;
          final x1 = rx + 0.5;
          final y1 = ry + 0.5;
          final x2 = rx + rw - 0.5;
          final y2 = ry + rh - 0.5;
          for (double x = x1; x < x2; x += dash + gap) {
            final end = math.min(x + dash, x2);
            canvas.drawLine(Offset(x, y1), Offset(end, y1), strokePaint);
            canvas.drawLine(Offset(x, y2), Offset(end, y2), strokePaint);
          }
          for (double y = y1; y < y2; y += dash + gap) {
            final end = math.min(y + dash, y2);
            canvas.drawLine(Offset(x1, y), Offset(x1, end), strokePaint);
            canvas.drawLine(Offset(x2, y), Offset(x2, end), strokePaint);
          }
        }
      }

      final gt = ghostRoomType;
      if (gt != null) {
        final rotated = ghostRoomRotation == 90 || ghostRoomRotation == 270;
        final gw = (rotated ? gt.heightTiles : gt.widthTiles) * kTileSize;
        final gh = (rotated ? gt.widthTiles : gt.heightTiles) * kTileSize;
        drawGhostRect(gc * kTileSize, gr * kTileSize, gw, gh,
            dashed: gt.category == RoomCategory.zone);

        // Adjacency bonus label centred over the ghost footprint.
        final label = adjacencyLabel;
        if (label != null && ghostIsValid) {
          final isBonus = !label.startsWith('−') && !label.startsWith('-');
          final labelColor =
              isBonus ? const Color(0xFF44FFAA) : const Color(0xFFFF7744);
          final tp = TextPainter(
            text: TextSpan(
              text: label,
              style: TextStyle(
                color: labelColor,
                fontSize: 5,
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              gc * kTileSize + gw / 2 - tp.width / 2,
              gr * kTileSize + gh / 2 - tp.height / 2,
            ),
          );
        }
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

  /// Renders the foundation-grid buffer past the owned grid edges (right and
  /// bottom). Tiles drawn here are "purchasable expansion" — the player can
  /// place a room into this area and the place transaction will auto-buy the
  /// required expansion step(s).
  ///
  /// Visual: subtle amber wash + 4 short L-shaped corner markers per tile
  /// (SimCity / Frostpunk lot-marker idiom). Hairline amber boundary line +
  /// compact per-tile "12К₲" cost stamp so the player can read both the
  /// affordance and the price without 60 plus-signs spamming the screen.
  void _drawFoundationBuffer(
      Canvas canvas, int gCols, int gRows, int bufC, int bufR) {
    // Soft amber wash — quiet enough that an 8×12 buffer doesn't dominate the
    // canvas. Dark overlay removed (V3 dropped it: corners + fill carry the
    // affordance on their own).
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFB020).withValues(alpha: 0.14);
    final corner = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFD680).withValues(alpha: 0.70);

    final startCol = gCols - 1;
    final endCol = gCols - 1 + bufC;
    final startRow = gRows - 1;
    final endRow = gRows - 1 + bufR;

    // L-corner geometry: short hairline arms so the buffer reads as a marked
    // grid without competing with the boundary line for weight.
    const armLen = 2.0;
    const armThick = 0.5;
    const inset = 2.5;

    bool isHoverThisTile(int c, int r) =>
        hoveredBufferCol == c &&
        hoveredBufferRow == r &&
        bufferHoverAlpha > 0.0;

    // Affordance palette: green when the next expansion step is affordable,
    // red otherwise. Press boosts saturation so the click reads as a positive
    // commit, not just a brighter hover.
    final hoverWashBase = bufferHoverAffordable
        ? const Color(0xFF52E07A) // green-leaning amber
        : const Color(0xFFE05252); // crimson
    final hoverCornerBase = bufferHoverAffordable
        ? const Color(0xFFB6FFC8)
        : const Color(0xFFFFC9C9);

    void paintTile(int c, int r) {
      final x = c * kTileSize;
      final y = r * kTileSize;
      canvas.drawRect(Rect.fromLTWH(x, y, kTileSize, kTileSize), fill);

      if (isHoverThisTile(c, r)) {
        final t = bufferHoverAlpha.clamp(0.0, 1.0);
        final washAlpha = (bufferHoverPressed ? 0.55 : 0.38) * t;
        canvas.drawRect(
          Rect.fromLTWH(x, y, kTileSize, kTileSize),
          Paint()
            ..style = PaintingStyle.fill
            ..color = hoverWashBase.withValues(alpha: washAlpha),
        );
        if (bufferHoverPressed) {
          // Inner 1-px stroke marking the click target — short-lived, only
          // while the pointer is down.
          canvas.drawRect(
            Rect.fromLTWH(x + 0.5, y + 0.5, kTileSize - 1, kTileSize - 1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.5
              ..color = hoverCornerBase.withValues(alpha: 0.9 * t),
          );
        }
      }

      // Top-left corner.
      canvas.drawRect(
          Rect.fromLTWH(x + inset, y + inset, armLen, armThick), corner);
      canvas.drawRect(
          Rect.fromLTWH(x + inset, y + inset, armThick, armLen), corner);
      // Top-right corner.
      canvas.drawRect(
          Rect.fromLTWH(x + kTileSize - inset - armLen, y + inset, armLen,
              armThick),
          corner);
      canvas.drawRect(
          Rect.fromLTWH(x + kTileSize - inset - armThick, y + inset, armThick,
              armLen),
          corner);
      // Bottom-left corner.
      canvas.drawRect(
          Rect.fromLTWH(x + inset, y + kTileSize - inset - armThick, armLen,
              armThick),
          corner);
      canvas.drawRect(
          Rect.fromLTWH(x + inset, y + kTileSize - inset - armLen, armThick,
              armLen),
          corner);
      // Bottom-right corner.
      canvas.drawRect(
          Rect.fromLTWH(x + kTileSize - inset - armLen,
              y + kTileSize - inset - armThick, armLen, armThick),
          corner);
      canvas.drawRect(
          Rect.fromLTWH(x + kTileSize - inset - armThick,
              y + kTileSize - inset - armLen, armThick, armLen),
          corner);
    }

    // Right buffer: full vertical strip past current right wall.
    for (int c = startCol; c <= endCol; c++) {
      for (int r = 0; r <= endRow; r++) {
        paintTile(c, r);
      }
    }
    // Bottom buffer: horizontal strip past current bottom wall, skipping
    // tiles already painted by the right buffer (corner overlap).
    for (int r = startRow; r <= endRow; r++) {
      for (int c = 0; c < startCol; c++) {
        paintTile(c, r);
      }
    }

    // Boundary line where owned grid ends — hairline amber so the buffer
    // reads as a separate purchasable area without dominating the canvas.
    final boundary = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0xFFFFD680).withValues(alpha: 0.85);
    final ownedRight = (gCols - 1) * kTileSize;
    final ownedBottom = (gRows - 1) * kTileSize;
    if (bufC > 0) {
      canvas.drawLine(Offset(ownedRight, 0),
          Offset(ownedRight, ownedBottom), boundary);
    }
    if (bufR > 0) {
      canvas.drawLine(Offset(0, ownedBottom),
          Offset(ownedRight, ownedBottom), boundary);
    }

    // ONE quiet price chip for the whole lot (replaces the old per-tile
    // "12К₲" stamp that read as clutter), anchored just past the boundary.
    final cost = nextExpansionCost;
    if (cost != null && (bufC > 0 || bufR > 0)) {
      final label = TextPainter(
        text: TextSpan(
          text: '+${_formatCompact(cost)}₲ / крок',
          style: const TextStyle(
            color: Color(0xFFFFD680),
            fontSize: 4.5,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lx = bufC > 0 ? ownedRight + 2.0 : kTileSize + 2.0;
      final ly = bufC > 0 ? kTileSize + 2.0 : ownedBottom + 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(lx - 1.5, ly - 1, label.width + 3, label.height + 2),
          const Radius.circular(1.5),
        ),
        Paint()..color = const Color(0xCC1A1A2E),
      );
      label.paint(canvas, Offset(lx, ly));
    }
  }

  /// "12000" → "12К", "1250" → "1.3К", "140" → "140". Mirrors the upgrade
  /// dialog's compact formatter so a single visual idiom carries across the
  /// shop, the foundation buffer, and any future ₲ surface.
  String _formatCompact(int n) {
    if (n >= 1000) {
      final k = n / 1000;
      return k % 1 == 0
          ? '${k.toStringAsFixed(0)}К'
          : '${k.toStringAsFixed(1)}К';
    }
    return n.toString();
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

    // Highlight placed furniture outlines. The held item (player picked it
    // up to move) gets a thicker, brighter, pulsing stroke so it reads as
    // distinct from passive "you can edit me" outlines.
    final pulse = ((tick % 30) / 30.0); // 0..1 sawtooth
    final pulseAlpha = 0.55 + 0.35 * (1 - (pulse - 0.5).abs() * 2).clamp(0, 1);

    for (int i = 0; i < placedFurniture.length; i++) {
      final placement = placedFurniture[i];
      final item = furnitureById(placement.itemId);
      if (item == null) continue;

      final fx = placement.col * kTileSize;
      final fy = placement.row * kTileSize;
      final fw = item.widthTiles * kTileSize;
      final fh = item.heightTiles * kTileSize;
      final isHeld = i == heldPlacedFurnitureIndex;

      canvas.drawRect(
        Rect.fromLTWH(fx + 0.5, fy + 0.5, fw - 1, fh - 1),
        Paint()
          ..color = isHeld
              ? const Color(0xFF7CFF7C).withValues(alpha: pulseAlpha)
              : const Color(0xFFFFD700).withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHeld ? 2 : 1,
      );

      if (isHeld) {
        // Inner glow — softens the harsh stroke and reads as "lifted".
        canvas.drawRect(
          Rect.fromLTWH(fx + 1.5, fy + 1.5, fw - 3, fh - 3),
          Paint()
            ..color = const Color(0xFF7CFF7C).withValues(alpha: 0.18)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Drop-preview ghost: the held / selected item's footprint at the current
    // hover tile, tinted by validity. Drawn last so it sits on top of the
    // gridlines and the held-item outline.
    final ghostItem = ghostFurnitureItem;
    final ghostCol = ghostFurnitureCol;
    final ghostRow = ghostFurnitureRow;
    if (ghostItem != null && ghostCol != null && ghostRow != null) {
      final gx = ghostCol * kTileSize;
      final gy = ghostRow * kTileSize;
      final gw = ghostItem.widthTiles * kTileSize;
      final gh = ghostItem.heightTiles * kTileSize;
      final tint = ghostFurnitureValid
          ? const Color(0xFF7CFF7C)
          : const Color(0xFFFF6B6B);
      canvas.drawRect(
        Rect.fromLTWH(gx, gy, gw, gh),
        Paint()..color = tint.withValues(alpha: 0.22),
      );
      canvas.drawRect(
        Rect.fromLTWH(gx + 0.5, gy + 0.5, gw - 1, gh - 1),
        Paint()
          ..color = tint.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
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
    final cw = gameState.canvasWidth;
    final ch = gameState.canvasHeight;
    final center = Offset(cw / 2, ch / 2);
    final rect = Rect.fromCenter(
      center: center,
      width: cw,
      height: ch,
    );
    final theme = _theme;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, cw, ch),
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
        Rect.fromLTWH(0, 0, cw, ch),
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
        Rect.fromLTWH(0, 0, cw, ch),
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
  bool shouldRepaint(PixelOfficePainter oldDelegate) {
    // Only repaint when the office scene has meaningfully changed:
    // - Game state (agent positions, states, economy)
    // - Placed rooms, corridors, furniture (the structural layout)
    // Ignore transient UI state: animations, hovers, selection, etc.
    const deepEquality = DeepCollectionEquality();

    return oldDelegate.gameState != gameState ||
        !deepEquality.equals(oldDelegate.placedRooms, placedRooms) ||
        !deepEquality.equals(oldDelegate.placedCorridors, placedCorridors) ||
        !deepEquality.equals(
            oldDelegate.placedFurniture, placedFurniture);
  }
}
