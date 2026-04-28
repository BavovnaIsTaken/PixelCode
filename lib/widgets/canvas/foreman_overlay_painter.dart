/// Paints the Майстер ремонту (foreman) and the back-wall "door to the next
/// tier" — the two diegetic entry points to building and upgrading the
/// office. Lives as a separate layer above [PixelOfficePainter] so we can
/// hit-test these elements without touching the main scene painter.
///
/// The foreman reuses one of the existing 16×32 character sprite sheets so
/// he reads as "one of the team" — just in a hard hat. The sprite is drawn
/// first, then a yellow pixel-art helmet is painted over the head.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import 'character_sprites.dart';
import 'office_game_state.dart';
import 'room_themes.dart';

// ─── Above-head hint priority ───────────────────────────────────────────────

/// Which hint, if any, should be drawn above the foreman this frame.
/// Pure ordering — extracted from the painter so the priority is testable
/// without spinning up a Flutter widget tree.
enum ForemanHint { none, attention, onboarding, needsDesk, hover }

/// Resolve the active hint given the live UI inputs. Hover wins over every
/// other hint (live cursor feedback), then the one-time onboarding chevron,
/// then the "needs desk" nudge for unassigned agents, then the affordability
/// "!" bubble.
ForemanHint pickForemanHint({
  required bool hovering,
  required bool firstTimePrompt,
  required bool attention,
  bool hasUnassignedAgent = false,
}) {
  if (hovering) return ForemanHint.hover;
  if (firstTimePrompt) return ForemanHint.onboarding;
  if (hasUnassignedAgent) return ForemanHint.needsDesk;
  if (attention) return ForemanHint.attention;
  return ForemanHint.none;
}

// ─── Layout constants ───────────────────────────────────────────────────────
// Foreman tile position is declared in office_game_state.dart (foremanColFor/
// foremanRowFor) so blockedTiles can reference it without a circular import.

/// Door is 2 tiles wide, painted on the top wall (row 0). Horizontal position
/// is computed from gridCols so the door sits at roughly the centre of the
/// back wall regardless of office size.
int doorLeftColFor(int gridCols) => math.max(1, (gridCols - 2) ~/ 2);
const int kDoorWidthTiles = 2;

/// Which character sprite sheet to use for the foreman. char_0 is the blue-
/// shirt base — works well next to a yellow hard hat.
const int _kForemanPaletteIndex = 0;

/// World-space bounds for the foreman, matching the 16×32 chibi sprite that
/// the other office workers use. Padded slightly so tapping near his
/// silhouette registers.
Rect foremanHitRect(int gridCols, int gridRows) {
  final col = foremanColFor(gridCols);
  final row = foremanRowFor(gridRows);
  final left = col * kTileSize - 2;
  final top = row * kTileSize - kTileSize + kForemanVertOffset + 2;
  return Rect.fromLTWH(left, top, kTileSize + 4, kTileSize * 2 - 2);
}

Rect doorHitRect(int gridCols) {
  final col = doorLeftColFor(gridCols);
  return Rect.fromLTWH(
    col * kTileSize,
    0,
    kDoorWidthTiles * kTileSize,
    kTileSize,
  );
}

// ─── Paint for pixel-perfect image rendering ────────────────────────────────

final _pixelPaint = Paint()..filterQuality = FilterQuality.none;

// ─── Painter ────────────────────────────────────────────────────────────────

class ForemanOverlayPainter extends CustomPainter {
  final int gridCols;
  final int gridRows;
  final int tick;
  final OfficeLevel officeLevel;
  final SpriteManager? sprites;

  /// Whether the "!" bubble hovers above the foreman — signal that something
  /// affordable is up for grabs (next tier OR an expansion).
  final bool attention;

  /// First-launch onboarding hint: shows a bouncing chevron above the foreman
  /// until the player has tapped him at least once. Distinct from [attention]
  /// (which fires for affordability). When true, takes priority over the
  /// attention bubble — onboarding the player matters more than upsells.
  final bool firstTimePrompt;

  /// True while a desktop pointer is hovering over the foreman hit rect.
  /// Triggers a small "Збудуємо щось?" speech bubble — a diegetic tooltip
  /// that replaces the chevron / attention bubble while active.
  final bool hovering;

