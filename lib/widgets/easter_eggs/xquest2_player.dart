// XQuest 2 — Player logic
// Ported from player.c (SGDK/C Sega Genesis), adapted for mouse input.
//
// Control model (same as XQuest 1):
//   Mouse movement → additive velocity with inertia
//   Left-click → fire, Right-click → smartbomb
//   Manhattan speed clamping (maxSpeed = 10)

import 'dart:math';
import 'package:flutter/material.dart';
import 'xquest2_types.dart';
import 'xquest2_world.dart';
import 'xquest2_powerup.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _velScale = 0.14; // mouse delta → velocity scale

// ─── Player Init ─────────────────────────────────────────────────────────────

void playerInit(GameData gd) {
  gd.player = Player(worldW / 2, worldH / 2);
}

// ─── Player Update (called each frame) ───────────────────────────────────────

void playerUpdate(GameData gd, Offset mouseDelta) {
  final p = gd.player;
  if (!p.active) return;

  // Dying animation
  if (p.dying > 0) {
    p.dying--;
    return;
  }

  // Invincibility countdown
  if (p.invincible > 0) p.invincible--;

  // Velocity from mouse delta (additive inertia, same model as XQ1)
  p.vx += mouseDelta.dx * _velScale;
  p.vy += mouseDelta.dy * _velScale;

  // Manhattan speed clamp
  final absX = p.vx.abs();
  final absY = p.vy.abs();
  if (absX + absY > maxSpeed) {
    if (absX > absY) {
      p.vx = (maxSpeed - absY) * p.vx.sign;
    } else {
      p.vy = (maxSpeed - absX) * p.vy.sign;
    }
  }

  // Integrate position
  p.x += p.vx;
  p.y += p.vy;

  // Update ship rotation frame (0-23, based on velocity direction)
  _updateShipFrame(p);

  // Wall collision against tilemap
  _wallCollide(gd);

  // Fire cooldown
  if (p.shootCooldown > 0) p.shootCooldown--;

  // Extra life check
  if (p.score >= p.nextLifeScore) {
    p.lives++;
    p.nextLifeScore += scoreExtraLifeBase;
  }
}

void _updateShipFrame(Player p) {
  if (p.vx.abs() < 0.1 && p.vy.abs() < 0.1) return;
  final angle = atan2(p.vy, p.vx); // -π to π
  // 24 frames covering 360°; frame 0 = pointing right (east)
  final frame = ((angle / (2 * pi) * 24).round() + 24) % 24;
  p.direction = frame;
}

// ─── Wall Collision ───────────────────────────────────────────────────────────

void _wallCollide(GameData gd) {
  final p = gd.player;
  final half = shipHitW / 2;

  // Border clamp (world edges)
  if (p.x - half < 0) {
    p.x = half;
    if (p.vx < 0) p.vx = 0;
  } else if (p.x + half > worldW) {
    p.x = worldW - half;
    if (p.vx > 0) p.vx = 0;
  }
  if (p.y - half < hudHeight) {
    p.y = hudHeight + half;
    if (p.vy < 0) p.vy = 0;
  } else if (p.y + half > worldH) {
    p.y = worldH - half;
    if (p.vy > 0) p.vy = 0;
  }

  // Tile map wall collision — 4 corner tests
  final corners = [
    Offset(p.x - half, p.y - half),
    Offset(p.x + half, p.y - half),
    Offset(p.x - half, p.y + half),
    Offset(p.x + half, p.y + half),
  ];

  bool hitH = false, hitV = false;
  for (final c in corners) {
    if (tileIsSolid(gd, c.dx, c.dy)) {
      if (p.vx.abs() >= p.vy.abs()) {
        hitH = true;
      } else {
        hitV = true;
      }
    }
  }

  if (hitH) {
    p.x -= p.vx;
    p.vx = 0;
  }
  if (hitV) {
    p.y -= p.vy;
    p.vy = 0;
  }

  // Re-check after push
  if (hitH || hitV) {
    for (final c in corners) {
      if (tileIsSolid(gd, c.dx, c.dy)) {
        // Still colliding — full stop
        p.x -= p.vx;
        p.y -= p.vy;
        p.vx = 0;
        p.vy = 0;
        break;
      }
    }
  }
}

// ─── Player Fire ─────────────────────────────────────────────────────────────

