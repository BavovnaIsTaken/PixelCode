library;

import 'package:flutter/material.dart';

/// Pixel-art loader: 3 chunky square dots, one bright at a time, cycling
/// left->right->left. Mirrors the in-game "thinking bubble" animation.
class PixelLoader extends StatefulWidget {
  const PixelLoader({
    super.key,
    this.size = 20,
    this.brightColor = const Color(0xFF00C0D1),
    this.dimColor = const Color(0xFF007A84),
  });

  final double size;
  final Color brightColor;
  final Color dimColor;

  @override
  State<PixelLoader> createState() => _PixelLoaderState();
}

class _PixelLoaderState extends State<PixelLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // 4 frames at ~3Hz cycle (ping-pong over 3 dots: 0,1,2,1).
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final phase = (_c.value * 4).floor() % 4;
          // Ping-pong: 0,1,2,1
          final active = phase == 3 ? 1 : phase;
          return CustomPaint(
            painter: _PixelLoaderPainter(
              active: active,
              bright: widget.brightColor,
              dim: widget.dimColor,
            ),
            size: Size.square(widget.size),
          );
        },
      ),
    );
  }
}

class _PixelLoaderPainter extends CustomPainter {
  _PixelLoaderPainter({
    required this.active,
    required this.bright,
    required this.dim,
  });

  final int active;
  final Color bright;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    // Virtual grid: 3 dots, each 2x2 virtual px, 1px gaps => 8 virtual px wide.
    const virtualW = 8.0;
    const virtualH = 2.0;
    final scale =
        (size.width / virtualW).floorToDouble().clamp(1.0, double.infinity);
    final drawW = virtualW * scale;
    final drawH = virtualH * scale;
    final offX = ((size.width - drawW) / 2).floorToDouble();
    final offY = ((size.height - drawH) / 2).floorToDouble();

    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      paint.color = i == active ? bright : dim;
      final x = offX + (i * 3) * scale;
      final y = offY;
      canvas.drawRect(Rect.fromLTWH(x, y, 2 * scale, 2 * scale), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PixelLoaderPainter old) =>
      old.active != active || old.bright != bright || old.dim != dim;
}
