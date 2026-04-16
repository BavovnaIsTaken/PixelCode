// XQuest 2 — World systems
// Ported from game.c + tilemap.c (SGDK/C Sega Genesis):
//   Level generation, tilemap, camera, gems, bullets, mines,
//   explosions, powercharges, collision, gate, level completion.

import 'dart:math';
import 'xquest2_types.dart';
import 'xquest2_data.dart';
import 'xquest2_powerup.dart';
import 'xquest2_player.dart';

// ─── Tilemap ──────────────────────────────────────────────────────────────────

bool tileIsSolid(GameData gd, double px, double py) {
  if (px < 0 || px >= worldW || py < hudHeight || py >= worldH) return true;
  final tx = (px / tileW).floor().clamp(0, mapTilesW - 1);
  final ty = ((py - hudHeight) / tileH).floor().clamp(0, mapTilesH - 1);
  return gd.tilemap[ty][tx] == 1;
}

bool tileIsSolidCell(GameData gd, int tx, int ty) {
  if (tx < 0 || tx >= mapTilesW || ty < 0 || ty >= mapTilesH) return true;
  return gd.tilemap[ty][tx] == 1;
}

// ─── Level Generation ─────────────────────────────────────────────────────────

void levelGenerate(GameData gd) {
  final def = levelDef(gd.level);
  final rng = gd.rng;

  // Clear tilemap
  for (int r = 0; r < mapTilesH; r++) {
    for (int c = 0; c < mapTilesW; c++) {
      gd.tilemap[r][c] = 0;
    }
  }

  // Border walls (matching original — only border)
  for (int c = 0; c < mapTilesW; c++) {
    gd.tilemap[0][c] = 1;
    gd.tilemap[mapTilesH - 1][c] = 1;
  }
  for (int r = 0; r < mapTilesH; r++) {
    gd.tilemap[r][0] = 1;
    gd.tilemap[r][mapTilesW - 1] = 1;
  }

  // Gate opening in top border (2 tiles wide, centred)
  gd.gateX = worldW / 2;
  final gateCol = (gd.gateX / tileW).round().clamp(1, mapTilesW - 3);
  gd.tilemap[0][gateCol] = 0;
  gd.tilemap[0][gateCol + 1] = 0;

  // Reset gate state
  gd.gateOpen = false;
  gd.gateAnimFrame = 0;
  gd.gateAnimTimer = 0;

  // Place gems on open floor
  gd.gems.clear();
  gd.gemsRemaining = 0;
  int placed = 0;
  int attempts = 0;
  while (placed < def.numCrystals && attempts < 500) {
    attempts++;
    final x = (tileW + rng.nextInt(((mapTilesW - 2) * tileW).round())).toDouble();
    final y = (hudHeight + tileH + rng.nextInt(((mapTilesH - 2) * tileH).round())).toDouble();
    if (!tileIsSolid(gd, x, y)) {
      gd.gems.add(Gem(x, y));
      gd.gemsRemaining++;
      placed++;
    }
  }

  // Place mines
  gd.mines.clear();
  int mPlaced = 0;
  attempts = 0;
  while (mPlaced < def.numMines && attempts < 500) {
    attempts++;
    final x = (tileW + rng.nextInt(((mapTilesW - 2) * tileW).round())).toDouble();
    final y = (hudHeight + tileH + rng.nextInt(((mapTilesH - 2) * tileH).round())).toDouble();
    if (!tileIsSolid(gd, x, y)) {
      gd.mines.add(Mine(x, y));
      mPlaced++;
    }
  }

  // Place powercharges (attractor pickups for smartbombs)
  gd.powerCharges.clear();
  final numCharges = (1 + rng.nextInt(maxPowerCharges)).clamp(1, maxPowerCharges);
  for (int i = 0; i < numCharges; i++) {
    attempts = 0;
    while (attempts < 100) {
      attempts++;
      final x = (tileW + rng.nextInt(((mapTilesW - 2) * tileW).round())).toDouble();
      final y = (hudHeight + tileH + rng.nextInt(((mapTilesH - 2) * tileH).round())).toDouble();
      if (!tileIsSolid(gd, x, y)) {
        gd.powerCharges.add(PowerCharge(x, y));
        break;
      }
    }
  }

  // Clear leftover entities
  gd.bullets.clear();
  gd.explosions.clear();
  gd.powerUpDrops.clear();
  gd.enemies.clear();

  // Reset level timer
  gd.levelTimer = 0;
}

