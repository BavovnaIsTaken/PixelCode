import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws an image with random pixel blocks coloured red or green
/// to simulate a digital glitch effect.
///
/// Pass [imagePixels] (from `image.toByteData(format: rawRgba)`) so that
/// glitch blocks are only applied to opaque logo pixels, not transparent
/// corners or background areas.
class PixelGlitchPainter extends CustomPainter {
  PixelGlitchPainter({
    required this.image,
    required this.seed,
    required this.pixelPercent,
    required this.displaySize,
    this.imagePixels,
  });

  final ui.Image image;
  final int seed;
  final double pixelPercent;
  final double displaySize;

  /// Raw RGBA bytes of [image] — used to skip glitch on transparent pixels.
  final ByteData? imagePixels;

  static const int _blockSize = 1;

  static const _glitchColors = [
    Color(0xFFFF2020), // red
    Color(0xFF00FF41), // green
  ];

  /// Returns true if the source image pixel at the center of block [col],[row]
  /// is sufficiently opaque to be considered a logo pixel.
  bool _isLogoPixel(int col, int row, int cols, int rows) {
    final pixels = imagePixels;
    if (pixels == null) return true;
    final srcX = ((col + 0.5) * image.width / cols).floor().clamp(0, image.width - 1);
    final srcY = ((row + 0.5) * image.height / rows).floor().clamp(0, image.height - 1);
    final byteOffset = (srcY * image.width + srcX) * 4;
    if (byteOffset + 3 >= pixels.lengthInBytes) return true;
    final alpha = pixels.getUint8(byteOffset + 3);
    return alpha > 32;
  }

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
        final shouldGlitch = rng.nextDouble() < pixelPercent;

        final dst = Rect.fromLTWH(
          col * _blockSize.toDouble(),
          row * _blockSize.toDouble(),
          _blockSize.toDouble(),
          _blockSize.toDouble(),
        );

        final src = Rect.fromLTWH(
          col * srcBlockW,
          row * srcBlockH,
          srcBlockW,
          srcBlockH,
        );

        // Always draw the source image pixel first (preserves transparency).
        canvas.drawImageRect(image, src, dst, imgPaint);

        // Only overlay the glitch colour on opaque logo pixels.
        if (shouldGlitch && _isLogoPixel(col, row, cols, rows)) {
          final color = _glitchColors[rng.nextInt(_glitchColors.length)];
          canvas.drawRect(dst, colorPaint..color = color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelGlitchPainter old) =>
      seed != old.seed ||
      pixelPercent != old.pixelPercent ||
      imagePixels != old.imagePixels;
}
