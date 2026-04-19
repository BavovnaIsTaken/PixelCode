/// Programmatic pixel-art drawing for placed office rooms.
///
/// No sprite sheets required — each room type is drawn from colored rectangles.
/// Replace individual cases with PNG draws later without changing callers.
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';
import 'office_game_state.dart';

void drawRoom(Canvas canvas, PlacedRoom room, RoomTheme theme, int tick) {
  final x = room.col * kTileSize;
  final y = room.row * kTileSize;
  final w = room.type.widthTiles * kTileSize;
  final h = room.type.heightTiles * kTileSize;

  // Shared background fill — slightly distinct from floor to delineate the area.
  final bg = Paint()
    ..style = PaintingStyle.fill
    ..color = theme.floorDark.withValues(alpha: 0.5);
  canvas.drawRect(Rect.fromLTWH(x, y, w, h), bg);

  // Thin border
  canvas.drawRect(
    Rect.fromLTWH(x + 0.5, y + 0.5, w - 1, h - 1),
    Paint()
      ..color = theme.wallBase.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8,
  );

  switch (room.type) {
    case RoomType.workstation:
      _drawWorkstation(canvas, x, y);
    case RoomType.breakRoom:
      _drawBreakRoom(canvas, x, y);
    case RoomType.meetingRoom:
      _drawMeetingRoom(canvas, x, y);
    case RoomType.serverRoom:
      _drawServerRoom(canvas, x, y, tick);
    case RoomType.lounge:
      _drawLounge(canvas, x, y);
    case RoomType.gym:
      _drawGym(canvas, x, y);
    case RoomType.cinema:
      _drawCinema(canvas, x, y, tick);
    case RoomType.pool:
      _drawPool(canvas, x, y, tick);
    case RoomType.miniGolf:
      _drawMiniGolf(canvas, x, y);
  }
}

// ─── Workstation (2×2) ──────────────────────────────────────────────────────

void _drawWorkstation(Canvas canvas, double x, double y) {
  final p = Paint()..style = PaintingStyle.fill;
  p.color = const Color(0xFF2A3A5C).withValues(alpha: 0.35);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 2 - 2, kTileSize * 2 - 2), p);
}

// ─── Break room (2×2) ───────────────────────────────────────────────────────

void _drawBreakRoom(Canvas canvas, double x, double y) {
  final p = Paint()..style = PaintingStyle.fill;
  // Warm carpet
  p.color = const Color(0xFF5C3A1E).withValues(alpha: 0.30);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 2 - 2, kTileSize * 2 - 2), p);

  // Small couch along the bottom
  p.color = const Color(0xFF8B5E3C);
  canvas.drawRect(
      Rect.fromLTWH(x + 2, y + kTileSize + 4, kTileSize * 2 - 4, kTileSize - 7),
      p);
  p.color = const Color(0xFFB07840);
  canvas.drawRect(Rect.fromLTWH(x + 3, y + kTileSize + 5, 5, kTileSize - 9), p);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize, y + kTileSize + 5, 5, kTileSize - 9), p);

  // Mini coffee mug on top-right
  p.color = const Color(0xFFD9B48F);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize + 4, y + 5, 3, 4), p);
}

// ─── Meeting room (3×2) ─────────────────────────────────────────────────────

void _drawMeetingRoom(Canvas canvas, double x, double y) {
  final p = Paint()..style = PaintingStyle.fill;
  p.color = const Color(0xFF1A3A2A).withValues(alpha: 0.35);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 3 - 2, kTileSize * 2 - 2), p);

  // Table
  p.color = const Color(0xFF6B4F2A);
  canvas.drawRect(
      Rect.fromLTWH(x + 6, y + kTileSize - 2, kTileSize * 3 - 12, 6), p);
  p.color = const Color(0xFF8B6A3A);
  canvas.drawRect(
      Rect.fromLTWH(x + 7, y + kTileSize - 1, kTileSize * 3 - 14, 1), p);

  // Chair dots
  p.color = const Color(0xFF3A3A5C);
  for (int i = 0; i < 3; i++) {
    final cx = x + 8 + i * (kTileSize * 0.75);
    canvas.drawRect(Rect.fromLTWH(cx, y + kTileSize - 6, 4, 3), p);
    canvas.drawRect(Rect.fromLTWH(cx, y + kTileSize + 5, 4, 3), p);
  }

  // Whiteboard along the top
  p.color = const Color(0xFFE8E8E8);
  canvas.drawRect(Rect.fromLTWH(x + 4, y + 2, kTileSize * 3 - 8, 3), p);
  p.color = const Color(0xFF88BBEE).withValues(alpha: 0.7);
  canvas.drawRect(Rect.fromLTWH(x + 6, y + 3, kTileSize * 3 - 12, 1), p);
}