  /// Next office tier, if any. Drives the door's accent palette.
  final OfficeLevel? nextTier;

  /// Can the player afford the jump to [nextTier] right now?
  final bool doorAffordable;

  /// True when there is no next tier (already maxed or next tier WIP). The
  /// door is replaced with a sealed plate.
  final bool doorDisabled;

  /// True when at least one hired agent has [WorkplaceStatus.unassigned].
  /// Triggers a house-icon nudge bubble above the foreman.
  final bool hasUnassignedAgent;

  ForemanOverlayPainter({
    required this.gridCols,
    required this.gridRows,
    required this.tick,
    required this.officeLevel,
    required this.sprites,
    required this.attention,
    required this.firstTimePrompt,
    required this.hovering,
    required this.nextTier,
    required this.doorAffordable,
    required this.doorDisabled,
    this.hasUnassignedAgent = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Mirror PixelOfficePainter's scale/translate math so world-space
    // coordinates line up exactly with the underlying scene.
    final cw = gridCols * kTileSize;
    final ch = gridRows * kTileSize;
    final scale = math.min(size.width / cw, size.height / ch);
    final offsetX = (size.width - cw * scale) / 2;
    final offsetY = (size.height - ch * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    _drawDoor(canvas);
    _drawForeman(canvas);

    canvas.restore();
  }

  // ─── Back-wall door ─────────────────────────────────────────────────────

  void _drawDoor(Canvas canvas) {
    final col = doorLeftColFor(gridCols);
    final x = col * kTileSize;
    final w = kDoorWidthTiles * kTileSize;
    final h = kTileSize; // fits within row 0 (the wall strip)

    final theme = roomThemeForLevel(officeLevel);

    // Tier palette: the door is painted in the NEXT tier's accent so the
    // player sees a glimpse of what's behind it. Falls back to current wall
    // tones if there's no next tier.
    final tierTheme = nextTier == null
        ? theme
        : roomThemeForLevel(nextTier!);
    final frameColor = doorDisabled
        ? theme.wallBase
        : Color.lerp(theme.wallBase, tierTheme.wallTop, 0.55)!;
    final panelColor = doorDisabled
        ? Color.lerp(theme.wallInner, Colors.black, 0.3)!
        : Color.lerp(tierTheme.floorLight, theme.wallInner, 0.55)!;
    final accentColor = doorDisabled
        ? theme.wallTop
        : Color.lerp(tierTheme.deskSurface, const Color(0xFFFFD700), 0.25)!;

    final p = Paint()..style = PaintingStyle.fill;

    // Frame (2px border around the door opening)
    p.color = frameColor;
    canvas.drawRect(Rect.fromLTWH(x, 0, w, h), p);

    // Inner panel — slightly inset so the frame reads as a frame.
    p.color = panelColor;
    canvas.drawRect(Rect.fromLTWH(x + 2, 2, w - 4, h - 2), p);

    // Vertical split line (double-door look) + horizontal trim.
    p.color = frameColor;
    canvas.drawRect(Rect.fromLTWH(x + w / 2 - 0.5, 2, 1, h - 2), p);
    canvas.drawRect(Rect.fromLTWH(x + 2, h / 2, w - 4, 1), p);

    // Door handles — two dots, one per leaf.
    p.color = accentColor;
    canvas.drawRect(Rect.fromLTWH(x + w / 2 - 3, h / 2 + 1, 2, 2), p);
    canvas.drawRect(Rect.fromLTWH(x + w / 2 + 1, h / 2 + 1, 2, 2), p);

    // Tier-label strip above the door (1px line under the top wall) — the
    // next office peeks through.
    if (!doorDisabled) {
      p.color = accentColor.withValues(alpha: 0.8);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, 1), p);
    }

    // Soft golden rim when the player can afford to move in.
    if (doorAffordable && !doorDisabled) {
      final pulse = (math.sin(tick * 0.12) + 1) / 2; // 0..1
      final rim = Paint()
        ..color = const Color(0xFFFFD700).withValues(alpha: 0.15 + 0.25 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawRect(Rect.fromLTWH(x, 0, w, h), rim);
    }

    // Locked padlock when the next tier exists but is unaffordable.
    if (!doorAffordable && !doorDisabled) {
      final lockX = x + w / 2 - 2;
      final lockY = h / 2 - 2;
      p.color = const Color(0xFF222222);
      canvas.drawRect(Rect.fromLTWH(lockX, lockY, 4, 3), p);
      p.color = const Color(0xFFAAAAAA);
      canvas.drawRect(Rect.fromLTWH(lockX + 1, lockY - 1, 2, 1), p);
    }
  }

  // ─── Foreman sprite ─────────────────────────────────────────────────────
  // Uses a real 16×32 character sheet (the same art as the other workers)
  // plus a pixel-art hard hat painted over the head. Falls back to a
  // programmatic silhouette while sprites are still loading.

  void _drawForeman(Canvas canvas) {
    final col = foremanColFor(gridCols);
    final row = foremanRowFor(gridRows);
    final tileX = col * kTileSize;
    final tileY = row * kTileSize;

    final spriteX = tileX;
    final spriteY = tileY - kTileSize + kForemanVertOffset; // sprite extends 1 tile up, shifted down 1/3 tile

    final sheet = sprites?.charSheet(_kForemanPaletteIndex);
    if (sheet != null) {
      _drawCharSprite(canvas, sheet, spriteX, spriteY);
    } else {
      _drawFallbackSilhouette(canvas, spriteX, spriteY);
    }

    // Shadow under feet.
    final p = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: 0.22);
    canvas.drawOval(Rect.fromLTWH(spriteX + 3, tileY - 1 + kForemanVertOffset, 10, 2), p);

    // Hard hat over the head — head occupies approximately rows 6–16 of the
    // 32-px sprite. Sitting the hat at rows 4–10 covers the hair and slightly
    // overhangs the forehead, giving a clear silhouette.
    _drawHardHat(canvas, spriteX, spriteY);

    final hint = pickForemanHint(
      hovering: hovering,
      firstTimePrompt: firstTimePrompt,
      attention: attention,
      hasUnassignedAgent: hasUnassignedAgent,
    );
    switch (hint) {
      case ForemanHint.hover:
        _drawSpeechBubble(canvas, spriteX, spriteY);
      case ForemanHint.onboarding:
        _drawOnboardingChevron(canvas, spriteX, spriteY);
      case ForemanHint.needsDesk:
        _drawNeedsDeskBubble(canvas, spriteX, spriteY);
      case ForemanHint.attention:
        _drawAttentionBubble(canvas, spriteX, spriteY);
      case ForemanHint.none:
        break;
    }
  }

