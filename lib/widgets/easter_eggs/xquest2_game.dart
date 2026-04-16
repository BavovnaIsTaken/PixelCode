// XQuest 2 — Main game widget
// Ties together all subsystems: world, player, enemy, powerup, painter.
// Input: mouse on desktop, floating joystick + auto-fire on touch (iOS/Android).

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'xquest2_types.dart';
import 'xquest2_world.dart';
import 'xquest2_enemy.dart';
import 'xquest2_player.dart';
import 'xquest2_powerup.dart';
import 'xquest2_painter.dart';

// ─── Platform detection ──────────────────────────────────────────────────────

bool _isTouchPlatform() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

// ─── Touch input constants ───────────────────────────────────────────────────

const _touchVelScale = 0.55;
const _touchJoyRadius = 24.0;
const _touchAnchorDriftMax = 60.0;
const _autoFireSpeedThreshold = 0.8;

// ─── Widget ───────────────────────────────────────────────────────────────────

class XQuest2Game extends StatefulWidget {
  final VoidCallback onClose;

  const XQuest2Game({super.key, required this.onClose});

  @override
  State<XQuest2Game> createState() => _XQuest2GameState();
}

class _XQuest2GameState extends State<XQuest2Game> {
  late GameData _gd;
  Timer? _timer;
  late final bool _isTouch;

  // ── Mouse input (desktop) ──
  Offset _mouseDelta = Offset.zero;
  bool _firePressed = false;

  // ── Touch input (mobile) ──
  Offset _touchAnchor = Offset.zero;
  Offset _touchCurrent = Offset.zero;
  bool _touchActive = false;
  double _pixelScale = 1.0; // cached from LayoutBuilder

  // Level complete display timer (frames)
  int _levelCompleteDisplay = 0;
  static const _levelCompleteFrames = 120; // 2 seconds

  // Focus node for keyboard input
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _isTouch = _isTouchPlatform();
    _startNewGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // ─── Game lifecycle ─────────────────────────────────────────────────────────

