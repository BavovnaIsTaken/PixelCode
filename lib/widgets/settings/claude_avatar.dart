/// Pixel-art Claude avatar with glitch animation.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class ClaudeAvatar extends StatefulWidget {
  final bool isActive;
  final double size;

  const ClaudeAvatar({super.key, this.isActive = false, this.size = 48});

  @override
  State<ClaudeAvatar> createState() => _ClaudeAvatarState();
}

class _ClaudeAvatarState extends State<ClaudeAvatar> {
  Timer? _glitchTimer;
  double _glitchOffsetX = 0;
  double _glitchOffsetY = 0;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _startGlitchLoop();
  }

  @override
  void didUpdateWidget(ClaudeAvatar old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      _glitchTimer?.cancel();
      _startGlitchLoop();
    }
  }

  void _startGlitchLoop() {
    if (!widget.isActive) {
      _glitchTimer?.cancel();
      _glitchOffsetX = 0;
      _glitchOffsetY = 0;
      return;
    }
    _glitchTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      setState(() {
        _glitchOffsetX = (_rng.nextDouble() - 0.5) * 3;
        _glitchOffsetY = (_rng.nextDouble() - 0.5) * 2;
      });
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) {
          setState(() {
            _glitchOffsetX = 0;
            _glitchOffsetY = 0;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _glitchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.translate(
        offset: Offset(_glitchOffsetX, _glitchOffsetY),
        child: CustomPaint(
          painter: _ClaudePixelPainter(isActive: widget.isActive),
        ),
      ),
    );
  }
}

class _ClaudePixelPainter extends CustomPainter {
  final bool isActive;

  _ClaudePixelPainter({required this.isActive});

  // 8x8 pixel grid representing a sparkle/diamond (Claude's ✦)
  static const _grid = [
    [0, 0, 0, 1, 1, 0, 0, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 1, 1, 1, 1, 1, 1, 0],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [0, 1, 1, 1, 1, 1, 1, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 1, 1, 0, 0, 0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 8;
    final cellH = size.height / 8;

    // Background rounded rect
    final bgPaint = Paint()
      ..color = isActive
          ? const Color(0xFF00C0D1).withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.05);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.15),
      ),
      bgPaint,
    );

    // Pixel cells
    final fillPaint = Paint();
    final glowColor = isActive
        ? const Color(0xFF00C0D1)
        : Colors.white.withValues(alpha: 0.25);

    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        if (_grid[row][col] == 1) {
          final dx = (col - 3.5).abs() / 3.5;
          final dy = (row - 3.5).abs() / 3.5;
          final dist = (dx + dy) / 2;
          final alpha = isActive ? (1.0 - dist * 0.5) : (0.3 - dist * 0.1);

          fillPaint.color = glowColor.withValues(alpha: alpha.clamp(0.1, 1.0));
          canvas.drawRect(
            Rect.fromLTWH(
              col * cellW + 0.5,
              row * cellH + 0.5,
              cellW - 1,
              cellH - 1,
            ),
            fillPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ClaudePixelPainter old) => old.isActive != isActive;
}
