/// Per-instance cosmetic accessories drawn on top of character sprites.
///
/// Accessories are deterministic from instanceId so a given developer always
/// looks the same across sessions. Extras of the same role therefore end up
/// visually distinct from the primary hire without any extra art assets.
library;

import 'package:flutter/material.dart';

import 'office_game_state.dart';

/// Lightweight accessory tags. Each tag is rendered programmatically in the
/// painter — no sprite sheet needed.
enum CharAccessory {
  none,
  glasses,
  headphones,
  cap,
  beanie,
  headband,
  earring,
}

/// Secondary hair-color tint. Applied as an alpha tint over the head area so
/// same-sheet instances of a role still read as different people.
enum HairTint {
  none,
  blond,
  red,
  silver,
  pink,
  blue,
  green,
}

extension HairTintExt on HairTint {
  Color? get color => switch (this) {
        HairTint.none => null,
        HairTint.blond => const Color(0xFFE6C34A),
        HairTint.red => const Color(0xFFB8371A),
        HairTint.silver => const Color(0xFFCED1D6),
        HairTint.pink => const Color(0xFFF06EA1),
        HairTint.blue => const Color(0xFF4E8BD1),
        HairTint.green => const Color(0xFF5FA765),
      };
}

/// Cosmetic spec derived from [instanceId]. Deterministic per instance so the
/// same developer always looks the same.
class CharCosmetics {
  final int paletteIndex;
  final CharAccessory accessory;
  final HairTint hairTint;

  const CharCosmetics({
    required this.paletteIndex,
    required this.accessory,
    required this.hairTint,
  });
}

/// Canonical sprite-sheet index per role — kept for parity with the original
/// single-instance game. The primary hire (ordinal = 1) of each role uses this
/// so existing saves don't suddenly change look; extras get a hashed variant.
const _canonicalPaletteIndex = <String, int>{
  'manager': 0,
  'tech-lead': 1,
  'coder': 2,
  'reviewer': 3,
  'tester': 4,
  'security': 5,
  'ui-ux-designer': 0,
  'llm-specialist': 3,
};

const _sheetCount = 6;

int _hash(String s) {
  // Stable non-negative hash. Dart's hashCode varies between runs for strings
  // starting with ASCII only in older SDKs; this simple FNV-ish loop avoids
  // the issue and gives the same result everywhere.
  var h = 2166136261;
  for (final c in s.codeUnits) {
    h = (h ^ c) * 16777619;
    h &= 0x7fffffff;
  }
  return h;
}

CharCosmetics cosmeticsFor(String instanceId, String roleType) {
  final canonical = _canonicalPaletteIndex[roleType] ?? 0;
  final isPrimary = instanceId.endsWith('#1') || !instanceId.contains('#');

  final h = _hash(instanceId);

  final paletteIndex = isPrimary
      ? canonical
      // Skew extras away from the canonical index so they read as different people.
      : (canonical + 1 + (h % (_sheetCount - 1))) % _sheetCount;

  // Primary hires stay clean; extras roll for an accessory.
  final CharAccessory accessory;
  if (isPrimary) {
    accessory = CharAccessory.none;
  } else {
    // 35% "none", otherwise spread across the rest.
    final roll = h % 100;
    if (roll < 35) {
      accessory = CharAccessory.none;
    } else {
      const pool = [
        CharAccessory.glasses,
        CharAccessory.headphones,
        CharAccessory.cap,
        CharAccessory.beanie,
        CharAccessory.headband,
        CharAccessory.earring,
      ];
      accessory = pool[(h ~/ 7) % pool.length];
    }
  }

  final HairTint hairTint;
  if (isPrimary) {
    hairTint = HairTint.none;
  } else {
    // 50% keep default hair, 50% roll a tint.
    if ((h ~/ 11) % 2 == 0) {
      hairTint = HairTint.none;
    } else {
      const pool = [
        HairTint.blond,
        HairTint.red,
        HairTint.silver,
        HairTint.pink,
        HairTint.blue,
        HairTint.green,
      ];
      hairTint = pool[(h ~/ 13) % pool.length];
    }
  }

  return CharCosmetics(
    paletteIndex: paletteIndex,
    accessory: accessory,
    hairTint: hairTint,
  );
}

