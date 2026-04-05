/// CustomPainter that renders the pixel-art office scene.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';
import 'pixel_sprites.dart';

// ─── Office layout ──────────────────────────────────────────────────────────

/// Virtual canvas size in "pixels" (scaled to fit the widget).
const kVirtualWidth = 224.0;
const kVirtualHeight = 160.0;

/// Tile size in virtual pixels.
const kTile = 16.0;

/// Desk station: defines where each agent sits.
class DeskStation {
  final String agentId;
  final double deskX; // desk top-left in virtual px
  final double deskY;
  final double charX; // character position (bottom-center anchor)
  final double charY;
  final double monitorX;
  final double monitorY;

  const DeskStation({
    required this.agentId,
    required this.deskX,
    required this.deskY,
    required this.charX,
    required this.charY,
    required this.monitorX,
    required this.monitorY,
  });
}

/// 7 desks arranged in a neat office layout.
/// Row 0: Tech Lead centered.
/// Row 1: Manager, Coder, Reviewer.
/// Row 2: Tester, Security, UI/UX Designer.
const _stations = <DeskStation>[
  // Tech Lead — centered, front row
  DeskStation(
    agentId: 'tech-lead',
    deskX: 96, deskY: 18,
    charX: 102, charY: 42,
    monitorX: 98, monitorY: 12,
  ),
  // Row 1
  DeskStation(
    agentId: 'manager',
    deskX: 24, deskY: 62,
    charX: 30, charY: 86,
    monitorX: 26, monitorY: 56,
  ),
  DeskStation(
    agentId: 'coder',
    deskX: 96, deskY: 62,
    charX: 102, charY: 86,
    monitorX: 98, monitorY: 56,
  ),
  DeskStation(
    agentId: 'reviewer',
    deskX: 168, deskY: 62,
    charX: 174, charY: 86,
    monitorX: 170, monitorY: 56,
  ),
  // Row 2
  DeskStation(
    agentId: 'tester',
    deskX: 24, deskY: 106,
    charX: 30, charY: 130,
    monitorX: 26, monitorY: 100,
  ),
  DeskStation(
    agentId: 'security',
    deskX: 96, deskY: 106,
    charX: 102, charY: 130,
    monitorX: 98, monitorY: 100,
  ),
  DeskStation(
    agentId: 'ui-ux-designer',
    deskX: 168, deskY: 106,
    charX: 174, charY: 130,
    monitorX: 170, monitorY: 100,
  ),
];

// ─── Painter ────────────────────────────────────────────────────────────────

class PixelOfficePainter extends CustomPainter {
  final Map<String, AgentState> agents;
  final int tick; // animation tick (increments every ~200ms)

  PixelOfficePainter({required this.agents, required this.tick});

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale to fit virtual canvas into the widget.
    final scale = math.min(
      size.width / kVirtualWidth,
      size.height / kVirtualHeight,
    );

    // Center the office in the widget.
    final offsetX = (size.width - kVirtualWidth * scale) / 2;
    final offsetY = (size.height - kVirtualHeight * scale) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    final px = 1.0; // one virtual pixel

    _drawFloor(canvas, px);
    _drawStations(canvas, px);
    _drawVignette(canvas, size, scale, offsetX, offsetY);