// ─── Camera ───────────────────────────────────────────────────────────────────
// Border-chase: scroll when player is within CAM_BORDER_H/V of viewport edge.
// Ported from game.c camera_update().

void cameraUpdate(GameData gd) {
  final p = gd.player;
  // Player position in viewport space
  final vpX = p.x - gd.camX;
  final vpY = p.y - gd.camY;

  const leftBorder = camBorderH - screenW / 2;   // player viewport X target left edge
  const rightBorder = screenW - camBorderH + screenW / 2;
  const topBorder = camBorderV;
  const bottomBorder = playFieldH - camBorderV + hudHeight;

  if (vpX < leftBorder) gd.camX = (gd.camX - (leftBorder - vpX) * 0.15).clamp(0, camMaxX);
  if (vpX > rightBorder - screenW) gd.camX = (gd.camX + (vpX - (rightBorder - screenW)) * 0.15).clamp(0, camMaxX);
  if (vpY < topBorder) gd.camY = (gd.camY - (topBorder - vpY) * 0.15).clamp(0, camMaxY);
  if (vpY > bottomBorder) gd.camY = (gd.camY + (vpY - bottomBorder) * 0.15).clamp(0, camMaxY);
}

// ─── Bullets ──────────────────────────────────────────────────────────────────

void spawnBullet(GameData gd, double x, double y, double vx, double vy,
    BulletType type, bool isPlayer) {
  for (final b in gd.bullets) {
    if (!b.active) {
      b.x = x; b.y = y; b.vx = vx; b.vy = vy;
      b.bulletType = type; b.isPlayer = isPlayer; b.active = true;
      return;
    }
  }
  if (gd.bullets.length < maxBullets) {
    gd.bullets.add(Bullet(x, y, vx, vy, type, isPlayer: isPlayer));
  }
}

void bulletsUpdate(GameData gd) {
  for (final b in gd.bullets) {
    if (!b.active) continue;
    b.x += b.vx;
    b.y += b.vy;

    // Out-of-world
    if (b.x < 0 || b.x > worldW || b.y < hudHeight || b.y > worldH) {
      b.active = false;
      continue;
    }

    // Wall hit
    if (tileIsSolid(gd, b.x, b.y)) {
      if (b.isPlayer && powerupActive(gd, PowerUpId.bounce)) {
        // Bounce
        if (tileIsSolid(gd, b.x + b.vx, b.y)) b.vx = -b.vx;
        if (tileIsSolid(gd, b.x, b.y + b.vy)) b.vy = -b.vy;
      } else {
        b.active = false;
      }
    }
  }
}

// ─── Explosions ───────────────────────────────────────────────────────────────

const _explosionFrames = 6;
const _explosionFrameDuration = 4; // frames per anim step

void explosionsUpdate(GameData gd) {
  for (final ex in gd.explosions) {
    if (!ex.active) continue;
    ex.timer++;
    if (ex.timer >= _explosionFrameDuration) {
      ex.timer = 0;
      ex.frame++;
      if (ex.frame >= _explosionFrames) ex.active = false;
    }
  }
}

void spawnExplosion(GameData gd, double x, double y) {
  for (final ex in gd.explosions) {
    if (!ex.active) { ex.x = x; ex.y = y; ex.active = true; ex.frame = 0; ex.timer = 0; return; }
  }
  if (gd.explosions.length < maxExplosions) gd.explosions.add(Explosion(x, y));
}

