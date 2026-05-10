/// The chat "send" button — the single most-clicked element in the app.
///
/// Renders one of five hand-crafted designs selected via the cosmetic
/// catalog (see [SendButtonVariant]). Interaction states (idle / hover /
/// pressed / tapped) are tuned per-variant so each design feels physically
/// distinct — the classic button is flat and responsive, Gold Rocket is
/// weighty with a shimmer, Neon Pulse breathes, Pixel Arcade snaps into its
/// drop-shadow like a real arcade cabinet key, and Liquid Glass refracts
/// the surface beneath with an engraved pixel arrow.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/send_button_style.dart';
import '../../providers/theme_provider.dart';

const double _kButtonSize = 44;

// ─── Public widget ────────────────────────────────────────────────────────

class SendButton extends ConsumerWidget {
  const SendButton({
    super.key,
    required this.onPressed,
    this.variantOverride,
    this.size = _kButtonSize,
  });

  final VoidCallback onPressed;

  /// When set, renders this variant regardless of the equipped cosmetic
  /// (used for settings previews). When null, reads the active variant
  /// from [activeSendButtonVariantProvider].
  final SendButtonVariant? variantOverride;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SendButtonVariant variant =
        variantOverride ?? ref.watch(activeSendButtonVariantProvider);
    return _SendButtonBody(
      variant: variant,
      onPressed: onPressed,
      size: size,
      accent: context.appColors.accent,
    );
  }
}

// ─── Interaction + render core ────────────────────────────────────────────

class _SendButtonBody extends StatefulWidget {
  const _SendButtonBody({
    required this.variant,
    required this.onPressed,
    required this.size,
    required this.accent,
  });

  final SendButtonVariant variant;
  final VoidCallback onPressed;
  final double size;
  final Color accent;

  @override
  State<_SendButtonBody> createState() => _SendButtonBodyState();
}

class _SendButtonBodyState extends State<_SendButtonBody>
    with TickerProviderStateMixin {
  late final AnimationController _press;
  late final AnimationController _hover;
  late final AnimationController _idle; // loops forever — drives shimmer/pulse
  late final AnimationController _drift; // 8s loop — cloud-mass drift
  late final AnimationController _burst; // one-shot on tap

  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _hover = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    _hover.dispose();
    _idle.dispose();
    _drift.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) => _press.forward();
  void _handleTapCancel() => _press.reverse();
  void _handleTapUp(TapUpDetails _) {
    _press.reverse();
    _burst.forward(from: 0);
    HapticFeedback.selectionClick();
    widget.onPressed();
  }

  void _onHoverChanged(bool hovered) {
    if (hovered == _hovered) return;
    setState(() => _hovered = hovered);
    hovered ? _hover.forward() : _hover.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onHoverChanged(true),
      onExit: (_) => _onHoverChanged(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapCancel: _handleTapCancel,
        onTapUp: _handleTapUp,
        child: AnimatedBuilder(
          animation:
              Listenable.merge([_press, _hover, _idle, _drift, _burst]),
          builder: (context, _) {
            final press = Curves.easeOut.transform(_press.value);
            final hover = Curves.easeInOut.transform(_hover.value);
            final idle = _idle.value;
            final drift = _drift.value;
            final burst = _burst.value;

            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: switch (widget.variant) {
                SendButtonVariant.classic => _ClassicPaint(
                    press: press,
                    hover: hover,
                    burst: burst,
                    accent: widget.accent,
                    size: widget.size,
                  ),
                SendButtonVariant.neonPulse => _NeonPulsePaint(
                    press: press,
                    hover: hover,
                    idle: idle,
                    burst: burst,
                    accent: widget.accent,
                    size: widget.size,
                  ),
                SendButtonVariant.goldRocket => _GoldRocketPaint(
                    press: press,
                    hover: hover,
                    idle: idle,
                    burst: burst,
                    size: widget.size,
                  ),
                SendButtonVariant.pixelArcade => _PixelArcadePaint(
                    press: press,
                    hover: hover,
                    burst: burst,
                    accent: widget.accent,
                    size: widget.size,
                  ),
                SendButtonVariant.liquidGlass => _LiquidGlassPaint(
                    press: press,
                    hover: hover,
                    burst: burst,
                    accent: widget.accent,
                    size: widget.size,
                  ),
                SendButtonVariant.cloudDrift => _CloudDriftPaint(
                    press: press,
                    hover: hover,
                    drift: drift,
                    burst: burst,
                    size: widget.size,
                  ),
              },
            );
          },
        ),
      ),
    );
  }
}