  void _drawCharSprite(Canvas canvas, ui.Image sheet, double x, double y) {
    // Frame 1 (standing pose, DOWN-facing) — same frame agents use when idle.
    final src = charFrameRect(1, 0);
    canvas.drawImageRect(
      sheet,
      src,
      Rect.fromLTWH(x, y, kSpriteW.toDouble(), kSpriteH.toDouble()),
      _pixelPaint,
    );
  }

  /// Minimal chibi silhouette shown for the one-frame window between widget
  /// mount and sprite-sheet load. Matches the character proportions so the
  /// hat placement works either way.
  void _drawFallbackSilhouette(Canvas canvas, double x, double y) {
    final p = Paint()..style = PaintingStyle.fill;
    // Head
    p.color = const Color(0xFFE8B89D);
    canvas.drawRect(Rect.fromLTWH(x + 4, y + 10, 8, 8), p);
    // Body
    p.color = const Color(0xFF2E4A7A);
    canvas.drawRect(Rect.fromLTWH(x + 4, y + 18, 8, 8), p);
    // Legs
    p.color = const Color(0xFF1C2E4D);
    canvas.drawRect(Rect.fromLTWH(x + 5, y + 26, 2, 4), p);
    canvas.drawRect(Rect.fromLTWH(x + 9, y + 26, 2, 4), p);
  }

