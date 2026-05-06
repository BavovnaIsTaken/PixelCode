import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

// ─── Brick types ─────────────────────────────────────────────────────────────

const _bEmpty = 0;
const _bNormal = 1; // 1 hit, coloured by row
const _bGlass = 2; // 2 hits (cracks first)
const _bCracked = 3; // glass after 1st hit
const _bGold = 4; // 1 hit, extra points
const _bBlast = 5; // 1 hit, chain-explodes neighbours
const _bSteel = 9; // indestructible

// ─── Constants ───────────────────────────────────────────────────────────────

const _brickCols = 13;
const _brickRows = 8;
const _brickGap = 2.0;
const _paddleH = 11.0;
const _ballR = 5.5;
const _baseBallSpeed = 4.2;
const _bottomPad = 28.0;
const _puW = 34.0;
const _puH = 13.0;
const _puFallSpeed = 1.8;
const _puChance = 0.20;
const _laserSpeed = 9.0;
const _laserFireInterval = 28; // ticks between auto-shots

// ─── Persistence keys ────────────────────────────────────────────────────────

const _keyLevel = 'arkanoid_level';
const _keyScore = 'arkanoid_score';
const _keyLives = 'arkanoid_lives';
const _keyHighScore = 'arkanoid_high_score';
const _keyBricks = 'arkanoid_bricks';

// ─── Enums / data classes ────────────────────────────────────────────────────

enum _Phase { waitingLaunch, running, paused, gameOver, won }

enum _PUType { expand, multiball, sticky, laser, thru, life, slow, blast }

class _Ball {
  double x, y, dx, dy;
  bool stuck;
  double stuckOffsetX = 0;
  _Ball(this.x, this.y, this.dx, this.dy, {this.stuck = false});
}

class _FallingPU {
  double x, y;
  _PUType type;
  _FallingPU(this.x, this.y, this.type);
}

class _Bullet {
  double x, y;
  _Bullet(this.x, this.y);
}

// ─── Level patterns (13 × 8 = 104 elements each) ─────────────────────────────
// 0=empty  1=normal  2=glass  4=gold  5=blast  9=steel