// ─── Variant 1: Classic ───────────────────────────────────────────────────
// Flat accent square. Subtle lift on hover, crisp press-in on tap,
// short glow burst on release.

class _ClassicPaint extends StatelessWidget {
  const _ClassicPaint({
    required this.press,
    required this.hover,
    required this.burst,
    required this.accent,
    required this.size,
  });

  final double press;
  final double hover;
  final double burst;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 - press * 0.08;
    final shadowBlur = 8.0 + hover * 6.0 - press * 5.0;
    final shadowOffset = Offset(0, 2.0 + hover * 2.0 - press * 1.5);
    final glowAlpha = 0.35 + hover * 0.25 + (1.0 - burst) * burst * 0.8;

    return Transform.scale(
      scale: scale,
      child: Container(
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(
                alpha: glowAlpha.clamp(0.0, 0.95),
              ),
              blurRadius: shadowBlur.clamp(0.0, 20.0),
              offset: shadowOffset,
            ),
          ],
          // Top-edge highlight — lifts the button off the surface.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(accent, Colors.white, 0.12)!,
              accent,
              Color.lerp(accent, Colors.black, 0.10)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Center(
          child: Transform.translate(
            offset: Offset(0, press * 0.8),
            child: Icon(
              Icons.send_rounded,
              color: Colors.black.withValues(alpha: 0.82),
              size: size * 0.46,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Variant 2: Neon Pulse ────────────────────────────────────────────────
// Dark core framed by a breathing neon ring. Glow intensity pulses even
// when idle; hover accelerates the breath; tap triggers a triple-ring
// shockwave. Follows the theme accent colour.

class _NeonPulsePaint extends StatelessWidget {
  const _NeonPulsePaint({
    required this.press,
    required this.hover,
    required this.idle,
    required this.burst,
    required this.accent,
    required this.size,
  });

  final double press;
  final double hover;
  final double idle;
  final double burst;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Idle sine breathing 0..1..0
    final breath = (math.sin(idle * math.pi * 2) + 1) / 2;
    final glow = 0.35 + breath * 0.35 + hover * 0.25;
    final scale = 1.0 - press * 0.05;

    return Transform.scale(
      scale: scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Tap shockwave — three concentric rings expanding outwards.
          if (burst > 0) _BurstRings(burst: burst, color: accent, size: size),
          // Core body
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF05060A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: 0.85),
                width: 1.3,
              ),
              boxShadow: [
                // Outer bloom
                BoxShadow(
                  color: accent.withValues(alpha: glow.clamp(0.0, 0.9)),
                  blurRadius: 12 + breath * 8 + hover * 6,
                  spreadRadius: 0.5 + hover * 0.8,
                ),
                // Tight inner ring halo
                BoxShadow(
                  color: accent.withValues(alpha: 0.25 + hover * 0.2),
                  blurRadius: 2,
                  spreadRadius: -1,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Inner thin frame 2px in — gives the "double border" look.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: accent.withValues(
                            alpha: 0.25 + breath * 0.15,
                          ),
                          width: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
                // Arrow with neon bloom
                Center(
                  child: _NeonIcon(
                    icon: Icons.send_rounded,
                    color: accent,
                    size: size * 0.44,
                    glow: 0.5 + breath * 0.3 + hover * 0.2,
                  ),
                ),
                // Flash on tap
                if (burst > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: (1.0 - burst).clamp(0.0, 1.0) * 0.35,
                        duration: const Duration(milliseconds: 40),
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NeonIcon extends StatelessWidget {
  const _NeonIcon({
    required this.icon,
    required this.color,
    required this.size,
    required this.glow,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double glow;

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: size,
      color: color,
      shadows: [
        Shadow(color: color.withValues(alpha: glow), blurRadius: 8),
        Shadow(color: color.withValues(alpha: glow * 0.6), blurRadius: 16),
      ],
    );
  }
}

class _BurstRings extends StatelessWidget {
  const _BurstRings({
    required this.burst,
    required this.color,
    required this.size,
  });

  final double burst;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 2,
      height: size * 2,
      child: CustomPaint(
        painter: _BurstRingsPainter(t: burst, color: color, baseSize: size),
      ),
    );
  }
}

class _BurstRingsPainter extends CustomPainter {
  _BurstRingsPainter({
    required this.t,
    required this.color,
    required this.baseSize,
  });

  final double t;
  final Color color;
  final double baseSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Stagger: each ring starts later, but all three must finish by t=1.0
    // (the burst controller stops there). Divide by (1 - maxOffset) so the
    // last ring also completes — otherwise its alpha never reaches 0 and the
    // ring stays drawn until the next tap.
    const maxOffset = 2 * 0.18;
    const span = 1.0 - maxOffset;
    final center = size.center(Offset.zero);
    for (int i = 0; i < 3; i++) {
      final offset = i * 0.18;
      final local = ((t - offset) / span).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final alpha = (1.0 - local) * 0.6;
      final radius = baseSize / 2 + local * baseSize * 0.9;
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * (1.0 - local) + 0.4;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BurstRingsPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

// ─── Variant 3: Gold Rocket ───────────────────────────────────────────────
// Metallic gold with a diagonal shimmer that sweeps across on hover. Deep
// bevel for weight. Tap triggers a medium haptic + golden lightburst.

class _GoldRocketPaint extends StatelessWidget {
  const _GoldRocketPaint({
    required this.press,
    required this.hover,
    required this.idle,
    required this.burst,
    required this.size,
  });

  final double press;
  final double hover;
  final double idle;
  final double burst;
  final double size;

  static const _goldLight = Color(0xFFFFEF9C);
  static const _goldMid = Color(0xFFFFC24A);
  static const _goldDeep = Color(0xFF8A5A1A);
  static const _goldGlow = Color(0xFFFFD24A);

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 - press * 0.07;
    // Shimmer x-position sweeps -1..2 over 1 hover cycle.
    final shimmerX = -0.8 + hover * 2.2 + math.sin(idle * math.pi * 2) * 0.05;

    return Transform.scale(
      scale: scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (burst > 0) _BurstRings(burst: burst, color: _goldGlow, size: size),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: const [_goldLight, _goldMid, _goldDeep],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: _goldGlow.withValues(
                    alpha: 0.45 + hover * 0.25 - press * 0.2,
                  ),
                  blurRadius: 14 + hover * 6 - press * 8,
                  offset: Offset(0, 3 + hover * 2 - press * 2),
                ),
                // Inner depth
                const BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                children: [
                  // Top bevel highlight
                  Positioned(
                    left: 2,
                    right: 2,
                    top: 1.5,
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  // Bottom bevel shadow
                  Positioned(
                    left: 2,
                    right: 2,
                    bottom: 1.5,
                    child: Container(
                      height: 1,
                      color: Colors.black.withValues(alpha: 0.30),
                    ),
                  ),
                  // Shimmer sweep
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment(shimmerX.clamp(-1.2, 1.2), 0),
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: Container(
                            width: size * 0.55,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: 0.55 * hover),
                                  Colors.white.withValues(alpha: 0),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Icon
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, press * 1.0),
                      child: Icon(
                        Icons.send_rounded,
                        size: size * 0.46,
                        color: const Color(0xFF3A1F08),
                        shadows: const [
                          Shadow(
                            color: Color(0x66FFFFFF),
                            offset: Offset(0, -0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Variant 4: Pixel Arcade ──────────────────────────────────────────────
// 8-bit arcade key. A hard 4px drop shadow sits below-right; on press the
// button body snaps down into its shadow (offset collapses to zero) —
// classic retro physical-feel. All rendering is aliased (no smooth blurs).

class _PixelArcadePaint extends StatelessWidget {
  const _PixelArcadePaint({
    required this.press,
    required this.hover,
    required this.burst,
    required this.accent,
    required this.size,
  });

  final double press;
  final double hover;
  final double burst;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Shadow depth: 4px at rest, retracts to 2px on hover, collapses to 0
    // on press.
    final depth = (4.0 - hover * 1.2) * (1.0 - press);
    final bodyShift = 4.0 - depth; // how far body has moved into shadow

    final dark = Color.lerp(accent, Colors.black, 0.55)!;
    final light = Color.lerp(accent, Colors.white, 0.25)!;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Drop shadow block (hard, no blur)
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(4, 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          // Body — shifts into the shadow on press
          Positioned(
            left: bodyShift,
            top: bodyShift,
            right: 4 - bodyShift,
            bottom: 4 - bodyShift,
            child: Stack(
              children: [
                // Outer dark frame
                Container(
                  decoration: BoxDecoration(
                    color: dark,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Inner body (pixel bevel: lighter top, base middle, darker bottom)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [light, accent, dark],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // Pixel arrow
                Center(
                  child: CustomPaint(
                    size: Size.square(size * 0.66),
                    painter: _PixelArrowPainter(
                      color: Colors.black.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                // Burst flash — brief scanline sweep on tap
                if (burst > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (1.0 - burst).clamp(0.0, 1.0) * 0.5,
                        child: Align(
                          alignment: Alignment(-1.0 + burst * 2, 0),
                          child: Container(
                            width: 6,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PixelArrowPainter extends CustomPainter {
  _PixelArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Pixel grid: 7x7 cells, draw a right-pointing arrow.
    // Triangle fills the full grid width with the tip at the right edge so
    // the symbol reads as a balanced, centered play glyph rather than a
    // sliver pinned to the left.
    // 1 = filled, 0 = empty.
    const grid = <List<int>>[
      [0, 1, 0, 0, 0, 0, 0],
      [0, 1, 1, 1, 0, 0, 0],
      [0, 1, 1, 1, 1, 1, 0],
      [0, 1, 1, 1, 1, 1, 1],
      [0, 1, 1, 1, 1, 1, 0],
      [0, 1, 1, 1, 0, 0, 0],
      [0, 1, 0, 0, 0, 0, 0],
    ];
    final cell = size.width / 7;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = false;
    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        if (grid[y][x] == 1) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ─── Variant 5: Liquid Glass ──────────────────────────────────────────────
// Apple iOS 26 / macOS Tahoe design language. Translucent glass surface
// with backdrop blur, rim highlight and a subtle accent tint. The
// pixel-art arrow is engraved (deboss + emboss layers, no fill) so the
// PixelCode identity reads through as etched glass instead of a sticker.

class _LiquidGlassPaint extends StatelessWidget {
  const _LiquidGlassPaint({
    required this.press,
    required this.hover,
    required this.burst,
    required this.accent,
    required this.size,
  });

  final double press;
  final double hover;
  final double burst;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 + hover * 0.04 - press * 0.06;
    final tintAlpha = 0.08 + hover * 0.05 + press * 0.10;
    final specularAlpha = 0.30 - press * 0.18;
    final rimAlpha = 0.28 + hover * 0.04;
    final borderRadius = BorderRadius.circular(12);

    final rimColor = Color.lerp(Colors.white, accent, 0.4)!
        .withValues(alpha: rimAlpha);
    final tintColor = accent.withValues(alpha: tintAlpha);

    final shadowOffset = Offset(0, 4 - press * 3);
    final shadowBlur = 16.0 - press * 10;

    final specularBegin = Alignment(-0.3 + hover * 0.6, -1.0);

    final arrowDim = size * 0.594;

    return Transform.scale(
      scale: scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: shadowBlur,
              offset: shadowOffset,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 4,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Stack(
              children: [
                // Pixel arrow — sits underneath the glass layers so the tint
                // and specular wash over it like a refracted shape beneath
                // the surface. Wrapped in ImageFiltered so the pixel edges
                // soften, reading as a refracted shape under glass rather
                // than a crisp sticker.
                Center(
                  child: SizedBox.square(
                    dimension: arrowDim,
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: 3.6, sigmaY: 3.6),
                      child: CustomPaint(
                        size: Size.square(arrowDim),
                        painter: _PixelArrowPainter(
                          color: Color.lerp(Colors.white, accent, 0.20)!
                              .withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                  ),
                ),
                // Glass tint — rosy wash over the arrow + blurred backdrop.
                Positioned.fill(
                  child: ColoredBox(color: tintColor),
                ),
                // Specular highlight (top slab of light, slides on hover)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: specularBegin,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.35, 1.0],
                        colors: [
                          Colors.white.withValues(alpha: specularAlpha),
                          Colors.white.withValues(alpha: specularAlpha * 0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Engraved pixel arrow on the glass surface — deboss shadow
                // + emboss highlight, layered on top of the wash so the same
                // shape reads twice: once as a refracted form beneath the
                // surface, once as an etched glyph on it.
                Center(
                  child: SizedBox.square(
                    dimension: arrowDim,
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: 1.12, sigmaY: 1.12),
                      child: Stack(
                        children: [
                          Transform.translate(
                            offset: const Offset(0.5, 1.0),
                            child: CustomPaint(
                              size: Size.square(arrowDim),
                              painter: _PixelArrowPainter(
                                color: Colors.black.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          Transform.translate(
                            offset: const Offset(-0.5, -0.5),
                            child: CustomPaint(
                              size: Size.square(arrowDim),
                              painter: _PixelArrowPainter(
                                color: Color.lerp(Colors.white, accent, 0.15)!
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Inner rim border — last so it stays crisp on top of the
                // glass wash.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(color: rimColor, width: 1.0),
                    ),
                  ),
                ),
                // Tap ripple — radial expansion from center
                if (burst > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            radius: 0.5 + burst * 1.2,
                            colors: [
                              Colors.white.withValues(
                                alpha: (1.0 - burst).clamp(0.0, 1.0) * 0.35,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Variant 6: Cloud Drift ───────────────────────────────────────────────
// Four pastel cloud-masses (lavender, peach, mint, fuchsia) drift slowly
// across the glow halo around a dark core. Each blob follows its own
// incommensurate sinusoid so the pattern never resolves — masses softly
// mix at the edges via BlendMode.screen but never collapse into a single
// mid-tone. Locked palette: identity-defining like Gold Rocket and Pixel
// Arcade, does not follow the theme accent.

class _CloudDriftPaint extends StatelessWidget {
  const _CloudDriftPaint({
    required this.press,
    required this.hover,
    required this.drift,
    required this.burst,
    required this.size,
  });

  final double press;
  final double hover;
  final double drift;
  final double burst;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 - press * 0.05;

    return Transform.scale(
      scale: scale,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: size * 2,
            height: size * 2,
            child: CustomPaint(
              painter: _CloudDriftPainter(
                t: drift,
                hover: hover,
                press: press,
                burst: burst,
                buttonSize: size,
              ),
            ),
          ),
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFF05060A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.send_rounded,
                size: size * 0.44,
                color: Colors.white.withValues(alpha: 0.95),
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudDriftPainter extends CustomPainter {
  _CloudDriftPainter({
    required this.t,
    required this.hover,
    required this.press,
    required this.burst,
    required this.buttonSize,
  });

  final double t;
  final double hover;
  final double press;
  final double burst;
  final double buttonSize;

  static const _colors = <Color>[
    Color(0xFFC4ACFF),
    Color(0xFFFFBFA0),
    Color(0xFF7FDDCC),
    Color(0xFFFFAACF),
  ];

  static const _baseOffsets = <Offset>[
    Offset(-12, -10),
    Offset(13, -8),
    Offset(10, 12),
    Offset(-11, 13),
  ];

  // (freqX, freqY, phaseX, phaseY) — incommensurate frequencies so blob
  // positions never realign across the 8s cycle.
  static const _driftParams = <List<double>>[
    [1.0, 1.3, 0.0, 0.0],
    [0.7, 1.1, 1.2, 0.8],
    [1.4, 0.9, 2.5, 1.7],
    [0.9, 1.2, 3.8, 0.4],
  ];

  static const _amplitudes = <Offset>[
    Offset(8, 7),
    Offset(7, 9),
    Offset(6, 8),
    Offset(9, 6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = buttonSize / 44.0;
    final center = size.center(Offset.zero);
    const twoPi = math.pi * 2;

    final amplBoost = 1.0 + hover * 0.4;
    final burstEnvelope = burst > 0
        ? math.sin(math.min(burst, 0.3) / 0.3 * math.pi) * (1.0 - burst)
        : 0.0;

    final blobRadius = (24.0 + burstEnvelope * 12.0 - press * 4.0) * scale;
    final alphaBoost =
        (1.0 + burstEnvelope * 0.6 - press * 0.15).clamp(0.0, 1.6);

    for (int i = 0; i < 4; i++) {
      final p = _driftParams[i];
      final amp = _amplitudes[i];
      final dx = math.sin(t * twoPi * p[0] + p[2]) * amp.dx * scale * amplBoost;
      final dy = math.cos(t * twoPi * p[1] + p[3]) * amp.dy * scale * amplBoost;
      final pos = center + _baseOffsets[i] * scale + Offset(dx, dy);

      final color = _colors[i];
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          pos,
          blobRadius,
          [
            color.withValues(alpha: (0.70 * alphaBoost).clamp(0.0, 1.0)),
            color.withValues(alpha: 0.0),
          ],
          [0.0, 1.0],
        )
        ..blendMode = BlendMode.screen;
      canvas.drawCircle(pos, blobRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CloudDriftPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.hover != hover ||
      oldDelegate.press != press ||
      oldDelegate.burst != burst ||
      oldDelegate.buttonSize != buttonSize;
}
