import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'xquest_sprites.dart';

// ─── Constants ──────────────────────────────────────────────────────────────

const _arenaW = 392.0;
const _arenaH = 320.0;
const _shipR = 6.0; // collision radius (original ship is 16x16)
const _missileSpeed = 5.0;
const _missileR = 1.5;
const _crystalR = 3.5;
const _mineR = 3.0;
const _powerUpR = 5.0;
const _maxMissiles = 50;
const _maxParticles = 80;
const _fireCooldown = 8; // frames between shots
const _rapidFireCooldown = 4;
const _powerUpDuration = 600; // ~10 sec at 60fps
const _invulnDuration = 120;
const _dyingDuration = 40;
const _borderW = 6.0; // arena border thickness

// ─── Colors ─────────────────────────────────────────────────────────────────

const _bgColor = Color(0xFF000020);
const _borderColor = Color(0xFF00AAFF);
const _gateColor = Color(0xFF444488);
const _shipColor = Color(0xFF00FF88);
const _missileColor = Color(0xFFFFFFFF);
const _crystalColor = Color(0xFFFFCC00);
const _mineColor = Color(0xFFFF0000);
const _exitOpenColor = Color(0xFF00FF88);

const _enemyColors = <_EnemyType, Color>{
  _EnemyType.grunger: Color(0xFFFF4444),
  _EnemyType.zippo: Color(0xFFFF8800),
  _EnemyType.zinger: Color(0xFFFFFF00),
  _EnemyType.retaliator: Color(0xFFFF00FF),
  _EnemyType.miner: Color(0xFFAA6600),
  _EnemyType.terrier: Color(0xFF44FF44),
  _EnemyType.doinger: Color(0xFF4488FF),
  _EnemyType.tribbler: Color(0xFFFF88FF),
  _EnemyType.tribble: Color(0xFFFFAAFF),
};

const _powerUpColors = <_PowerUpType, Color>{
  _PowerUpType.shield: Color(0xFF00FFFF),
  _PowerUpType.aimedFire: Color(0xFFFFFF00),
  _PowerUpType.rapidFire: Color(0xFFFF8800),
  _PowerUpType.multiFire: Color(0xFF00FF00),
  _PowerUpType.assFire: Color(0xFFAA44FF),
  _PowerUpType.heavyFire: Color(0xFFFF2222),
  _PowerUpType.bounce: Color(0xFFFFFFFF),
};

const _powerUpLetters = <_PowerUpType, String>{
  _PowerUpType.shield: 'S',
  _PowerUpType.aimedFire: 'A',
  _PowerUpType.rapidFire: 'R',
  _PowerUpType.multiFire: 'M',
  _PowerUpType.assFire: 'F',
  _PowerUpType.heavyFire: 'H',
  _PowerUpType.bounce: 'B',
};

// ─── Enums ──────────────────────────────────────────────────────────────────

enum _Phase { title, running, paused, levelComplete, gameOver }

enum _EnemyType { grunger, zippo, zinger, retaliator, miner, terrier, doinger, tribbler, tribble }

enum _PowerUpType { shield, aimedFire, rapidFire, multiFire, assFire, heavyFire, bounce }

// ─── Data classes ───────────────────────────────────────────────────────────

class _Missile {
  double x, y, vx, vy;
  bool heavy;
  bool bouncing;
  _Missile(this.x, this.y, this.vx, this.vy, {this.heavy = false, this.bouncing = false});
}

class _Enemy {
  double x, y, vx, vy;
  _EnemyType type;
  int health = 1;
  int timer = 0;
  double param = 0.0; // sine phase for zinger, etc.
  double baseVx, baseVy; // original velocity for zinger sine
  _Enemy(this.x, this.y, this.vx, this.vy, this.type)
      : baseVx = vx, baseVy = vy;
}

class _Crystal {
  double x, y;
  bool collected;
  _Crystal(this.x, this.y) : collected = false;
}

class _Mine {
  double x, y;
  _Mine(this.x, this.y);
}

class _PowerUp {
  double x, y;
  _PowerUpType type;
  _PowerUp(this.x, this.y, this.type);
}

class _Particle {
  double x, y, vx, vy;
  int life, maxLife;
  Color color;
  _Particle(this.x, this.y, this.vx, this.vy, this.life, this.color) : maxLife = life;
}

class _EnemyMissile {
  double x, y, vx, vy;
  _EnemyMissile(this.x, this.y, this.vx, this.vy);
}

class _LevelDef {
  final int crystalCount;
  final int mineCount;
  final int maxSmartBombs;
  final double enemySpawnRate; // frames between spawns
  final int maxEnemies;
  final int timeLimitSec;
  final double gateWidth;
  final double gateSpeed;
  final List<_EnemyType> enemyTypes;

  const _LevelDef({
    required this.crystalCount,
    this.mineCount = 0,
    this.maxSmartBombs = 1,
    required this.enemySpawnRate,
    required this.maxEnemies,
    this.timeLimitSec = 120,
    this.gateWidth = 50,
    this.gateSpeed = 0.3,
    required this.enemyTypes,
  });
}

// ─── Enemy scoring ──────────────────────────────────────────────────────────

const _enemyScores = <_EnemyType, int>{
  _EnemyType.grunger: 50,
  _EnemyType.zippo: 100,
  _EnemyType.zinger: 150,
  _EnemyType.retaliator: 200,
  _EnemyType.miner: 150,
  _EnemyType.terrier: 200,
  _EnemyType.doinger: 100,
  _EnemyType.tribbler: 300,
  _EnemyType.tribble: 50,
};

const _enemySpeeds = <_EnemyType, double>{
  _EnemyType.grunger: 1.2,
  _EnemyType.zippo: 2.2,
  _EnemyType.zinger: 1.4,
  _EnemyType.retaliator: 1.0,
  _EnemyType.miner: 0.9,
  _EnemyType.terrier: 1.3,
  _EnemyType.doinger: 1.8,
  _EnemyType.tribbler: 1.0,
  _EnemyType.tribble: 2.0,
};

// ─── Level definitions (20 handcrafted) ─────────────────────────────────────