// ─── Mines ────────────────────────────────────────────────────────────────────

void minesUpdate(GameData gd) {
  // Mines are static — collision handled in collision_check_all
}

void placeMine(GameData gd, double x, double y) {
  for (final m in gd.mines) {
    if (!m.active) { m.x = x; m.y = y; m.active = true; return; }
  }
  if (gd.mines.length < maxMines) gd.mines.add(Mine(x, y));
}

// ─── PowerCharges ─────────────────────────────────────────────────────────────

void powerChargesUpdate(GameData gd) {
  for (final pc in gd.powerCharges) {
    if (!pc.active) continue;
    pc.lifetime--;
    if (pc.lifetime <= 0) pc.active = false;
  }
}

// ─── Collision (all) ─────────────────────────────────────────────────────────
// Ported from collision_check_all() in game.c

bool _rectsOverlap(double ax, double ay, double aw, double ah,
    double bx, double by, double bw, double bh) {
  final ax1 = ax - aw / 2, ax2 = ax + aw / 2;
  final ay1 = ay - ah / 2, ay2 = ay + ah / 2;
  final bx1 = bx - bw / 2, bx2 = bx + bw / 2;
  final by1 = by - bh / 2, by2 = by + bh / 2;
  return ax1 < bx2 && ax2 > bx1 && ay1 < by2 && ay2 > by1;
}

void collisionCheckAll(GameData gd) {
  final p = gd.player;
  if (!p.active || p.invincible > 0 || p.dying > 0) return;

  const phw = shipHitW / 2, phh = shipHitH / 2;

  // Player vs Enemies
  for (final e in gd.enemies) {
    if (!e.active) continue;
    final ehw = enemyHitW[e.type.index] / 2;
    final ehh = enemyHitH[e.type.index] / 2;
    if (_rectsOverlap(p.x, p.y, phw * 2, phh * 2, e.x, e.y, ehw * 2, ehh * 2)) {
      if (!powerupActive(gd, PowerUpId.shield)) {
        playerDie(gd);
        return;
      }
    }
  }

  // Player vs Mines
  for (final m in gd.mines) {
    if (!m.active) continue;
    if (_rectsOverlap(p.x, p.y, phw * 2, phh * 2, m.x, m.y, 10, 10)) {
      m.active = false;
      if (!powerupActive(gd, PowerUpId.shield)) {
        playerDie(gd);
        return;
      }
    }
  }

  // Player vs Gems
  for (final g in gd.gems) {
    if (!g.active || g.collected) continue;
    if (_rectsOverlap(p.x, p.y, phw * 2, phh * 2, g.x, g.y, 12, 12)) {
      g.collected = true;
      g.active = false;
      p.score += 200;
      gd.gemsRemaining--;
    }
  }

  // Player vs PowerCharges (+1 smartbomb)
  for (final pc in gd.powerCharges) {
    if (!pc.active) continue;
    if (_rectsOverlap(p.x, p.y, phw * 2, phh * 2, pc.x, pc.y, 14, 14)) {
      p.smartbombs = (p.smartbombs + 1).clamp(0, maxSmartbombs);
      pc.active = false;
    }
  }

  // Player vs PowerUp drops
  powerUpDropsUpdate(gd);

  // Player bullets vs Enemies
  for (final b in gd.bullets) {
    if (!b.active || !b.isPlayer) continue;
    for (final e in gd.enemies) {
      if (!e.active) continue;
      final ehw = enemyHitW[e.type.index] / 2;
      final ehh = enemyHitH[e.type.index] / 2;
      if (_rectsOverlap(b.x, b.y, 6, 6, e.x, e.y, ehw * 2, ehh * 2)) {
        // HeavyFire pierces — bullet stays active
        if (!powerupActive(gd, PowerUpId.heavyFire)) {
          b.active = false;
        }
        if (powerupActive(gd, PowerUpId.heavyFire)) {
          e.hp = 0;
        } else {
          e.hp--;
        }
        if (e.hp <= 0) {
          enemyDieCallback(gd, e);
        }
        if (!b.active) break;
      }
    }
  }

  // Enemy bullets vs Player
  for (final b in gd.bullets) {
    if (!b.active || b.isPlayer) continue;
    if (_rectsOverlap(b.x, b.y, 6, 6, p.x, p.y, phw * 2, phh * 2)) {
      b.active = false;
      if (!powerupActive(gd, PowerUpId.shield)) {
        playerDie(gd);
        return;
      }
    }
  }
}

