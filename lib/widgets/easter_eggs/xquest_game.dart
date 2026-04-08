import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// XQuest-style mini-game — collect all gems, avoid enemies, reach the exit.
/// Inspired by the classic DOS game XQuest (1990s).
class XQuestGame extends StatefulWidget {
  final VoidCallback onClose;

  const XQuestGame({super.key, required this.onClose});

  @override
  State<XQuestGame> createState() => _XQuestGameState();
}

class _Enemy {
  double x, y, vx, vy;
  _Enemy(this.x, this.y, this.vx, this.vy);
}

class _Gem {
  double x, y;
  bool collected;
  _Gem(this.x, this.y) : collected = false;
}

class _GemFx {
  double x, y;
  int frame;
  _GemFx(this.x, this.y) : frame = 0;
}

class _XQuestGameState extends State<XQuestGame> {
  // === Physics constants (in base coordinate space) ===
  static const _ts = 16.0; // base tile size
  static const _pR = 5.0; // player radius
  static const _eR = 5.0; // enemy radius
  static const _gemR = 4.5; // gem collect radius
  static const _accel = 0.35;
  static const _friction = 0.93;
  static const _maxSpeed = 3.0;
  static const _numLevels = 3;

  // === Player state ===
  double _px = 0, _py = 0;
  double _pvx = 0, _pvy = 0;

  // === Camera ===
  double _camX = 0;

  // === Game state ===
  int _score = 0;
  int _lives = 3;
  int _level = 0;
  bool _running = false;
  bool _gameOver = false;
  bool _won = false;
  bool _waitingStart = true;
  bool _levelCleared = false;
  int _flashFrames = 0;
  int _invulnFrames = 0;
  int _exitOpenFrames = 0;
  int _frameTick = 0;
  Timer? _ticker;

  // === Level data ===
  late List<List<int>> _tiles;
  final List<_Gem> _gems = [];
  final List<_Enemy> _enemies = [];
  final List<_GemFx> _gemFx = [];
  final List<Offset> _trail = [];
  int _levelCols = 0, _levelRows = 0;
  int _startTx = 0, _startTy = 0;
  int _exitTx = 0, _exitTy = 0;

  // === Layout ===
  double _gameW = 440, _gameH = 500;

