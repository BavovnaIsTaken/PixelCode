import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

// ─── Brick types ────────────────────────────────────────────────────────────

const _bEmpty = 0;
const _bNormal = 1;
const _bHard = 2;
const _bCracked = 3; // hard brick after 1 hit
const _bGold = 4;
const _bExplosive = 5;
const _bUnbreakable = 9;

// ─── Constants ──────────────────────────────────────────────────────────────

const _brickCols = 10;
const _brickRows = 6;
const _brickGap = 3.0;
const _paddleH = 10.0;
const _ballR = 5.0;
const _baseBallSpeed = 4.5;
const _bottomPad = 30.0;
const _powerUpSize = 14.0;
const _powerUpFallSpeed = 2.0;
const _powerUpChance = 0.14;

const _rowColors = [
  Color(0xFFFF6B6B),
  Color(0xFFFF9F43),
  Color(0xFFFECA57),
  Color(0xFF48DBFB),
  Color(0xFF00C0D1),
  Color(0xFFA29BFE),
];

// ─── Persistence keys ───────────────────────────────────────────────────────

const _keyLevel = 'arkanoid_level';
const _keyScore = 'arkanoid_score';
const _keyLives = 'arkanoid_lives';
const _keyHighScore = 'arkanoid_high_score';
const _keyBricks = 'arkanoid_bricks';

// ─── Enums & helpers ────────────────────────────────────────────────────────

enum _Phase { waitingLaunch, running, paused, gameOver, won }

enum _PUType { multiBall, widePaddle, extraLife, fireball, slowBall }

class _Ball {
  double x, y, dx, dy;
  _Ball(this.x, this.y, this.dx, this.dy);
}

class _FallingPU {
  double x, y;
  _PUType type;
  _FallingPU(this.x, this.y, this.type);
}

// ─── Level patterns (10×6 = 60 elements each) ──────────────────────────────

const _levelPatterns = <List<int>>[
  // Level 1: Introduction
  [1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   0,0,0,0,0,0,0,0,0,0,
   0,0,0,0,0,0,0,0,0,0],

  // Level 2: Hard top
  [2,2,2,2,2,2,2,2,2,2,
   1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   0,0,0,0,0,0,0,0,0,0],

  // Level 3: Fortress
  [9,2,2,2,2,2,2,2,2,9,
   9,0,1,1,1,1,1,1,0,9,
   9,0,1,4,1,1,4,1,0,9,
   9,0,1,1,1,1,1,1,0,9,
   9,0,1,1,1,1,1,1,0,9,
   9,2,2,2,2,2,2,2,2,9],

  // Level 4: Gold rush
  [4,1,4,1,4,1,4,1,4,1,
   1,4,1,4,1,4,1,4,1,4,
   2,2,2,2,2,2,2,2,2,2,
   1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,
   0,0,0,0,0,0,0,0,0,0],

  // Level 5: Explosions
  [2,1,5,1,2,2,1,5,1,2,
   1,1,1,1,1,1,1,1,1,1,
   1,5,1,1,5,5,1,1,5,1,
   1,1,1,1,1,1,1,1,1,1,
   2,1,5,1,2,2,1,5,1,2,
   0,0,0,0,0,0,0,0,0,0],

  // Level 6: Maze
  [9,0,9,0,9,0,9,0,9,0,
   1,1,1,1,1,1,1,1,1,1,
   0,9,0,9,0,9,0,9,0,9,
   1,1,1,1,1,1,1,1,1,1,
   9,0,9,0,9,0,9,0,9,0,
   2,2,2,2,2,2,2,2,2,2],

  // Level 7: Diamond
  [0,0,0,0,4,4,0,0,0,0,
   0,0,0,2,4,4,2,0,0,0,
   0,0,2,1,5,5,1,2,0,0,
   0,2,1,1,1,1,1,1,2,0,
   2,1,1,1,1,1,1,1,1,2,
   1,1,1,4,1,1,4,1,1,1],

  // Level 8: Ultimate
  [9,2,2,4,9,9,4,2,2,9,
   2,5,2,2,4,4,2,2,5,2,
   2,2,1,1,2,2,1,1,2,2,
   4,2,1,5,1,1,5,1,2,4,
   2,2,1,1,1,1,1,1,2,2,
   9,2,2,2,4,4,2,2,2,9],
];