// ─── Server room (2×2) ──────────────────────────────────────────────────────

void _drawServerRoom(Canvas canvas, double x, double y, int tick) {
  final p = Paint()..style = PaintingStyle.fill;
  // Dark floor
  p.color = const Color(0xFF0A1020).withValues(alpha: 0.55);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 2 - 2, kTileSize * 2 - 2), p);

  // Two server racks
  for (int i = 0; i < 2; i++) {
    final rx = x + i * kTileSize + 1;
    final ry = y + 2;
    p.color = const Color(0xFF1C2230);
    canvas.drawRect(Rect.fromLTWH(rx, ry, kTileSize - 2, kTileSize * 2 - 4), p);
    p.color = const Color(0xFF2A3448);
    canvas.drawRect(Rect.fromLTWH(rx, ry, 2, kTileSize * 2 - 4), p);
    final ledOn = (tick + i) % 4 != 0;
    p.color = ledOn ? const Color(0xFF00FF88) : const Color(0xFF004422);
    for (int j = 0; j < 4; j++) {
      canvas.drawRect(Rect.fromLTWH(rx + 4, ry + 3 + j * 6, 6, 2), p);
    }
  }
}

// ─── Lounge (3×2) ───────────────────────────────────────────────────────────

void _drawLounge(Canvas canvas, double x, double y) {
  final p = Paint()..style = PaintingStyle.fill;
  p.color = const Color(0xFF2A1A5C).withValues(alpha: 0.35);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 3 - 2, kTileSize * 2 - 2), p);

  // Mini skate ramp
  p.color = const Color(0xFF3A3A5C);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize * 2, y + 4, kTileSize - 2, kTileSize * 2 - 8),
      p);
  p.color = const Color(0xFF4A4A78);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize * 2, y + kTileSize + 2, kTileSize - 2, 2), p);

  // Beanbag
  p.color = const Color(0xFF8B2222);
  canvas.drawRect(Rect.fromLTWH(x + 3, y + kTileSize + 2, 9, 9), p);

  // Neon strip
  p.color = const Color(0xFF8844FF).withValues(alpha: 0.6);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 2, kTileSize * 3 - 4, 2), p);
}

// ─── Gym (4×3) ──────────────────────────────────────────────────────────────

void _drawGym(Canvas canvas, double x, double y) {
  final p = Paint()..style = PaintingStyle.fill;
  // Rubber mat
  p.color = const Color(0xFF0A2818).withValues(alpha: 0.5);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 4 - 2, kTileSize * 3 - 2), p);

  // Treadmill (left)
  p.color = const Color(0xFF2A2A2A);
  canvas.drawRect(Rect.fromLTWH(x + 2, y + 4, kTileSize - 2, kTileSize * 3 - 8), p);
  p.color = const Color(0xFF4A4A4A);
  canvas.drawRect(
      Rect.fromLTWH(x + 2, y + 4, kTileSize - 2, 3), p); // console
  p.color = const Color(0xFF88DD44);
  canvas.drawRect(Rect.fromLTWH(x + 5, y + 5, 5, 1), p); // display

  // Weight bench (center)
  p.color = const Color(0xFF5A1A1A);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize + 4, y + kTileSize + 2, kTileSize + 4, 6), p);
  // Barbell
  p.color = const Color(0xFF888888);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize, y + kTileSize, kTileSize * 2 + 8, 2), p);
  p.color = const Color(0xFF1A1A1A);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize - 2, y + kTileSize - 2, 4, 6), p);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize * 3 + 6, y + kTileSize - 2, 4, 6), p);

  // Mirror (right)
  p.color = const Color(0xFFB8DFFF).withValues(alpha: 0.7);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize * 3 + 2, y + 4,
      kTileSize - 4, kTileSize * 2 - 2), p);
  p.color = const Color(0xFFEEEEFF).withValues(alpha: 0.4);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize * 3 + 3, y + 5, kTileSize - 6, 1), p);
}

// ─── Cinema (5×3) ───────────────────────────────────────────────────────────