  // === Input ===
  final Set<LogicalKeyboardKey> _keysDown = {};
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _buildLevel(0);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  // =====================================================================
  // Level generation — deterministic rooms with walls, gems, and enemies
  // =====================================================================
  void _buildLevel(int num) {
    final rng = Random(42 + num * 777);

    final w = [60, 75, 90][num.clamp(0, _numLevels - 1)];
    final h = 23;
    final gemCount = [20, 28, 35][num.clamp(0, _numLevels - 1)];
    final enemyCount = [4, 7, 10][num.clamp(0, _numLevels - 1)];
    final enemySpeed = [1.2, 1.6, 2.0][num.clamp(0, _numLevels - 1)];
    final roomW = [14, 11, 9][num.clamp(0, _numLevels - 1)];

    _levelCols = w;
    _levelRows = h;
    _tiles = List.generate(h, (_) => List.filled(w, 0));
    _gems.clear();
    _enemies.clear();
    _gemFx.clear();
    _trail.clear();

    // Border walls
    for (var x = 0; x < w; x++) {
      _tiles[0][x] = 1;
      _tiles[h - 1][x] = 1;
    }
    for (var y = 0; y < h; y++) {
      _tiles[y][0] = 1;
      _tiles[y][w - 1] = 1;
    }

    // Vertical room dividers with doorways
    for (var wx = roomW; wx < w - 4; wx += roomW) {
      for (var y = 1; y < h - 1; y++) {
        _tiles[y][wx] = 1;
      }
      final numDoors = num >= 1 ? 3 : 2;
      final spacing = (h - 4) / numDoors;
      for (var d = 0; d < numDoors; d++) {
        final dy = (2 + spacing * (d + 0.5)).round();
        for (var y = dy - 1; y <= dy + 1; y++) {
          if (y >= 1 && y < h - 1) _tiles[y][wx] = 0;
        }
      }
    }

    // Horizontal obstacles inside rooms
    for (var rx = 1; rx < w - 2; rx += roomW) {
      final rEnd = min(rx + roomW - 1, w - 2);
      if (rEnd - rx < 6) continue;

      if (rng.nextDouble() < 0.7) {
        final wy = h ~/ 3 + rng.nextInt(3) - 1;
        final start = rx + 2;
        final end = min(start + 4 + rng.nextInt(3), rEnd - 1);
        for (var x = start; x < end; x++) {
          _tiles[wy][x] = 1;
        }
        _tiles[wy][(start + end) ~/ 2] = 0;
      }

      if (rng.nextDouble() < 0.7) {
        final wy = 2 * h ~/ 3 + rng.nextInt(3) - 1;
        final start = rx + 2;
        final end = min(start + 4 + rng.nextInt(3), rEnd - 1);
        for (var x = start; x < end; x++) {
          _tiles[wy][x] = 1;
        }
        _tiles[wy][(start + end) ~/ 2] = 0;
      }
    }

    // Start (left side, center)
    _startTx = 2;
    _startTy = h ~/ 2;
    _clearArea(_startTx, _startTy, 2);

    // Exit (right side, center)
    _exitTx = w - 3;
    _exitTy = h ~/ 2;
    _clearArea(_exitTx, _exitTy, 2);

    // Place gems in empty tiles
    var placed = 0;
    for (var attempts = 0; attempts < 2000 && placed < gemCount; attempts++) {
      final gx = 2 + rng.nextInt(w - 4);
      final gy = 2 + rng.nextInt(h - 4);
      if (_tiles[gy][gx] == 0 &&
          !((gx - _startTx).abs() <= 3 && (gy - _startTy).abs() <= 2)) {
        _gems.add(_Gem((gx + 0.5) * _ts, (gy + 0.5) * _ts));
        placed++;
      }
    }

    // Place enemies away from start
    placed = 0;
    for (var attempts = 0; attempts < 2000 && placed < enemyCount; attempts++) {
      final ex = 6 + rng.nextInt(w - 12);
      final ey = 2 + rng.nextInt(h - 4);
      if (_tiles[ey][ex] == 0 && (ex - _startTx).abs() > 5) {
        final angle = rng.nextDouble() * 2 * pi;
        _enemies.add(_Enemy(
          (ex + 0.5) * _ts,
          (ey + 0.5) * _ts,
          cos(angle) * enemySpeed,
          sin(angle) * enemySpeed,
        ));
        placed++;
      }
    }

    // Player start position
    _px = (_startTx + 0.5) * _ts;
    _py = (_startTy + 0.5) * _ts;
    _pvx = 0;
    _pvy = 0;
    _invulnFrames = 0;
    _exitOpenFrames = 0;
    _levelCleared = false;
    _camX = 0;
  }