// ─── Widget ─────────────────────────────────────────────────────────────────

class ArkanoidGame extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const ArkanoidGame({super.key, required this.onClose});

  @override
  ConsumerState<ArkanoidGame> createState() => _ArkanoidGameState();
}

class _ArkanoidGameState extends ConsumerState<ArkanoidGame> {
  // Layout (recalculated each build)
  double _gameW = 400, _gameH = 500;
  double _brickW = 36, _brickH = 14, _brickTop = 50;
  double _paddleW = 64;
  bool _layoutReady = false;

  // Game state
  var _phase = _Phase.waitingLaunch;
  var _bricks = <int>[];
  var _balls = <_Ball>[];
  final _fallingPUs = <_FallingPU>[];
  double _paddleX = 0;
  int _level = 1;
  int _score = 0;
  int _lives = 3;
  int _highScore = 0;

  // Power-up timers (ticks at ~60 fps)
  int _widePaddleTicks = 0;
  int _fireballTicks = 0;
  int _slowBallTicks = 0;

  Timer? _ticker;
  final _focusNode = FocusNode();
  final _rng = Random();

  // ── Computed ────────────────────────────────────────────────────────────

  double get _brickLeft =>
      (_gameW - (_brickCols * (_brickW + _brickGap) - _brickGap)) / 2;
  double get _effectivePaddleW =>
      _widePaddleTicks > 0 ? _paddleW * 1.5 : _paddleW;
  double get _effectiveSpeed =>
      _slowBallTicks > 0 ? _baseBallSpeed * 0.6 : _baseBallSpeed;
  bool get _isFireball => _fireballTicks > 0;
  bool get _allCleared =>
      !_bricks.any((b) => b != _bEmpty && b != _bUnbreakable);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadGame();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  void _loadGame() {
    final prefs = ref.read(sharedPrefsProvider);
    _highScore = prefs.getInt(_keyHighScore) ?? 0;

    final savedLevel = prefs.getInt(_keyLevel);
    if (savedLevel != null) {
      _level = savedLevel;
      _score = prefs.getInt(_keyScore) ?? 0;
      _lives = prefs.getInt(_keyLives) ?? 3;
      final bricksJson = prefs.getString(_keyBricks);
      if (bricksJson != null) {
        try {
          final loaded = List<int>.from(jsonDecode(bricksJson));
          _bricks = loaded.length == _brickCols * _brickRows
              ? loaded
              : _generateBricks();
        } catch (_) {
          _bricks = _generateBricks();
        }
      } else {
        _bricks = _generateBricks();
      }
    } else {
      _level = 1;
      _score = 0;
      _lives = 3;
      _bricks = _generateBricks();
    }
  }

  Future<void> _saveGame() async {
    final prefs = ref.read(sharedPrefsProvider);
    await Future.wait([
      prefs.setInt(_keyLevel, _level),
      prefs.setInt(_keyScore, _score),
      prefs.setInt(_keyLives, _lives),
      prefs.setString(_keyBricks, jsonEncode(_bricks)),
    ]);
    if (_score > _highScore) {
      _highScore = _score;
      await prefs.setInt(_keyHighScore, _highScore);
    }
  }

  Future<void> _clearSave() async {
    final prefs = ref.read(sharedPrefsProvider);
    await Future.wait([
      prefs.remove(_keyLevel),
      prefs.remove(_keyScore),
      prefs.remove(_keyLives),
      prefs.remove(_keyBricks),
    ]);
  }

  // ── Level generation ────────────────────────────────────────────────────

  List<int> _generateBricks() {
    final patIdx = (_level - 1) % _levelPatterns.length;
    final loop = (_level - 1) ~/ _levelPatterns.length;
    final pattern = List<int>.from(_levelPatterns[patIdx]);

    // Difficulty scaling on subsequent loops
    if (loop >= 1) {
      for (var i = 0; i < pattern.length; i++) {
        if (pattern[i] == _bNormal) {
          if (loop >= 2 || _rng.nextBool()) {
            pattern[i] = _bHard;
          }
        }
      }
    }
    return pattern;
  }

