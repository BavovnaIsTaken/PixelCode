import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws an image with random pixel blocks coloured red or green
/// to simulate a digital glitch effect.
class PixelGlitchPainter extends CustomPainter {
  PixelGlitchPainter({
    required this.image,
    required this.seed,
    required this.pixelPercent,
    required this.displaySize,
  });

  final ui.Image image;
  final int seed;
  final double pixelPercent;
  final double displaySize;

  static const int _blockSize = 1;

  static const _glitchColors = [
    Color(0xFFFF2020), // red
    Color(0xFF00FF41), // green
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final imgPaint = Paint()..filterQuality = FilterQuality.none;
    final colorPaint = Paint();
    final rng = Random(seed);

    final cols = (displaySize / _blockSize).ceil();
    final rows = (displaySize / _blockSize).ceil();
    final srcBlockW = image.width / cols;
    final srcBlockH = image.height / rows;

    canvas.clipRect(Rect.fromLTWH(0, 0, displaySize, displaySize));

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final glitched = rng.nextDouble() < pixelPercent;

        final dst = Rect.fromLTWH(
          col * _blockSize.toDouble(),
          row * _blockSize.toDouble(),
          _blockSize.toDouble(),
          _blockSize.toDouble(),
        );

        if (glitched) {
          final color = _glitchColors[rng.nextInt(_glitchColors.length)];
          canvas.drawRect(dst, colorPaint..color = color);
        } else {
          final src = Rect.fromLTWH(
            col * srcBlockW,
            row * srcBlockH,
            srcBlockW,
            srcBlockH,
          );
          canvas.drawImageRect(image, src, dst, imgPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGlitchPainter old) =>
      seed != old.seed || pixelPercent != old.pixelPercent;
}
