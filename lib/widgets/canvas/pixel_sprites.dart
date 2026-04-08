/// Pixel-art sprite definitions and rendering helpers.
///
/// Characters are 8-wide grids. Each cell is a palette key:
///   '.' = transparent
///   'h' = hair, 's' = skin, 'f' = skin light, 'e' = eye,
///   'c' = clothes, 'p' = pants, 'b' = boots
///   'm' = monitor frame, 'g' = monitor glow, 'k' = desk/keyboard
library;

import 'package:flutter/material.dart';

import 'office_game_state.dart';

// ─── Sprite selection ───────────────────────────────────────────────────────

/// Get the correct sprite for a character's state, direction, and frame.
/// Returns (sprite, mirrored). mirrored=true → draw flipped horizontally.
(List<String>, bool) getCharacterSprite(GameCharacter ch) {
  final isLeft = ch.dir == CharDirection.left;
  final lookupDir = isLeft ? CharDirection.right : ch.dir;

  switch (ch.state) {
    case CharState.typing:
      final sprites = ch.isReading
          ? (_readSprites[lookupDir] ?? _readSprites[CharDirection.up]!)
          : (_typeSprites[lookupDir] ?? _typeSprites[CharDirection.up]!);
      return (sprites[ch.frame % sprites.length], isLeft);
    case CharState.walk:
      return (_walkSprites[lookupDir]![ch.frame % 4], isLeft);
    case CharState.idle:
      return (_walkSprites[lookupDir]![1], isLeft); // standing pose
  }
}

// ─── DOWN (front-facing) walk ───────────────────────────────────────────────

const _downWalk0 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '..pp....',
  '.p..p...',
  '.p...p..',
  '.b...b..',
];

const _downWalk1 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '...pp...',
  '..p..p..',
  '..p..p..',
  '..b..b..',
];

const _downWalk2 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '....pp..',
  '...p..p.',
  '..p...p.',
  '..b...b.',
];

// ─── DOWN type / read ───────────────────────────────────────────────────────

const _downType0 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  'cc.cc.cc',
  '..cccc..',
  '...cc...',
];

const _downType1 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '.cc..cc.',
  '..cccc..',
  '...cc...',
];

const _downRead0 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '...cc...',
];

// ─── UP (back-facing) walk ──────────────────────────────────────────────────

const _upWalk0 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..hhhh..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '..pp....',
  '.p..p...',
  '.p...p..',
  '.b...b..',
];

const _upWalk1 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..hhhh..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '...pp...',
  '..p..p..',
  '..p..p..',
  '..b..b..',
];

const _upWalk2 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..hhhh..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '....pp..',
  '...p..p.',
  '..p...p.',
  '..b...b.',
];

// ─── UP type / read ─────────────────────────────────────────────────────────

const _upType0 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..hhhh..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  'cc.cc.cc',
  '..cccc..',
  '...cc...',
];

const _upType1 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..hhhh..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '.cc..cc.',
  '..cccc..',
  '...cc...',
];

const _upRead0 = [
  '...hh...',
  '..hhhh..',
  '..hhhh..',
  '..hhhh..',
  '...hh...',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '...cc...',
];

// ─── RIGHT (side-facing) walk ───────────────────────────────────────────────

const _rightWalk0 = [
  '..hh....',
  '..hhhh..',
  '..shh...',
  '..seh...',
  '...ss...',
  '..cccc..',
  '..ccccc.',
  '..cccc..',
  '..pp....',
  '.p..p...',
  '.p...p..',
  '.b...b..',
];

const _rightWalk1 = [
  '..hh....',
  '..hhhh..',
  '..shh...',
  '..seh...',
  '...ss...',
  '..cccc..',
  '..ccccc.',
  '..cccc..',
  '...pp...',
  '..p..p..',
  '..p..p..',
  '..b..b..',
];

const _rightWalk2 = [
  '..hh....',
  '..hhhh..',
  '..shh...',
  '..seh...',
  '...ss...',
  '..cccc..',
  '..ccccc.',
  '..cccc..',
  '....pp..',
  '...p..p.',
  '..p...p.',
  '..b...b.',
];

