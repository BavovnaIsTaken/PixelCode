import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders a logo image with authentic-looking digital glitch artifacts.
///
/// Three types of distortion are applied via seeded randomness:
///   • SHIFT  — a horizontal scanline band is displaced left/right
///   • COLOR  — a scanline band is overlaid with a glitch colour (opaque pixels only)
///   • CHROMA — a scanline band gets R/B channel separation
///
/// When [pixelPercent] > 0.12 a full-image chromatic aberration pass is added.
///
/// Pass [imagePixels] (from `image.toByteData(format: rawRgba)`) so that
/// colour overlays skip transparent corners of the logo.
class PixelGlitchPainter extends CustomPainter {
  PixelGlitchPainter({
    required this.image,
    required this.seed,
    required this.pixelPercent,
    required this.displaySize,
    this.imagePixels,
    this.bandHeightMax = 3,
    this.shiftStrength = 0.5,
    this.chromaStrength = 0.5,
  });

  final ui.Image image;
  final int seed;
  final double pixelPercent;
  final double displaySize;

  /// Raw RGBA bytes of [image] — used to skip glitch on transparent pixels.
  final ByteData? imagePixels;

  /// Max height of each scanline band in display pixels (1–8).
  final int bandHeightMax;

  /// Horizontal shift amount (0.0–1.0). 1.0 = ±50% of display width.
  final double shiftStrength;

  /// Chromatic aberration strength (0.0 = off, 1.0 = max).
  final double chromaStrength;

  // Glitch colours for the COLOR band type.
  static const _glitchColors = [
    Color(0xFFFF2020), // red
    Color(0xFF00FF41), // green
  ];

  // ColorFilter matrices that isolate a single channel.
  static const _rChannelFilter = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 1, 0,
  ]);
  static const _bChannelFilter = ColorFilter.matrix(<double>[
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  // ── helpers ─────────────────────────────────────────────────────────────

  /// Maps a display-space x coordinate to the matching source image x.
  double _srcX(double dstX) => dstX * image.width / displaySize;

  /// Maps a display-space y coordinate to the matching source image y.
  double _srcY(double dstY) => dstY * image.height / displaySize;

  /// True if the source pixel at display position ([dx], [dy]) is opaque enough
  /// to be considered part of the logo (alpha > 32).
  bool _isOpaque(double dx, double dy) {
    final pixels = imagePixels;
    if (pixels == null) return true;
    final sx = _srcX(dx).floor().clamp(0, image.width - 1);
    final sy = _srcY(dy).floor().clamp(0, image.height - 1);
    final offset = (sy * image.width + sx) * 4;
    if (offset + 3 >= pixels.lengthInBytes) return true;
    return pixels.getUint8(offset + 3) > 32;
  }

  // ── paint ───────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final s = displaySize;

    canvas.clipRect(Rect.fromLTWH(0, 0, s, s));

    // ── Phase 1: base image ──────────────────────────────────────────────
    final basePaint = Paint()..filterQuality = FilterQuality.none;
    final fullSrc = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final fullDst = Rect.fromLTWH(0, 0, s, s);
    canvas.drawImageRect(image, fullSrc, fullDst, basePaint);

    // ── Phase 2: scanline bands ──────────────────────────────────────────
    // Number of bands scales with pixelPercent so a low intensity value
    // produces only 1–2 subtle bands while a high value gives 4–5.
    final bandCount = 1 + (pixelPercent * 20).round().clamp(1, 4);

    for (int i = 0; i < bandCount; i++) {
      final bandY = rng.nextDouble() * s;
      // Band height: 1–bandHeightMax display pixels.
      final maxH = bandHeightMax.clamp(1, 8);
      final bandH = (1 + rng.nextInt(maxH)).toDouble();
      final bandType = rng.nextDouble();

      if (bandType < 0.55) {
        // ── SHIFT: displace this band horizontally ───────────────────────
        final maxShift = s * 0.5 * shiftStrength;
        final dx = (rng.nextDouble() - 0.5) * 2 * maxShift;

        // Source slice for the band (no horizontal offset in source).
        final srcSlice = Rect.fromLTWH(
          0,
          _srcY(bandY),
          image.width.toDouble(),
          (_srcY(bandY + bandH) - _srcY(bandY)).clamp(1, image.height.toDouble()),
        );
        // Destination band, shifted.
        final dstBand = Rect.fromLTWH(dx, bandY, s, bandH);

        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, bandY, s, bandH));
        canvas.drawImageRect(image, srcSlice, dstBand, basePaint);
        canvas.restore();
      } else if (bandType < 0.85) {
        // ── COLOR: solid glitch colour over opaque pixels in band ────────
        final color = _glitchColors[rng.nextInt(_glitchColors.length)];
        final colorPaint = Paint()..color = color;
        for (double py = bandY; py < bandY + bandH && py < s; py++) {
          for (double px = 0; px < s; px++) {
            if (_isOpaque(px, py)) {
              canvas.drawRect(Rect.fromLTWH(px, py, 1, 1), colorPaint);
            }
          }
        }
      } else if (chromaStrength > 0) {
        // ── CHROMA: R/B channel separation on this band ─────────────────
        final chromaShift = 1.0 + chromaStrength * 3.0; // 1–4 px
        final chromaOpacity = 0.5 + chromaStrength * 0.4; // 0.5–0.9
        final srcSlice = Rect.fromLTWH(
          0,
          _srcY(bandY),
          image.width.toDouble(),
          (_srcY(bandY + bandH) - _srcY(bandY)).clamp(1, image.height.toDouble()),
        );
        final dstBand = Rect.fromLTWH(0, bandY, s, bandH);

        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, bandY, s, bandH));

        final rPaint = Paint()
          ..filterQuality = FilterQuality.none
          ..colorFilter = _rChannelFilter
          ..color = Color.fromRGBO(255, 255, 255, chromaOpacity);
        canvas.drawImageRect(image, srcSlice, dstBand.translate(chromaShift, 0), rPaint);

        final bPaint = Paint()
          ..filterQuality = FilterQuality.none
          ..colorFilter = _bChannelFilter
          ..color = Color.fromRGBO(255, 255, 255, chromaOpacity);
        canvas.drawImageRect(image, srcSlice, dstBand.translate(-chromaShift, 0), bPaint);

        canvas.restore();
      }
    }

    // ── Phase 3: full-image chromatic aberration ─────────────────────────
    if (chromaStrength > 0 && pixelPercent > 0.12) {
      final chromaShift = chromaStrength * 1.5; // 0–1.5 px
      final chromaOpacity = chromaStrength * 0.30; // 0–0.30

      final rPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = _rChannelFilter
        ..color = Color.fromRGBO(255, 255, 255, chromaOpacity);
      canvas.drawImageRect(image, fullSrc, fullDst.translate(chromaShift, 0), rPaint);

      final bPaint = Paint()
        ..filterQuality = FilterQuality.none
        ..colorFilter = _bChannelFilter
        ..color = Color.fromRGBO(255, 255, 255, chromaOpacity);
      canvas.drawImageRect(image, fullSrc, fullDst.translate(-chromaShift, 0), bPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PixelGlitchPainter old) =>
      seed != old.seed ||
      pixelPercent != old.pixelPercent ||
      imagePixels != old.imagePixels ||
      bandHeightMax != old.bandHeightMax ||
      shiftStrength != old.shiftStrength ||
      chromaStrength != old.chromaStrength;
}
