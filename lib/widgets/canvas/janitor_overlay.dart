/// Janitor character — appears over the empty office while disconnected.
///
/// Becomes visible 5 s after the last connection attempt fails.
/// On reconnection plays a three-phase transition:
///   1. Walks off the right edge of the canvas.
///   2. Re-enters from the left, walks to centre.
///   3. Raises the broom like a magic wand → sparkle burst → fades out.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ws_provider.dart';

// ─── Sprite data (8 cols × 12 rows) ─────────────────────────────────────────
//
// Palette keys:
//   h = dark chestnut hair      (#3D2010)
//   s = warm skin               (#E8BEA0)
//   f = lighter skin highlight  (#F2CEA8)
//   e = dark eye                (#2A1A0A)
//   c = cream vyshyvanka shirt  (#F0ECD8)
//   v = navy embroidery border  (#1E3055)
//   p = charcoal trousers       (#2A2D3A)
//   b = dark boots              (#2A1A0A)
//   . = transparent

const _walk0 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..vccv..',
  '.vccccv.',
  '..vccv..',
  '..pp....',
  '.p..p...',
  '.p...p..',
  '.b...b..',
];

const _walk1 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..vccv..',
  '.vccccv.',
  '..vccv..',
  '...pp...',
  '..p..p..',
  '..p..p..',
  '..b..b..',
];

const _walk2 = [
  '...hh...',
  '..hhhh..',
  '..sffs..',
  '..sees..',
  '...ss...',
  '..vccv..',
  '.vccccv.',
  '..vccv..',
  '....pp..',
  '...p..p.',
  '..p...p.',
  '..b...b.',
];

const _walkFrames = [_walk0, _walk1, _walk2, _walk1];

Color _palette(String key, double alpha) => switch (key) {
      'h' => Color(0xFF3D2010).withValues(alpha: alpha),
      's' => Color(0xFFE8BEA0).withValues(alpha: alpha),
      'f' => Color(0xFFF2CEA8).withValues(alpha: alpha),
      'e' => Color(0xFF2A1A0A).withValues(alpha: alpha),
      'c' => Color(0xFFF0ECD8).withValues(alpha: alpha),
      'v' => Color(0xFF1E3055).withValues(alpha: alpha),
      'p' => Color(0xFF2A2D3A).withValues(alpha: alpha),
      'b' => Color(0xFF2A1A0A).withValues(alpha: alpha),
      _ => Colors.transparent,
    };

// ─── Sparkle ─────────────────────────────────────────────────────────────────

class _Sparkle {
  double x, y, life, speed, angle;
  final Color color;

  _Sparkle({
    required this.x,
    required this.y,
    required this.speed,
    required this.angle,
    required this.color,
  }) : life = 1.0;
}

// ─── Animation phase ─────────────────────────────────────────────────────────

enum _Phase { hidden, appearing, wandering, exitWalk, enterWalk, magicWave, vanishing }

// ─── Widget ──────────────────────────────────────────────────────────────────

class JanitorOverlay extends ConsumerStatefulWidget {
  const JanitorOverlay({super.key});

  @override
  ConsumerState<JanitorOverlay> createState() => _JanitorOverlayState();
}