// ─── Sprite lookup maps ─────────────────────────────────────────────────────

const _walkSprites = <CharDirection, List<List<String>>>{
  CharDirection.down: [_downWalk0, _downWalk1, _downWalk2, _downWalk1],
  CharDirection.up: [_upWalk0, _upWalk1, _upWalk2, _upWalk1],
  CharDirection.right: [_rightWalk0, _rightWalk1, _rightWalk2, _rightWalk1],
  // left = mirror of right at render time
};

const _typeSprites = <CharDirection, List<List<String>>>{
  CharDirection.down: [_downType0, _downType1],
  CharDirection.up: [_upType0, _upType1],
};

const _readSprites = <CharDirection, List<List<String>>>{
  CharDirection.down: [_downRead0],
  CharDirection.up: [_upRead0],
};

// ─── Desk & monitor sprites ────────────────────────────────────────────────

/// Desk top-down (12×6).
const deskSprite = [
  'kkkkkkkkkkkk',
  'kdddddddddk',
  'kdddddddddk',
  'kdddddddddk',
  'kdddddddddk',
  'kkkkkkkkkkkk',
];

/// Monitor on desk (8×6).
const monitorOff = [
  '..mmmm..',
  '.mmmmmm.',
  '.m....m.',
  '.m....m.',
  '.mmmmmm.',
  '...mm...',
];

const monitorOn0 = [
  '..mmmm..',
  '.mmmmmm.',
  '.mgGGgm.',
  '.mGggGm.',
  '.mmmmmm.',
  '...mm...',
];

const monitorOn1 = [
  '..mmmm..',
  '.mmmmmm.',
  '.mGggGm.',
  '.mgGGgm.',
  '.mmmmmm.',
  '...mm...',
];

// ─── Agent color palettes ───────────────────────────────────────────────────

class AgentPalette {
  final Color hair;
  final Color skin;
  final Color skinLight;
  final Color eye;
  final Color clothes;
  final Color pants;
  final Color boots;

  const AgentPalette({
    required this.hair,
    required this.skin,
    required this.skinLight,
    required this.eye,
    required this.clothes,
    required this.pants,
    required this.boots,
  });

  Color resolve(String key) => switch (key) {
        'h' => hair,
        's' => skin,
        'f' => skinLight,
        'e' => eye,
        'c' => clothes,
        'p' => pants,
        'b' => boots,
        _ => Colors.transparent,
      };
}

const agentPalettes = <String, AgentPalette>{
  'tech-lead': AgentPalette(
    hair: Color(0xFF1A1A2E),
    skin: Color(0xFFE8B89D),
    skinLight: Color(0xFFF5CDB8),
    eye: Color(0xFF00C0D1),
    clothes: Color(0xFF00949F),
    pants: Color(0xFF2C3E50),
    boots: Color(0xFF1A1A1A),
  ),
  'manager': AgentPalette(
    hair: Color(0xFF8B4513),
    skin: Color(0xFFD4A574),
    skinLight: Color(0xFFE8C49A),
    eye: Color(0xFFF59E0B),
    clothes: Color(0xFFD97706),
    pants: Color(0xFF44403C),
    boots: Color(0xFF292524),
  ),
  'coder': AgentPalette(
    hair: Color(0xFF2D1B69),
    skin: Color(0xFFC68642),
    skinLight: Color(0xFFD4956B),
    eye: Color(0xFF10B981),
    clothes: Color(0xFF059669),
    pants: Color(0xFF1E293B),
    boots: Color(0xFF0F172A),
  ),
  'reviewer': AgentPalette(
    hair: Color(0xFF4A1A6B),
    skin: Color(0xFFE8B89D),
    skinLight: Color(0xFFF5CDB8),
    eye: Color(0xFF8B5CF6),
    clothes: Color(0xFF7C3AED),
    pants: Color(0xFF334155),
    boots: Color(0xFF1E293B),
  ),
  'tester': AgentPalette(
    hair: Color(0xFFB91C1C),
    skin: Color(0xFFFDBCB4),
    skinLight: Color(0xFFFFD5CC),
    eye: Color(0xFFEC4899),
    clothes: Color(0xFFDB2777),
    pants: Color(0xFF374151),
    boots: Color(0xFF1F2937),
  ),
  'security': AgentPalette(
    hair: Color(0xFF1F2937),
    skin: Color(0xFF8D5524),
    skinLight: Color(0xFFA0714B),
    eye: Color(0xFFEF4444),
    clothes: Color(0xFFDC2626),
    pants: Color(0xFF27272A),
    boots: Color(0xFF18181B),
  ),
  'ui-ux-designer': AgentPalette(
    hair: Color(0xFFFF6B9D),
    skin: Color(0xFFF3D2C1),
    skinLight: Color(0xFFFBE8DC),
    eye: Color(0xFF3B82F6),
    clothes: Color(0xFF2563EB),
    pants: Color(0xFF3F3F46),
    boots: Color(0xFF27272A),
  ),
};