const _levels = <_LevelDef>[
  // 1: Tutorial
  _LevelDef(crystalCount: 8, enemySpawnRate: 200, maxEnemies: 3, timeLimitSec: 150,
    gateWidth: 50, gateSpeed: 0, enemyTypes: [_EnemyType.grunger]),
  // 2
  _LevelDef(crystalCount: 10, enemySpawnRate: 170, maxEnemies: 4, timeLimitSec: 140,
    gateWidth: 48, gateSpeed: 0.2, enemyTypes: [_EnemyType.grunger]),
  // 3: Zippo intro
  _LevelDef(crystalCount: 12, enemySpawnRate: 150, maxEnemies: 5, timeLimitSec: 130,
    gateWidth: 46, gateSpeed: 0.3, enemyTypes: [_EnemyType.grunger, _EnemyType.zippo]),
  // 4
  _LevelDef(crystalCount: 14, mineCount: 2, enemySpawnRate: 140, maxEnemies: 6, timeLimitSec: 130,
    gateWidth: 45, gateSpeed: 0.3, enemyTypes: [_EnemyType.grunger, _EnemyType.zippo]),
  // 5: Zinger intro
  _LevelDef(crystalCount: 16, mineCount: 2, enemySpawnRate: 130, maxEnemies: 7, timeLimitSec: 120,
    gateWidth: 44, gateSpeed: 0.4, enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.zinger]),
  // 6: Terrier intro
  _LevelDef(crystalCount: 18, mineCount: 3, enemySpawnRate: 120, maxEnemies: 8, timeLimitSec: 120,
    gateWidth: 42, gateSpeed: 0.5, enemyTypes: [_EnemyType.grunger, _EnemyType.zinger, _EnemyType.terrier]),
  // 7: Retaliator intro
  _LevelDef(crystalCount: 20, mineCount: 3, enemySpawnRate: 110, maxEnemies: 9, timeLimitSec: 110,
    gateWidth: 40, gateSpeed: 0.5,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.retaliator, _EnemyType.terrier]),
  // 8: Miner intro
  _LevelDef(crystalCount: 22, mineCount: 4, enemySpawnRate: 100, maxEnemies: 10, timeLimitSec: 110,
    gateWidth: 40, gateSpeed: 0.6,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zinger, _EnemyType.miner, _EnemyType.terrier]),
  // 9: Doinger intro
  _LevelDef(crystalCount: 24, mineCount: 4, enemySpawnRate: 95, maxEnemies: 12, timeLimitSec: 100,
    gateWidth: 38, gateSpeed: 0.6,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.doinger, _EnemyType.retaliator]),
  // 10: Tribbler intro
  _LevelDef(crystalCount: 26, mineCount: 5, maxSmartBombs: 2, enemySpawnRate: 90, maxEnemies: 14, timeLimitSec: 100,
    gateWidth: 36, gateSpeed: 0.7,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zinger, _EnemyType.terrier, _EnemyType.tribbler]),
  // 11
  _LevelDef(crystalCount: 28, mineCount: 5, maxSmartBombs: 2, enemySpawnRate: 85, maxEnemies: 15, timeLimitSec: 95,
    gateWidth: 36, gateSpeed: 0.7,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.retaliator, _EnemyType.miner, _EnemyType.tribbler]),
  // 12
  _LevelDef(crystalCount: 30, mineCount: 6, maxSmartBombs: 2, enemySpawnRate: 80, maxEnemies: 16, timeLimitSec: 95,
    gateWidth: 34, gateSpeed: 0.8,
    enemyTypes: [_EnemyType.zippo, _EnemyType.zinger, _EnemyType.terrier, _EnemyType.doinger, _EnemyType.tribbler]),
  // 13
  _LevelDef(crystalCount: 30, mineCount: 6, maxSmartBombs: 2, enemySpawnRate: 75, maxEnemies: 18, timeLimitSec: 90,
    gateWidth: 34, gateSpeed: 0.8,
    enemyTypes: [_EnemyType.grunger, _EnemyType.retaliator, _EnemyType.miner, _EnemyType.terrier, _EnemyType.doinger]),
  // 14
  _LevelDef(crystalCount: 32, mineCount: 7, maxSmartBombs: 2, enemySpawnRate: 70, maxEnemies: 20, timeLimitSec: 90,
    gateWidth: 32, gateSpeed: 0.9,
    enemyTypes: [_EnemyType.zippo, _EnemyType.zinger, _EnemyType.retaliator, _EnemyType.terrier, _EnemyType.tribbler]),
  // 15
  _LevelDef(crystalCount: 32, mineCount: 7, maxSmartBombs: 3, enemySpawnRate: 65, maxEnemies: 22, timeLimitSec: 85,
    gateWidth: 32, gateSpeed: 0.9,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.miner, _EnemyType.doinger, _EnemyType.tribbler]),
  // 16
  _LevelDef(crystalCount: 34, mineCount: 8, maxSmartBombs: 3, enemySpawnRate: 60, maxEnemies: 22, timeLimitSec: 85,
    gateWidth: 30, gateSpeed: 1.0,
    enemyTypes: [_EnemyType.zippo, _EnemyType.zinger, _EnemyType.retaliator, _EnemyType.miner, _EnemyType.terrier, _EnemyType.tribbler]),
  // 17
  _LevelDef(crystalCount: 34, mineCount: 8, maxSmartBombs: 3, enemySpawnRate: 55, maxEnemies: 24, timeLimitSec: 80,
    gateWidth: 30, gateSpeed: 1.0,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.retaliator, _EnemyType.doinger, _EnemyType.terrier, _EnemyType.tribbler]),
  // 18
  _LevelDef(crystalCount: 36, mineCount: 9, maxSmartBombs: 3, enemySpawnRate: 50, maxEnemies: 25, timeLimitSec: 80,
    gateWidth: 28, gateSpeed: 1.1,
    enemyTypes: [_EnemyType.zippo, _EnemyType.zinger, _EnemyType.retaliator, _EnemyType.miner, _EnemyType.terrier, _EnemyType.doinger, _EnemyType.tribbler]),
  // 19
  _LevelDef(crystalCount: 38, mineCount: 10, maxSmartBombs: 3, enemySpawnRate: 45, maxEnemies: 28, timeLimitSec: 75,
    gateWidth: 28, gateSpeed: 1.1,
    enemyTypes: [_EnemyType.zippo, _EnemyType.zinger, _EnemyType.retaliator, _EnemyType.miner, _EnemyType.terrier, _EnemyType.doinger, _EnemyType.tribbler]),
  // 20: Full chaos
  _LevelDef(crystalCount: 40, mineCount: 10, maxSmartBombs: 3, enemySpawnRate: 40, maxEnemies: 30, timeLimitSec: 75,
    gateWidth: 26, gateSpeed: 1.2,
    enemyTypes: [_EnemyType.grunger, _EnemyType.zippo, _EnemyType.zinger, _EnemyType.retaliator, _EnemyType.miner, _EnemyType.terrier, _EnemyType.doinger, _EnemyType.tribbler]),
];