const _levelPatterns = <List<int>>[
  // Level 1 – Warm-up
  [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 2 – Checkerboard
  [
    1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0,
    1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0,
    1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0,
    1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 3 – Pyramid
  [
    0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 1, 1, 2, 1, 1, 0, 0, 0, 0,
    0, 0, 0, 1, 1, 2, 4, 2, 1, 1, 0, 0, 0,
    0, 0, 1, 1, 1, 2, 4, 2, 1, 1, 1, 0, 0,
    0, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 4 – Fortress
  [
    9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
    9, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 9,
    9, 0, 0, 1, 1, 2, 2, 2, 1, 1, 0, 0, 9,
    9, 0, 1, 2, 2, 4, 4, 4, 2, 2, 1, 0, 9,
    9, 0, 1, 2, 2, 4, 9, 4, 2, 2, 1, 0, 9,
    9, 0, 0, 1, 1, 2, 2, 2, 1, 1, 0, 0, 9,
    9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 5 – Blast zone
  [
    1, 1, 5, 1, 1, 1, 1, 1, 1, 1, 5, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    5, 1, 1, 1, 5, 1, 5, 1, 5, 1, 1, 1, 5,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 5, 1, 1, 5, 1, 5, 1, 1, 5, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    5, 1, 1, 5, 1, 1, 1, 1, 1, 5, 1, 1, 5,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 6 – Cross
  [
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 0, 0, 0, 0, 2, 0, 2, 0, 0, 0, 0, 1,
    1, 0, 9, 0, 0, 2, 0, 2, 0, 0, 9, 0, 1,
    1, 1, 1, 1, 1, 2, 4, 2, 1, 1, 1, 1, 1,
    1, 0, 9, 0, 0, 2, 4, 2, 0, 0, 9, 0, 1,
    1, 0, 0, 0, 0, 2, 0, 2, 0, 0, 0, 0, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 7 – Zigzag
  [
    1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
    0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0,
    0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0,
    2, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 2,
    2, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 2,
    0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0,
    0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 0,
    1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
  ],

  // Level 8 – Gold rush
  [
    4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4,
    1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4,
    1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1, 4, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 9 – Diamond
  [
    0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 4, 1, 4, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 4, 1, 2, 1, 4, 0, 0, 0, 0,
    0, 0, 0, 4, 1, 2, 4, 2, 1, 4, 0, 0, 0,
    0, 0, 4, 1, 2, 4, 9, 4, 2, 1, 4, 0, 0,
    0, 0, 0, 4, 1, 2, 4, 2, 1, 4, 0, 0, 0,
    0, 0, 0, 0, 4, 1, 2, 1, 4, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 4, 1, 4, 0, 0, 0, 0, 0,
  ],

  // Level 10 – Double fort
  [
    9, 1, 1, 1, 9, 0, 0, 0, 9, 1, 1, 1, 9,
    1, 2, 2, 2, 1, 0, 0, 0, 1, 2, 2, 2, 1,
    1, 2, 4, 2, 1, 0, 0, 0, 1, 2, 4, 2, 1,
    1, 2, 2, 2, 1, 0, 0, 0, 1, 2, 2, 2, 1,
    9, 1, 1, 1, 9, 0, 0, 0, 9, 1, 1, 1, 9,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 11 – Columns
  [
    1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1,
    2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2,
    2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2,
    4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4,
    4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4, 0, 4,
    9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],

  // Level 12 – Chaos
  [
    9, 2, 5, 1, 9, 4, 1, 4, 9, 1, 5, 2, 9,
    2, 1, 2, 5, 2, 1, 2, 1, 2, 5, 2, 1, 2,
    5, 2, 1, 2, 1, 5, 4, 5, 1, 2, 1, 2, 5,
    4, 1, 5, 1, 4, 2, 9, 2, 4, 1, 5, 1, 4,
    5, 2, 1, 2, 1, 5, 4, 5, 1, 2, 1, 2, 5,
    2, 1, 2, 5, 2, 1, 2, 1, 2, 5, 2, 1, 2,
    9, 2, 5, 1, 9, 4, 1, 4, 9, 1, 5, 2, 9,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ],
];

// ─── Widget ──────────────────────────────────────────────────────────────────

class ArkanoidGame extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const ArkanoidGame({super.key, required this.onClose});

  @override
  ConsumerState<ArkanoidGame> createState() => _ArkanoidGameState();
}

class _ArkanoidGameState extends ConsumerState<ArkanoidGame> {
  // Layout
  double _gameW = 400, _gameH = 500;
  double _brickW = 28, _brickH = 13, _brickTop = 50;
  double _paddleW = 64;
  bool _layoutReady = false;

  // Game state
  var _phase = _Phase.waitingLaunch;
  var _bricks = <int>[];
  // Per-brick hit-flash counter: brightens brick for ~6 ticks after a hit
  // to replace the bevel-flash feedback we lose by dropping DX-Ball gloss.
  var _brickFlash = <int>[];
  var _balls = <_Ball>[];
  final _fallingPUs = <_FallingPU>[];
  final _bullets = <_Bullet>[];
  double _paddleX = 0;
  int _level = 1;
  int _score = 0;
  int _lives = 3;
  int _highScore = 0;

  // Power-up timers (ticks at ~60 fps)
  int _expandTicks = 0;
  int _stickyTicks = 0;
  int _laserTicks = 0;
  int _thruTicks = 0;
  int _slowTicks = 0;
  int _blastTicks = 0;
  int _laserCooldown = 0;

  Timer? _ticker;
  final _focusNode = FocusNode();
  final _rng = Random();

  // ── Computed ─────────────────────────────────────────────────────────────

  double get _brickLeft =>
      (_gameW - (_brickCols * (_brickW + _brickGap) - _brickGap)) / 2;
  double get _effectivePaddleW =>
      _expandTicks > 0 ? _paddleW * 1.6 : _paddleW;
  double get _effectiveSpeed =>
      _slowTicks > 0 ? _baseBallSpeed * 0.58 : _baseBallSpeed;
  bool get _isBlast => _blastTicks > 0;
  bool get _isThru => _thruTicks > 0;
  bool get _isSticky => _stickyTicks > 0;
  bool get _isLaser => _laserTicks > 0;
  bool get _allCleared =>
      !_bricks.any((b) => b != _bEmpty && b != _bSteel);

  // ── Lifecycle ────────────────────────────────────────────────────────────

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

  // ── Persistence ──────────────────────────────────────────────────────────

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
    _brickFlash = List<int>.filled(_bricks.length, 0);
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

  // ── Level generation ─────────────────────────────────────────────────────

  List<int> _generateBricks() {
    final patIdx = (_level - 1) % _levelPatterns.length;
    final loop = (_level - 1) ~/ _levelPatterns.length;
    final pattern = List<int>.from(_levelPatterns[patIdx]);

    if (loop >= 1) {
      for (var i = 0; i < pattern.length; i++) {
        if (pattern[i] == _bNormal && (loop >= 2 || _rng.nextBool())) {
          pattern[i] = _bGlass;
        }
      }
    }
    return pattern;
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  void _applyLayout(double w, double h) {
    _gameW = w;
    _gameH = h;
    _brickW = (w - _brickGap * (_brickCols + 1)) / _brickCols;
    _brickH = _brickW * 0.5;
    _brickTop = h * 0.07;
    _paddleW = (w * 0.20).clamp(52.0, 88.0);
    if (!_layoutReady) {
      _paddleX = (w - _effectivePaddleW) / 2;
      _resetBallPosition();
      _layoutReady = true;
    }
  }

  // ── Game flow ────────────────────────────────────────────────────────────

  void _resetBallPosition() {
    _balls = [
      _Ball(
        _paddleX + _effectivePaddleW / 2,
        _gameH - _bottomPad - _paddleH - _ballR - 1,
        0,
        0,
        stuck: false,
      ),
    ];
    _fallingPUs.clear();
    _bullets.clear();
    _expandTicks = 0;
    _stickyTicks = 0;
    _laserTicks = 0;
    _thruTicks = 0;
    _slowTicks = 0;
    _blastTicks = 0;
    _laserCooldown = 0;
  }

  void _launchBalls() {
    if (_phase != _Phase.waitingLaunch) return;
    _phase = _Phase.running;
    final angle = -pi / 2 + (_rng.nextDouble() - 0.5) * 0.7;
    final spd = _baseBallSpeed;
    _balls.first
      ..dx = spd * cos(angle)
      ..dy = spd * sin(angle)
      ..stuck = false;
    _startTicker();
  }

  void _releaseStuckBalls() {
    final pw = _effectivePaddleW;
    for (final ball in _balls) {
      if (!ball.stuck) continue;
      ball.stuck = false;
      final hitPos = ((ball.x - _paddleX) / pw).clamp(0.0, 1.0);
      final angle = -pi / 2 + (hitPos - 0.5) * 1.2;
      final spd = _effectiveSpeed;
      ball.dx = spd * cos(angle);
      ball.dy = spd * sin(angle);
      if (ball.dy > -1.0) ball.dy = -1.0;
    }
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
      _brickFlash = List<int>.filled(_bricks.length, 0);
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
      _brickFlash = List<int>.filled(_bricks.length, 0);
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

  // ── Input ────────────────────────────────────────────────────────────────

  void _onTap() {
    setState(() {
      switch (_phase) {
        case _Phase.waitingLaunch:
          _launchBalls();
        case _Phase.running:
          final hasStuck = _balls.any((b) => b.stuck);
          if (hasStuck) {
            _releaseStuckBalls();
          } else {
            _pause();
          }
        case _Phase.paused:
          _resume();
        case _Phase.gameOver:
          _restart();
        case _Phase.won:
          _nextLevel();
      }
    });
  }

  void _movePaddle(double localX) {
    setState(() {
      _paddleX =
          (localX - _effectivePaddleW / 2).clamp(0, _gameW - _effectivePaddleW);
      if (_phase == _Phase.waitingLaunch && _balls.isNotEmpty) {
        _balls.first.x = _paddleX + _effectivePaddleW / 2;
      }
      for (final ball in _balls) {
        if (ball.stuck) {
          ball.x = (_paddleX + _effectivePaddleW / 2 + ball.stuckOffsetX)
              .clamp(_ballR, _gameW - _ballR);
        }
      }
    });
  }

  // ── Game loop ────────────────────────────────────────────────────────────

  void _tick() {
    if (!mounted || _phase != _Phase.running) return;
    setState(() {
      if (_expandTicks > 0) _expandTicks--;
      if (_stickyTicks > 0) _stickyTicks--;
      if (_laserTicks > 0) {
        _laserTicks--;
        if (_laserCooldown > 0) {
          _laserCooldown--;
        } else {
          _fireLaser();
          _laserCooldown = _laserFireInterval;
        }
      }
      if (_thruTicks > 0) _thruTicks--;
      if (_slowTicks > 0) _slowTicks--;
      if (_blastTicks > 0) _blastTicks--;

      for (var i = 0; i < _brickFlash.length; i++) {
        if (_brickFlash[i] > 0) _brickFlash[i]--;
      }

      final speed = _effectiveSpeed;
      final pw = _effectivePaddleW;
      final paddleTop = _gameH - _bottomPad - _paddleH;

      // ── Laser bullets ──
      _bullets.removeWhere((bullet) {
        bullet.y -= _laserSpeed;
        if (bullet.y < 0) return true;
        for (var row = 0; row < _brickRows; row++) {
          for (var col = 0; col < _brickCols; col++) {
            final idx = row * _brickCols + col;
            if (_bricks[idx] == _bEmpty || _bricks[idx] == _bSteel) continue;
            final bx = _brickLeft + col * (_brickW + _brickGap);
            final by = _brickTop + row * (_brickH + _brickGap);
            if (bullet.x >= bx &&
                bullet.x <= bx + _brickW &&
                bullet.y >= by &&
                bullet.y <= by + _brickH) {
              _hitBrick(idx);
              if (_allCleared) {
                _winLevel();
                return true;
              }
              return true;
            }
          }
        }
        return false;
      });

      // ── Falling power-ups ──
      _fallingPUs.removeWhere((pu) {
        pu.y += _puFallSpeed;
        if (pu.y + _puH / 2 >= paddleTop &&
            pu.y - _puH / 2 <= paddleTop + _paddleH + 4 &&
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

        // Stuck balls follow paddle
        if (ball.stuck) {
          ball.x = (_paddleX + pw / 2 + ball.stuckOffsetX)
              .clamp(_ballR, _gameW - _ballR);
          ball.y = paddleTop - _ballR;
          continue;
        }

        // Normalise speed
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
          if (_isSticky) {
            ball.stuck = true;
            ball.stuckOffsetX = (ball.x - (_paddleX + pw / 2))
                .clamp(-pw / 2, pw / 2);
            ball.y = paddleTop - _ballR;
            continue;
          }
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
              if (!_isThru && !_isBlast) {
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
            }
          }
        }

        if (_allCleared) {
          _winLevel();
          return;
        }
      }

      for (final bi in ballsToRemove.reversed) {
        _balls.removeAt(bi);
      }

      if (_balls.isEmpty) {
        _loseLife();
      }
    });
  }

  void _fireLaser() {
    final paddleTop = _gameH - _bottomPad - _paddleH;
    final pw = _effectivePaddleW;
    _bullets.add(_Bullet(_paddleX + pw * 0.2, paddleTop));
    _bullets.add(_Bullet(_paddleX + pw * 0.8, paddleTop));
  }

  // ── Brick logic ──────────────────────────────────────────────────────────

  void _hitBrick(int idx, {bool isChain = false}) {
    final type = _bricks[idx];
    if (type == _bEmpty || type == _bSteel) return;

    _brickFlash[idx] = 6;

    if (type == _bGlass && !isChain && !_isBlast) {
      _bricks[idx] = _bCracked;
      return;
    }

    _bricks[idx] = _bEmpty;
    _score += _brickPoints(type);
    _maybeDropPowerUp(idx);

    if (type == _bBlast) {
      _explodeNeighbours(idx);
    }
  }

  void _explodeNeighbours(int center) {
    final row = center ~/ _brickCols;
    final col = center % _brickCols;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = row + dr;
        final nc = col + dc;
        if (nr >= 0 && nr < _brickRows && nc >= 0 && nc < _brickCols) {
          final ni = nr * _brickCols + nc;
          if (_bricks[ni] != _bEmpty && _bricks[ni] != _bSteel) {
            _hitBrick(ni, isChain: true);
          }
        }
      }
    }
  }

  int _brickPoints(int type) => switch (type) {
        _bNormal => 10,
        _bGlass || _bCracked => 20,
        _bGold => 50,
        _bBlast => 10,
        _ => 0,
      };

  // ── Power-ups ────────────────────────────────────────────────────────────

  void _maybeDropPowerUp(int brickIdx) {
    if (_rng.nextDouble() > _puChance) return;
    final col = brickIdx % _brickCols;
    final row = brickIdx ~/ _brickCols;
    final x = _brickLeft + col * (_brickW + _brickGap) + _brickW / 2;
    final y = _brickTop + row * (_brickH + _brickGap) + _brickH / 2;

    final roll = _rng.nextDouble();
    final type = roll < 0.18
        ? _PUType.expand
        : roll < 0.33
            ? _PUType.multiball
            : roll < 0.45
                ? _PUType.sticky
                : roll < 0.55
                    ? _PUType.laser
                    : roll < 0.63
                        ? _PUType.thru
                        : roll < 0.72
                            ? _PUType.life
                            : roll < 0.86
                                ? _PUType.slow
                                : _PUType.blast;

    _fallingPUs.add(_FallingPU(x, y, type));
  }

  void _collectPowerUp(_PUType type) {
    switch (type) {
      case _PUType.expand:
        _expandTicks = 700;
      case _PUType.multiball:
        if (_balls.isNotEmpty && _balls.length < 12) {
          final src = _balls.firstWhere((b) => !b.stuck, orElse: () => _balls.first);
          final s = _effectiveSpeed;
          _balls.add(_Ball(src.x, src.y, s * cos(-pi / 2 + 0.45),
              s * sin(-pi / 2 + 0.45)));
          _balls.add(_Ball(src.x, src.y, s * cos(-pi / 2 - 0.45),
              s * sin(-pi / 2 - 0.45)));
        }
      case _PUType.sticky:
        _stickyTicks = 600;
      case _PUType.laser:
        _laserTicks = 550;
        _laserCooldown = 0;
      case _PUType.thru:
        _thruTicks = 480;
      case _PUType.life:
        _lives++;
      case _PUType.slow:
        _slowTicks = 540;
      case _PUType.blast:
        _blastTicks = 420;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showButton = ref.watch(settingsProvider).showArkanoidButton;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.escape) _onClose();
          if (e.logicalKey == LogicalKeyboardKey.space) {
            setState(() => _onTap());
          }
          if (e.logicalKey == LogicalKeyboardKey.keyR &&
              _phase == _Phase.paused) {
            setState(() => _restart());
          }
        }
      },
      child: Container(
        color: const Color(0xFF000812),
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
                      painter: _DxBallPainter(
                        bricks: _bricks,
                        brickFlash: _brickFlash,
                        brickW: _brickW,
                        brickH: _brickH,
                        brickTop: _brickTop,
                        brickLeft: _brickLeft,
                        paddleX: _paddleX,
                        paddleW: _effectivePaddleW,
                        bottomPad: _bottomPad,
                        balls: _balls,
                        fallingPUs: _fallingPUs,
                        bullets: _bullets,
                        phase: _phase,
                        isBlast: _isBlast,
                        isThru: _isThru,
                        isLaser: _isLaser,
                        isExpand: _expandTicks > 0,
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
        color: const Color(0xFF00050F),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'PIXEL·BALL',
            style: TextStyle(
              color: Color(0xFF00AAFF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
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
                      ? const Color(0xFF00AAFF)
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
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          if (_expandTicks > 0) _puChip('EXPAND', const Color(0xFF44CC44)),
          if (_stickyTicks > 0) _puChip('CATCH', const Color(0xFFFFCC00)),
          if (_laserTicks > 0) _puChip('LASER', const Color(0xFFFF4444)),
          if (_thruTicks > 0) _puChip('THRU', const Color(0xFF00CCFF)),
          if (_slowTicks > 0) _puChip('SLOW', const Color(0xFF4488FF)),
          if (_blastTicks > 0) _puChip('BLAST', const Color(0xFFFF8800)),
          if (_balls.length > 1)
            _puChip('×${_balls.length}', const Color(0xFFAA44FF)),
          const SizedBox(width: 4),
          for (var i = 0; i < _lives.clamp(0, 7); i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  gradient: const RadialGradient(
                    colors: [Colors.white, Color(0xFF88AAFF)],
                    stops: [0.3, 1.0],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4488FF).withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
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
              '★$_highScore',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.28),
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
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _puChip(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _DxBallPainter extends CustomPainter {
  final List<int> bricks;
  final List<int> brickFlash;
  final double brickW, brickH, brickTop, brickLeft;
  final double paddleX, paddleW, bottomPad;
  final List<_Ball> balls;
  final List<_FallingPU> fallingPUs;
  final List<_Bullet> bullets;
  final _Phase phase;
  final bool isBlast, isThru, isLaser, isExpand;
  final int score, highScore;

  _DxBallPainter({
    required this.bricks,
    required this.brickFlash,
    required this.brickW,
    required this.brickH,
    required this.brickTop,
    required this.brickLeft,
    required this.paddleX,
    required this.paddleW,
    required this.bottomPad,
    required this.balls,
    required this.fallingPUs,
    required this.bullets,
    required this.phase,
    required this.isBlast,
    required this.isThru,
    required this.isLaser,
    required this.isExpand,
    required this.score,
    required this.highScore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawBricks(canvas);
    _drawFallingPowerUps(canvas);
    _drawBullets(canvas);
    _drawPaddle(canvas, size);
    _drawBalls(canvas);
    _drawOverlay(canvas, size);
  }

  // ── Background ───────────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size) {
    // Floor base — same dark navy as office canvas, so the arkanoid arena
    // reads as the same physical space as the office.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF131320),
    );

    // 16-px checker tiles. Low contrast so bricks/ball stay foreground.
    const tile = 16.0;
    final lightTile = Paint()..color = const Color(0xFF171728);
    for (var ty = 0.0; ty < size.height; ty += tile) {
      for (var tx = 0.0; tx < size.width; tx += tile) {
        final isLight =
            (((tx / tile).floor() + (ty / tile).floor()) & 1) == 0;
        if (isLight) {
          canvas.drawRect(Rect.fromLTWH(tx, ty, tile, tile), lightTile);
        }
      }
    }

    // Radial vignette to focus the play area without competing with bricks.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height / 2),
          size.shortestSide * 0.75,
          [const Color(0x00000000), const Color(0x66000000)],
          [0.55, 1.0],
        ),
    );
  }

  // ── Bricks ───────────────────────────────────────────────────────────────

  void _drawBricks(Canvas canvas) {
    for (var row = 0; row < _brickRows; row++) {
      for (var col = 0; col < _brickCols; col++) {
        final idx = row * _brickCols + col;
        final type = bricks[idx];
        if (type == _bEmpty) continue;
        final x = brickLeft + col * (brickW + _brickGap);
        final y = brickTop + row * (brickH + _brickGap);
        final flash = idx < brickFlash.length ? brickFlash[idx] : 0;
        _drawSingleBrick(canvas, x, y, type, row, flash);
      }
    }
  }

  void _drawSingleBrick(
      Canvas canvas, double x, double y, int type, int row, int flash) {
    final rect = Rect.fromLTWH(x, y, brickW, brickH);

    switch (type) {
      case _bNormal:
        _paintDeskBrick(canvas, rect, row);
      case _bGlass:
        _paintWhiteboardBrick(canvas, rect, cracked: false);
      case _bCracked:
        _paintWhiteboardBrick(canvas, rect, cracked: true);
      case _bGold:
        _paintTrophyBrick(canvas, rect);
      case _bBlast:
        _paintServerRackBrick(canvas, rect);
      case _bSteel:
        _paintSafeBrick(canvas, rect);
    }

    // Cyan accent rim — office signature, prevents bricks from sinking into
    // the navy floor without resorting to glossy gradients.
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..color = const Color(0xFF00C0D1).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Hit-flash overlay — replaces the bevel-flash feedback we lose by
    // dropping the DX-Ball gloss. 6-tick decay → ~100ms at 60fps.
    if (flash > 0) {
      canvas.drawRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: 0.05 * flash),
      );
    }
  }

  // skinDefault `clothes` palette mirrored from character_skins.dart so each
  // brick row reads as one agent class.
  static const _agentClothes = <Color>[
    Color(0xFF00949F), // tech-lead
    Color(0xFFD97706), // manager
    Color(0xFF059669), // coder
    Color(0xFF7C3AED), // reviewer
    Color(0xFFDB2777), // tester
    Color(0xFFDC2626), // security
    Color(0xFF2563EB), // ui-ux
    Color(0xFFCA8A04), // game-designer
  ];

  void _paintDeskBrick(Canvas canvas, Rect r, int row) {
    canvas.drawRect(r, Paint()..color = const Color(0xFF6B4F2A));
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, 1),
      Paint()..color = const Color(0xFF8B6A3A),
    );
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.bottom - 1, r.width, 1),
      Paint()..color = const Color(0xFF3E2B22),
    );

    final mw = r.width * 0.45;
    final mh = r.height * 0.62;
    final mx = r.left + (r.width - mw) / 2;
    final my = r.top + (r.height - mh) / 2;
    canvas.drawRect(
      Rect.fromLTWH(mx, my, mw, mh),
      Paint()..color = const Color(0xFF111418),
    );
    canvas.drawRect(
      Rect.fromLTWH(mx + 1, my + 1, mw - 2, mh - 2),
      Paint()..color = _agentClothes[row % _agentClothes.length],
    );
  }

  void _paintWhiteboardBrick(Canvas canvas, Rect r, {required bool cracked}) {
    canvas.drawRect(r, Paint()..color = const Color(0xFF252540));
    canvas.drawRect(
      r.deflate(1),
      Paint()..color = const Color(0xFF3A3A5C),
    );
    // Top sheen — wide horizontal strip distinguishes whiteboard from safe.
    canvas.drawRect(
      Rect.fromLTWH(r.left + 1, r.top + 1, r.width - 2, 2),
      Paint()..color = const Color(0xFFB0C4DE).withValues(alpha: 0.55),
    );
    if (cracked) {
      final cp = Paint()
        ..color = const Color(0xFF0A0A18)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(r.left + r.width * 0.32, r.top + r.height * 0.1),
        Offset(r.left + r.width * 0.55, r.bottom - 1),
        cp,
      );
      canvas.drawLine(
        Offset(r.left + r.width * 0.55, r.top + r.height * 0.2),
        Offset(r.left + r.width * 0.25, r.top + r.height * 0.72),
        cp,
      );
    }
  }

  void _paintTrophyBrick(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0xFFCA8A04));
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, 2),
      Paint()..color = const Color(0xFFFFD700),
    );
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.bottom - 1, r.width, 1),
      Paint()..color = const Color(0xFF7A5200),
    );
    final cup = Paint()..color = const Color(0xFF7A5200);
    final cx = r.center.dx;
    final cy = r.center.dy;
    canvas.drawRect(Rect.fromLTWH(cx - 3, cy - 2, 6, 1), cup);
    canvas.drawRect(Rect.fromLTWH(cx - 2, cy - 1, 4, 3), cup);
    canvas.drawRect(Rect.fromLTWH(cx - 3, cy + 2, 6, 1), cup);
  }

  void _paintServerRackBrick(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0xFF142028));
    final shelf = Paint()..color = const Color(0xFF303038);
    canvas.drawRect(
      Rect.fromLTWH(r.left + 2, r.top + r.height * 0.28, r.width * 0.55, 1.5),
      shelf,
    );
    canvas.drawRect(
      Rect.fromLTWH(r.left + 2, r.top + r.height * 0.6, r.width * 0.55, 1.5),
      shelf,
    );
    canvas.drawRect(
      Rect.fromLTWH(r.right - 4, r.top + r.height * 0.32, 2, 2),
      Paint()..color = const Color(0xFF00E5FF),
    );
    canvas.drawRect(
      Rect.fromLTWH(r.right - 4, r.top + r.height * 0.62, 2, 2),
      Paint()..color = const Color(0xFFDC2626),
    );
  }

  void _paintSafeBrick(Canvas canvas, Rect r) {
    canvas.drawRect(r, Paint()..color = const Color(0xFF2A2A3C));
    canvas.drawRect(r.deflate(1), Paint()..color = const Color(0xFF3C3C52));
    canvas.drawRect(
      r.deflate(0.5),
      Paint()
        ..color = const Color(0xFFB0B0C0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final rivet = Paint()..color = const Color(0xFFB0B0C0);
    canvas.drawRect(Rect.fromLTWH(r.left + 1, r.top + 1, 1, 1), rivet);
    canvas.drawRect(Rect.fromLTWH(r.right - 2, r.top + 1, 1, 1), rivet);
    canvas.drawRect(Rect.fromLTWH(r.left + 1, r.bottom - 2, 1, 1), rivet);
    canvas.drawRect(Rect.fromLTWH(r.right - 2, r.bottom - 2, 1, 1), rivet);
    canvas.drawRect(
      Rect.fromCenter(center: r.center, width: 4, height: 4),
      Paint()..color = const Color(0xFF1A1A28),
    );
  }

  // ── Paddle ───────────────────────────────────────────────────────────────

  void _drawPaddle(Canvas canvas, Size size) {
    final py = size.height - bottomPad - _paddleH;
    final baseColor =
        isExpand ? const Color(0xFF33BB33) : const Color(0xFF2255CC);
    final rect = Rect.fromLTWH(paddleX, py, paddleW, _paddleH);
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(_paddleH / 2));

    // Metallic gradient
    final light = Color.lerp(baseColor, Colors.white, 0.50)!;
    final dark = Color.lerp(baseColor, Colors.black, 0.28)!;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(paddleX, py),
          Offset(paddleX, py + _paddleH),
          [light, baseColor, dark],
          [0.0, 0.50, 1.0],
        ),
    );

    // Outer glow
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = baseColor.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Bright top edge
    canvas.drawLine(
      Offset(paddleX + _paddleH / 2 + 1, py + 1.5),
      Offset(paddleX + paddleW - _paddleH / 2 - 1, py + 1.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.5,
    );

    // Laser gun nozzles
    if (isLaser) {
      final nozzleP = Paint()..color = const Color(0xFFFF4444);
      final nozzleGlow = Paint()
        ..color = const Color(0xFFFF4444).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      for (final nx in [paddleX + paddleW * 0.18, paddleX + paddleW * 0.82]) {
        canvas.drawRect(Rect.fromLTWH(nx - 1.5, py - 4, 3, 5), nozzleP);
        canvas.drawRect(Rect.fromLTWH(nx - 2.5, py - 5, 5, 6), nozzleGlow);
      }
    }
  }

  // ── Balls ────────────────────────────────────────────────────────────────

  void _drawBalls(Canvas canvas) {
    for (final ball in balls) {
      _drawSingleBall(canvas, ball.x, ball.y);
    }
  }

  void _drawSingleBall(Canvas canvas, double x, double y) {
    if (isBlast) {
      // Fireball glow
      canvas.drawCircle(
        Offset(x, y),
        _ballR + 5,
        Paint()
          ..color = const Color(0xFFFF6600).withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(
        Offset(x, y),
        _ballR,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(x - _ballR * 0.3, y - _ballR * 0.35),
            _ballR * 1.5,
            [
              const Color(0xFFFFEEAA),
              const Color(0xFFFF8800),
              const Color(0xFF882200),
            ],
            [0.0, 0.45, 1.0],
          ),
      );
    } else if (isThru) {
      // Cyan thru-ball
      canvas.drawCircle(
        Offset(x, y),
        _ballR + 4,
        Paint()
          ..color = const Color(0xFF00CCFF).withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(x, y),
        _ballR,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(x - _ballR * 0.3, y - _ballR * 0.35),
            _ballR * 1.5,
            [
              Colors.white,
              const Color(0xFF00CCFF),
              const Color(0xFF003366),
            ],
            [0.0, 0.50, 1.0],
          ),
      );
    } else {
      // Normal metallic sphere
      canvas.drawCircle(
        Offset(x, y),
        _ballR + 4,
        Paint()
          ..color = const Color(0xFF6699FF).withValues(alpha: 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        Offset(x, y),
        _ballR,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(x - _ballR * 0.30, y - _ballR * 0.36),
            _ballR * 1.6,
            [
              Colors.white,
              const Color(0xFFCCDDFF),
              const Color(0xFF4466AA),
            ],
            [0.0, 0.40, 1.0],
          ),
      );
    }

    // Specular highlight (top-left)
    canvas.drawCircle(
      Offset(x - _ballR * 0.33, y - _ballR * 0.38),
      _ballR * 0.30,
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
  }

  // ── Laser bullets ────────────────────────────────────────────────────────

  void _drawBullets(Canvas canvas) {
    for (final b in bullets) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(b.x, b.y), width: 2.5, height: 9),
        Paint()..color = const Color(0xFFFF5555),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(b.x, b.y), width: 5, height: 11),
        Paint()
          ..color = const Color(0xFFFF4444).withValues(alpha: 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  // ── Falling power-ups ────────────────────────────────────────────────────

  void _drawFallingPowerUps(Canvas canvas) {
    for (final pu in fallingPUs) {
      final Color color;
      final String label;
      switch (pu.type) {
        case _PUType.expand:
          color = const Color(0xFF44CC44);
          label = 'EXPAND';
        case _PUType.multiball:
          color = const Color(0xFFAA44FF);
          label = 'MULTI';
        case _PUType.sticky:
          color = const Color(0xFFFFCC00);
          label = 'CATCH';
        case _PUType.laser:
          color = const Color(0xFFFF4444);
          label = 'LASER';
        case _PUType.thru:
          color = const Color(0xFF00CCFF);
          label = 'THRU';
        case _PUType.life:
          color = const Color(0xFFFF88AA);
          label = '+LIFE';
        case _PUType.slow:
          color = const Color(0xFF4488FF);
          label = 'SLOW';
        case _PUType.blast:
          color = const Color(0xFFFF8800);
          label = 'BLAST';
      }

      // Pill / capsule shape
      final rect = Rect.fromCenter(
          center: Offset(pu.x, pu.y), width: _puW, height: _puH);
      final rrect =
          RRect.fromRectAndRadius(rect, Radius.circular(_puH / 2));

      // Dark pill body
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFF0A0A1A));

      // Coloured border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Inner glow fill
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );

      // Label text
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: 7,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pu.x - tp.width / 2, pu.y - tp.height / 2));
    }
  }

  // ── Overlay ──────────────────────────────────────────────────────────────

  void _drawOverlay(Canvas canvas, Size size) {
    if (phase == _Phase.running) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final cy = size.height / 2;

    switch (phase) {
      case _Phase.waitingLaunch:
        _drawText(canvas, size.width, cy - 14, 'КЛІК ДЛЯ ЗАПУСКУ', 22,
            Colors.white);
        _drawText(canvas, size.width, cy + 18, 'Рухайте мишею для прицілювання',
            10, Colors.white.withValues(alpha: 0.45));
      case _Phase.paused:
        _drawText(
            canvas, size.width, cy - 14, 'ПАУЗА', 22, Colors.white);
        _drawText(
            canvas,
            size.width,
            cy + 18,
            'Клік для продовження  ·  R для рестарту',
            10,
            Colors.white.withValues(alpha: 0.45));
      case _Phase.gameOver:
        _drawText(canvas, size.width, cy - 26, 'КІНЕЦЬ ГРИ', 24,
            const Color(0xFFFF4444));
        final sub =
            'Рахунок: $score${highScore > 0 ? '   Рекорд: $highScore' : ''}';
        _drawText(canvas, size.width, cy + 10, sub, 12,
            Colors.white.withValues(alpha: 0.7));
        _drawText(canvas, size.width, cy + 34, 'Клік для рестарту', 10,
            Colors.white.withValues(alpha: 0.4));
      case _Phase.won:
        _drawText(canvas, size.width, cy - 26, 'РІВЕНЬ ПРОЙДЕНО!', 24,
            const Color(0xFFFFCC00));
        _drawText(canvas, size.width, cy + 10, 'Рахунок: $score', 12,
            Colors.white.withValues(alpha: 0.7));
        _drawText(canvas, size.width, cy + 34, 'Клік для наступного рівня', 10,
            Colors.white.withValues(alpha: 0.4));
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
          letterSpacing: fontSize > 14 ? 2.5 : 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((width - tp.width) / 2, y));
  }

  @override
  bool shouldRepaint(covariant _DxBallPainter old) => true;
}
