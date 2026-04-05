/// Pixel-art sprite definitions and rendering helpers.
///
/// Characters are 8×12 grids. Each cell is a palette key:
///   '.' = transparent
///   'h' = hair, 's' = skin, 'e' = eye, 'c' = clothes, 'p' = pants, 'b' = boots
///   'm' = monitor frame, 'g' = monitor glow, 'k' = desk/keyboard
library;

import 'package:flutter/material.dart';

// ─── Character sprite frames ────────────────────────────────────────────────

/// Idle, facing down — standing pose.
const charIdle0 = [
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

/// Idle frame 2 — subtle shift.
const charIdle1 = [
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

/// Typing, seated at desk (10 rows — legs hidden behind desk).
const charType0 = [
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

/// Typing frame 2 — hands shifted.
const charType1 = [
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

/// Reading frame — looking at monitor, slight lean.
const charRead0 = [
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

/// Walking frame 0.
const charWalk0 = [
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
  '.p....p.',
  '.b....b.',
];

/// Walking frame 1.
const charWalk1 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..cccc..',
  '.cccccc.',
  '..cccc..',
  '...pp...',
  '..pp....',
  '..pp....',
  '..bb....',
];

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

/// Chair (4×4).
const chairSprite = [
  '.rr.',
  'rrrr',
  '.rr.',
  '.rr.',
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

// ─── Furniture palette ──────────────────────────────────────────────────────

const _deskWood = Color(0xFF5C4033);
const _deskEdge = Color(0xFF3E2B22);
const _monitorFrame = Color(0xFF2A2A35);
const _monitorGlow = Color(0xFF00C0D1);
const _monitorGlowDim = Color(0xFF007A84);
const _chairColor = Color(0xFF3A3A4A);

Color resolveFurniture(String key, {bool monitorActive = false}) => switch (key) {
      'd' => _deskWood,
      'k' => _deskEdge,
      'm' => _monitorFrame,
      'g' => monitorActive ? _monitorGlowDim : _monitorFrame,
      'G' => monitorActive ? _monitorGlow : _monitorFrame,
      'r' => _chairColor,
      _ => Colors.transparent,
    };

// ─── Rendering helper ───────────────────────────────────────────────────────

/// Draws a sprite onto [canvas] at the given pixel position.
/// [pixelSize] is the screen size of one virtual pixel.
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
          pixelSize + 0.5, // +0.5 to avoid sub-pixel gaps
          pixelSize + 0.5,
        ),
        paint,
      );
    }
  }
}