  void _startNewGame() {
    _timer?.cancel();
    _gd = GameData();
    initEnemyCallbacks();
    levelGenerate(_gd);
    playerInit(_gd);
    _gd.phase = GamePhase.title;
    _levelCompleteDisplay = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  // ─── Touch → joystick vector ─────────────────────────────────────────────

  Offset _getTouchInput() {
    if (!_touchActive) return Offset.zero;
    final rawDx = _touchCurrent.dx - _touchAnchor.dx;
    final rawDy = _touchCurrent.dy - _touchAnchor.dy;
    final wDx = rawDx / _pixelScale;
    final wDy = rawDy / _pixelScale;
    final dist = sqrt(wDx * wDx + wDy * wDy);
    if (dist < 0.5) return Offset.zero;
    final clamped = dist.clamp(0.0, _touchJoyRadius);
    return Offset(wDx / dist * clamped, wDy / dist * clamped);
  }

  bool get _shouldAutoFire {
    if (!_touchActive) return false;
    final p = _gd.player;
    return p.vx.abs() + p.vy.abs() > _autoFireSpeedThreshold;
  }

  // ─── Main tick ──────────────────────────────────────────────────────────────

  void _tick() {
    if (!mounted) return;

    final phase = _gd.phase;

    if (phase == GamePhase.title || phase == GamePhase.gameOver) {
      setState(() {});
      return;
    }

    if (phase == GamePhase.paused) {
      setState(() {});
      return;
    }

    if (phase == GamePhase.levelComplete) {
      _levelCompleteDisplay--;
      if (_levelCompleteDisplay <= 0) {
        levelNext(_gd);
        _levelCompleteDisplay = 0;
      }
      setState(() {});
      return;
    }

    // ── Running ──
    _gd.frameCount++;

    if (_isTouch) {
      // Touch: floating joystick → velocity
      final joy = _getTouchInput();
      final touchDelta = Offset(
        joy.dx * _touchVelScale / 0.14,
        joy.dy * _touchVelScale / 0.14,
      );
      playerUpdate(_gd, touchDelta);
      if (_shouldAutoFire && _gd.player.active) {
        playerFire(_gd);
      }
    } else {
      // Mouse: consume accumulated delta
      final delta = _mouseDelta;
      _mouseDelta = Offset.zero;
      playerUpdate(_gd, delta);
      if (_firePressed && _gd.player.active) {
        playerFire(_gd);
      }
    }

    enemiesUpdate(_gd);
    bulletsUpdate(_gd);
    powerupTick(_gd);
    powerUpDropsUpdate(_gd);
    cameraUpdate(_gd);
    collisionCheckAll(_gd);

    // Spawn enemies
    trySpawnEnemy(_gd);

    // Check level complete (sets gd.phase = levelComplete internally)
    levelCheckComplete(_gd);
    if (_gd.phase == GamePhase.levelComplete && _levelCompleteDisplay == 0) {
      _levelCompleteDisplay = _levelCompleteFrames;
    }

    // Check game over
    if (!_gd.player.active && _gd.phase == GamePhase.running) {
      _gd.phase = GamePhase.gameOver;
    }

    setState(() {});
  }

  // ─── Input ──────────────────────────────────────────────────────────────────

  void _onPointerMove(PointerMoveEvent e) {
    if (_gd.phase != GamePhase.running) return;
    if (_isTouch) {
      if (!_touchActive) return;
      _touchCurrent = e.localPosition;
      final drift = (_touchCurrent - _touchAnchor).distance;
      if (drift > _touchAnchorDriftMax) {
        _touchAnchor = _touchCurrent -
            (_touchCurrent - _touchAnchor) / drift * _touchAnchorDriftMax;
      }
    } else {
      _mouseDelta = Offset(
        _mouseDelta.dx + e.delta.dx,
        _mouseDelta.dy + e.delta.dy,
      );
    }
  }

  void _onPointerHover(PointerHoverEvent e) {
    if (_isTouch || _gd.phase != GamePhase.running) return;
    _mouseDelta = Offset(
      _mouseDelta.dx + e.delta.dx,
      _mouseDelta.dy + e.delta.dy,
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    // Title / Game Over / Paused — tap/click to start/restart/resume
    if (_gd.phase == GamePhase.title) {
      setState(() => _gd.phase = GamePhase.running);
      return;
    }
    if (_gd.phase == GamePhase.gameOver) {
      _startNewGame();
      setState(() => _gd.phase = GamePhase.running);
      return;
    }
    if (_gd.phase == GamePhase.paused) {
      setState(() => _gd.phase = GamePhase.running);
      return;
    }
    if (_gd.phase != GamePhase.running) return;

    if (_isTouch) {
      _touchAnchor = e.localPosition;
      _touchCurrent = e.localPosition;
      _touchActive = true;
    } else {
      if (e.buttons & kPrimaryButton != 0) {
        _firePressed = true;
        playerFire(_gd);
      } else if (e.buttons & kSecondaryButton != 0) {
        smartbombActivate(_gd);
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_isTouch) {
      _touchActive = false;
    } else {
      if (e.buttons & kPrimaryButton == 0) {
        _firePressed = false;
      }
    }
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_gd.phase == GamePhase.running) {
        setState(() => _gd.phase = GamePhase.paused);
      } else if (_gd.phase == GamePhase.paused) {
        setState(() => _gd.phase = GamePhase.running);
      } else {
        widget.onClose();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      if (_gd.phase == GamePhase.running) {
        playerFire(_gd);
      } else if (_gd.phase == GamePhase.title) {
        setState(() => _gd.phase = GamePhase.running);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
      _startNewGame();
      setState(() => _gd.phase = GamePhase.running);
    } else if (event.logicalKey == LogicalKeyboardKey.keyB) {
      if (_gd.phase == GamePhase.running) {
        smartbombActivate(_gd);
      }
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        onPointerMove: _onPointerMove,
        onPointerHover: _onPointerHover,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        child: MouseRegion(
          cursor: _isTouch ? MouseCursor.defer : SystemMouseCursors.none,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewW = constraints.maxWidth;
              final viewH = constraints.maxHeight;
              final scaleX = viewW / worldW;
              final scaleY = viewH / worldH;
              final ps = min(scaleX, scaleY);
              _pixelScale = ps;

              return Stack(
                children: [
                  CustomPaint(
                    size: Size(viewW, viewH),
                    painter: XQuest2Painter(_gd, ps),
                  ),
                  // Touch: smartbomb button
                  if (_isTouch && _gd.phase == GamePhase.running)
                    _smartbombButton(),
                  // Touch: joystick indicator
                  if (_isTouch && _touchActive && _gd.phase == GamePhase.running)
                    _joystickIndicator(),
                  // Overlays
                  if (_gd.phase == GamePhase.title)
                    _titleOverlay(),
                  if (_gd.phase == GamePhase.paused)
                    _pauseOverlay(),
                  if (_gd.phase == GamePhase.gameOver)
                    _gameOverOverlay(),
                  if (_gd.phase == GamePhase.levelComplete)
                    _levelCompleteOverlay(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Touch UI: Smartbomb button ──────────────────────────────────────────

  Widget _smartbombButton() {
    final hasBombs = _gd.player.smartbombs > 0;
    return Positioned(
      top: 8,
      right: 8,
      child: GestureDetector(
        onTap: hasBombs ? () => smartbombActivate(_gd) : null,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border.all(
              color: hasBombs
                  ? const Color(0xFF44AAFF).withValues(alpha: 0.6)
                  : Colors.grey.withValues(alpha: 0.3),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('✦', style: TextStyle(
                color: hasBombs ? const Color(0xFF44AAFF) : Colors.grey,
                fontSize: 18, decoration: TextDecoration.none,
              )),
              Text('${_gd.player.smartbombs}', style: TextStyle(
                color: hasBombs ? Colors.white : Colors.grey,
                fontSize: 11, fontWeight: FontWeight.bold,
                fontFamily: 'monospace', decoration: TextDecoration.none,
              )),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Touch UI: Joystick indicator ──────────────────────────────────────

  Widget _joystickIndicator() {
    const baseR = 40.0;
    const knobR = 14.0;
    final dx = _touchCurrent.dx - _touchAnchor.dx;
    final dy = _touchCurrent.dy - _touchAnchor.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final clampedDist = dist.clamp(0.0, baseR);
    final knobDx = dist < 0.5 ? 0.0 : dx / dist * clampedDist;
    final knobDy = dist < 0.5 ? 0.0 : dy / dist * clampedDist;

    return Positioned(
      left: _touchAnchor.dx - baseR,
      top: _touchAnchor.dy - baseR,
      child: IgnorePointer(
        child: SizedBox(
          width: baseR * 2,
          height: baseR * 2,
          child: CustomPaint(
            painter: _JoystickPainter(knobDx, knobDy, baseR, knobR),
          ),
        ),
      ),
    );
  }

  // ─── Overlays ────────────────────────────────────────────────────────────────

  Widget _overlay(List<Widget> children) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _overlayText(String text, {double size = 22, Color color = Colors.white}) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
        letterSpacing: 2,
        decoration: TextDecoration.none,
      ),
    );
  }

  Widget _titleOverlay() {
    return _overlay([
      _overlayText('XQUEST 2', size: 36, color: const Color(0xFF00C0D1)),
      const SizedBox(height: 12),
      if (_isTouch) ...[
        _overlayText('DRAG TO MOVE', size: 13, color: Colors.white70),
        _overlayText('AUTO-FIRE WHILE MOVING', size: 13, color: Colors.white70),
        _overlayText('✦ BUTTON = SMARTBOMB', size: 13, color: Colors.white70),
      ] else ...[
        _overlayText('MOUSE TO MOVE', size: 13, color: Colors.white70),
        _overlayText('LEFT CLICK = FIRE', size: 13, color: Colors.white70),
        _overlayText('RIGHT CLICK = SMARTBOMB', size: 13, color: Colors.white70),
        _overlayText('ESC = PAUSE   R = RESTART', size: 13, color: Colors.white70),
      ],
      const SizedBox(height: 24),
      _overlayText(
        _isTouch ? 'TAP TO START' : 'CLICK TO START',
        size: 16, color: const Color(0xFFFFCC00),
      ),
    ]);
  }

  Widget _pauseOverlay() {
    return _overlay([
      _overlayText('PAUSED', size: 30, color: const Color(0xFF00C0D1)),
      const SizedBox(height: 16),
      _overlayText(
        _isTouch ? 'TAP TO RESUME' : 'ESC TO RESUME',
        size: 14, color: Colors.white70,
      ),
      if (!_isTouch)
        _overlayText('R TO RESTART', size: 14, color: Colors.white70),
    ]);
  }

  Widget _gameOverOverlay() {
    return _overlay([
      _overlayText('GAME OVER', size: 32, color: const Color(0xFFFF4444)),
      const SizedBox(height: 12),
      _overlayText('SCORE: ${_gd.player.score}', size: 18, color: Colors.white),
      _overlayText('LEVEL: ${_gd.level}', size: 14, color: Colors.white70),
      const SizedBox(height: 24),
      _overlayText(
        _isTouch ? 'TAP TO RESTART' : 'CLICK TO RESTART',
        size: 16, color: const Color(0xFFFFCC00),
      ),
    ]);
  }

  Widget _levelCompleteOverlay() {
    final alpha = (_levelCompleteDisplay / _levelCompleteFrames).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.5 * alpha),
        child: Center(
          child: Opacity(
            opacity: alpha,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _overlayText(
                  'LEVEL ${_gd.level} COMPLETE!',
                  size: 28,
                  color: const Color(0xFF00FF88),
                ),
                if (_gd.lastTimeBonus > 0)
                  _overlayText(
                    'TIME BONUS: +${_gd.lastTimeBonus}',
                    size: 16,
                    color: const Color(0xFFFFCC00),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Joystick painter (touch only) ───────────────────────────────────────────

class _JoystickPainter extends CustomPainter {
  final double knobDx, knobDy, baseR, knobR;
  _JoystickPainter(this.knobDx, this.knobDy, this.baseR, this.knobR);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Base circle
    canvas.drawCircle(center, baseR,
        Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawCircle(center, baseR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
    // Knob
    canvas.drawCircle(center + Offset(knobDx, knobDy), knobR,
        Paint()..color = Colors.white.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.knobDx != knobDx || old.knobDy != knobDy;
}
