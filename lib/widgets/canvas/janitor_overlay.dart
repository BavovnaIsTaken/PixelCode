/// Janitor character — appears over the office while disconnected.
///
/// Enters through the back-wall door 5 s after disconnection, sweeps around,
/// and exits back through the door when the connection is restored.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ws_provider.dart';

// ─── Sprite data (8 cols × 12 rows) ─────────────────────────────────────────

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

// ─── Animation phase ─────────────────────────────────────────────────────────

enum _Phase { hidden, doorEntry, wandering, doorExit }

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

  // Normalised position within canvas [0..1]
  double _nx = 0.5, _ny = -0.20;
  double _targetNx = 0.4, _targetNy = 0.45;

  // Walk animation
  int _walkFrame = 0;
  double _frameTimer = 0.0;
  bool _facingLeft = false;

  // Sweep pause at each waypoint
  bool _isSweeping = false;
  double _sweepTimer = 0.0;
  double _sweepAngle = 0.0;
  double _sweepDir = 1.0;
  int _sweepOsc = 0;

  // 5-second delay timer before janitor appears
  Timer? _delayTimer;

  // Filled by LayoutBuilder each build
  Size _size = Size.zero;

  static const _kSpeed = 55.0;
  static const _kFastSpeed = 90.0;
  static const _kFrameRate = 0.14;
  static const _kPixelSize = 3.0;
  static const _kSweepAmp = 0.6;
  static const _kCarryAngle = 0.38;
  static const _kHandOffsetX = 0.38;
  static const _kHandOffsetY = 0.30;
  static const _kHandleLen = 28.0;

  // Back-wall door x (mirrors doorLeftColFor for gridCols=20: col 9 → 9.5 tiles → nx≈0.475)
  static const _kDoorNx = 0.475;
  // Off-screen above the canvas: character is fully hidden until it walks in
  static const _kDoorOffNy = -0.20;

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
      // Start at the door position (off-screen above back wall)
      _nx = _kDoorNx;
      _ny = _kDoorOffNy;
      // First wander target: somewhere in the upper-middle office area
      _targetNx = 0.25 + _rng.nextDouble() * 0.50;
      _targetNy = 0.35 + _rng.nextDouble() * 0.25;
      _facingLeft = false;
      _isSweeping = false;
      setState(() => _phase = _Phase.doorEntry);
    });
  }

  void _onConnected() {
    _delayTimer?.cancel();
    if (_phase == _Phase.doorEntry || _phase == _Phase.wandering) {
      _isSweeping = false;
      _sweepOsc = 0;
      _sweepAngle = 0.0;
      setState(() => _phase = _Phase.doorExit);
    }
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
      case _Phase.doorEntry:
        // Walk in from door; switch to wandering once the first target is reached.
        _moveTo(dt, _kFastSpeed);
        _tickFrame(dt);
        final edx = (_targetNx - _nx) * _size.width;
        final edy = (_targetNy - _ny) * _size.height;
        if (edx * edx + edy * edy < 16.0) {
          _isSweeping = false;
          _pickTarget();
          _phase = _Phase.wandering;
        }

      case _Phase.wandering:
        _wander(dt);

      case _Phase.doorExit:
        // Walk back to door and disappear off the top edge.
        _targetNx = _kDoorNx;
        _targetNy = _kDoorOffNy;
        _moveTo(dt, _kFastSpeed);
        _tickFrame(dt);
        if (_ny <= _kDoorOffNy + 0.02) {
          _phase = _Phase.hidden;
        }

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
      _walkFrame = 1;
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
        _facingLeft = false;
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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(connectionStatusProvider, (prev, next) {
      final now = next.valueOrNull ?? false;
      if (now) {
        _onConnected();
      } else {
        _scheduleAppearance();
      }
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

  static const _ps = _JanitorOverlayState._kPixelSize;
  static const _handleLen = _JanitorOverlayState._kHandleLen;
  static const _carryAngle = _JanitorOverlayState._kCarryAngle;
  static const _handOffX = _JanitorOverlayState._kHandOffsetX;
  static const _handOffY = _JanitorOverlayState._kHandOffsetY;

  double get _charW => 8 * _ps;
  double get _charH => 12 * _ps;

  const _JanitorPainter({
    required this.nx,
    required this.ny,
    required this.walkFrame,
    required this.facingLeft,
    required this.isSweeping,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final cx = nx * size.width;
    final cy = ny * size.height;

    // Skip drawing if fully off-screen (performance guard)
    if (cy < -_charH * 1.5 || cy > size.height + _charH) return;

    _drawBroom(canvas, cx, cy);
    _drawBody(canvas, cx, cy);
  }

  void _drawBody(Canvas canvas, double cx, double cy) {
    final sprite = _walkFrames[walkFrame % 4];
    final charLeft = cx - _charW / 2;
    final charTop = cy - _charH * 0.72;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int row = 0; row < sprite.length; row++) {
      final line = sprite[row];
      for (int col = 0; col < line.length; col++) {
        final key = line[col];
        if (key == '.') continue;
        final color = _palette(key, 1.0);
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

    final double angle =
        isSweeping ? dir * sweepAngle : dir * _carryAngle;

    canvas.save();
    canvas.translate(handX, handY);
    canvas.rotate(angle);

    canvas.drawRect(
      Rect.fromLTWH(-1.5, 0, 3, _handleLen),
      Paint()
        ..color = const Color(0xFF8B6B35)
        ..style = PaintingStyle.fill,
    );

    canvas.translate(0, _handleLen);
    const strawHalfW = 10.0;
    const strawH = 7.0;

    canvas.drawRect(
      Rect.fromLTWH(-strawHalfW, 0, strawHalfW * 2, strawH * 0.55),
      Paint()
        ..color = const Color(0xFFD4A030)
        ..style = PaintingStyle.fill,
    );

    final tipPaint = Paint()
      ..color = const Color(0xFFE8C040)
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

  @override
  bool shouldRepaint(_JanitorPainter old) =>
      old.nx != nx ||
      old.ny != ny ||
      old.walkFrame != walkFrame ||
      old.facingLeft != facingLeft ||
      old.isSweeping != isSweeping ||
      old.sweepAngle != sweepAngle;
}