// ─── Gate & Level Completion ──────────────────────────────────────────────────

void levelCheckComplete(GameData gd) {
  gd.levelTimer++;

  // Open gate when all gems collected
  if (gd.gemsRemaining <= 0 && !gd.gateOpen) {
    gd.gateOpen = true;
  }

  // Gate animation
  if (gd.gateOpen && gd.gateAnimFrame < 8) {
    gd.gateAnimTimer++;
    if (gd.gateAnimTimer >= 5) {
      gd.gateAnimTimer = 0;
      gd.gateAnimFrame++;
    }
  }

  // Check player flying through gate
  if (gd.gateOpen && gd.gateAnimFrame >= 8) {
    final p = gd.player;
    if (p.active && p.dying == 0) {
      // Gate is at the top border, centred at gateX
      final inGateX = (p.x - gd.gateX).abs() < 20;
      final atTopEdge = p.y < hudHeight + tileH * 1.5;
      if (inGateX && atTopEdge) {
        _onLevelComplete(gd);
      }
    }
  }
}

void _onLevelComplete(GameData gd) {
  // Time bonus
  final def = levelDef(gd.level);
  final elapsed = gd.levelTimer ~/ 60;
  final bonus = ((def.parTime - elapsed) * 10).clamp(0, 5000);
  gd.player.score += bonus;
  gd.lastTimeBonus = bonus;

  gd.level++;
  if (gd.level > 50) gd.level = 50; // cap at 50

  gd.phase = GamePhase.levelComplete;
  gd.levelCompleteTimer = 120; // 2 sec display
}

void levelNext(GameData gd) {
  // Respawn player in centre
  final p = gd.player;
  p.x = worldW / 2;
  p.y = worldH / 2;
  p.vx = 0;
  p.vy = 0;
  p.invincible = invulnDuration;

  levelGenerate(gd);
  gd.phase = GamePhase.running;
}

// ─── Enemy Spawn (simplified — no portal animation) ───────────────────────────

void trySpawnEnemy(GameData gd) {
  final def = levelDef(gd.level);
  final active = gd.enemies.where((e) => e.active).length;
  if (active >= def.maxEnemies) return;

  // Spawn probability check (eReleaseProb / 65536 per frame)
  if (gd.rng.nextInt(65536) >= def.eReleaseProb) return;

  final probs = levelProbsFor(gd.level);
  final type = pickEnemyType(probs, gd.rng.nextInt);
  if (type == null) return;

  // Spawn from left or right edge, at vertical midpoint
  final fromLeft = gd.rng.nextBool();
  final spawnX = fromLeft ? 20.0 : worldW - 20.0;
  final spawnY = hudHeight + playFieldH / 2 + (gd.rng.nextDouble() - 0.5) * 40;

  enemySpawnCallback(gd, type, spawnX, spawnY);
}

// ─── Callbacks (implemented in xquest2_enemy.dart) ────────────────────────────
// Forward declarations — resolved at link time via late function references.

// ignore: prefer_function_declarations_over_variables
void Function(GameData gd, EnemyType type, double x, double y) enemySpawnCallback =
    (gd, type, x, y) {};

// ignore: prefer_function_declarations_over_variables
void Function(GameData gd, Enemy e) enemyDieCallback = (gd, e) {};