/// Agent accent colors for UI elements.
Color agentAccentColor(String id) => switch (id) {
      'tech-lead' => const Color(0xFF00C0D1),
      'manager' => const Color(0xFFF59E0B),
      'coder' => const Color(0xFF10B981),
      'reviewer' => const Color(0xFF8B5CF6),
      'tester' => const Color(0xFFEC4899),
      'security' => const Color(0xFFEF4444),
      'ui-ux-designer' => const Color(0xFF3B82F6),
      _ => const Color(0xFF6B7280),
    };

// ─── Furniture palette ──────────────────────────────────────────────────────

const _deskWood = Color(0xFF5C4033);
const _deskEdge = Color(0xFF3E2B22);
const _monitorFrame = Color(0xFF2A2A35);
const _monitorGlow = Color(0xFF00C0D1);
const _monitorGlowDim = Color(0xFF007A84);

Color resolveFurniture(String key, {bool monitorActive = false}) =>
    switch (key) {
      'd' => _deskWood,
      'k' => _deskEdge,
      'm' => _monitorFrame,
      'g' => monitorActive ? _monitorGlowDim : _monitorFrame,
      'G' => monitorActive ? _monitorGlow : _monitorFrame,
      _ => Colors.transparent,
    };

// ─── Rendering helpers ──────────────────────────────────────────────────────

/// Draws a sprite at the given pixel position.
void drawSprite(
  Canvas canvas,
  List<String> sprite,
  double x,
  double y,
  double pixelSize,
  Color Function(String key) colorResolver,
) {
  final paint = Paint()..style = PaintingStyle.fill;

  for (int row = 0; row < sprite.length; row++) {
    final line = sprite[row];
    for (int col = 0; col < line.length; col++) {
      final ch = line[col];
      if (ch == '.') continue;
      paint.color = colorResolver(ch);
      if (paint.color == Colors.transparent) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          x + col * pixelSize,
          y + row * pixelSize,
          pixelSize + 0.5,
          pixelSize + 0.5,
        ),
        paint,
      );
    }
  }
}

/// Draws a sprite mirrored horizontally (for LEFT direction).
void drawSpriteMirrored(
  Canvas canvas,
  List<String> sprite,
  double x,
  double y,
  double pixelSize,
  Color Function(String key) colorResolver,
) {
  final paint = Paint()..style = PaintingStyle.fill;

  for (int row = 0; row < sprite.length; row++) {
    final line = sprite[row];
    final width = line.length;
    for (int col = 0; col < width; col++) {
      final ch = line[col];
      if (ch == '.') continue;
      paint.color = colorResolver(ch);
      if (paint.color == Colors.transparent) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          x + (width - 1 - col) * pixelSize,
          y + row * pixelSize,
          pixelSize + 0.5,
          pixelSize + 0.5,
        ),
        paint,
      );
    }
  }
}
