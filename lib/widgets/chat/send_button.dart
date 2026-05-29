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
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../models/send_button_style.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/theme_provider.dart';

const double _kButtonSize = 44;

// ─── Public widget ────────────────────────────────────────────────────────

class SendButton extends ConsumerStatefulWidget {
  const SendButton({
    super.key,
    required this.onPressed,
    this.variantOverride,
    this.size = _kButtonSize,
  });

  final VoidCallback onPressed;

  /// When set, renders this variant regardless of the equipped cosmetic
  /// (used for shop and settings previews). When null, reads the active
  /// variant from [activeSendButtonVariantProvider].
  final SendButtonVariant? variantOverride;

  final double size;

  @override
  ConsumerState<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends ConsumerState<SendButton>
    with TickerProviderStateMixin {
  late final AnimationController _firstCast;
  bool _firstCastPlaying = false;

  @override
  void initState() {
    super.initState();
    _firstCast = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _firstCastPlaying = false);
        }
      });
  }

  @override
  void dispose() {
    _firstCast.dispose();
    super.dispose();
  }

  void _handlePressed() {
    // First-cast only fires for the live chat send button (no override),
    // and only for premium stamps the player hasn't cast yet.
    if (widget.variantOverride == null) {
      final equippedId = ref
          .read(gameEconomyProvider)
          .equippedFor(CosmeticType.sendButtonStyle);
      if (equippedId != null && equippedId != 'send_classic') {
        final eco = ref.read(gameEconomyProvider.notifier);
        if (eco.isStampVirgin(equippedId)) {
          eco.markStampCast(equippedId);
          setState(() => _firstCastPlaying = true);
          _firstCast.forward(from: 0);
        }
      }
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final SendButtonVariant variant =
        widget.variantOverride ?? ref.watch(activeSendButtonVariantProvider);
    final body = _SendButtonBody(
      variant: variant,
      onPressed: _handlePressed,
      size: widget.size,
      accent: context.appColors.accent,
    );

    if (!_firstCastPlaying) return body;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        body,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _firstCast,
              builder: (context, _) => CustomPaint(
                painter: _FirstCastSparklePainter(
                  t: _firstCast.value,
                  accent: context.appColors.accent,
                  size: widget.size,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── First-cast sparkle painter ─────────────────────────────────────────────

/// Eight pixel-sized white/gold particles flying radially outward from the
/// button center on first send after equipping a premium stamp. Fires once
/// per stamp per lifetime (tracked via [GameState.castStamps]).
class _FirstCastSparklePainter extends CustomPainter {
  _FirstCastSparklePainter({
    required this.t,
    required this.accent,
    required this.size,
  });

  final double t;
  final Color accent;
  final double size;

  static const int _count = 8;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (t <= 0 || t >= 1) return;
    final center = canvasSize.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(t);
    final radius = size * 0.55 + eased * size * 0.85;
    final alpha = (1.0 - t).clamp(0.0, 1.0);

    for (int i = 0; i < _count; i++) {
      final angle = (i / _count) * 2 * math.pi;
      final pos = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final particleSize = 3.0 * (1.0 - eased * 0.5);
      final paint = Paint()
        ..color = (i.isEven ? Colors.white : accent).withValues(alpha: alpha)
        ..isAntiAlias = false;
      canvas.drawRect(
        Rect.fromCenter(center: pos, width: particleSize, height: particleSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FirstCastSparklePainter oldDelegate) =>
      oldDelegate.t != t;
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
              Listenable.merge([_press, _hover, _idle, _burst]),
          builder: (context, _) {
            final press = Curves.easeOut.transform(_press.value);
            final hover = Curves.easeInOut.transform(_hover.value);
            final idle = _idle.value;
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

class _CloudDriftPaint extends StatefulWidget {
  const _CloudDriftPaint({
    required this.press,
    required this.hover,
    required this.burst,
    required this.size,
  });

  final double press;
  final double hover;
  final double burst;
  final double size;

  @override
  State<_CloudDriftPaint> createState() => _CloudDriftPaintState();
}

/// Minimal "air" engine: each blob is a point mass tethered to its anchor
/// by a spring, dragged by air, and gently jostled by an ambient turbulence
/// force. A tap injects an outward radial impulse; the spring then gathers
/// the blobs back. No envelope, no pre-computed paths — the puff/return
/// shape emerges from the dynamics.
class _CloudDriftPaintState extends State<_CloudDriftPaint>
    with SingleTickerProviderStateMixin {
  // Spring k and damping c chosen so ζ = c/(2√k) ≈ 0.66 — slight overshoot,
  // settles in ~1 s. Underdamped enough to feel like air, not jelly.
  static const double _springK = 24.0;
  static const double _damping = 6.5;
  static const double _impulseSpeed = 23.5; // px/s @ scale=1

  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _ambientT = 0.0;
  double _prevBurst = 0.0;
  late final List<_CloudParticle> _particles;

  @override
  void initState() {
    super.initState();
    _particles = _spawnParticles();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(_CloudDriftPaint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_prevBurst <= 0 && widget.burst > 0) {
      _applyTapImpulse();
    }
    _prevBurst = widget.burst;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final raw = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (raw <= 0) return;
    // Clamp dt so a stalled frame can't blow up the integrator.
    final dt = math.min(raw, 1.0 / 30.0);
    _ambientT += dt;
    _step(dt);
    if (mounted) setState(() {});
  }

  void _step(double dt) {
    final scale = widget.size / 44.0;
    final ambBoost = 1.0 + widget.hover * 0.6;
    for (final p in _particles) {
      // Ambient turbulence as a force — drives the steady-state drift.
      final fx = math.sin(_ambientT * p.ambFreqX + p.ambPhaseX) *
          p.ambAmp *
          ambBoost;
      final fy = math.cos(_ambientT * p.ambFreqY + p.ambPhaseY) *
          p.ambAmp *
          ambBoost;
      // Spring pulls toward anchor (in screen units, hence scale on anchor).
      final ax = p.base.dx * scale;
      final ay = p.base.dy * scale;
      final accelX = fx - _springK * (p.pos.dx - ax) - _damping * p.vel.dx;
      final accelY = fy - _springK * (p.pos.dy - ay) - _damping * p.vel.dy;
      p.vel = Offset(p.vel.dx + accelX * dt, p.vel.dy + accelY * dt);
      p.pos = Offset(p.pos.dx + p.vel.dx * dt, p.pos.dy + p.vel.dy * dt);
    }
  }

  void _applyTapImpulse() {
    final scale = widget.size / 44.0;
    for (final p in _particles) {
      final d = p.base.distance;
      if (d <= 0.001) continue;
      final dir = Offset(p.base.dx / d, p.base.dy / d);
      p.vel = p.vel + dir * (_impulseSpeed * scale);
    }
  }

  List<_CloudParticle> _spawnParticles() {
    final scale = widget.size / 44.0;
    final list = <_CloudParticle>[];
    for (int i = 0; i < _CloudDriftPainter._basePositions.length; i++) {
      final anchor = _CloudDriftPainter._basePositions[i];
      list.add(_CloudParticle(
        base: anchor,
        colorIdx: _CloudDriftPainter._colorIdx[i],
        baseRadius: _CloudDriftPainter._baseRadii[i],
        pos: anchor * scale,
        ambFreqX: _CloudDriftPainter._ambFreqs[i][0],
        ambFreqY: _CloudDriftPainter._ambFreqs[i][1],
        ambPhaseX: _CloudDriftPainter._ambFreqs[i][2],
        ambPhaseY: _CloudDriftPainter._ambFreqs[i][3],
        ambAmp: _CloudDriftPainter._ambAmps[i],
      ));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 - widget.press * 0.05;

    return Transform.scale(
      scale: scale,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: widget.size * 2,
            height: widget.size * 2,
            child: CustomPaint(
              painter: _CloudDriftPainter(
                particles: _particles,
                press: widget.press,
                buttonSize: widget.size,
              ),
            ),
          ),
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _CloudDriftBodyPainter(),
              child: Center(
                child: Icon(
                  Icons.send_rounded,
                  size: widget.size * 0.44,
                  color: Colors.white.withValues(alpha: 0.95),
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudParticle {
  _CloudParticle({
    required this.base,
    required this.colorIdx,
    required this.baseRadius,
    required this.pos,
    required this.ambFreqX,
    required this.ambFreqY,
    required this.ambPhaseX,
    required this.ambPhaseY,
    required this.ambAmp,
  }) : vel = Offset.zero;

  final Offset base; // anchor in local units (relative to button center)
  final int colorIdx;
  final double baseRadius;
  final double ambFreqX;
  final double ambFreqY;
  final double ambPhaseX;
  final double ambPhaseY;
  final double ambAmp;

  Offset pos;
  Offset vel;
}

class _CloudDriftPainter extends CustomPainter {
  _CloudDriftPainter({
    required this.particles,
    required this.press,
    required this.buttonSize,
  });

  final List<_CloudParticle> particles;
  final double press;
  final double buttonSize;

  // Six-hue ambient palette: cool dominant (lavender / ice-sky / rose-lilac /
  // blush-rose) with two accent hues (mint-aqua / peach-gold) sprinkled in
  // for chromatic depth without breaking the WWDC-glass feel.
  static const _colors = <Color>[
    Color(0xFF7A66F0), // lavender-air (saturated)
    Color(0xFF42B5F5), // ice-sky (saturated)
    Color(0xFFBE6FE0), // rose-lilac (saturated)
    Color(0xFFFF6F8E), // blush-rose (saturated)
    Color(0xFF50E8C5), // mint-aqua (saturated)
    Color(0xFFFFA85F), // peach-gold (saturated)
  ];

  // 22 blob layout: 8 cardinal ring + 4 corner anchors + 8 mid-side fills
  // (two per side) + 2 inner wisps. Each side has two fills positioned to
  // close the gap between corner and cardinals, producing a continuous halo
  // without visible voids along the rim.
  static const _basePositions = <Offset>[
    Offset(-1.75, -12.0),  // N1 (lavender)
    Offset(1.75, -12.0),   // N2 (mint-aqua)
    Offset(12.5, -1.75),   // E1 (ice-sky)
    Offset(12.5, 1.75),    // E2 (rose-lilac)
    Offset(1.75, 12.5),    // S1 (peach-gold)
    Offset(-1.75, 12.5),   // S2 (blush-rose)
    Offset(-12.5, 1.75),   // W1 (rose-lilac)
    Offset(-12.5, -1.75),  // W2 (lavender)
    Offset(11.75, -11.75), // NE corner (ice-sky)
    Offset(11.75, 11.75),  // SE corner (peach-gold)
    Offset(-11.75, 11.75), // SW corner (blush-rose)
    Offset(-11.75, -11.75),// NW corner (mint-aqua)
    Offset(-8.0, -11.75),  // N-W fill (rose-lilac)
    Offset(11.75, -8.0),   // E-N fill (mint-aqua)
    Offset(8.0, 11.75),    // S-E fill (lavender)
    Offset(-11.75, 8.0),   // W-S fill (ice-sky)
    Offset(8.0, -11.75),   // N-E fill (peach-gold)
    Offset(11.75, 8.0),    // E-S fill (lavender)
    Offset(-8.0, 11.75),   // S-W fill (ice-sky)
    Offset(-11.75, -8.0),  // W-N fill (rose-lilac)
    Offset(0.0, -7.0),     // inner top (lavender)
    Offset(0.0, 7.0),      // inner bottom (mint-aqua)
  ];

  static const _colorIdx = <int>[
    0, 4, 1, 2, 5, 3, 2, 0,
    1, 5, 3, 4,
    2, 4, 0, 1,
    5, 0, 1, 2,
    0, 4,
  ];

  // Per-particle radii tuned for hue-luminance balance: corners with bright
  // warm/cool hues (peach, blush, mint, ice) are shrunk to stop them screaming
  // through screen blend; cardinals with low-luminance hues (lavender) are
  // grown to compete; fills are widened to bridge gaps along each edge.
  static const _baseRadii = <double>[
    17.5,  15.25, 15.75, 14.5,  14.5,  14.0,  15.75, 13.5,
    15.5,  15.0,  15.0,  15.5,
    13.0,  11.75, 14.0,  11.75,
    12.75, 13.0,  14.0,  11.75,
    9.5,   7.5,
  ];

  // Ambient turbulence freq pairs + phases. Per-particle incommensurate so the
  // collective drift never resolves into a visible repeating pattern.
  static const _ambFreqs = <List<double>>[
    [0.9, 1.1, 0.0, 0.0],   // N1
    [0.9, 1.1, 0.4, 0.3],   // N2
    [1.2, 0.8, 2.5, 1.7],   // E1
    [1.2, 0.8, 2.9, 2.0],   // E2
    [0.75, 1.0, 4.7, 2.3],  // S1
    [0.75, 1.0, 5.1, 2.6],  // S2
    [1.05, 0.85, 6.0, 4.4], // W1
    [1.05, 0.85, 6.4, 4.7], // W2
    [1.35, 0.95, 1.2, 3.8], // NE corner
    [0.85, 1.25, 3.6, 5.5], // SE corner
    [0.95, 1.2, 2.4, 0.6],  // SW corner
    [1.15, 0.7, 5.7, 1.1],  // NW corner
    [0.8, 1.3, 1.5, 4.8],   // N-W fill
    [1.25, 0.9, 2.7, 0.4],  // E-N fill
    [0.95, 1.1, 4.1, 5.2],  // S-E fill
    [1.1, 0.95, 5.9, 2.7],  // W-S fill
    [1.3, 0.85, 0.9, 5.6],  // N-E fill
    [0.9, 1.2, 3.1, 1.9],   // E-S fill
    [1.05, 1.0, 4.5, 3.3],  // S-W fill
    [0.85, 1.15, 2.2, 5.0], // W-N fill
    [1.5, 0.6, 3.3, 2.1],   // inner top
    [0.65, 1.45, 5.4, 3.7], // inner bottom
  ];

  // Per-particle ambient force amplitude (px/s²). Corners drift the slowest
  // to act as visual anchors; cardinal ring breathes more lively.
  static const _ambAmps = <double>[
    15.5,  14.5,  14.75, 14.0,  13.5,  13.0,  14.0,  14.0,
    14.5,  14.0,  14.0,  14.5,
    12.5,  11.75, 13.5,  11.75,
    12.0,  12.5,  13.5,  11.75,
    9.0,   7.5,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = buttonSize / 44.0;
    final center = size.center(Offset.zero);
    final radiusBoost = -press * 3.2;

    for (final p in particles) {
      final pos = center + p.pos;
      final anchorScreen = p.base * scale;
      // Alpha falls off with displacement from anchor — the further the
      // blob is pushed (by impulse or turbulence), the more diffuse it
      // reads, exactly like a real puff of air dispersing.
      final disp = (p.pos - anchorScreen).distance;
      final disperse = (disp / (4.5 * scale)).clamp(0.0, 1.0);
      final alphaScale = (1.0 - disperse * 0.65 - press * 0.15)
          .clamp(0.0, 1.0);

      final color = _colors[p.colorIdx];
      final blobRadius = (p.baseRadius + radiusBoost) * scale;
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          pos,
          blobRadius,
          [
            color.withValues(alpha: 0.62 * alphaScale),
            color.withValues(alpha: 0.32 * alphaScale),
            color.withValues(alpha: 0.0),
          ],
          [0.0, 0.5, 1.0],
        )
        ..blendMode = BlendMode.screen;
      canvas.drawCircle(pos, blobRadius, paint);
    }
  }

  // The painter is repainted from the Ticker via setState — list identity is
  // stable but contents mutate, so we always need to repaint.
  @override
  bool shouldRepaint(covariant _CloudDriftPainter oldDelegate) => true;
}

/// Dark body of Cloud Drift with a thin "wire" stroke and a specular gloss,
/// to read as a polished/glassy material rather than a flat painted card.
class _CloudDriftBodyPainter extends CustomPainter {
  _CloudDriftBodyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * 0.28);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    final fill = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        const [Color(0xFF0A0C12), Color(0xFF030407)],
      );
    canvas.drawRRect(rrect, fill);

    final innerShade = Paint()
      ..shader = ui.Gradient.radial(
        rect.bottomRight,
        size.width,
        [
          Colors.black.withValues(alpha: 0.55),
          Colors.black.withValues(alpha: 0.0),
        ],
      )
      ..blendMode = BlendMode.multiply;
    canvas.drawRRect(rrect, innerShade);

    final glossRect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.06,
      size.width * 0.84,
      size.height * 0.46,
    );
    final glossPath = Path()
      ..addRRect(RRect.fromRectAndRadius(glossRect, radius * 0.85));
    final glossPaint = Paint()
      ..shader = ui.Gradient.linear(
        glossRect.topCenter,
        glossRect.bottomCenter,
        [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      )
      ..blendMode = BlendMode.screen;
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawPath(glossPath, glossPaint);
    canvas.restore();

    // Apple-style metallic rim — bilateral bevel lit from world-up.
    // Three passes on the same RRect: dark anchor, top specular highlight,
    // bottom shadow rim. Plus a faint lavender inner radial glow for depth.
    final wireStroke = (size.width * 0.038).clamp(1.0, 1.7);
    final inset = wireStroke / 2;
    final rimRRect = RRect.fromRectAndRadius(
      rect.deflate(inset),
      Radius.circular(radius.x - inset),
    );

    canvas.drawRRect(
      rimRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = wireStroke
        ..color = const Color(0xFF1A1D26).withValues(alpha: 0.70),
    );

    canvas.drawRRect(
      rimRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = wireStroke
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.linear(
          Offset(rect.center.dx, rect.top),
          Offset(rect.center.dx, rect.top + size.height * 0.38),
          [
            Colors.white.withValues(alpha: 0.88),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
          const [0.0, 0.30, 1.0],
        ),
    );

    canvas.drawRRect(
      rimRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = wireStroke
        ..shader = ui.Gradient.linear(
          Offset(rect.center.dx, rect.bottom),
          Offset(rect.center.dx, rect.bottom - size.height * 0.45),
          [
            const Color(0xFF4A4F5C).withValues(alpha: 0.85),
            const Color(0xFF2E323C).withValues(alpha: 0.55),
            const Color(0xFF2E323C).withValues(alpha: 0.0),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = wireStroke * 1.4
        ..blendMode = BlendMode.screen
        ..shader = ui.Gradient.radial(
          rect.center,
          size.width * 0.72,
          [
            const Color(0xFF8B7AE8).withValues(alpha: 0.18),
            const Color(0xFF8B7AE8).withValues(alpha: 0.0),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _CloudDriftBodyPainter oldDelegate) => false;
}