/// Draws the accessory over a character at the given world position.
///
/// [headX], [headY] — top-center of the character sprite in world coords.
/// [dir] — which way the character is facing; used to mirror asymmetric
/// accessories (earring, headband knot).
void drawAccessory(
  Canvas canvas,
  CharCosmetics cosm,
  double headX,
  double headY,
  CharDirection dir,
) {
  if (cosm.accessory == CharAccessory.none) return;

  final paint = Paint()..style = PaintingStyle.fill;
  final facingBack = dir == CharDirection.up;

  switch (cosm.accessory) {
    case CharAccessory.none:
      break;

    case CharAccessory.glasses:
      if (facingBack) break; // glasses don't show from behind
      paint.color = const Color(0xFF1A1A1A);
      // Eye-level bar
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 6, 8, 1), paint);
      // Lenses
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 5, 3, 3), paint);
      canvas.drawRect(Rect.fromLTWH(headX + 1, headY + 5, 3, 3), paint);
      paint.color = const Color(0x88AEE7FF);
      canvas.drawRect(Rect.fromLTWH(headX - 3, headY + 6, 1, 1), paint);
      canvas.drawRect(Rect.fromLTWH(headX + 2, headY + 6, 1, 1), paint);
      break;

    case CharAccessory.headphones:
      paint.color = const Color(0xFF111318);
      // Band across top
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 1, 8, 1), paint);
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 2, 1, 2), paint);
      canvas.drawRect(Rect.fromLTWH(headX + 3, headY + 2, 1, 2), paint);
      // Ear cups
      paint.color = const Color(0xFF2A2F3A);
      canvas.drawRect(Rect.fromLTWH(headX - 5, headY + 3, 2, 3), paint);
      canvas.drawRect(Rect.fromLTWH(headX + 3, headY + 3, 2, 3), paint);
      paint.color = const Color(0xFF00C0D1);
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 4, 1, 1), paint);
      canvas.drawRect(Rect.fromLTWH(headX + 3, headY + 4, 1, 1), paint);
      break;

    case CharAccessory.cap:
      paint.color = const Color(0xFF2B4E8C);
      // Crown
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 1, 8, 3), paint);
      // Brim (extends forward)
      final brimX = switch (dir) {
        CharDirection.left => headX - 6,
        CharDirection.right => headX + 1,
        _ => headX - 4,
      };
      final brimW = switch (dir) {
        CharDirection.left || CharDirection.right => 5.0,
        _ => 8.0,
      };
      canvas.drawRect(Rect.fromLTWH(brimX, headY + 3, brimW, 1), paint);
      // Highlight stripe
      paint.color = const Color(0xFF4A7BC8);
      canvas.drawRect(Rect.fromLTWH(headX - 3, headY + 2, 6, 1), paint);
      break;

    case CharAccessory.beanie:
      paint.color = const Color(0xFF8E2A2A);
      // Rounded top
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 1, 8, 3), paint);
      canvas.drawRect(Rect.fromLTWH(headX - 3, headY, 6, 1), paint);
      // Knit fold
      paint.color = const Color(0xFFB03030);
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 3, 8, 1), paint);
      // Pompom
      paint.color = const Color(0xFFEADFBF);
      canvas.drawRect(Rect.fromLTWH(headX - 1, headY - 1, 2, 2), paint);
      break;

    case CharAccessory.headband:
      paint.color = const Color(0xFFEF4444);
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 3, 8, 1), paint);
      // Knot on the side (mirrors with facing)
      final knotX = dir == CharDirection.left ? headX - 5 : headX + 3;
      canvas.drawRect(Rect.fromLTWH(knotX, headY + 2, 2, 2), paint);
      paint.color = const Color(0xFFC02020);
      canvas.drawRect(Rect.fromLTWH(headX - 4, headY + 3, 8, 1)
          .deflate(0.0)
          .translate(0, 0.5), paint..color = const Color(0x44000000));
      break;

    case CharAccessory.earring:
      if (facingBack) break;
      paint.color = const Color(0xFFEAD35C);
      final earX = dir == CharDirection.left ? headX - 4 : headX + 3;
      canvas.drawRect(Rect.fromLTWH(earX, headY + 7, 1, 1), paint);
      break;
  }
}

/// Optional subtle hair tint. Drawn as a translucent rectangle over the head
/// region so it blends with whatever the underlying sheet has.
void drawHairTint(
  Canvas canvas,
  CharCosmetics cosm,
  double headX,
  double headY,
  CharDirection dir,
) {
  final color = cosm.hairTint.color;
  if (color == null) return;

  // Front / side hair silhouette is roughly rows 0-4, cols -4..+3 of the head.
  final paint = Paint()
    ..color = color.withValues(alpha: 0.45)
    ..style = PaintingStyle.fill
    ..blendMode = BlendMode.modulate;

  // When facing back (up), the whole top of the head is visible — cover more.
  final top = dir == CharDirection.up ? headY + 1 : headY + 1;
  final height = dir == CharDirection.up ? 5.0 : 4.0;
  canvas.drawRect(Rect.fromLTWH(headX - 4, top, 8, height), paint);
}
