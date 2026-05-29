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

import '../../providers/game_economy_provider.dart';
import '../../providers/ws_provider.dart';
import 'foreman_overlay_painter.dart' show doorLeftColFor;
import 'office_game_state.dart' show kTileSize;

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

  // Position in office tile-space. (0,0) = top-left of grid; walkable deck is
  // cols [1..gridCols-2], rows [1..gridRows-2]. Negative ty means the janitor
  // is behind the back wall (off-grid, hidden).
  double _tx = 10.0, _ty = -1.5;
  double _targetTx = 8.0, _targetTy = 4.0;

  // Latest grid dimensions captured each build from gameEconomyProvider — used
  // by ticker math (which runs outside build) to clamp wander targets.
  int _gridCols = 20;
  int _gridRows = 12;

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

  // Tiles per second.
  static const _kSpeed = 3.4;
  static const _kFastSpeed = 5.6;
  static const _kFrameRate = 0.14;
  static const _kPixelSize = 3.0;
  static const _kSweepAmp = 0.6;
  static const _kCarryAngle = 0.38;
  static const _kHandOffsetX = 0.38;
  static const _kHandOffsetY = 0.30;
  static const _kHandleLen = 28.0;

  // Off-grid Y for entry/exit — 1.5 tiles above the back wall so the sprite
  // is fully hidden above the deck.
  static const _kDoorOffTy = -1.5;

  double get _doorCenterTx => doorLeftColFor(_gridCols) + 1.0;

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
      // Start at the door position (off-grid above the back wall).
      _tx = _doorCenterTx;
      _ty = _kDoorOffTy;
      // First wander target: somewhere in the upper half of the deck.
      _targetTx = 2.0 + _rng.nextDouble() * (_gridCols - 5).clamp(1, 999);
      _targetTy = 2.0 + _rng.nextDouble() * ((_gridRows - 5) * 0.5).clamp(1, 999);
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
    // Stay inside the deck with a one-tile margin from walls. For very small
    // grids the clamp collapses the range to a single point — that's fine,
    // the janitor will just stop in the middle.
    final minTx = 2.0;
    final maxTx = (_gridCols - 3).toDouble().clamp(minTx, double.infinity);
    final minTy = 2.0;
    final maxTy = (_gridRows - 3).toDouble().clamp(minTy, double.infinity);
    _targetTx = minTx + _rng.nextDouble() * (maxTx - minTx);
    _targetTy = minTy + _rng.nextDouble() * (maxTy - minTy);
  }

  // ─── Ticker ────────────────────────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1_000_000.0)
        .clamp(0.0, 0.1);
    _lastElapsed = elapsed;

    if (_phase == _Phase.hidden) return;
    _step(dt);
    setState(() {});
  }

  void _step(double dt) {
    switch (_phase) {
      case _Phase.doorEntry:
        // Walk in from door; switch to wandering once the first target is reached.
        _moveTo(dt, _kFastSpeed);
        _tickFrame(dt);
        final edx = _targetTx - _tx;
        final edy = _targetTy - _ty;
        if (edx * edx + edy * edy < 0.25) {
          _isSweeping = false;
          _pickTarget();
          _phase = _Phase.wandering;
        }

      case _Phase.wandering:
        _wander(dt);

      case _Phase.doorExit:
        // Walk back to door and disappear above the back wall.
        _targetTx = _doorCenterTx;
        _targetTy = _kDoorOffTy;
        _moveTo(dt, _kFastSpeed);
        _tickFrame(dt);
        if (_ty <= _kDoorOffTy + 0.2) {
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
      final dx = _targetTx - _tx;
      final dy = _targetTy - _ty;
      if (dx * dx + dy * dy < 0.25) {
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
    final dx = _targetTx - _tx;
    final dy = _targetTy - _ty;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 0.02) return;
    final step = math.min(speed * dt, dist);
    _tx += dx / dist * step;
    _ty += dy / dist * step;
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

    final game = ref.watch(gameEconomyProvider);
    _gridCols = game.gridCols;
    _gridRows = game.gridRows;

    if (_phase == _Phase.hidden) return const SizedBox.expand();

    return IgnorePointer(
      child: CustomPaint(
        painter: _JanitorPainter(
          tx: _tx,
          ty: _ty,
          gridCols: _gridCols,
          gridRows: _gridRows,
          walkFrame: _walkFrame,
          facingLeft: _facingLeft,
          isSweeping: _isSweeping,
          sweepAngle: _sweepAngle,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _JanitorPainter extends CustomPainter {
  final double tx, ty;
  final int gridCols, gridRows;
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
    required this.tx,
    required this.ty,
    required this.gridCols,
    required this.gridRows,
    required this.walkFrame,
    required this.facingLeft,
    required this.isSweeping,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Replicate PixelOfficePainter's fit-to-viewport transform so tile-space
    // coordinates land on the actual deck, regardless of letterboxing.
    final canvasW = gridCols * kTileSize;
    final canvasH = gridRows * kTileSize;
    final scale = math.min(size.width / canvasW, size.height / canvasH);
    final offsetX = (size.width - canvasW * scale) / 2;
    final offsetY = (size.height - canvasH * scale) / 2;

    final cx = offsetX + tx * kTileSize * scale;
    final cy = offsetY + ty * kTileSize * scale;

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
      old.tx != tx ||
      old.ty != ty ||
      old.gridCols != gridCols ||
      old.gridRows != gridRows ||
      old.walkFrame != walkFrame ||
      old.facingLeft != facingLeft ||
      old.isSweeping != isSweeping ||
      old.sweepAngle != sweepAngle;
}
