/// A 3D coin spinning around Y using stacked layers + perspective.
///
/// The same proven technique as CSS 3D coins: one outer [Transform] with
/// `rotateY` + perspective wraps a [Stack] of thin coloured circles at
/// different Z depths.  The perspective projection creates natural volume —
/// no manual sin/cos geometry needed.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SpinningCoin extends StatefulWidget {
  /// Diameter of the coin face.
  final double size;

  /// Number of edge layers (more = thicker coin).
  final int layers;

  const SpinningCoin({super.key, this.size = 32, this.layers = 5});

  @override
  State<SpinningCoin> createState() => _SpinningCoinState();
}

class _SpinningCoinState extends State<SpinningCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final layers = widget.layers;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final angle = _ctrl.value * 2 * math.pi;
          final cosA = math.cos(angle);
          // true when the front face points toward the viewer.
          final showFront = cosA >= 0;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.004) // perspective
              ..rotateX(0.15) // ~8° tilt — breaks symmetry
              ..rotateY(angle),
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Far face ──
                  Transform(
                    transform:
                        Matrix4.translationValues(0, 0, -layers.toDouble()),
                    child: _Face(size: size, isFront: !showFront),
                  ),

                  // ── Edge layers ──
                  for (int i = layers; i >= 1; i--)
                    Transform(
                      transform: Matrix4.translationValues(0, 0, -i.toDouble()),
                      child:
                          _EdgeLayer(size: size, depth: i, total: layers),
                    ),

                  // ── Near face ──
                  _Face(size: size, isFront: showFront),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Gold constants ─────────────────────────────────────────────────────────

const _faceGold = [Color(0xFFFFE066), Color(0xFFFFD700), Color(0xFFDAA520)];
const _backGold = [Color(0xFFDAA520), Color(0xFFB8860B), Color(0xFF8B6914)];
const _rimBright = Color(0xFFB8860B);
const _rimDark = Color(0xFF6B4F0A);

// ─── Face ───────────────────────────────────────────────────────────────────

class _Face extends StatelessWidget {
  final double size;
  final bool isFront;

  const _Face({required this.size, required this.isFront});

  @override
  Widget build(BuildContext context) {
    final colors = isFront ? _faceGold : _backGold;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: isFront ? Alignment.topLeft : Alignment.topRight,
          end: isFront ? Alignment.bottomRight : Alignment.bottomLeft,
          colors: colors,
        ),
      ),
      child: Center(
        child: isFront
            ? Text(
                '₲',
                style: TextStyle(
                  color: const Color(0xFF4A3000),
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              )
            : Container(
                width: size * 0.4,
                height: size * 0.4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF4A3000).withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
              ),
      ),
    );
  }
}

// ─── Edge layer ─────────────────────────────────────────────────────────────

class _EdgeLayer extends StatelessWidget {
  final double size;
  final int depth;
  final int total;

  const _EdgeLayer({
    required this.size,
    required this.depth,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    // Slightly darker toward the middle of the edge for a rounded look.
    final t = depth / total;
    final color = Color.lerp(_rimBright, _rimDark, (t - 0.5).abs() * 2)!;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