_LevelDef _proceduralLevel(int n) {
  final t = (n - 20).clamp(0, 100);
  return _LevelDef(
    crystalCount: (40 + t).clamp(40, 60),
    mineCount: (10 + t ~/ 3).clamp(10, 20),
    maxSmartBombs: 3,
    enemySpawnRate: (40 - t * 0.3).clamp(15, 40),
    maxEnemies: (30 + t ~/ 2).clamp(30, 40),
    timeLimitSec: (75 - t ~/ 2).clamp(45, 75),
    gateWidth: (26 - t * 0.2).clamp(16, 26),
    gateSpeed: (1.2 + t * 0.02).clamp(1.2, 2.0),
    enemyTypes: _EnemyType.values.where((e) => e != _EnemyType.tribble).toList(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget
// ═══════════════════════════════════════════════════════════════════════════

class XQuestGame extends StatefulWidget {
  final VoidCallback onClose;
  const XQuestGame({super.key, required this.onClose});

  @override
  State<XQuestGame> createState() => _XQuestGameState();
}

class _XQuestGameState extends State<XQuestGame> {
  final _rng = Random();
  final _focusNode = FocusNode();
  Timer? _ticker;

  // Phase
  var _phase = _Phase.title;
  int _frameTick = 0;

  // Ship
  double _shipX = _arenaW / 2, _shipY = _arenaH / 2;
  double _shipVx = 0, _shipVy = 0;
  int _shipDir = 0; // 0-23
  int _fireCooldownTimer = 0;
  int _invulnTimer = 0;
  int _dyingTimer = 0;
  bool _shieldActive = false;

  // Power-ups
  bool _aimedFire = false, _rapidFire = false, _multiFire = false;
  bool _assFire = false, _heavyFire = false, _bounceFire = false;
  int _powerUpTimer = 0;

  // Game state
  int _score = 0;
  int _lives = 3;
  int _level = 0;
  int _smartBombs = 0;
  int _timeRemaining = 0; // in frames
  int _smartBombFlash = 0;
  bool _exitOpen = false;
  bool _pauseHintShown = false;
  int _nextLifeAt = 10000;

  // Objects
  final _missiles = <_Missile>[];
  final _enemies = <_Enemy>[];
  final _enemyMissiles = <_EnemyMissile>[];
  final _crystals = <_Crystal>[];
  final _mines = <_Mine>[];
  final _powerUps = <_PowerUp>[];
  final _particles = <_Particle>[];

  // Gates
  double _leftGateY = _arenaH / 2, _rightGateY = _arenaH / 2;
  double _leftGateDir = 1, _rightGateDir = -1;
  double _gateWidth = 50;
  double _gateSpeed = 0.3;

  // Enemy spawning
  double _spawnAccum = 0;
  int _maxEnemiesForLevel = 10;
  double _enemySpawnRate = 100;
  List<_EnemyType> _levelEnemyTypes = [_EnemyType.grunger];

  // Mouse input — original XQuest uses additive inertia (no friction)
  double _mouseAccumDx = 0, _mouseAccumDy = 0;
  static const _mouseSensitivity = 0.6; // scale mouse mickeys to velocity units
  static const _maxShipSpeed = 10.0; // MaxShipSpeed=640 / 64 = 10 px/frame
  double _currentScale = 1.0;

  // Starfield (static)
  late final List<Offset> _stars;

  @override
  void initState() {
    super.initState();
    _stars = List.generate(80, (_) => Offset(
      _rng.nextDouble() * _arenaW,
      _rng.nextDouble() * _arenaH,
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Level setup ─────────────────────────────────────────────────────────

  _LevelDef _getLevelDef(int n) => n < _levels.length ? _levels[n] : _proceduralLevel(n);

  void _initLevel(int levelNum) {
    final def = _getLevelDef(levelNum);

    _missiles.clear();
    _enemies.clear();
    _enemyMissiles.clear();
    _crystals.clear();
    _mines.clear();
    _powerUps.clear();
    _particles.clear();

    _shipX = _arenaW / 2;
    _shipY = _arenaH / 2;
    _shipVx = 0;
    _shipVy = 0;
    _shipDir = 0;
    _fireCooldownTimer = 0;
    _invulnTimer = _invulnDuration;
    _exitOpen = false;

    _shieldActive = false;
    _aimedFire = false;
    _rapidFire = false;
    _multiFire = false;
    _assFire = false;
    _heavyFire = false;
    _bounceFire = false;
    _powerUpTimer = 0;

    _smartBombs = def.maxSmartBombs;
    _timeRemaining = def.timeLimitSec * 60; // 60fps
    _gateWidth = def.gateWidth;
    _gateSpeed = def.gateSpeed;
    _leftGateY = _arenaH / 2;
    _rightGateY = _arenaH / 2;
    _leftGateDir = 1;
    _rightGateDir = -1;
    _spawnAccum = 0;
    _maxEnemiesForLevel = def.maxEnemies;
    _enemySpawnRate = def.enemySpawnRate;
    _levelEnemyTypes = def.enemyTypes;

    // Place crystals randomly avoiding center spawn area and borders
    for (var i = 0; i < def.crystalCount; i++) {
      for (var attempt = 0; attempt < 100; attempt++) {
        final cx = _borderW + 20 + _rng.nextDouble() * (_arenaW - _borderW * 2 - 40);
        final cy = _borderW + 10 + _rng.nextDouble() * (_arenaH - _borderW * 2 - 20);
        // Avoid ship spawn area
        if ((cx - _arenaW / 2).abs() < 30 && (cy - _arenaH / 2).abs() < 30) continue;
        // Avoid overlap with existing crystals
        var ok = true;
        for (final c in _crystals) {
          if ((c.x - cx).abs() < 8 && (c.y - cy).abs() < 8) { ok = false; break; }
        }
        if (ok) { _crystals.add(_Crystal(cx, cy)); break; }
      }
    }

    // Place mines
    for (var i = 0; i < def.mineCount; i++) {
      for (var attempt = 0; attempt < 100; attempt++) {
        final mx = _borderW + 20 + _rng.nextDouble() * (_arenaW - _borderW * 2 - 40);
        final my = _borderW + 10 + _rng.nextDouble() * (_arenaH - _borderW * 2 - 20);
        if ((mx - _arenaW / 2).abs() < 40 && (my - _arenaH / 2).abs() < 40) continue;
        _mines.add(_Mine(mx, my));
        break;
      }
    }
  }

  // ── Timer management ────────────────────────────────────────────────────

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // ── Phase transitions ───────────────────────────────────────────────────

  void _startGame() {
    setState(() {
      _score = 0;
      _lives = 3;
      _level = 0;
      _nextLifeAt = 10000;
      _initLevel(0);
      _phase = _Phase.running;
      _startTicker();
    });
  }

  void _pause() {
    if (_phase != _Phase.running) return;
    setState(() {
      _phase = _Phase.paused;
      _pauseHintShown = true;
      _stopTicker();
    });
  }

  void _resume() {
    if (_phase != _Phase.paused) return;
    setState(() {
      _phase = _Phase.running;
      _mouseAccumDx = 0;
      _mouseAccumDy = 0;
      _startTicker();
    });
  }

  void _nextLevel() {
    setState(() {
      _level++;
      _initLevel(_level);
      _phase = _Phase.running;
      _startTicker();
    });
  }

  void _restart() {
    _stopTicker();
    _startGame();
  }

  // ── Main game tick ──────────────────────────────────────────────────────

  void _tick() {
    if (!mounted || _phase != _Phase.running) return;
    setState(() {
      _frameTick++;

      if (_dyingTimer > 0) {
        _dyingTimer--;
        _updateParticles();
        if (_dyingTimer == 0) {
          if (_lives <= 0) {
            _phase = _Phase.gameOver;
            _stopTicker();
          } else {
            _shipX = _arenaW / 2;
            _shipY = _arenaH / 2;
            _shipVx = 0;
            _shipVy = 0;
            _invulnTimer = _invulnDuration;
            _mouseAccumDx = 0;
            _mouseAccumDy = 0;
          }
        }
        return;
      }

      _updateInput();
      _moveShip();
      _updateShipDirection();
      _moveMissiles();
      _spawnEnemies();
      _moveEnemies();
      _moveEnemyMissiles();
      _moveGates();
      _checkMissileHits();
      _checkEnemyMissileHits();
      _checkPlayerCollision();
      _collectCrystals();
      _collectPowerUps();
      _updatePowerUpTimers();
      _checkLevelComplete();
      _checkExitReached();
      _updateParticles();
      _updateTimers();
    });
  }

  // ── Input ───────────────────────────────────────────────────────────────

  void _updateInput() {
    // Original XQuest: mouse delta is ADDED to existing velocity (inertia).
    // delx := delx + mx; — ship keeps moving until you counter-steer.
    _shipVx += _mouseAccumDx * _mouseSensitivity;
    _shipVy += _mouseAccumDy * _mouseSensitivity;

    // Clamp combined speed (Manhattan, matching original: abs(delx)+abs(dely) <= MaxShipSpeed)
    final speed = _shipVx.abs() + _shipVy.abs();
    if (speed > _maxShipSpeed) {
      _shipVx = _shipVx / speed * _maxShipSpeed;
      _shipVy = _shipVy / speed * _maxShipSpeed;
    }

    _mouseAccumDx = 0;
    _mouseAccumDy = 0;
  }

  // ── Ship movement ─────────────────────────────────────────────────────

  void _moveShip() {
    _shipX += _shipVx;
    _shipY += _shipVy;

    // Wall bounces (original: delx := -abs(delx) / abs(delx))
    final minX = _borderW + _shipR, maxX = _arenaW - _borderW - _shipR;
    final minY = _borderW + _shipR, maxY = _arenaH - _borderW - _shipR;
    if (_shipX <= minX) { _shipX = minX; _shipVx = _shipVx.abs(); }
    if (_shipX >= maxX) { _shipX = maxX; _shipVx = -_shipVx.abs(); }
    if (_shipY <= minY) { _shipY = minY; _shipVy = _shipVy.abs(); }
    if (_shipY >= maxY) { _shipY = maxY; _shipVy = -_shipVy.abs(); }

    if (_fireCooldownTimer > 0) _fireCooldownTimer--;
    if (_invulnTimer > 0) _invulnTimer--;
  }

  void _updateShipDirection() {
    if (_shipVx.abs() < 0.15 && _shipVy.abs() < 0.15) return;
    final angle = atan2(_shipVy, _shipVx);
    _shipDir = ((angle / (2 * pi) * 24) + 24).round() % 24;
  }

  // ── Firing ────────────────────────────────────────────────────────────

  void _fireMissile() {
    if (_phase != _Phase.running || _dyingTimer > 0) return;
    final cooldown = _rapidFire ? _rapidFireCooldown : _fireCooldown;
    if (_fireCooldownTimer > 0) return;
    if (_missiles.length >= _maxMissiles) return;

    _fireCooldownTimer = cooldown;
    final angle = _shipDir * (2 * pi / 24);
    final speed = _heavyFire ? _missileSpeed * 0.7 : _missileSpeed;

    _missiles.add(_Missile(
      _shipX, _shipY,
      cos(angle) * speed, sin(angle) * speed,
      heavy: _heavyFire, bouncing: _bounceFire,
    ));

    // Aimed fire: target nearest enemy
    if (_aimedFire && _enemies.isNotEmpty) {
      _Enemy? nearest;
      double bestDist = double.infinity;
      for (final e in _enemies) {
        final d = (e.x - _shipX) * (e.x - _shipX) + (e.y - _shipY) * (e.y - _shipY);
        if (d < bestDist) { bestDist = d; nearest = e; }
      }
      if (nearest != null) {
        final a = atan2(nearest.y - _shipY, nearest.x - _shipX);
        _missiles.add(_Missile(_shipX, _shipY, cos(a) * speed, sin(a) * speed,
          heavy: _heavyFire, bouncing: _bounceFire));
      }
    }

    // Multi fire: 2 extra at ±15°
    if (_multiFire) {
      for (final offset in [-0.26, 0.26]) {
        final a = angle + offset;
        _missiles.add(_Missile(_shipX, _shipY, cos(a) * speed, sin(a) * speed,
          heavy: _heavyFire, bouncing: _bounceFire));
      }
    }

    // Ass fire: backwards
    if (_assFire) {
      final backAngle = angle + pi;
      _missiles.add(_Missile(_shipX, _shipY, cos(backAngle) * speed, sin(backAngle) * speed,
        heavy: _heavyFire, bouncing: _bounceFire));
    }
  }

  void _fireSmartBomb() {
    if (_phase != _Phase.running || _dyingTimer > 0) return;
    if (_smartBombs <= 0) return;
    _smartBombs--;
    for (final e in _enemies) {
      _spawnExplosion(e.x, e.y, _enemyColors[e.type] ?? _mineColor);
    }
    _enemies.clear();
    _enemyMissiles.clear();
    _smartBombFlash = 20;
  }

  // ── Missile movement ──────────────────────────────────────────────────

  void _moveMissiles() {
    _missiles.removeWhere((m) {
      m.x += m.vx;
      m.y += m.vy;
      // Bouncing missiles bounce off top/bottom walls
      if (m.bouncing) {
        if (m.y < _borderW + _missileR) { m.y = _borderW + _missileR; m.vy = -m.vy; }
        if (m.y > _arenaH - _borderW - _missileR) { m.y = _arenaH - _borderW - _missileR; m.vy = -m.vy; }
        // Still remove if out of left/right
        return m.x < 0 || m.x > _arenaW;
      }
      return m.x < 0 || m.x > _arenaW || m.y < 0 || m.y > _arenaH;
    });
  }

  // ── Enemy spawning ────────────────────────────────────────────────────

  void _spawnEnemies() {
    if (_enemies.length >= _maxEnemiesForLevel) return;
    _spawnAccum += 1;
    if (_spawnAccum < _enemySpawnRate) return;
    _spawnAccum = 0;

    final type = _levelEnemyTypes[_rng.nextInt(_levelEnemyTypes.length)];
    final fromLeft = _rng.nextBool();
    final x = fromLeft ? _borderW + 2 : _arenaW - _borderW - 2;
    final gateY = fromLeft ? _leftGateY : _rightGateY;
    final speed = _enemySpeeds[type] ?? 1.0;
    final vx = fromLeft ? speed : -speed;
    final vy = (_rng.nextDouble() - 0.5) * speed * 0.5;

    final enemy = _Enemy(x, gateY, vx, vy, type);
    if (type == _EnemyType.retaliator || type == _EnemyType.tribbler) {
      enemy.health = 2;
    }
    _enemies.add(enemy);
  }

  // ── Enemy movement ────────────────────────────────────────────────────

  void _moveEnemies() {
    final toAdd = <_Enemy>[];
    _enemies.removeWhere((e) {
      e.timer++;
      switch (e.type) {
        case _EnemyType.grunger:
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
        case _EnemyType.zippo:
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
        case _EnemyType.zinger:
          e.param += 0.08;
          final perp = sin(e.param) * 2.0;
          final len = sqrt(e.baseVx * e.baseVx + e.baseVy * e.baseVy);
          if (len > 0.01) {
            e.x += e.baseVx + (-e.baseVy / len) * perp;
            e.y += e.baseVy + (e.baseVx / len) * perp;
          } else {
            e.x += e.vx;
            e.y += e.vy;
          }
          _bounceEnemyWalls(e);
        case _EnemyType.retaliator:
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
          if (e.timer % 120 == 0 && _enemyMissiles.length < 70) {
            final a = atan2(_shipY - e.y, _shipX - e.x);
            _enemyMissiles.add(_EnemyMissile(e.x, e.y, cos(a) * 2.5, sin(a) * 2.5));
          }
        case _EnemyType.miner:
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
          if (e.timer % 90 == 0) {
            _mines.add(_Mine(e.x, e.y));
          }
        case _EnemyType.terrier:
          final dx = _shipX - e.x;
          final dy = _shipY - e.y;
          final d = sqrt(dx * dx + dy * dy);
          if (d > 1) {
            final turnRate = 0.03;
            e.vx += dx / d * turnRate;
            e.vy += dy / d * turnRate;
            final spd = sqrt(e.vx * e.vx + e.vy * e.vy);
            final maxSpd = _enemySpeeds[_EnemyType.terrier]!;
            if (spd > maxSpd) {
              e.vx = e.vx / spd * maxSpd;
              e.vy = e.vy / spd * maxSpd;
            }
          }
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
        case _EnemyType.doinger:
          e.x += e.vx;
          e.y += e.vy;
          // Bounce off all 4 walls
          if (e.y < _borderW + 4) { e.y = _borderW + 4; e.vy = e.vy.abs(); }
          if (e.y > _arenaH - _borderW - 4) { e.y = _arenaH - _borderW - 4; e.vy = -e.vy.abs(); }
          if (e.x < _borderW + 4) { e.x = _borderW + 4; e.vx = e.vx.abs(); }
          if (e.x > _arenaW - _borderW - 4) { e.x = _arenaW - _borderW - 4; e.vx = -e.vx.abs(); }
          return false; // doinger stays until killed
        case _EnemyType.tribbler:
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
        case _EnemyType.tribble:
          e.x += e.vx;
          e.y += e.vy;
          _bounceEnemyWalls(e);
      }
      // Remove if fully exited through opposite gate
      if (e.type != _EnemyType.doinger) {
        if (e.x < -10 || e.x > _arenaW + 10) return true;
      }
      return false;
    });
    _enemies.addAll(toAdd);
  }

  void _bounceEnemyWalls(_Enemy e) {
    if (e.y < _borderW + 4) { e.y = _borderW + 4; e.vy = e.vy.abs(); }
    if (e.y > _arenaH - _borderW - 4) { e.y = _arenaH - _borderW - 4; e.vy = -e.vy.abs(); }
  }

  // ── Enemy missile movement ────────────────────────────────────────────

  void _moveEnemyMissiles() {
    _enemyMissiles.removeWhere((m) {
      m.x += m.vx;
      m.y += m.vy;
      return m.x < 0 || m.x > _arenaW || m.y < 0 || m.y > _arenaH;
    });
  }

  // ── Gate movement ─────────────────────────────────────────────────────

  void _moveGates() {
    _leftGateY += _gateSpeed * _leftGateDir;
    if (_leftGateY - _gateWidth / 2 < _borderW) _leftGateDir = 1;
    if (_leftGateY + _gateWidth / 2 > _arenaH - _borderW) _leftGateDir = -1;

    _rightGateY += _gateSpeed * _rightGateDir;
    if (_rightGateY - _gateWidth / 2 < _borderW) _rightGateDir = 1;
    if (_rightGateY + _gateWidth / 2 > _arenaH - _borderW) _rightGateDir = -1;
  }

  // ── Collision: missiles vs enemies ────────────────────────────────────

  void _checkMissileHits() {
    final toRemoveMissiles = <_Missile>{};
    final toRemoveEnemies = <_Enemy>{};
    final toAddEnemies = <_Enemy>[];

    for (final m in _missiles) {
      for (final e in _enemies) {
        if (toRemoveEnemies.contains(e)) continue;
        final dx = m.x - e.x;
        final dy = m.y - e.y;
        final hitR = _missileR + 5;
        if (dx * dx + dy * dy < hitR * hitR) {
          if (!m.heavy) toRemoveMissiles.add(m);
          e.health--;
          if (e.health <= 0) {
            toRemoveEnemies.add(e);
            _score += _enemyScores[e.type] ?? 50;
            _checkExtraLife();
            _spawnExplosion(e.x, e.y, _enemyColors[e.type] ?? _mineColor);
            // Tribbler splits
            if (e.type == _EnemyType.tribbler) {
              for (var i = 0; i < 2; i++) {
                final a = _rng.nextDouble() * 2 * pi;
                final spd = _enemySpeeds[_EnemyType.tribble]!;
                toAddEnemies.add(_Enemy(e.x, e.y, cos(a) * spd, sin(a) * spd, _EnemyType.tribble));
              }
            }
            // Power-up drop chance
            if (_rng.nextDouble() < 0.15) {
              final puType = _PowerUpType.values[_rng.nextInt(_PowerUpType.values.length)];
              _powerUps.add(_PowerUp(e.x, e.y, puType));
            }
          }
          break;
        }
      }
    }
    _missiles.removeWhere(toRemoveMissiles.contains);
    _enemies.removeWhere(toRemoveEnemies.contains);
    _enemies.addAll(toAddEnemies);
  }

  // ── Collision: enemy missiles vs player ───────────────────────────────

  void _checkEnemyMissileHits() {
    if (_invulnTimer > 0 || _dyingTimer > 0) return;
    _enemyMissiles.removeWhere((m) {
      final dx = m.x - _shipX;
      final dy = m.y - _shipY;
      if (dx * dx + dy * dy < (_shipR + _missileR + 2) * (_shipR + _missileR + 2)) {
        _playerHit();
        return true;
      }
      return false;
    });
  }

  // ── Collision: enemies/mines vs player ────────────────────────────────

  void _checkPlayerCollision() {
    if (_invulnTimer > 0 || _dyingTimer > 0) return;

    for (final e in _enemies) {
      final dx = _shipX - e.x;
      final dy = _shipY - e.y;
      if (dx * dx + dy * dy < (_shipR + 4) * (_shipR + 4)) {
        _playerHit();
        return;
      }
    }

    _mines.removeWhere((m) {
      final dx = _shipX - m.x;
      final dy = _shipY - m.y;
      if (dx * dx + dy * dy < (_shipR + _mineR) * (_shipR + _mineR)) {
        _playerHit();
        return true;
      }
      return false;
    });
  }

  void _playerHit() {
    if (_shieldActive) {
      _shieldActive = false;
      _invulnTimer = 30;
      _spawnExplosion(_shipX, _shipY, const Color(0xFF00FFFF));
      return;
    }
    _lives--;
    _dyingTimer = _dyingDuration;
    _clearPowerUps();
    _spawnExplosion(_shipX, _shipY, _shipColor);
  }

  void _clearPowerUps() {
    _shieldActive = false;
    _aimedFire = false;
    _rapidFire = false;
    _multiFire = false;
    _assFire = false;
    _heavyFire = false;
    _bounceFire = false;
    _powerUpTimer = 0;
  }

  // ── Crystal collection ────────────────────────────────────────────────

  void _collectCrystals() {
    if (_dyingTimer > 0) return;
    for (final c in _crystals) {
      if (c.collected) continue;
      final dx = _shipX - c.x;
      final dy = _shipY - c.y;
      if (dx * dx + dy * dy < (_shipR + _crystalR) * (_shipR + _crystalR)) {
        c.collected = true;
        _score += 100;
        _checkExtraLife();
        // Sparkle particles
        for (var i = 0; i < 6; i++) {
          final a = i * pi / 3;
          _particles.add(_Particle(c.x, c.y, cos(a) * 2, sin(a) * 2, 20, _crystalColor));
        }
      }
    }
  }

  // ── Power-up collection ───────────────────────────────────────────────

  void _collectPowerUps() {
    if (_dyingTimer > 0) return;
    _powerUps.removeWhere((p) {
      final dx = _shipX - p.x;
      final dy = _shipY - p.y;
      if (dx * dx + dy * dy < (_shipR + _powerUpR) * (_shipR + _powerUpR)) {
        _applyPowerUp(p.type);
        return true;
      }
      return false;
    });
  }

  void _applyPowerUp(_PowerUpType type) {
    switch (type) {
      case _PowerUpType.shield:
        _shieldActive = true;
      case _PowerUpType.aimedFire:
        _aimedFire = true;
        _powerUpTimer = _powerUpDuration;
      case _PowerUpType.rapidFire:
        _rapidFire = true;
        _powerUpTimer = _powerUpDuration;
      case _PowerUpType.multiFire:
        _multiFire = true;
        _powerUpTimer = _powerUpDuration;
      case _PowerUpType.assFire:
        _assFire = true;
        _powerUpTimer = _powerUpDuration;
      case _PowerUpType.heavyFire:
        _heavyFire = true;
        _powerUpTimer = _powerUpDuration;
      case _PowerUpType.bounce:
        _bounceFire = true;
        _powerUpTimer = _powerUpDuration;
    }
  }

  void _updatePowerUpTimers() {
    if (_powerUpTimer > 0) {
      _powerUpTimer--;
      if (_powerUpTimer == 0) {
        _aimedFire = false;
        _rapidFire = false;
        _multiFire = false;
        _assFire = false;
        _heavyFire = false;
        _bounceFire = false;
      }
    }
  }

  // ── Level completion ──────────────────────────────────────────────────

  void _checkLevelComplete() {
    if (!_exitOpen && _crystals.every((c) => c.collected)) {
      _exitOpen = true;
    }
  }

  void _checkExitReached() {
    if (!_exitOpen || _dyingTimer > 0) return;
    // Exit through either gate
    final leftGateOpen = (_shipY - _leftGateY).abs() < _gateWidth / 2;
    final rightGateOpen = (_shipY - _rightGateY).abs() < _gateWidth / 2;

    if ((_shipX < _borderW + _shipR + 2 && leftGateOpen) ||
        (_shipX > _arenaW - _borderW - _shipR - 2 && rightGateOpen)) {
      // Time bonus
      final timeBonusSec = (_timeRemaining / 60).floor();
      _score += timeBonusSec * 10;
      _checkExtraLife();
      _phase = _Phase.levelComplete;
      _stopTicker();
    }
  }

  // ── Extra lives ───────────────────────────────────────────────────────

  void _checkExtraLife() {
    if (_score >= _nextLifeAt) {
      _lives++;
      _nextLifeAt += 10000;
    }
  }

  // ── Particle effects ──────────────────────────────────────────────────

  void _spawnExplosion(double x, double y, Color color) {
    final count = min(12, _maxParticles - _particles.length);
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * 2 * pi;
      final spd = 1 + _rng.nextDouble() * 3;
      _particles.add(_Particle(x, y, cos(a) * spd, sin(a) * spd, 20 + _rng.nextInt(15), color));
    }
  }

  void _updateParticles() {
    _particles.removeWhere((p) {
      p.x += p.vx;
      p.y += p.vy;
      p.vx *= 0.96;
      p.vy *= 0.96;
      p.life--;
      return p.life <= 0;
    });
  }

  // ── Timers ────────────────────────────────────────────────────────────

  void _updateTimers() {
    if (_timeRemaining > 0) _timeRemaining--;
    if (_smartBombFlash > 0) _smartBombFlash--;
    // Time up = lose a life
    if (_timeRemaining <= 0 && _dyingTimer == 0) {
      _playerHit();
    }
  }

  // ── Input handlers ────────────────────────────────────────────────────

  void _onPointerMove(PointerEvent event) {
    if (_phase == _Phase.running && _dyingTimer == 0) {
      _mouseAccumDx += event.delta.dx / _currentScale;
      _mouseAccumDy += event.delta.dy / _currentScale;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    if (_phase == _Phase.title) {
      _startGame();
      return;
    }
    if (_phase == _Phase.paused) {
      _resume();
      return;
    }
    if (_phase == _Phase.levelComplete) {
      _nextLevel();
      return;
    }
    if (_phase == _Phase.gameOver) {
      _restart();
      return;
    }
    if (_phase == _Phase.running) {
      if (event.buttons & kPrimaryButton != 0) {
        _fireMissile();
      }
      if (event.buttons & kSecondaryButton != 0) {
        _fireSmartBomb();
      }
    }
  }

  void _onKeyEvent(KeyEvent e) {
    if (e is KeyDownEvent) {
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        if (_phase == _Phase.paused) {
          widget.onClose();
        } else if (_phase == _Phase.running) {
          _pause();
        } else {
          widget.onClose();
        }
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.space) {
        if (_phase == _Phase.running) {
          _pause();
        } else if (_phase == _Phase.paused) {
          _resume();
        } else if (_phase == _Phase.title) {
          _startGame();
        } else if (_phase == _Phase.levelComplete) {
          _nextLevel();
        } else if (_phase == _Phase.gameOver) {
          _restart();
        }
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.keyR) {
        if (_phase == _Phase.paused || _phase == _Phase.gameOver) {
          _restart();
        }
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Container(
        color: _bgColor,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  _currentScale = min(w / _arenaW, h / _arenaH);
                  return Listener(
                    onPointerMove: _onPointerMove,
                    onPointerDown: _onPointerDown,
                    child: MouseRegion(
                      onHover: _onPointerMove,
                      cursor: _phase == _Phase.running
                          ? SystemMouseCursors.none
                          : SystemMouseCursors.basic,
                      child: CustomPaint(
                        size: Size(w, h),
                        painter: _XQuestPainter(
                          phase: _phase,
                          frameTick: _frameTick,
                          shipX: _shipX,
                          shipY: _shipY,
                          shipDir: _shipDir,
                          invulnTimer: _invulnTimer,
                          dyingTimer: _dyingTimer,
                          shieldActive: _shieldActive,
                          missiles: _missiles,
                          enemies: _enemies,
                          enemyMissiles: _enemyMissiles,
                          crystals: _crystals,
                          mines: _mines,
                          powerUps: _powerUps,
                          particles: _particles,
                          exitOpen: _exitOpen,
                          leftGateY: _leftGateY,
                          rightGateY: _rightGateY,
                          gateWidth: _gateWidth,
                          level: _level,
                          score: _score,
                          smartBombFlash: _smartBombFlash,
                          stars: _stars,
                          powerUpTimer: _powerUpTimer,
                          activePowerUps: _getActivePowerUpNames(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getActivePowerUpNames() {
    final names = <String>[];
    if (_shieldActive) names.add('S');
    if (_aimedFire) names.add('A');
    if (_rapidFire) names.add('R');
    if (_multiFire) names.add('M');
    if (_assFire) names.add('F');
    if (_heavyFire) names.add('H');
    if (_bounceFire) names.add('B');
    return names;
  }

  Widget _buildHeader() {
    final crystalsLeft = _crystals.where((c) => !c.collected).length;
    final timeStr = _phase == _Phase.running || _phase == _Phase.paused
        ? '${(_timeRemaining / 60).ceil()}s'
        : '';
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
          Text(
            'XQUEST  L${_level + 1}',
            style: const TextStyle(
              color: _shipColor, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 2, fontFamily: 'monospace',
            ),
          ),
          if (_phase == _Phase.running || _phase == _Phase.paused) ...[
            const SizedBox(width: 12),
            Text(
              '\u25C6$crystalsLeft',
              style: TextStyle(
                color: _exitOpen ? _exitOpenColor : _crystalColor,
                fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 10),
            Text(
              timeStr,
              style: TextStyle(
                color: _timeRemaining < 600 ? _mineColor : Colors.white.withValues(alpha: 0.5),
                fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace',
              ),
            ),
            if (_smartBombs > 0) ...[
              const SizedBox(width: 10),
              Text(
                '\u2737$_smartBombs',
                style: const TextStyle(
                  color: Color(0xFF00CCFF), fontSize: 11,
                  fontWeight: FontWeight.w600, fontFamily: 'monospace',
                ),
              ),
            ],
          ],
          if (!_pauseHintShown && _phase == _Phase.running)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                'SPACE \u00B7 pause',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 9, fontFamily: 'monospace',
                ),
              ),
            ),
          const Spacer(),
          for (var i = 0; i < _lives; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(color: _shipColor, shape: BoxShape.circle),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '$_score',
            style: const TextStyle(
              color: Colors.white, fontSize: 12,
              fontWeight: FontWeight.w600, fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 14, color: Colors.white.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Painter
// ═══════════════════════════════════════════════════════════════════════════

class _XQuestPainter extends CustomPainter {
  final _Phase phase;
  final int frameTick;
  final double shipX, shipY;
  final int shipDir;
  final int invulnTimer, dyingTimer;
  final bool shieldActive;
  final List<_Missile> missiles;
  final List<_Enemy> enemies;
  final List<_EnemyMissile> enemyMissiles;
  final List<_Crystal> crystals;
  final List<_Mine> mines;
  final List<_PowerUp> powerUps;
  final List<_Particle> particles;
  final bool exitOpen;
  final double leftGateY, rightGateY, gateWidth;
  final int level, score;
  final int smartBombFlash;
  final List<Offset> stars;
  final int powerUpTimer;
  final List<String> activePowerUps;

  _XQuestPainter({
    required this.phase,
    required this.frameTick,
    required this.shipX,
    required this.shipY,
    required this.shipDir,
    required this.invulnTimer,
    required this.dyingTimer,
    required this.shieldActive,
    required this.missiles,
    required this.enemies,
    required this.enemyMissiles,
    required this.crystals,
    required this.mines,
    required this.powerUps,
    required this.particles,
    required this.exitOpen,
    required this.leftGateY,
    required this.rightGateY,
    required this.gateWidth,
    required this.level,
    required this.score,
    required this.smartBombFlash,
    required this.stars,
    required this.powerUpTimer,
    required this.activePowerUps,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final scale = min(size.width / _arenaW, size.height / _arenaH);
    final offsetX = (size.width - _arenaW * scale) / 2;
    final offsetY = (size.height - _arenaH * scale) / 2;
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    // 1. Background
    canvas.drawRect(const Rect.fromLTWH(0, 0, _arenaW, _arenaH), Paint()..color = _bgColor);

    // Stars
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    for (final s in stars) {
      canvas.drawCircle(s, 0.6, starPaint);
    }

    // 2. Arena border with gate gaps
    _drawBorder(canvas);

    // 3. Mines
    _drawMines(canvas);

    // 4. Crystals
    _drawCrystals(canvas);

    // 5. Power-ups
    _drawPowerUps(canvas);

    // 6. Enemies
    _drawEnemies(canvas);

    // 7. Missiles
    _drawMissiles(canvas);

    // 8. Enemy missiles
    _drawEnemyMissiles(canvas);

    // 9. Ship
    if (dyingTimer == 0) _drawShip(canvas);

    // 10. Particles
    _drawParticles(canvas);

    // 11. Active power-up indicators
    _drawPowerUpBar(canvas);

    // Smart bomb flash
    if (smartBombFlash > 0) {
      final alpha = (smartBombFlash / 20.0) * 0.4;
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _arenaW, _arenaH),
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }

    // 12. Phase overlays
    _drawOverlay(canvas);

    canvas.restore();
  }

  // Draw an ARGB sprite centered at (cx, cy). Each pixel is 1 logical unit.
  void _drawSprite(Canvas canvas, List<int> pixels, int w, int h, double cx, double cy) {
    final paint = Paint();
    final ox = cx - w / 2;
    final oy = cy - h / 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final argb = pixels[y * w + x];
        if (argb == 0x00000000) continue;
        paint.color = Color(argb);
        canvas.drawRect(Rect.fromLTWH(ox + x, oy + y, 1, 1), paint);
      }
    }
  }

  void _drawBorder(Canvas canvas) {
    final borderPaint = Paint()..color = _borderColor;
    final exitGatePaint = Paint()..color = exitOpen
        ? Color.lerp(_exitOpenColor, _crystalColor, (sin(frameTick * 0.15) + 1) / 2)!
        : _gateColor;

    // Top border
    canvas.drawRect(Rect.fromLTWH(0, 0, _arenaW, _borderW), borderPaint);
    // Bottom border
    canvas.drawRect(Rect.fromLTWH(0, _arenaH - _borderW, _arenaW, _borderW), borderPaint);

    // Left border with gate gap
    final leftGateTop = leftGateY - gateWidth / 2;
    final leftGateBottom = leftGateY + gateWidth / 2;
    canvas.drawRect(Rect.fromLTWH(0, _borderW, _borderW, leftGateTop - _borderW), borderPaint);
    canvas.drawRect(Rect.fromLTWH(0, leftGateBottom, _borderW, _arenaH - _borderW - leftGateBottom), borderPaint);
    // Gate opening
    canvas.drawRect(Rect.fromLTWH(0, leftGateTop, _borderW, gateWidth), exitGatePaint);

    // Right border with gate gap
    final rightGateTop = rightGateY - gateWidth / 2;
    final rightGateBottom = rightGateY + gateWidth / 2;
    canvas.drawRect(Rect.fromLTWH(_arenaW - _borderW, _borderW, _borderW, rightGateTop - _borderW), borderPaint);
    canvas.drawRect(Rect.fromLTWH(_arenaW - _borderW, rightGateBottom, _borderW, _arenaH - _borderW - rightGateBottom), borderPaint);
    canvas.drawRect(Rect.fromLTWH(_arenaW - _borderW, rightGateTop, _borderW, gateWidth), exitGatePaint);

    // Gate glow when exit is open
    if (exitOpen) {
      final glowAlpha = (sin(frameTick * 0.1) + 1) / 2 * 0.3;
      final glowPaint = Paint()
        ..color = _exitOpenColor.withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawRect(Rect.fromLTWH(-2, leftGateTop, _borderW + 4, gateWidth), glowPaint);
      canvas.drawRect(Rect.fromLTWH(_arenaW - _borderW - 2, rightGateTop, _borderW + 4, gateWidth), glowPaint);
    }
  }

  void _drawMines(Canvas canvas) {
    for (final m in mines) {
      // Use enemy mine sprite (smaller, 7x7) for enemy-laid mines
      _drawSprite(canvas, ogEnemyMine, ogEnemyMineW, ogEnemyMineH, m.x, m.y);
      // Blink glow
      if (frameTick % 30 < 15) {
        canvas.drawCircle(
          Offset(m.x, m.y), _mineR + 2,
          Paint()
            ..color = _mineColor.withValues(alpha: 0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
    }
  }

  void _drawCrystals(Canvas canvas) {
    for (final c in crystals) {
      if (c.collected) continue;
      // Glow
      final sparkle = sin(frameTick * 0.1 + c.x * 0.1) * 0.15 + 0.2;
      canvas.drawCircle(
        Offset(c.x, c.y), 7,
        Paint()
          ..color = _crystalColor.withValues(alpha: sparkle)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      _drawSprite(canvas, ogCrystal, ogCrystalW, ogCrystalH, c.x, c.y);
    }
  }

  void _drawPowerUps(Canvas canvas) {
    for (final p in powerUps) {
      final pulse = (sin(frameTick * 0.12 + p.x) + 1) / 2;
      // Glow
      final color = _powerUpColors[p.type] ?? Colors.white;
      canvas.drawCircle(
        Offset(p.x, p.y), 8,
        Paint()
          ..color = color.withValues(alpha: 0.15 + pulse * 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      _drawSprite(canvas, ogSmartBomb, ogSmartBombW, ogSmartBombH, p.x, p.y);
    }
  }

  static const _enemySpriteData = <_EnemyType, (List<int>, int, int)>{
    _EnemyType.grunger: (ogGrunger, ogGrungerW, ogGrungerH),
    _EnemyType.zippo: (ogZippo, ogZippoW, ogZippoH),
    _EnemyType.zinger: (ogZinger, ogZingerW, ogZingerH),
    _EnemyType.retaliator: (ogRetaliator, ogRetaliatorW, ogRetaliatorH),
    _EnemyType.miner: (ogMiner, ogMinerW, ogMinerH),
    _EnemyType.terrier: (ogTerrier, ogTerrierW, ogTerrierH),
    _EnemyType.doinger: (ogDoinger, ogDoingerW, ogDoingerH),
    _EnemyType.tribbler: (ogTribbler, ogTribblerW, ogTribblerH),
    _EnemyType.tribble: (ogTribble, ogTribbleW, ogTribbleH),
  };

  void _drawEnemies(Canvas canvas) {
    for (final e in enemies) {
      final data = _enemySpriteData[e.type];
      if (data != null) {
        _drawSprite(canvas, data.$1, data.$2, data.$3, e.x, e.y);
      }
    }
  }

  void _drawMissiles(Canvas canvas) {
    final paint = Paint()..color = _missileColor;
    final heavyPaint = Paint()..color = const Color(0xFFFF4444);
    for (final m in missiles) {
      final p = m.heavy ? heavyPaint : paint;
      final len = m.heavy ? 4.0 : 2.5;
      final spd = sqrt(m.vx * m.vx + m.vy * m.vy);
      if (spd > 0.01) {
        final nx = m.vx / spd;
        final ny = m.vy / spd;
        canvas.drawLine(
          Offset(m.x - nx * len, m.y - ny * len),
          Offset(m.x + nx * len, m.y + ny * len),
          p..strokeWidth = m.heavy ? 1.5 : 1.0,
        );
      } else {
        canvas.drawCircle(Offset(m.x, m.y), 1.0, p);
      }
    }
  }

  void _drawEnemyMissiles(Canvas canvas) {
    final paint = Paint()..color = const Color(0xFFFF8888);
    for (final m in enemyMissiles) {
      canvas.drawCircle(Offset(m.x, m.y), 1.5, paint);
    }
  }

  void _drawShip(Canvas canvas) {
    if (invulnTimer > 0 && frameTick % 4 < 2) return;

    final center = Offset(shipX, shipY);
    const r = _shipR + 2; // visual radius

    // White filled circle
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFFFFFFFF));

    // Thin yellow plus sign inside
    final plusPaint = Paint()
      ..color = const Color(0xFFFFDD00)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const arm = r - 1.5;
    canvas.drawLine(Offset(shipX - arm, shipY), Offset(shipX + arm, shipY), plusPaint);
    canvas.drawLine(Offset(shipX, shipY - arm), Offset(shipX, shipY + arm), plusPaint);

    // Shield circle
    if (shieldActive) {
      final pulse = (sin(frameTick * 0.15) + 1) / 2;
      canvas.drawCircle(
        center, 10 + pulse * 2,
        Paint()
          ..color = const Color(0xFF00FFFF).withValues(alpha: 0.3 + pulse * 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  void _drawParticles(Canvas canvas) {
    for (final p in particles) {
      final alpha = (p.life / p.maxLife).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(p.x, p.y), 1.0 + alpha,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }
  }

  void _drawPowerUpBar(Canvas canvas) {
    if (activePowerUps.isEmpty) return;
    // Draw small indicators at bottom of arena
    var x = _arenaW / 2 - activePowerUps.length * 7.0;
    for (final name in activePowerUps) {
      final type = _PowerUpType.values.firstWhere(
        (t) => _powerUpLetters[t] == name,
        orElse: () => _PowerUpType.shield,
      );
      final color = _powerUpColors[type] ?? Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(x, _arenaH - _borderW - 12, 12, 10),
        Paint()..color = color.withValues(alpha: 0.3),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(color: color, fontSize: 6, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 6 - tp.width / 2, _arenaH - _borderW - 11));

      // Timer bar
      if (name != 'S' && powerUpTimer > 0) {
        final frac = powerUpTimer / _powerUpDuration;
        canvas.drawRect(
          Rect.fromLTWH(x, _arenaH - _borderW - 2, 12 * frac, 1),
          Paint()..color = color,
        );
      }
      x += 14;
    }
  }

  void _drawOverlay(Canvas canvas) {
    if (phase == _Phase.title) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _arenaW, _arenaH),
        Paint()..color = Colors.black.withValues(alpha: 0.7),
      );
      _drawText(canvas, 'XQUEST', 20, Colors.white, -40);
      _drawText(canvas, 'Збирайте кристали \u2022 Тікайте через ворота', 8, Colors.white.withValues(alpha: 0.5), -10);
      _drawText(canvas, 'Мишка для руху \u2022 Лівий клік — стріляти', 8, Colors.white.withValues(alpha: 0.5), 6);
      _drawText(canvas, 'Правий клік — бомба \u2022 Space — пауза', 8, Colors.white.withValues(alpha: 0.5), 22);
      _drawText(canvas, 'Клік для старту', 10, _shipColor, 50);
    } else if (phase == _Phase.paused) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _arenaW, _arenaH),
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );
      _drawText(canvas, 'ПАУЗА', 18, Colors.white, -10);
      _drawText(canvas, 'Клік або Space для продовження \u00B7 R для перезапуску', 8, Colors.white.withValues(alpha: 0.5), 16);
    } else if (phase == _Phase.levelComplete) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _arenaW, _arenaH),
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );
      _drawText(canvas, 'РІВЕНЬ ${level + 1} ПРОЙДЕНО!', 18, _exitOpenColor, -10);
      _drawText(canvas, 'Клік для наступного рівня', 9, Colors.white.withValues(alpha: 0.5), 16);
    } else if (phase == _Phase.gameOver) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _arenaW, _arenaH),
        Paint()..color = Colors.black.withValues(alpha: 0.7),
      );
      _drawText(canvas, 'КІНЕЦЬ ГРИ', 20, _mineColor, -20);
      _drawText(canvas, 'Рахунок: $score', 10, Colors.white, 10);
      _drawText(canvas, 'Клік для перезапуску', 9, Colors.white.withValues(alpha: 0.5), 30);
    }
  }

  void _drawText(Canvas canvas, String text, double fontSize, Color color, double yOff) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color, fontSize: fontSize,
          fontWeight: FontWeight.w700, fontFamily: 'monospace', letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((_arenaW - tp.width) / 2, (_arenaH - tp.height) / 2 + yOff));
  }

  @override
  bool shouldRepaint(covariant _XQuestPainter old) => true;
}