  // ── Layout ──────────────────────────────────────────────────────────────

  void _applyLayout(double w, double h) {
    _gameW = w;
    _gameH = h;
    _brickW = (w - _brickGap * (_brickCols + 1)) / _brickCols;
    _brickH = (_brickW * 0.4).clamp(10.0, 16.0);
    _brickTop = h * 0.08;
    _paddleW = (w * 0.18).clamp(50.0, 80.0);
    if (!_layoutReady) {
      _paddleX = (w - _effectivePaddleW) / 2;
      _resetBallPosition();
      _layoutReady = true;
    }
  }

  // ── Game flow ───────────────────────────────────────────────────────────

  void _resetBallPosition() {
    _balls = [
      _Ball(
        _paddleX + _effectivePaddleW / 2,
        _gameH - 60,
        _baseBallSpeed * 0.7,
        -_baseBallSpeed,
      ),
    ];
    _fallingPUs.clear();
    _widePaddleTicks = 0;
    _fireballTicks = 0;
    _slowBallTicks = 0;
  }

  void _launchBall() {
    if (_phase != _Phase.waitingLaunch) return;
    _phase = _Phase.running;
    final angle = -pi / 2 + (_rng.nextDouble() - 0.5) * 0.8;
    _balls.first
      ..dx = _baseBallSpeed * cos(angle)
      ..dy = _baseBallSpeed * sin(angle);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _pause() {
    if (_phase != _Phase.running) return;
    _phase = _Phase.paused;
    _ticker?.cancel();
    _saveGame();
  }

  void _resume() {
    if (_phase != _Phase.paused) return;
    _phase = _Phase.running;
    _startTicker();
  }

  void _loseLife() {
    _lives--;
    if (_lives <= 0) {
      _phase = _Phase.gameOver;
      _ticker?.cancel();
      if (_score > _highScore) {
        _highScore = _score;
        ref.read(sharedPrefsProvider).setInt(_keyHighScore, _highScore);
      }
      _clearSave();
    } else {
      _phase = _Phase.waitingLaunch;
      _ticker?.cancel();
      _resetBallPosition();
      _saveGame();
    }
  }

  void _winLevel() {
    _phase = _Phase.won;
    _ticker?.cancel();
    _saveGame();
  }

  void _nextLevel() {
    setState(() {
      _level++;
      _bricks = _generateBricks();
      _phase = _Phase.waitingLaunch;
      _resetBallPosition();
      _saveGame();
    });
  }

  void _restart() {
    setState(() {
      _level = 1;
      _score = 0;
      _lives = 3;
      _bricks = _generateBricks();
      _phase = _Phase.waitingLaunch;
      _resetBallPosition();
      _clearSave();
    });
  }

  void _onClose() {
    if (_phase == _Phase.running) _ticker?.cancel();
    _saveGame();
    widget.onClose();
  }

  // ── Tap / keyboard ─────────────────────────────────────────────────────

  void _onTap() {
    setState(() {
      switch (_phase) {
        case _Phase.waitingLaunch:
          _launchBall();
        case _Phase.running:
          _pause();
        case _Phase.paused:
          _resume();
        case _Phase.gameOver:
          _restart();
        case _Phase.won:
          _nextLevel();
      }
    });
  }

  // ── Game loop ───────────────────────────────────────────────────────────

  void _tick() {
    if (!mounted || _phase != _Phase.running) return;
    setState(() {
      if (_widePaddleTicks > 0) _widePaddleTicks--;
      if (_fireballTicks > 0) _fireballTicks--;
      if (_slowBallTicks > 0) _slowBallTicks--;

      final speed = _effectiveSpeed;
      final pw = _effectivePaddleW;
      final paddleTop = _gameH - _bottomPad - _paddleH;

      // ── Falling power-ups ──
      _fallingPUs.removeWhere((pu) {
        pu.y += _powerUpFallSpeed;
        if (pu.y + _powerUpSize / 2 >= paddleTop &&
            pu.y - _powerUpSize / 2 <= paddleTop + _paddleH + 4 &&
            pu.x >= _paddleX &&
            pu.x <= _paddleX + pw) {
          _collectPowerUp(pu.type);
          return true;
        }
        return pu.y > _gameH;
      });

      // ── Balls ──
      final ballsToRemove = <int>[];
      for (var bi = 0; bi < _balls.length; bi++) {
        final ball = _balls[bi];

        // Normalize to effective speed
        final mag = sqrt(ball.dx * ball.dx + ball.dy * ball.dy);
        if (mag > 0) {
          ball.dx = ball.dx / mag * speed;
          ball.dy = ball.dy / mag * speed;
        }

        ball.x += ball.dx;
        ball.y += ball.dy;

        // Wall collisions
        if (ball.x - _ballR <= 0) {
          ball.x = _ballR;
          ball.dx = ball.dx.abs();
        }
        if (ball.x + _ballR >= _gameW) {
          ball.x = _gameW - _ballR;
          ball.dx = -ball.dx.abs();
        }
        if (ball.y - _ballR <= 0) {
          ball.y = _ballR;
          ball.dy = ball.dy.abs();
        }

        // Fell below
        if (ball.y + _ballR >= _gameH) {
          ballsToRemove.add(bi);
          continue;
        }

        // Paddle collision
        if (ball.dy > 0 &&
            ball.y + _ballR >= paddleTop &&
            ball.y + _ballR <= paddleTop + _paddleH + 4 &&
            ball.x >= _paddleX &&
            ball.x <= _paddleX + pw) {
          ball.y = paddleTop - _ballR;
          final hit = (ball.x - _paddleX) / pw;
          final angle = -pi / 2 + (hit - 0.5) * 1.2;
          ball.dx = speed * cos(angle);
          ball.dy = speed * sin(angle);
          if (ball.dy > -1.0) ball.dy = -1.0;
        }

        // Brick collisions
        bool hitBrick = false;
        for (var row = 0; row < _brickRows && !hitBrick; row++) {
          for (var col = 0; col < _brickCols; col++) {
            final idx = row * _brickCols + col;
            if (_bricks[idx] == _bEmpty) continue;
            final bx = _brickLeft + col * (_brickW + _brickGap);
            final by = _brickTop + row * (_brickH + _brickGap);
            if (ball.x + _ballR >= bx &&
                ball.x - _ballR <= bx + _brickW &&
                ball.y + _ballR >= by &&
                ball.y - _ballR <= by + _brickH) {
              _hitBrick(idx);

              if (!_isFireball) {
                // Bounce direction
                final cx = ball.x - (bx + _brickW / 2);
                final cy = ball.y - (by + _brickH / 2);
                if (cx.abs() / _brickW > cy.abs() / _brickH) {
                  ball.dx = -ball.dx;
                } else {
                  ball.dy = -ball.dy;
                }
                hitBrick = true;
                break;
              }
              // Fireball: pass through, keep checking
            }
          }
        }

        if (_allCleared) {
          _winLevel();
          return;
        }
      }

      // Remove fallen balls (reverse order to keep indices valid)
      for (final bi in ballsToRemove.reversed) {
        _balls.removeAt(bi);
      }

      if (_balls.isEmpty) {
        _loseLife();
      }
    });
  }

  // ── Brick logic ─────────────────────────────────────────────────────────

  void _hitBrick(int idx, {bool isExplosion = false}) {
    final type = _bricks[idx];
    if (type == _bEmpty || type == _bUnbreakable) return;

    // Hard brick cracks first (unless explosion)
    if (type == _bHard && !isExplosion) {
      _bricks[idx] = _bCracked;
      return;
    }

    _bricks[idx] = _bEmpty;
    _score += _brickPoints(type);
    _maybeDropPowerUp(idx);

    if (type == _bExplosive) {
      _explodeNeighbors(idx);
    }
  }

  void _explodeNeighbors(int center) {
    final row = center ~/ _brickCols;
    final col = center % _brickCols;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = row + dr, nc = col + dc;
        if (nr >= 0 && nr < _brickRows && nc >= 0 && nc < _brickCols) {
          final ni = nr * _brickCols + nc;
          if (_bricks[ni] != _bEmpty && _bricks[ni] != _bUnbreakable) {
            _hitBrick(ni, isExplosion: true);
          }
        }
      }
    }
  }

  int _brickPoints(int type) => switch (type) {
        _bNormal => 10,
        _bHard || _bCracked => 20,
        _bGold => 50,
        _bExplosive => 10,
        _ => 0,
      };

  // ── Power-ups ───────────────────────────────────────────────────────────

  void _maybeDropPowerUp(int brickIdx) {
    if (_rng.nextDouble() > _powerUpChance) return;
    final col = brickIdx % _brickCols;
    final row = brickIdx ~/ _brickCols;
    final x = _brickLeft + col * (_brickW + _brickGap) + _brickW / 2;
    final y = _brickTop + row * (_brickH + _brickGap) + _brickH / 2;

    final roll = _rng.nextDouble();
    final type = roll < 0.20
        ? _PUType.multiBall
        : roll < 0.45
            ? _PUType.widePaddle
            : roll < 0.55
                ? _PUType.extraLife
                : roll < 0.75
                    ? _PUType.fireball
                    : _PUType.slowBall;

    _fallingPUs.add(_FallingPU(x, y, type));
  }

  void _collectPowerUp(_PUType type) {
    switch (type) {
      case _PUType.multiBall:
        if (_balls.isNotEmpty && _balls.length < 10) {
          final src = _balls.first;
          final s = _effectiveSpeed;
          _balls.add(_Ball(src.x, src.y, s * cos(-pi / 2 + 0.4),
              s * sin(-pi / 2 + 0.4)));
          _balls.add(_Ball(src.x, src.y, s * cos(-pi / 2 - 0.4),
              s * sin(-pi / 2 - 0.4)));
        }
      case _PUType.widePaddle:
        _widePaddleTicks = 625; // ~10s
      case _PUType.extraLife:
        _lives++;
      case _PUType.fireball:
        _fireballTicks = 500; // ~8s
      case _PUType.slowBall:
        _slowBallTicks = 500; // ~8s
    }
  }

  // ── Input ───────────────────────────────────────────────────────────────

  void _movePaddle(double localX) {
    setState(() {
      _paddleX =
          (localX - _effectivePaddleW / 2).clamp(0, _gameW - _effectivePaddleW);
      if (_phase == _Phase.waitingLaunch && _balls.isNotEmpty) {
        _balls.first.x = _paddleX + _effectivePaddleW / 2;
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showButton = ref.watch(settingsProvider).showArkanoidButton;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.escape) _onClose();
          if (e.logicalKey == LogicalKeyboardKey.keyR &&
              _phase == _Phase.paused) {
            setState(() => _restart());
          }
        }
      },
      child: Container(
        color: const Color(0xFF0E0E11),
        child: Column(
          children: [
            _buildHeader(showButton),
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                _applyLayout(constraints.maxWidth, constraints.maxHeight);
                return MouseRegion(
                  onHover: (e) => _movePaddle(e.localPosition.dx),
                  child: GestureDetector(
                    onPanUpdate: (d) => _movePaddle(d.localPosition.dx),
                    onTap: _onTap,
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _ArkanoidPainter(
                        bricks: _bricks,
                        brickW: _brickW,
                        brickH: _brickH,
                        brickTop: _brickTop,
                        brickLeft: _brickLeft,
                        paddleX: _paddleX,
                        paddleW: _effectivePaddleW,
                        bottomPad: _bottomPad,
                        balls: _balls,
                        fallingPUs: _fallingPUs,
                        phase: _phase,
                        isFireball: _isFireball,
                        isWidePaddle: _widePaddleTicks > 0,
                        score: _score,
                        highScore: _highScore,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool showButton) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'ARKANOID',
            style: TextStyle(
              color: Color(0xFF00C0D1),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Pin toggle — show game button on menu bar
          Tooltip(
            message: showButton ? 'Сховати з панелі' : 'Показати на панелі',
            child: InkWell(
              onTap: () => ref
                  .read(settingsProvider.notifier)
                  .setShowArkanoidButton(!showButton),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  showButton ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 12,
                  color: showButton
                      ? const Color(0xFF00C0D1)
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 14,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(width: 8),
          Text(
            'Lvl $_level',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          // Active power-up indicators
          if (_widePaddleTicks > 0)
            _puIndicator('W', const Color(0xFF66BB6A)),
          if (_fireballTicks > 0)
            _puIndicator('F', const Color(0xFFFF9800)),
          if (_slowBallTicks > 0)
            _puIndicator('S', const Color(0xFF4FC3F7)),
          if (_balls.length > 1)
            _puIndicator('\u00d7${_balls.length}', const Color(0xFFA29BFE)),
          const SizedBox(width: 4),
          for (var i = 0; i < _lives; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B6B),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '$_score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          if (_highScore > 0) ...[
            const SizedBox(width: 6),
            Text(
              '\u2605$_highScore',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(width: 8),
          InkWell(
            onTap: _onClose,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _puIndicator(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

// ─── Painter ────────────────────────────────────────────────────────────────

class _ArkanoidPainter extends CustomPainter {
  final List<int> bricks;
  final double brickW, brickH, brickTop, brickLeft;
  final double paddleX, paddleW, bottomPad;
  final List<_Ball> balls;
  final List<_FallingPU> fallingPUs;
  final _Phase phase;
  final bool isFireball, isWidePaddle;
  final int score, highScore;

  _ArkanoidPainter({
    required this.bricks,
    required this.brickW,
    required this.brickH,
    required this.brickTop,
    required this.brickLeft,
    required this.paddleX,
    required this.paddleW,
    required this.bottomPad,
    required this.balls,
    required this.fallingPUs,
    required this.phase,
    required this.isFireball,
    required this.isWidePaddle,
    required this.score,
    required this.highScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawBricks(canvas);
    _drawFallingPowerUps(canvas);
    _drawPaddle(canvas, size);
    _drawBalls(canvas);
    _drawOverlay(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.03);
    for (var x = 0.0; x < size.width; x += 20) {
      for (var y = 0.0; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
  }

  void _drawBricks(Canvas canvas) {
    for (var row = 0; row < _brickRows; row++) {
      for (var col = 0; col < _brickCols; col++) {
        final type = bricks[row * _brickCols + col];
        if (type == _bEmpty) continue;

        final x = brickLeft + col * (brickW + _brickGap);
        final y = brickTop + row * (brickH + _brickGap);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, brickW, brickH),
          const Radius.circular(2),
        );

        final Color color;
        switch (type) {
          case _bNormal:
            color = _rowColors[row % _rowColors.length];
          case _bHard:
            color = const Color(0xFF5C6370);
          case _bCracked:
            color = const Color(0xFF5C6370);
          case _bGold:
            color = const Color(0xFFFFD700);
          case _bExplosive:
            color = const Color(0xFFFF4500);
          case _bUnbreakable:
            color = const Color(0xFF9EA0A5);
          default:
            color = Colors.white;
        }

        canvas.drawRRect(rect, Paint()..color = color);

        // Highlight strip
        canvas.drawRect(
          Rect.fromLTWH(x + 2, y + 1, brickW - 4, 2),
          Paint()
            ..color = Colors.white
                .withValues(alpha: type == _bUnbreakable ? 0.5 : 0.3),
        );

        // Crack lines
        if (type == _bCracked) {
          final cp = Paint()
            ..color = Colors.black.withValues(alpha: 0.6)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
          canvas.drawLine(
            Offset(x + brickW * 0.3, y),
            Offset(x + brickW * 0.6, y + brickH),
            cp,
          );
          canvas.drawLine(
            Offset(x + brickW * 0.7, y + brickH * 0.2),
            Offset(x + brickW * 0.4, y + brickH * 0.8),
            cp,
          );
        }

        // Gold sparkle
        if (type == _bGold) {
          canvas.drawRect(
            Rect.fromLTWH(x + brickW * 0.4, y + 1, brickW * 0.2, 2),
            Paint()..color = Colors.white.withValues(alpha: 0.6),
          );
        }

        // Explosive mark
        if (type == _bExplosive) {
          final tp = TextPainter(
            text: const TextSpan(
              text: '!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(
              x + (brickW - tp.width) / 2,
              y + (brickH - tp.height) / 2,
            ),
          );
        }

        // Unbreakable border
        if (type == _bUnbreakable) {
          canvas.drawRRect(
            rect,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
      }
    }
  }

  void _drawPaddle(Canvas canvas, Size size) {
    final color =
        isWidePaddle ? const Color(0xFF66BB6A) : const Color(0xFF00C0D1);
    final paddleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        paddleX,
        size.height - bottomPad - _paddleH,
        paddleW,
        _paddleH,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(paddleRect, Paint()..color = color);
    canvas.drawRRect(
      paddleRect,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }

  void _drawBalls(Canvas canvas) {
    for (final ball in balls) {
      final color = isFireball ? const Color(0xFFFF9800) : Colors.white;
      canvas.drawCircle(Offset(ball.x, ball.y), _ballR, Paint()..color = color);
      canvas.drawCircle(
        Offset(ball.x, ball.y),
        _ballR + 2,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _drawFallingPowerUps(Canvas canvas) {
    for (final pu in fallingPUs) {
      final Color color;
      final String letter;
      switch (pu.type) {
        case _PUType.multiBall:
          color = const Color(0xFFA29BFE);
          letter = 'M';
        case _PUType.widePaddle:
          color = const Color(0xFF66BB6A);
          letter = 'W';
        case _PUType.extraLife:
          color = const Color(0xFFFF6B6B);
          letter = '+';
        case _PUType.fireball:
          color = const Color(0xFFFF9800);
          letter = 'F';
        case _PUType.slowBall:
          color = const Color(0xFF4FC3F7);
          letter = 'S';
      }

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(pu.x, pu.y),
          width: _powerUpSize,
          height: _powerUpSize,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.8));
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(pu.x - tp.width / 2, pu.y - tp.height / 2),
      );
    }
  }

  void _drawOverlay(Canvas canvas, Size size) {
    if (phase == _Phase.running) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    final cy = size.height / 2;

    switch (phase) {
      case _Phase.waitingLaunch:
        _drawText(canvas, size.width, cy - 12, 'CLICK TO LAUNCH', 24,
            Colors.white);
        _drawText(canvas, size.width, cy + 20, 'Move mouse to aim', 11,
            Colors.white.withValues(alpha: 0.5));
      case _Phase.paused:
        _drawText(
            canvas, size.width, cy - 12, 'PAUSED', 24, Colors.white);
        _drawText(
            canvas,
            size.width,
            cy + 20,
            'Click to resume \u00b7 R to restart',
            11,
            Colors.white.withValues(alpha: 0.5));
      case _Phase.gameOver:
        _drawText(
            canvas, size.width, cy - 24, 'GAME OVER', 24, Colors.white);
        final sub = 'Score: $score${highScore > 0 ? '  Best: $highScore' : ''}';
        _drawText(canvas, size.width, cy + 12, sub, 12,
            Colors.white.withValues(alpha: 0.7));
        _drawText(canvas, size.width, cy + 34, 'Click to restart', 11,
            Colors.white.withValues(alpha: 0.5));
      case _Phase.won:
        _drawText(canvas, size.width, cy - 24, 'LEVEL COMPLETE!', 24,
            Colors.white);
        _drawText(canvas, size.width, cy + 12, 'Score: $score', 12,
            Colors.white.withValues(alpha: 0.7));
        _drawText(canvas, size.width, cy + 34, 'Click for next level', 11,
            Colors.white.withValues(alpha: 0.5));
      case _Phase.running:
        break;
    }
  }

  void _drawText(Canvas canvas, double width, double y, String text,
      double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: fontSize > 15 ? 3 : 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((width - tp.width) / 2, y));
  }

  @override
  bool shouldRepaint(covariant _ArkanoidPainter old) => true;
}