void playerFire(GameData gd) {
  final p = gd.player;
  if (!p.active || p.dying > 0 || p.shootCooldown > 0) return;

  final cooldown = powerupActive(gd, PowerUpId.rapidFire)
      ? rapidFireCooldown
      : fireCooldown;
  p.shootCooldown = cooldown;

  // Main shot direction — along velocity, or straight right if stationary
  double dx = p.vx, dy = p.vy;
  final mag = sqrt(dx * dx + dy * dy);
  if (mag < 0.5) { dx = 1; dy = 0; }
  else { dx /= mag; dy /= mag; }

  _spawnPlayerBullet(gd, p.x, p.y, dx * missileSpeed, dy * missileSpeed);

  // MultiFire: two extra bullets at ±15°
  if (powerupActive(gd, PowerUpId.multiFire)) {
    const a = 15.0 * pi / 180.0;
    final cos15 = cos(a), sin15 = sin(a);
    _spawnPlayerBullet(gd, p.x, p.y,
        (dx * cos15 - dy * sin15) * missileSpeed,
        (dx * sin15 + dy * cos15) * missileSpeed);
    _spawnPlayerBullet(gd, p.x, p.y,
        (dx * cos15 + dy * sin15) * missileSpeed,
        (-dx * sin15 + dy * cos15) * missileSpeed);
  }

  // AssFire: rear bullet
  if (powerupActive(gd, PowerUpId.assFire)) {
    _spawnPlayerBullet(gd, p.x, p.y, -dx * missileSpeed, -dy * missileSpeed);
  }

  // AimedFire: extra bullet toward nearest active enemy
  if (powerupActive(gd, PowerUpId.aimedFire)) {
    _fireAimed(gd, p);
  }
}

void _fireAimed(GameData gd, Player p) {
  Enemy? nearest;
  double bestDist = double.infinity;
  for (final e in gd.enemies) {
    if (!e.active) continue;
    final dx = e.x - p.x, dy = e.y - p.y;
    final d = dx * dx + dy * dy;
    if (d < bestDist) { bestDist = d; nearest = e; }
  }
  if (nearest == null) return;
  final dx = nearest.x - p.x, dy = nearest.y - p.y;
  final mag = sqrt(dx * dx + dy * dy);
  if (mag < 1) return;
  _spawnPlayerBullet(gd, p.x, p.y,
      dx / mag * missileSpeed, dy / mag * missileSpeed,
      isHeavy: powerupActive(gd, PowerUpId.heavyFire));
}

void _spawnPlayerBullet(GameData gd, double x, double y, double vx, double vy,
    {bool isHeavy = false}) {
  for (final b in gd.bullets) {
    if (!b.active) {
      b.x = x; b.y = y;
      b.vx = vx; b.vy = vy;
      b.isPlayer = true;
      b.bulletType = BulletType.player;
      b.active = true;
      return;
    }
  }
  // Pool full — add new if under limit
  if (gd.bullets.length < maxBullets) {
    gd.bullets.add(Bullet(x, y, vx, vy, BulletType.player, isPlayer: true));
  }
}

// ─── Smartbomb ───────────────────────────────────────────────────────────────

void smartbombActivate(GameData gd) {
  final p = gd.player;
  if (!p.active || p.smartbombs <= 0) return;
  p.smartbombs--;

  // Destroy all active enemies
  for (final e in gd.enemies) {
    if (!e.active) continue;
    p.score += enemyScoreFor(e.type);
    _spawnExplosion(gd, e.x, e.y);
    e.active = false;
  }
  // Clear enemy bullets
  for (final b in gd.bullets) {
    if (b.active && !b.isPlayer) b.active = false;
  }
}

void _spawnExplosion(GameData gd, double x, double y) {
  for (final ex in gd.explosions) {
    if (!ex.active) { ex.x = x; ex.y = y; ex.active = true; ex.frame = 0; ex.timer = 0; return; }
  }
  if (gd.explosions.length < maxExplosions) {
    gd.explosions.add(Explosion(x, y));
  }
}

int enemyScoreFor(EnemyType t) {
  return [200, 300, 300, 500, 500, 600, 2000, 1000, 1000, 1000, 1250, 500, 1500, 5000, 2000][t.index];
}

// ─── Player Death ────────────────────────────────────────────────────────────

void playerDie(GameData gd) {
  final p = gd.player;
  if (!p.active || p.invincible > 0 || p.dying > 0) return;

  _spawnExplosion(gd, p.x, p.y);
  p.lives--;

  if (p.lives <= 0) {
    p.active = false;
  } else {
    // Respawn at center with invincibility
    p.x = worldW / 2;
    p.y = worldH / 2;
    p.vx = 0;
    p.vy = 0;
    p.dying = dyingDuration;
    p.invincible = invulnDuration;
    // Clear all powerups on death
    for (int i = 0; i < gd.powerupTimer.length; i++) {
      gd.powerupTimer[i] = 0;
    }
  }
}