  void _drawHardHat(Canvas canvas, double x, double y) {
    const hatYellow = Color(0xFFFFC107);
    const hatYellowLight = Color(0xFFFFEAA0);
    const hatBand = Color(0xFFB07500);

    final p = Paint()..style = PaintingStyle.fill;

    // Dome — slightly narrower than the head, 8 px wide.
    p.color = hatYellow;
    canvas.drawRect(Rect.fromLTWH(x + 4, y + 6, 8, 4), p);
    canvas.drawRect(Rect.fromLTWH(x + 5, y + 5, 6, 1), p);
    canvas.drawRect(Rect.fromLTWH(x + 6, y + 4, 4, 1), p);
    // Highlight streak
    p.color = hatYellowLight;
    canvas.drawRect(Rect.fromLTWH(x + 5, y + 6, 2, 1), p);
    canvas.drawRect(Rect.fromLTWH(x + 6, y + 5, 1, 1), p);
    // Band
    p.color = hatBand;
    canvas.drawRect(Rect.fromLTWH(x + 4, y + 9, 8, 1), p);
    // Brim — 1 px wider on each side, extends over the forehead.
    p.color = hatYellow;
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 10, 10, 1), p);
  }

  void _drawAttentionBubble(Canvas canvas, double x, double y) {
    final bubbleY = y - 5;
    final bubbleX = x + 11;
    final p = Paint()..style = PaintingStyle.fill;
    p.color = const Color(0xFFFFD700);
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY, 5, 6), p);
    p.color = const Color(0xFFB07500);
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY + 5, 5, 1), p);
    // "!"
    p.color = const Color(0xFF1A1A1F);
    canvas.drawRect(Rect.fromLTWH(bubbleX + 2, bubbleY + 1, 1, 3), p);
    canvas.drawRect(Rect.fromLTWH(bubbleX + 2, bubbleY + 5, 1, 1), p);
    // Tail
    p.color = const Color(0xFFFFD700);
    canvas.drawRect(Rect.fromLTWH(bubbleX + 1, bubbleY + 6, 2, 1), p);
  }

  /// Pixel-art desk icon bubble shown when an agent has no workstation yet.
  /// Cyan tint — distinct from the gold "!" affordability bubble.
  /// Icon: simplified 5×5 desk silhouette (flat top + two legs).
  void _drawNeedsDeskBubble(Canvas canvas, double x, double y) {
    final bubbleY = y - 5;
    final bubbleX = x + 11;
    final p = Paint()..style = PaintingStyle.fill;

    // Bubble body
    p.color = const Color(0xFF00C0D1);
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY, 7, 8), p);
    p.color = const Color(0xFF007A87);
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY + 7, 7, 1), p);

    // Desk icon: tabletop (row 1), two legs (rows 3–4)
    p.color = const Color(0xFF1A1A1F);
    canvas.drawRect(Rect.fromLTWH(bubbleX + 1, bubbleY + 1, 5, 1), p); // top
    canvas.drawRect(Rect.fromLTWH(bubbleX + 1, bubbleY + 3, 1, 2), p); // left leg
    canvas.drawRect(Rect.fromLTWH(bubbleX + 5, bubbleY + 3, 1, 2), p); // right leg

    // Tail
    p.color = const Color(0xFF00C0D1);
    canvas.drawRect(Rect.fromLTWH(bubbleX + 2, bubbleY + 8, 2, 1), p);
  }

  /// One-time onboarding chevron — pixel-art down arrow that bobs above the
  /// foreman so first-time players notice the build entry. Drawn larger and
  /// brighter than the affordability "!" so it actually catches the eye.
  void _drawOnboardingChevron(Canvas canvas, double x, double y) {
    // Slow bob ~1 cycle per second (tick @ 30fps → 0.21 rad/frame ≈ 1Hz).
    final bob = math.sin(tick * 0.21) * 1.5;
    final cx = x + 8; // centred over the head
    final topY = y - 10 + bob;

    final p = Paint()..style = PaintingStyle.fill;

    // Drop shadow for legibility against busy backgrounds.
    p.color = const Color(0x44000000);
    _paintChevron(canvas, p, cx + 1, topY + 1);

    // Bright accent fill (gold so it reads as friendly, not warning).
    p.color = const Color(0xFFFFE357);
    _paintChevron(canvas, p, cx, topY);

    // Inner highlight stripe — 1 px lighter line on the top edge.
    p.color = const Color(0xFFFFF7C2);
    canvas.drawRect(Rect.fromLTWH(cx - 2, topY, 4, 1), p);
  }

  /// Pixel-art chevron pointing DOWN. 7 px wide, 5 px tall.
  ///   ███████
  ///    █████
  ///     ███
  ///      █
  void _paintChevron(Canvas canvas, Paint p, double cx, double topY) {
    canvas.drawRect(Rect.fromLTWH(cx - 3, topY, 7, 1), p);
    canvas.drawRect(Rect.fromLTWH(cx - 2, topY + 1, 5, 1), p);
    canvas.drawRect(Rect.fromLTWH(cx - 1, topY + 2, 3, 1), p);
    canvas.drawRect(Rect.fromLTWH(cx, topY + 3, 1, 1), p);
  }

  /// Diegetic hover tooltip — pixel-art speech bubble with "Збудуємо щось?"
  /// in a tiny 4 px font built from rectangles. Renders a fixed bubble; the
  /// painter doesn't try to layout text via a TextPainter because it would
  /// blur on the integer-scale pixel grid.
  void _drawSpeechBubble(Canvas canvas, double x, double y) {
    // Bubble sits to the right of the foreman so it doesn't clip into the
    // grid above. 38 × 9 px keeps the proportions reading as a pixel-art
    // bubble even at 4× canvas scale.
    const bubbleW = 38.0;
    const bubbleH = 9.0;
    // Clamp so the bubble never overflows the right canvas edge (world-space).
    final maxBubbleX = gridCols * kTileSize - bubbleW - 1.0;
    final bubbleX = math.min(x + 14, maxBubbleX);
    // Same base Y as _drawAttentionBubble so the two hints sit at the same height.
    final bubbleY = y - 5;

    final p = Paint()..style = PaintingStyle.fill;

    // Shadow (1 px offset down-right).
    p.color = const Color(0x44000000);
    canvas.drawRect(
      Rect.fromLTWH(bubbleX + 1, bubbleY + 1, bubbleW, bubbleH),
      p,
    );

    // Bubble body — soft cream so text reads warm, not clinical.
    p.color = const Color(0xFFFFF6D8);
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY, bubbleW, bubbleH), p);

    // 1 px outline.
    p.color = const Color(0xFF2A2218);
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY, bubbleW, 1), p);
    canvas.drawRect(
      Rect.fromLTWH(bubbleX, bubbleY + bubbleH - 1, bubbleW, 1),
      p,
    );
    canvas.drawRect(Rect.fromLTWH(bubbleX, bubbleY, 1, bubbleH), p);
    canvas.drawRect(
      Rect.fromLTWH(bubbleX + bubbleW - 1, bubbleY, 1, bubbleH),
      p,
    );

    // Tail — points down-left toward the foreman's head.
    p.color = const Color(0xFFFFF6D8);
    canvas.drawRect(Rect.fromLTWH(bubbleX - 1, bubbleY + 4, 1, 2), p);
    canvas.drawRect(Rect.fromLTWH(bubbleX - 2, bubbleY + 5, 1, 1), p);
    p.color = const Color(0xFF2A2218);
    canvas.drawRect(Rect.fromLTWH(bubbleX - 2, bubbleY + 4, 1, 1), p);
    canvas.drawRect(Rect.fromLTWH(bubbleX - 3, bubbleY + 5, 1, 1), p);
    canvas.drawRect(Rect.fromLTWH(bubbleX - 1, bubbleY + 6, 1, 1), p);

    // "Збудуємо?" — 4 px tall, drawn via TextPainter at the bubble centre.
    // We allow TextPainter here because the bubble itself is large enough
    // that 1-px font hinting blurs aren't visible. The bubble outline is
    // pixel-art; the inner text is anti-aliased by design.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'Збудуємо?',
        style: TextStyle(
          color: Color(0xFF2A2218),
          fontSize: 5.5,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bubbleW - 2);
    tp.paint(
      canvas,
      Offset(bubbleX + (bubbleW - tp.width) / 2, bubbleY + 1.5),
    );
  }

  @override
  bool shouldRepaint(covariant ForemanOverlayPainter old) =>
      old.gridCols != gridCols ||
      old.gridRows != gridRows ||
      old.tick != tick ||
      old.officeLevel != officeLevel ||
      old.sprites != sprites ||
      old.attention != attention ||
      old.firstTimePrompt != firstTimePrompt ||
      old.hovering != hovering ||
      old.nextTier != nextTier ||
      old.doorAffordable != doorAffordable ||
      old.doorDisabled != doorDisabled;
}