class _JanitorOverlayState extends ConsumerState<JanitorOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  final math.Random _rng = math.Random();

  _Phase _phase = _Phase.hidden;
  double _opacity = 0.0;

  // Normalised position within canvas [0..1]
  double _nx = 0.4, _ny = 0.6;
  double _targetNx = 0.3, _targetNy = 0.7;

  // Walk animation
  int _walkFrame = 0;
  double _frameTimer = 0.0;
  bool _facingLeft = false;

  // Sweep pause at each waypoint
  bool _isSweeping = false;
  double _sweepTimer = 0.0;
  double _sweepAngle = 0.0; // oscillates ± kSweepAmp
  double _sweepDir = 1.0;
  int _sweepOsc = 0;

  // Magic-wave broom lift
  double _broomAngle = 0.0; // grows from carry → π (pointing up)

  // Sparkles
  final List<_Sparkle> _sparkles = [];

  // 5-second delay timer before janitor appears
  Timer? _delayTimer;

  // Filled by LayoutBuilder each build
  Size _size = Size.zero;

  static const _kSpeed = 55.0;
  static const _kFastSpeed = 95.0;
  static const _kFrameRate = 0.14; // s per walk frame
  static const _kPixelSize = 3.0;
  static const _kSweepAmp = 0.6; // broom swing amplitude, radians
  static const _kCarryAngle = 0.38; // broom tilt while walking
  static const _kHandOffsetX = 0.38; // fraction of charW
  static const _kHandOffsetY = 0.30; // fraction of charH (from char bottom)
  static const _kHandleLen = 28.0;

  double get _charW => 8 * _kPixelSize;
  double get _charH => 12 * _kPixelSize;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connected = ref.read(connectionStatusProvider).valueOrNull ?? false;
      if (!connected) _scheduleAppearance();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  void _scheduleAppearance() {
    if (_phase != _Phase.hidden) return;
    _delayTimer?.cancel();
    _delayTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _phase != _Phase.hidden) return;
      _nx = 0.25 + _rng.nextDouble() * 0.5;
      _ny = 0.40 + _rng.nextDouble() * 0.25;
      _pickTarget();
      setState(() => _phase = _Phase.appearing);
    });
  }

  void _onConnected() {
    _delayTimer?.cancel();
    if (_phase == _Phase.appearing || _phase == _Phase.wandering) {
      setState(() => _phase = _Phase.exitWalk);
    }
  }

  void _onDisconnected() {
    if (_phase == _Phase.hidden) _scheduleAppearance();
  }

  void _pickTarget() {
    _targetNx = 0.10 + _rng.nextDouble() * 0.80;
    _targetNy = 0.30 + _rng.nextDouble() * 0.50;
  }

  // ─── Ticker ────────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1_000_000.0)
        .clamp(0.0, 0.1);
    _lastElapsed = elapsed;

    if (_phase == _Phase.hidden || _size == Size.zero) return;
    _step(dt);
    setState(() {});
  }

  void _step(double dt) {
    switch (_phase) {
      case _Phase.appearing:
        _opacity = (_opacity + dt).clamp(0.0, 1.0);
        if (_opacity >= 1.0) _phase = _Phase.wandering;
        _wander(dt);

      case _Phase.wandering:
        _wander(dt);

      case _Phase.exitWalk:
        _opacity = (_opacity + dt * 2).clamp(0.0, 1.0);
        _facingLeft = false;
        _targetNx = 1.08;
        _targetNy = _ny;
        _moveTo(dt, _kFastSpeed);
        _tickFrame(dt);
        if (_nx > 1.05) {
          _nx = -0.08;
          _ny = 0.44 + (_rng.nextDouble() - 0.5) * 0.12;
          _phase = _Phase.enterWalk;
        }

      case _Phase.enterWalk:
        _facingLeft = false;
        _targetNx = 0.40 + _rng.nextDouble() * 0.20;
        _targetNy = 0.42 + _rng.nextDouble() * 0.16;
        _moveTo(dt, _kFastSpeed);
        _tickFrame(dt);
        final dx = (_targetNx - _nx) * _size.width;
        final dy = (_targetNy - _ny) * _size.height;
        if (dx * dx + dy * dy < 9.0) {
          _walkFrame = 1;
          _broomAngle = _kCarryAngle;
          _phase = _Phase.magicWave;
        }

      case _Phase.magicWave:
        // Lift broom smoothly from carry angle to π (pointing up).
        _broomAngle = (_broomAngle + dt * 2.4).clamp(0.0, math.pi);
        _emitSparkles(dt);
        _tickSparkles(dt);
        if (_broomAngle >= math.pi - 0.05) _phase = _Phase.vanishing;

      case _Phase.vanishing:
        _opacity = (_opacity - dt * 1.2).clamp(0.0, 1.0);
        _tickSparkles(dt);
        if (_opacity <= 0 && _sparkles.isEmpty) _phase = _Phase.hidden;

      case _Phase.hidden:
        break;
    }
  }

  void _wander(double dt) {
    if (_isSweeping) {
      _sweepAngle += _sweepDir * dt * 2.0;
      if (_sweepAngle.abs() >= _kSweepAmp) {
        _sweepDir = -_sweepDir;
        _sweepOsc++;
      }
      _sweepTimer -= dt;
      _walkFrame = 1; // standing pose while sweeping
      if (_sweepTimer <= 0 && _sweepOsc >= 6) {
        _isSweeping = false;
        _sweepOsc = 0;
        _sweepAngle = 0;
        _pickTarget();
      }
    } else {
      _moveTo(dt, _kSpeed);
      _tickFrame(dt);
      final dx = (_targetNx - _nx) * _size.width;
      final dy = (_targetNy - _ny) * _size.height;
      if (dx * dx + dy * dy < 16.0) {
        _isSweeping = true;
        _sweepTimer = 2.0 + _rng.nextDouble() * 2.5;
        _sweepDir = 1.0;
        _sweepAngle = 0;
        _sweepOsc = 0;
        _facingLeft = false; // face viewer while sweeping
      }
    }
  }

  void _moveTo(double dt, double speed) {
    final dx = (_targetNx - _nx) * _size.width;
    final dy = (_targetNy - _ny) * _size.height;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.5) return;
    final step = math.min(speed * dt, dist);
    _nx += dx / dist * step / _size.width;
    _ny += dy / dist * step / _size.height;
    _facingLeft = dx < 0;
  }

  void _tickFrame(double dt) {
    _frameTimer += dt;
    if (_frameTimer >= _kFrameRate) {
      _frameTimer -= _kFrameRate;
      _walkFrame = (_walkFrame + 1) % 4;
    }
  }

  void _emitSparkles(double dt) {
    final dir = _facingLeft ? -1.0 : 1.0;
    final cx = _nx * _size.width;
    final cy = _ny * _size.height;
    final handX = cx + dir * _charW * _kHandOffsetX;
    final handY = cy - _charH * _kHandOffsetY;
    // Straw tip (end of handle in world space after rotation by _broomAngle)
    final angle = dir * _broomAngle;
    final tipX = handX + _kHandleLen * math.sin(angle);
    final tipY = handY + _kHandleLen * math.cos(angle);

    final count = (dt * 30).round().clamp(0, 5);
    for (var i = 0; i < count; i++) {
      _sparkles.add(_Sparkle(
        x: tipX + (_rng.nextDouble() - 0.5) * 14,
        y: tipY + (_rng.nextDouble() - 0.5) * 14,
        speed: 28 + _rng.nextDouble() * 55,
        angle: -math.pi / 2 + (_rng.nextDouble() - 0.5) * math.pi * 1.4,
        color: const [
          Color(0xFFFFD700),
          Color(0xFF00C0D1),
          Color(0xFFFFFFFF),
          Color(0xFF4AD1B4),
          Color(0xFFFFAAAA),
        ][math.Random().nextInt(5)],
      ));
    }
  }

  void _tickSparkles(double dt) {
    for (final s in _sparkles) {
      s.x += math.cos(s.angle) * s.speed * dt;
      s.y += math.sin(s.angle) * s.speed * dt;
      s.life -= dt * 1.8;
    }
    _sparkles.removeWhere((s) => s.life <= 0);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionStatusProvider, (prev, next) {
      final was = prev?.valueOrNull ?? false;
      final now = next.valueOrNull ?? false;
      if (!was && now) _onConnected();
      if (was && !now) _onDisconnected();
    });

    if (_phase == _Phase.hidden) return const SizedBox.expand();

    return LayoutBuilder(
      builder: (_, constraints) {
        _size = constraints.biggest;
        return IgnorePointer(
          child: CustomPaint(
            painter: _JanitorPainter(
              nx: _nx,
              ny: _ny,
              walkFrame: _walkFrame,
              facingLeft: _facingLeft,
              isSweeping: _isSweeping,
              sweepAngle: _sweepAngle,
              phase: _phase,
              broomAngle: _broomAngle,
              sparkles: List.of(_sparkles),
              opacity: _opacity,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _JanitorPainter extends CustomPainter {
  final double nx, ny;
  final int walkFrame;
  final bool facingLeft;
  final bool isSweeping;
  final double sweepAngle;
  final _Phase phase;
  final double broomAngle;
  final List<_Sparkle> sparkles;
  final double opacity;

  static const _ps = _JanitorOverlayState._kPixelSize;
  static const _handleLen = _JanitorOverlayState._kHandleLen;
  static const _carryAngle = _JanitorOverlayState._kCarryAngle;
  static const _handOffX = _JanitorOverlayState._kHandOffsetX;
  static const _handOffY = _JanitorOverlayState._kHandOffsetY;

  double get _charW => 8 * _ps;
  double get _charH => 12 * _ps;

  _JanitorPainter({
    required this.nx,
    required this.ny,
    required this.walkFrame,
    required this.facingLeft,
    required this.isSweeping,
    required this.sweepAngle,
    required this.phase,
    required this.broomAngle,
    required this.sparkles,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.isEmpty) return;

    final cx = nx * size.width;
    final cy = ny * size.height;

    _drawBroom(canvas, cx, cy);
    _drawBody(canvas, cx, cy);
    _drawSparkles(canvas);
  }

  void _drawBody(Canvas canvas, double cx, double cy) {
    final sprite = _walkFrames[walkFrame % 4];
    final charLeft = cx - _charW / 2;
    final charTop = cy - _charH * 0.72; // feet near cy
    final paint = Paint()..style = PaintingStyle.fill;

    for (int row = 0; row < sprite.length; row++) {
      final line = sprite[row];
      for (int col = 0; col < line.length; col++) {
        final key = line[col];
        if (key == '.') continue;
        final color = _palette(key, opacity);
        if (color == Colors.transparent) continue;
        paint.color = color;
        final px = charLeft + (facingLeft ? (7 - col) * _ps : col * _ps);
        final py = charTop + row * _ps;
        canvas.drawRect(
          Rect.fromLTWH(px, py, _ps + 0.5, _ps + 0.5),
          paint,
        );
      }
    }
  }

  void _drawBroom(Canvas canvas, double cx, double cy) {
    final dir = facingLeft ? -1.0 : 1.0;
    final handX = cx + dir * _charW * _handOffX;
    final handY = cy - _charH * _handOffY;

    // Effective broom rotation angle.
    final double angle;
    if (phase == _Phase.magicWave || phase == _Phase.vanishing) {
      angle = dir * broomAngle;
    } else if (isSweeping) {
      angle = dir * sweepAngle; // oscillates ± amplitude around 0 (=straight down)
    } else {
      angle = dir * _carryAngle;
    }

    canvas.save();
    canvas.translate(handX, handY);
    canvas.rotate(angle);

    // Pole
    canvas.drawRect(
      Rect.fromLTWH(-1.5, 0, 3, _handleLen),
      Paint()
        ..color = const Color(0xFF8B6B35).withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );

    // Straw head at bottom of pole
    canvas.translate(0, _handleLen);
    const strawHalfW = 10.0;
    const strawH = 7.0;

    // Body of straw
    canvas.drawRect(
      Rect.fromLTWH(-strawHalfW, 0, strawHalfW * 2, strawH * 0.55),
      Paint()
        ..color = const Color(0xFFD4A030).withValues(alpha: opacity)
        ..style = PaintingStyle.fill,
    );

    // Straw bristle tips (fan)
    final tipPaint = Paint()
      ..color = const Color(0xFFE8C040).withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    for (var i = -4; i <= 4; i++) {
      final tx = i * (strawHalfW / 4.5);
      canvas.drawRect(
        Rect.fromLTWH(tx - 1.0, strawH * 0.4, 2.0, strawH * 0.6 + i.abs() * 0.25),
        tipPaint,
      );
    }

    canvas.restore();
  }

  void _drawSparkles(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final s in sparkles) {
      final a = s.life.clamp(0.0, 1.0) * opacity;
      if (a <= 0) continue;
      paint.color = s.color.withValues(alpha: a);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(s.x, s.y), width: 3, height: 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_JanitorPainter old) => true;
}
