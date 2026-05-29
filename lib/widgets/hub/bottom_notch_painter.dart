/// Mirror of `_NotchPainter` in `hub_screen.dart` — instead of drooping from
/// the top title bar, this paints a notch *rising* from the bottom edge of
/// the window. Used by the activity-overlay peek button so it sits in
/// symmetric counterpoint to the top view-switcher notch.
library;

import 'package:flutter/material.dart';

class BottomNotchPainter extends CustomPainter {
  final Color fillColor;
  final Color strokeColor;

  /// Distance from the widget's bottom edge to the notch's *flat top* (chin).
  /// The S-bend lives between `size.height - bottomBarInset` (top of chin) and
  /// `size.height` (the bottom edge where the wing line runs).
  final double bottomBarInset;
  final double flareRadius;

  BottomNotchPainter({
    required this.fillColor,
    required this.strokeColor,
    required this.bottomBarInset,
    required this.flareRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - bottomBarInset; // top edge of the rising chin
    final bottomY = size.height; // where the outer wings live
    const wing = 10000.0;

    // Fill: rectangle below the wing line + S-bend rising chin above.
    final fillPath = Path()
      ..moveTo(-flareRadius, bottomY)
      ..lineTo(size.width + flareRadius, bottomY)
      ..lineTo(size.width + flareRadius, bottomY)
      ..cubicTo(
        size.width,
        bottomY,
        size.width,
        y,
        size.width - flareRadius,
        y,
      )
      ..lineTo(flareRadius, y)
      ..cubicTo(0, y, 0, bottomY, -flareRadius, bottomY)
      ..close();

    // Shadow: cast upward (translate y: -4) and clipped above the wing line so
    // it doesn't bleed into the window chrome below.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
      -wing,
      -wing,
      size.width + wing,
      bottomY,
    ));
    canvas.translate(0, -4);
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();

    canvas.drawPath(fillPath, Paint()..color = fillColor);

    // Single continuous outline: left wing along the bottom edge → S-bend up
    // to the chin → flat chin top → S-bend down → right wing. Tangents match
    // at every joint so there are no visible kinks.
    final outlinePath = Path()
      ..moveTo(-wing, bottomY)
      ..lineTo(-flareRadius, bottomY)
      ..cubicTo(0, bottomY, 0, y, flareRadius, y)
      ..lineTo(size.width - flareRadius, y)
      ..cubicTo(
        size.width,
        y,
        size.width,
        bottomY,
        size.width + flareRadius,
        bottomY,
      )
      ..lineTo(size.width + wing, bottomY);

    canvas.drawPath(
      outlinePath,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant BottomNotchPainter old) =>
      old.fillColor != fillColor ||
      old.strokeColor != strokeColor ||
      old.bottomBarInset != bottomBarInset ||
      old.flareRadius != flareRadius;
}