    canvas.restore();
  }

  void _drawFloor(Canvas canvas, double px) {
    final paint = Paint()..style = PaintingStyle.fill;
    final tilesX = (kVirtualWidth / kTile).ceil();
    final tilesY = (kVirtualHeight / kTile).ceil();

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final isDark = (tx + ty) % 2 == 0;
        paint.color = isDark
            ? const Color(0xFF121218)
            : const Color(0xFF15151D);
        canvas.drawRect(
          Rect.fromLTWH(tx * kTile, ty * kTile, kTile + 0.5, kTile + 0.5),
          paint,
        );
      }
    }

    // Subtle grid lines
    paint.color = const Color(0xFF1E1E28);
    paint.strokeWidth = 0.5;
    paint.style = PaintingStyle.stroke;
    for (int tx = 0; tx <= tilesX; tx++) {
      canvas.drawLine(
        Offset(tx * kTile, 0),
        Offset(tx * kTile, kVirtualHeight),
        paint,
      );
    }
    for (int ty = 0; ty <= tilesY; ty++) {
      canvas.drawLine(
        Offset(0, ty * kTile),
        Offset(kVirtualWidth, ty * kTile),
        paint,
      );
    }
  }

  void _drawStations(Canvas canvas, double px) {
    for (final station in _stations) {
      final agentState = agents[station.agentId];
      final isActive = agentState != null &&
          agentState.status != AgentStatus.idle;

      // Draw desk
      drawSprite(canvas, deskSprite, station.deskX, station.deskY, px,
          (k) => resolveFurniture(k));

      // Draw monitor (animated if agent is active)
      final monitorFrame = isActive
          ? (tick % 2 == 0 ? monitorOn0 : monitorOn1)
          : monitorOff;
      drawSprite(canvas, monitorFrame, station.monitorX, station.monitorY, px,
          (k) => resolveFurniture(k, monitorActive: isActive));

      // Draw monitor glow on desk surface when active
      if (isActive) {
        final glowPaint = Paint()
          ..color = const Color(0xFF00C0D1).withValues(alpha: 0.08)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(station.deskX, station.deskY, 12 * px, 6 * px),
          glowPaint,
        );
      }

      // Draw character
      _drawCharacter(canvas, station, agentState, px);

      // Draw status label above character
      if (agentState != null && isActive) {
        _drawStatusBubble(canvas, station, agentState, px);
      }

      // Draw name tag
      _drawNameTag(canvas, station, agentState, px);
    }
  }

  void _drawCharacter(
    Canvas canvas,
    DeskStation station,
    AgentState? agentState,
    double px,
  ) {
    final palette = agentPalettes[station.agentId] ??
        agentPalettes['tech-lead']!;

    final status = agentState?.status ?? AgentStatus.idle;

    // Select sprite frame based on status and tick
    final List<String> frame;
    switch (status) {
      case AgentStatus.typing:
        frame = tick % 2 == 0 ? charType0 : charType1;
      case AgentStatus.reading:
        frame = charRead0;
      case AgentStatus.thinking:
        frame = tick % 2 == 0 ? charType0 : charType1;
      case AgentStatus.running:
        frame = tick % 2 == 0 ? charType0 : charType1;
      case AgentStatus.waiting:
        frame = charIdle0;
      case AgentStatus.idle:
        frame = charIdle0;
    }

    // Character position — centered horizontally on charX
    final spriteWidth = frame[0].length;
    final drawX = station.charX - (spriteWidth * px) / 2;
    final drawY = station.charY - frame.length * px;

    drawSprite(canvas, frame, drawX, drawY, px, (k) => palette.resolve(k));

    // Active glow under character
    if (status != AgentStatus.idle) {
      final agentColor = _agentGlowColor(station.agentId);
      final glowPaint = Paint()
        ..color = agentColor.withValues(alpha: 0.12 + 0.04 * (tick % 3))
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(station.charX, station.charY + 1),
          width: 12 * px,
          height: 4 * px,
        ),
        glowPaint,
      );
    }
  }

  void _drawStatusBubble(
    Canvas canvas,
    DeskStation station,
    AgentState agentState,
    double px,
  ) {
    final status = agentState.status;
    final color = _agentGlowColor(station.agentId);

    // Bubble position above the character's head
    final bubbleX = station.charX;
    final bubbleY = station.charY - 18 * px;

    // Draw small colored dot indicator
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.6 + 0.3 * ((tick % 3) / 2))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(bubbleX, bubbleY), 2 * px, dotPaint);

    // Glow around the dot
    dotPaint.color = color.withValues(alpha: 0.15);
    dotPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(bubbleX, bubbleY), 3 * px, dotPaint);

    // Draw tiny pixel activity indicator
    if (status == AgentStatus.thinking) {
      // Three animated dots
      for (int i = 0; i < 3; i++) {
        final dotAlpha = ((tick + i) % 3 == 0) ? 0.8 : 0.2;
        final dp = Paint()
          ..color = color.withValues(alpha: dotAlpha)
          ..style = PaintingStyle.fill;
        canvas.drawRect(
          Rect.fromLTWH(bubbleX - 3 * px + i * 3 * px, bubbleY - 4 * px, px, px),
          dp,
        );
      }
    }
  }

  void _drawNameTag(
    Canvas canvas,
    DeskStation station,
    AgentState? agentState,
    double px,
  ) {
    final isActive = agentState != null &&
        agentState.status != AgentStatus.idle;

    final color = _agentGlowColor(station.agentId);

    // Small colored line under the desk to identify the agent
    final tagPaint = Paint()
      ..color = isActive ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(station.deskX + 2, station.deskY + 7 * px, 8 * px, px),
      tagPaint,
    );
  }

  void _drawVignette(
    Canvas canvas,
    Size widgetSize,
    double scale,
    double offsetX,
    double offsetY,
  ) {
    // Draw vignette in virtual coordinates
    final center = Offset(kVirtualWidth / 2, kVirtualHeight / 2);
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: 0.5),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(
        Rect.fromCenter(
          center: center,
          width: kVirtualWidth,
          height: kVirtualHeight,
        ),
      );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, kVirtualWidth, kVirtualHeight),
      paint,
    );
  }

  Color _agentGlowColor(String id) => switch (id) {
        'tech-lead' => const Color(0xFF00C0D1),
        'manager' => const Color(0xFFF59E0B),
        'coder' => const Color(0xFF10B981),
        'reviewer' => const Color(0xFF8B5CF6),
        'tester' => const Color(0xFFEC4899),
        'security' => const Color(0xFFEF4444),
        'ui-ux-designer' => const Color(0xFF3B82F6),
        _ => const Color(0xFF6B7280),
      };

  @override
  bool shouldRepaint(PixelOfficePainter oldDelegate) =>
      tick != oldDelegate.tick || agents != oldDelegate.agents;
}