  void _clearArea(int cx, int cy, int r) {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final y = cy + dy;
        final x = cx + dx;
        if (y >= 1 && y < _levelRows - 1 && x >= 1 && x < _levelCols - 1) {
          _tiles[y][x] = 0;
        }
      }
    }
  }

  bool _isWall(int tx, int ty) {
    if (tx < 0 || ty < 0 || tx >= _levelCols || ty >= _levelRows) return true;
    return _tiles[ty][tx] == 1;
  }

  // =====================================================================
  // Game control
  // =====================================================================
  void _startGame() {
    if (_running) return;
    _running = true;
    _waitingStart = false;
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _gameOver || _won || _levelCleared) return;
    setState(() {
      _frameTick++;
      _handleInput();
      _movePlayer();
      _moveEnemies();
      _collectGems();
      _checkEnemies();
      _checkExit();
      _updateCamera();
      _updateTrail();
      _updateFx();
      if (_flashFrames > 0) _flashFrames--;
      if (_invulnFrames > 0) _invulnFrames--;
      if (_exitOpenFrames > 0) _exitOpenFrames--;
    });
  }

  // =====================================================================
  // Input
  // =====================================================================
  void _handleInput() {
    double ax = 0, ay = 0;
    if (_keysDown.contains(LogicalKeyboardKey.arrowLeft) ||
        _keysDown.contains(LogicalKeyboardKey.keyA)) {
      ax -= _accel;
    }
    if (_keysDown.contains(LogicalKeyboardKey.arrowRight) ||
        _keysDown.contains(LogicalKeyboardKey.keyD)) {
      ax += _accel;
    }
    if (_keysDown.contains(LogicalKeyboardKey.arrowUp) ||
        _keysDown.contains(LogicalKeyboardKey.keyW)) {
      ay -= _accel;
    }
    if (_keysDown.contains(LogicalKeyboardKey.arrowDown) ||
        _keysDown.contains(LogicalKeyboardKey.keyS)) {
      ay += _accel;
    }

    _pvx = (_pvx + ax) * _friction;
    _pvy = (_pvy + ay) * _friction;

    final spd = sqrt(_pvx * _pvx + _pvy * _pvy);
    if (spd > _maxSpeed) {
      _pvx = _pvx / spd * _maxSpeed;
      _pvy = _pvy / spd * _maxSpeed;
    }
    if (spd < 0.05) {
      _pvx = 0;
      _pvy = 0;
    }
  }

  // =====================================================================
  // Player movement + wall collision
  // =====================================================================
  void _movePlayer() {
    _px += _pvx;
    _resolvePlayerWalls(true);
    _py += _pvy;
    _resolvePlayerWalls(false);
  }

  void _resolvePlayerWalls(bool xAxis) {
    final r = _pR;
    final minTx = ((_px - r) / _ts).floor();
    final maxTx = ((_px + r) / _ts).floor();
    final minTy = ((_py - r) / _ts).floor();
    final maxTy = ((_py + r) / _ts).floor();

    for (var ty = minTy; ty <= maxTy; ty++) {
      for (var tx = minTx; tx <= maxTx; tx++) {
        if (!_isWall(tx, ty)) continue;
        final cx = _px.clamp(tx * _ts, (tx + 1) * _ts);
        final cy = _py.clamp(ty * _ts, (ty + 1) * _ts);
        final dx = _px - cx;
        final dy = _py - cy;
        final d = sqrt(dx * dx + dy * dy);
        if (d < r) {
          if (d > 0.001) {
            final overlap = r - d;
            _px += dx / d * overlap;
            _py += dy / d * overlap;
          }
          if (xAxis) {
            _pvx = -_pvx * 0.3;
          } else {
            _pvy = -_pvy * 0.3;
          }
        }
      }
    }
  }

  // =====================================================================
  // Enemy movement — bounce off walls
  // =====================================================================
  void _moveEnemies() {
    for (final e in _enemies) {
      e.x += e.vx;
      _bounceEnemy(e, true);
      e.y += e.vy;
      _bounceEnemy(e, false);
    }
  }

  void _bounceEnemy(_Enemy e, bool xAxis) {
    final r = _eR;
    final minTx = ((e.x - r) / _ts).floor();
    final maxTx = ((e.x + r) / _ts).floor();
    final minTy = ((e.y - r) / _ts).floor();
    final maxTy = ((e.y + r) / _ts).floor();

    for (var ty = minTy; ty <= maxTy; ty++) {
      for (var tx = minTx; tx <= maxTx; tx++) {
        if (!_isWall(tx, ty)) continue;
        final cx = e.x.clamp(tx * _ts, (tx + 1) * _ts);
        final cy = e.y.clamp(ty * _ts, (ty + 1) * _ts);
        final dx = e.x - cx;
        final dy = e.y - cy;
        final d = sqrt(dx * dx + dy * dy);
        if (d < r && d > 0.001) {
          final overlap = r - d;
          e.x += dx / d * overlap;
          e.y += dy / d * overlap;
          if (xAxis) {
            e.vx = -e.vx;
          } else {
            e.vy = -e.vy;
          }
        }
      }
    }
  }

  // =====================================================================
  // Gem collection
  // =====================================================================
  void _collectGems() {
    var wasAllCollected = _exitOpen;
    for (final g in _gems) {
      if (g.collected) continue;
      final dx = _px - g.x;
      final dy = _py - g.y;
      if (dx * dx + dy * dy < (_pR + _gemR) * (_pR + _gemR)) {
        g.collected = true;
        _score += 50;
        _gemFx.add(_GemFx(g.x, g.y));
      }
    }
    if (!wasAllCollected && _exitOpen) {
      _exitOpenFrames = 120;
    }
  }

  // =====================================================================
  // Enemy collision — kills player
  // =====================================================================
  void _checkEnemies() {
    if (_invulnFrames > 0) return;
    for (final e in _enemies) {
      final dx = _px - e.x;
      final dy = _py - e.y;
      if (dx * dx + dy * dy < (_pR + _eR) * (_pR + _eR)) {
        _die();
        return;
      }
    }
  }

  void _die() {
    _lives--;
    if (_lives <= 0) {
      _gameOver = true;
      _running = false;
      _ticker?.cancel();
      return;
    }
    _flashFrames = 15;
    _invulnFrames = 90;
    _px = (_startTx + 0.5) * _ts;
    _py = (_startTy + 0.5) * _ts;
    _pvx = 0;
    _pvy = 0;
    _trail.clear();
  }

  // =====================================================================
  // Exit check
  // =====================================================================
  bool get _exitOpen => _gems.every((g) => g.collected);

  void _checkExit() {
    if (!_exitOpen) return;
    final ex = (_exitTx + 0.5) * _ts;
    final ey = (_exitTy + 0.5) * _ts;
    final dx = _px - ex;
    final dy = _py - ey;
    if (dx * dx + dy * dy < (_pR + _ts * 0.6) * (_pR + _ts * 0.6)) {
      _levelCleared = true;
      _score += 200;
      _running = false;
      _ticker?.cancel();
    }
  }

  // =====================================================================
  // Camera — follows player horizontally
  // =====================================================================
  void _updateCamera() {
    final scale = _gameH / (_levelRows * _ts);
    final viewW = _gameW / scale;
    final target = _px - viewW / 2;
    final maxCam = _levelCols * _ts - viewW;
    final clamped = target.clamp(0.0, max(maxCam, 0.0));
    _camX += (clamped - _camX) * 0.12;
  }

  // =====================================================================
  // Trail + effects
  // =====================================================================
  void _updateTrail() {
    _trail.insert(0, Offset(_px, _py));
    if (_trail.length > 10) _trail.removeLast();
  }

  void _updateFx() {
    for (final f in _gemFx) {
      f.frame++;
    }
    _gemFx.removeWhere((f) => f.frame > 20);
  }

  // =====================================================================
  // Restart / Next level
  // =====================================================================
  void _restart() {
    setState(() {
      _level = 0;
      _score = 0;
      _lives = 3;
      _gameOver = false;
      _won = false;
      _running = false;
      _waitingStart = true;
      _ticker?.cancel();
      _buildLevel(0);
    });
  }

  void _nextLevel() {
    setState(() {
      _level++;
      if (_level >= _numLevels) {
        _won = true;
        return;
      }
      _running = false;
      _waitingStart = true;
      _ticker?.cancel();
      _buildLevel(_level);
    });
  }

  // =====================================================================
  // Build
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
            return;
          }
          _keysDown.add(e.logicalKey);
          if (_waitingStart) _startGame();
        } else if (e is KeyUpEvent) {
          _keysDown.remove(e.logicalKey);
        }
      },
      child: Container(
        color: const Color(0xFF060620),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  _gameW = constraints.maxWidth;
                  _gameH = constraints.maxHeight;
                  return GestureDetector(
                    onTap: () {
                      _focusNode.requestFocus();
                      if (_waitingStart) {
                        _startGame();
                      } else if (_levelCleared) {
                        _nextLevel();
                      } else if (_gameOver || _won) {
                        _restart();
                      }
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _XQuestPainter(
                        tiles: _tiles,
                        levelCols: _levelCols,
                        levelRows: _levelRows,
                        ts: _ts,
                        gems: _gems,
                        enemies: _enemies,
                        gemFx: _gemFx,
                        trail: _trail,
                        px: _px,
                        py: _py,
                        pR: _pR,
                        eR: _eR,
                        camX: _camX,
                        exitTx: _exitTx,
                        exitTy: _exitTy,
                        exitOpen: _exitOpen,
                        gameOver: _gameOver,
                        won: _won,
                        waitingStart: _waitingStart,
                        levelCleared: _levelCleared,
                        level: _level,
                        flashFrames: _flashFrames,
                        invulnFrames: _invulnFrames,
                        exitOpenFrames: _exitOpenFrames,
                        frameTick: _frameTick,
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

  Widget _buildHeader() {
    final gemsLeft = _gems.where((g) => !g.collected).length;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'XQUEST  L${_level + 1}',
            style: const TextStyle(
              color: Color(0xFF00ff88),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '\u25C6$gemsLeft',
            style: TextStyle(
              color:
                  _exitOpen ? const Color(0xFF00ff88) : const Color(0xFFffcc00),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const Spacer(),
          for (var i = 0; i < _lives; i++)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF00ff88),
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
          const SizedBox(width: 8),
          InkWell(
            onTap: widget.onClose,
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
}

// =======================================================================
// Painter
// =======================================================================
class _XQuestPainter extends CustomPainter {
  final List<List<int>> tiles;
  final int levelCols;
  final int levelRows;
  final double ts;
  final List<_Gem> gems;
  final List<_Enemy> enemies;
  final List<_GemFx> gemFx;
  final List<Offset> trail;
  final double px, py, pR, eR;
  final double camX;
  final int exitTx, exitTy;
  final bool exitOpen;
  final bool gameOver, won, waitingStart, levelCleared;
  final int level;
  final int flashFrames, invulnFrames, exitOpenFrames, frameTick;

  _XQuestPainter({
    required this.tiles,
    required this.levelCols,
    required this.levelRows,
    required this.ts,
    required this.gems,
    required this.enemies,
    required this.gemFx,
    required this.trail,
    required this.px,
    required this.py,
    required this.pR,
    required this.eR,
    required this.camX,
    required this.exitTx,
    required this.exitTy,
    required this.exitOpen,
    required this.gameOver,
    required this.won,
    required this.waitingStart,
    required this.levelCleared,
    required this.level,
    required this.flashFrames,
    required this.invulnFrames,
    required this.exitOpenFrames,
    required this.frameTick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final levelPixelH = levelRows * ts;
    final scale = size.height / levelPixelH;
    final viewW = size.width / scale;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(scale, scale);
    canvas.translate(-camX, 0);

    // --- Background stars ---
    final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.04);
    final startCol = max((camX / 24).floor() * 24, 0).toDouble();
    for (var x = startCol; x < camX + viewW + 24; x += 24) {
      for (var y = 0.0; y < levelRows * ts; y += 24) {
        canvas.drawCircle(Offset(x, y), 0.8, starPaint);
      }
    }

    // --- Walls ---
    final wallPaint = Paint()..color = const Color(0xFF2244aa);
    final wallHL = Paint()..color = const Color(0xFF3355cc);
    final wallShadow = Paint()..color = const Color(0xFF112266);

    final visStart = max((camX / ts).floor() - 1, 0);
    final visEnd = min(((camX + viewW) / ts).ceil() + 1, levelCols);

    for (var ty = 0; ty < levelRows; ty++) {
      for (var tx = visStart; tx < visEnd; tx++) {
        if (tiles[ty][tx] != 1) continue;
        final x = tx * ts;
        final y = ty * ts;
        canvas.drawRect(Rect.fromLTWH(x, y, ts, ts), wallPaint);
        // Top + left highlight
        canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, ts - 2, 2), wallHL);
        canvas.drawRect(Rect.fromLTWH(x + 1, y + 1, 2, ts - 2), wallHL);
        // Bottom + right shadow
        canvas.drawRect(
            Rect.fromLTWH(x + 1, y + ts - 3, ts - 2, 2), wallShadow);
        canvas.drawRect(
            Rect.fromLTWH(x + ts - 3, y + 1, 2, ts - 2), wallShadow);
      }
    }

    // --- Exit ---
    final ex = exitTx * ts;
    final ey = exitTy * ts;
    if (exitOpen) {
      final pulse = (sin(frameTick * 0.15) + 1) / 2;
      final exitColor = Color.lerp(
        const Color(0xFF00ff88),
        const Color(0xFFffcc00),
        pulse,
      )!;
      canvas.drawRect(Rect.fromLTWH(ex, ey, ts, ts), Paint()..color = exitColor);
      // Glow
      canvas.drawRect(
        Rect.fromLTWH(ex - 2, ey - 2, ts + 4, ts + 4),
        Paint()
          ..color = exitColor.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(ex, ey, ts, ts),
        Paint()..color = const Color(0xFF333366),
      );
      // X pattern (locked)
      final xPaint = Paint()
        ..color = const Color(0xFF555588)
        ..strokeWidth = 1.5;
      canvas.drawLine(
          Offset(ex + 3, ey + 3), Offset(ex + ts - 3, ey + ts - 3), xPaint);
      canvas.drawLine(
          Offset(ex + ts - 3, ey + 3), Offset(ex + 3, ey + ts - 3), xPaint);
    }

    // --- Gems ---
    final gemPaint = Paint()..color = const Color(0xFFffcc00);
    final gemGlow = Paint()
      ..color = const Color(0xFFffcc00).withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final g in gems) {
      if (g.collected) continue;
      final sparkle = sin(frameTick * 0.1 + g.x * 0.1) * 0.3 + 0.7;
      canvas.drawCircle(Offset(g.x, g.y), 3.5 * sparkle, gemGlow);
      canvas.drawCircle(Offset(g.x, g.y), 2.5, gemPaint);
      // Highlight dot
      canvas.drawCircle(
        Offset(g.x - 0.8, g.y - 0.8),
        1.0,
        Paint()..color = Colors.white.withValues(alpha: 0.6),
      );
    }

    // --- Gem collection effects ---
    for (final f in gemFx) {
      final t = f.frame / 20.0;
      final radius = 6 + t * 14;
      final alpha = (1 - t).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(f.x, f.y),
        radius,
        Paint()
          ..color = const Color(0xFFffcc00).withValues(alpha: alpha * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // --- Enemies ---
    final enemyPaint = Paint()..color = const Color(0xFFff4444);
    final enemyGlow = Paint()
      ..color = const Color(0xFFff4444).withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (final e in enemies) {
      canvas.drawCircle(Offset(e.x, e.y), eR + 2, enemyGlow);
      canvas.drawCircle(Offset(e.x, e.y), eR, enemyPaint);
      // Eyes
      canvas.drawCircle(
        Offset(e.x - 2, e.y - 1),
        1.0,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(e.x + 2, e.y - 1),
        1.0,
        Paint()..color = Colors.white,
      );
    }

    // --- Player trail ---
    for (var i = 0; i < trail.length; i++) {
      final t = i / trail.length;
      final alpha = (1 - t) * 0.25;
      final r = pR * (1 - t * 0.5);
      canvas.drawCircle(
        trail[i],
        r,
        Paint()..color = const Color(0xFF00ff88).withValues(alpha: alpha),
      );
    }

    // --- Player ---
    if (invulnFrames <= 0 || frameTick % 4 < 2) {
      final playerGlow = Paint()
        ..color = const Color(0xFF00ff88).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(px, py), pR + 3, playerGlow);
      canvas.drawCircle(
          Offset(px, py), pR, Paint()..color = const Color(0xFF00ff88));
      // Highlight
      canvas.drawCircle(
        Offset(px - 1.5, py - 1.5),
        1.8,
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
    }

    canvas.restore();

    // --- Flash (death) ---
    if (flashFrames > 0) {
      final alpha = flashFrames / 15.0 * 0.3;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.red.withValues(alpha: alpha),
      );
    }

    // --- EXIT OPEN notification ---
    if (exitOpenFrames > 0 && !waitingStart && !gameOver && !won && !levelCleared) {
      final alpha = (exitOpenFrames / 120.0).clamp(0.0, 1.0);
      _drawText(
        canvas,
        size,
        'EXIT OPEN!',
        16,
        const Color(0xFF00ff88).withValues(alpha: alpha),
        -30,
      );
    }

    // --- Overlay messages ---
    if (gameOver || won || waitingStart || levelCleared) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );

      String title, sub;
      if (gameOver) {
        title = 'GAME OVER';
        sub = 'Click to restart';
      } else if (won) {
        title = 'YOU WIN!';
        sub = 'All levels complete! Click to restart';
      } else if (levelCleared) {
        title = 'LEVEL ${level + 1} CLEAR!';
        sub = 'Click for next level';
      } else {
        title = 'LEVEL ${level + 1}';
        sub = 'Arrow keys / WASD to move \u2022 Collect all gems';
      }

      _drawText(canvas, size, title, 22, Colors.white, 0);
      _drawText(
          canvas, size, sub, 11, Colors.white.withValues(alpha: 0.5), 36);
    }
  }

  void _drawText(
    Canvas c,
    Size s,
    String text,
    double fontSize,
    Color color,
    double yOff,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      c,
      Offset(
        (s.width - tp.width) / 2,
        (s.height - tp.height) / 2 + yOff,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _XQuestPainter old) => true;
}