void _drawCinema(Canvas canvas, double x, double y, int tick) {
  final p = Paint()..style = PaintingStyle.fill;
  // Dark room
  p.color = const Color(0xFF080810).withValues(alpha: 0.7);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 5 - 2, kTileSize * 3 - 2), p);

  // Screen (top) — flickers each tick with a different scene color
  final screenColors = [
    const Color(0xFFFFE88A),
    const Color(0xFFB0E0FF),
    const Color(0xFFFF9A8B),
    const Color(0xFF9A7BFF),
  ];
  p.color = screenColors[tick % screenColors.length].withValues(alpha: 0.9);
  canvas.drawRect(
      Rect.fromLTWH(x + 6, y + 3, kTileSize * 5 - 12, kTileSize - 4), p);
  // Frame
  p.color = const Color(0xFF2A2A2A);
  canvas.drawRect(Rect.fromLTWH(x + 4, y + 2, kTileSize * 5 - 8, 1), p);
  canvas.drawRect(Rect.fromLTWH(x + 4, y + kTileSize, kTileSize * 5 - 8, 1), p);

  // Seat rows (2 rows × 4 seats)
  p.color = const Color(0xFF2A1A5C);
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 4; c++) {
      final sx = x + 8 + c * (kTileSize * 1.1);
      final sy = y + kTileSize + 4 + r * (kTileSize * 0.75);
      canvas.drawRect(Rect.fromLTWH(sx, sy, 9, 7), p);
    }
  }
}

// ─── Pool (5×4) ─────────────────────────────────────────────────────────────

void _drawPool(Canvas canvas, double x, double y, int tick) {
  final p = Paint()..style = PaintingStyle.fill;
  // Tile surround
  p.color = const Color(0xFFD4E4F0).withValues(alpha: 0.5);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 5 - 2, kTileSize * 4 - 2), p);

  // Water
  p.color = const Color(0xFF2080C8);
  canvas.drawRect(Rect.fromLTWH(x + 6, y + 6,
      kTileSize * 5 - 12, kTileSize * 4 - 12), p);
  // Deeper center
  p.color = const Color(0xFF1060A8);
  canvas.drawRect(Rect.fromLTWH(x + 8, y + 8,
      kTileSize * 5 - 16, kTileSize * 4 - 16), p);

  // Ripples — move with tick
  p.color = const Color(0xFFA0D8F8).withValues(alpha: 0.8);
  for (int i = 0; i < 5; i++) {
    final rx = x + 10 + ((tick + i * 3) % (kTileSize * 5 - 22).toInt()).toDouble();
    final ry = y + 12 + (i * 7) % (kTileSize * 4 - 20).toInt();
    canvas.drawRect(Rect.fromLTWH(rx, ry, 3, 1), p);
  }

  // Pool ladder
  p.color = const Color(0xFFCCCCCC);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize * 4 + 3, y + 4, 2, kTileSize - 2), p);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize * 4 + 8, y + 4, 2, kTileSize - 2), p);
}

// ─── Mini-golf (5×3) ────────────────────────────────────────────────────────

void _drawMiniGolf(Canvas canvas, double x, double y) {
  final p = Paint()..style = PaintingStyle.fill;
  // Green grass
  p.color = const Color(0xFF2E7A3E);
  canvas.drawRect(
      Rect.fromLTWH(x + 1, y + 1, kTileSize * 5 - 2, kTileSize * 3 - 2), p);
  // Lighter patches
  p.color = const Color(0xFF3A8A4A);
  for (int i = 0; i < 6; i++) {
    final px = x + 4 + (i * 13) % (kTileSize * 5 - 8).toInt();
    final py = y + 4 + ((i * 7) % (kTileSize * 3 - 8).toInt()).toDouble();
    canvas.drawRect(Rect.fromLTWH(px, py, 6, 3), p);
  }

  // Path
  p.color = const Color(0xFFCAA87C);
  canvas.drawRect(
      Rect.fromLTWH(x + 4, y + kTileSize + 2, kTileSize * 5 - 8, 6), p);

  // Hole (right side)
  p.color = const Color(0xFF000000);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize * 4 + 4, y + kTileSize + 3, 4, 4), p);
  // Flag
  p.color = const Color(0xFF8B4513);
  canvas.drawRect(
      Rect.fromLTWH(x + kTileSize * 4 + 5, y + 4, 1, kTileSize), p);
  p.color = const Color(0xFFCC2222);
  canvas.drawRect(Rect.fromLTWH(x + kTileSize * 4 + 6, y + 4, 5, 4), p);

  // Ball
  p.color = const Color(0xFFF0F0F0);
  canvas.drawRect(Rect.fromLTWH(x + 8, y + kTileSize + 4, 2, 2), p);
}
