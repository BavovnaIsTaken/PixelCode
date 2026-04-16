// XQuest 2 — Enemy AI (15 types)
// Ported from enemy.c (SGDK/C Sega Genesis)
//
// All 15 AI functions ported 1:1 from C. fix16 → double.
// Curved motion (Meeby/Sticktight) uses rotation matrix: curvesin/curvecos.
// g_game_speed equivalent: gameSpeed double (default 1.0).

import 'dart:math';
import 'xquest2_types.dart';
import 'xquest2_data.dart';
import 'xquest2_world.dart';
import 'xquest2_powerup.dart';

// ─── Game speed scalar (increases when player exceeds par time) ───────────────
double gameSpeed = 1.0;

// ─── Speed scaling ────────────────────────────────────────────────────────────

double _scaledSpeed(Enemy e, double baseSpeed) =>
    baseSpeed * (e.speedScale / 100.0) * gameSpeed;

// ─── Velocity helpers ─────────────────────────────────────────────────────────

void _randomVel(Enemy e, double range, Random rng) {
  e.vx = rng.nextDouble() * range * 2 - range;
  e.vy = rng.nextDouble() * range * 2 - range;
}

void _moveToward(Enemy e, double tx, double ty, double speed) {
  final dx = tx - e.x, dy = ty - e.y;
  final dist = dx.abs() + dy.abs();
  if (dist < 1) return;
  final s = _scaledSpeed(e, speed);
  e.vx = dx / dist * s;
  e.vy = dy / dist * s;
}

// ─── AI Functions (one per enemy type) ────────────────────────────────────────

/// GRUNGER — slow random walk, changedir ~186 frames
void _aiGrunger(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 186) {
    e.aiTimer = gd.rng.nextInt(40);
    _randomVel(e, 0.84, gd.rng);
  }
}

/// ZIPPO — curved random walk, changedir ~372 frames
void _aiZippo(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 372) {
    e.aiTimer = gd.rng.nextInt(60);
    _randomVel(e, 1.96, gd.rng);
    final cs = gd.rng.nextDouble() * 2 * 0.0832 - 0.0832; // ±~4.8°
    e.curveSin = cs;
    e.curveCos = sqrt(max(0, 1 - cs * cs));
  }
}

/// ZINGER — random walk + 4-way burst fire every ~50 frames
void _aiZinger(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 186) {
    e.aiTimer = gd.rng.nextInt(40);
    _randomVel(e, 0.70, gd.rng);
  }
  if (gd.frameCount % 50 == (e.hashCode & 0x3F) % 50) {
    const spd = 1.8;
    spawnBullet(gd, e.x, e.y,  spd,  0,   BulletType.green, false);
    spawnBullet(gd, e.x, e.y,  0,    spd, BulletType.green, false);
    spawnBullet(gd, e.x, e.y, -spd,  0,   BulletType.green, false);
    spawnBullet(gd, e.x, e.y,  0,   -spd, BulletType.green, false);
  }
}

/// VINCE — random walk, changedir ~372 frames, HP=20 (near-invulnerable)
void _aiVince(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 372) {
    e.aiTimer = gd.rng.nextInt(60);
    _randomVel(e, 1.40, gd.rng);
  }
}

/// MINER — slow random walk + mine drop every ~120 frames
void _aiMiner(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 186) {
    e.aiTimer = gd.rng.nextInt(40);
    _randomVel(e, 0.40, gd.rng);
  }
  if (gd.frameCount % 120 == (e.hashCode & 0x7F) % 120) {
    placeMine(gd, e.x, e.y);
  }
}

/// MEEBY — curved motion, re-aims at player periodically
void _aiMeeby(Enemy e, GameData gd) {
  // Apply curve rotation to velocity every frame
  if (e.curveSin != 0) {
    final nvx = e.vx * e.curveCos - e.vy * e.curveSin;
    final nvy = e.vy * e.curveCos + e.vx * e.curveSin;
    e.vx = nvx;
    e.vy = nvy;
  }
  e.aiTimer++;
  if (e.aiTimer >= 186) {
    e.aiTimer = gd.rng.nextInt(40);
    _moveToward(e, gd.player.x, gd.player.y, enemySpeed[EnemyType.meeby.index]);
    final cs = gd.rng.nextDouble() * 2 * 0.0666 - 0.0666;
    e.curveSin = cs;
    e.curveCos = sqrt(max(0, 1 - cs * cs));
  }
}

/// RETALIATOR — periodic homing, fires back when hit (handled in collision), HP=5
void _aiRetaliator(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 100) {
    e.aiTimer = gd.rng.nextInt(30);
    _moveToward(e, gd.player.x, gd.player.y, enemySpeed[EnemyType.retaliator.index]);
  } else if (e.aiTimer == 50) {
    _randomVel(e, 0.56, gd.rng);
  }
}

/// TERRIER — random walk until player within 80px, then hunts
void _aiTerrier(Enemy e, GameData gd) {
  if (e.aiState == 0) {
    e.aiTimer++;
    if (e.aiTimer >= 186) {
      e.aiTimer = gd.rng.nextInt(40);
      _randomVel(e, 0.84, gd.rng);
    }
    final dx = gd.player.x - e.x, dy = gd.player.y - e.y;
    if (dx.abs() < 80 && dy.abs() < 80) e.aiState = 1;
  } else {
    e.aiTimer++;
    if (e.aiTimer >= 30) {
      e.aiTimer = 0;
      _moveToward(e, gd.player.x, gd.player.y, enemySpeed[EnemyType.terrier.index]);
    }
  }
}

/// DOINGER — escalating aggression over time, aimed fire with decreasing cooldown
void _aiDoinger(Enemy e, GameData gd) {
  if (e.aiTimer < 900) e.aiTimer++;
  e.aiState = (e.aiState + 1) % 65536;
  final cd = (56 - e.aiTimer ~/ 30).clamp(20, 56);
  if (e.aiState % cd == 0) {
    final pSpd = gd.player.vx.abs() + gd.player.vy.abs();
    if (pSpd < 1.0) {
      _moveToward(e, gd.player.x, gd.player.y,
          _scaledSpeed(e, 0.75));
    } else {
      final range = (enemySpeed[EnemyType.doinger.index] + e.aiTimer / 1800).clamp(
          enemySpeed[EnemyType.doinger.index], 1.5);
      _randomVel(e, range, gd.rng);
    }
  }
  final fireCd = (90 - e.aiTimer ~/ 15).clamp(30, 90);
  if (gd.frameCount % fireCd == (e.hashCode & 0x1F) % fireCd) {
    const spd = 1.8;
    final dx = gd.player.x - e.x, dy = gd.player.y - e.y;
    final dist = dx.abs() + dy.abs();
    if (dist > 0) {
      spawnBullet(gd, e.x, e.y, dx / dist * spd, dy / dist * spd,
          BulletType.green, false);
    }
  }
}

/// SNIPE — nearly stationary, precise aimed fire every ~150 frames
void _aiSnipe(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 372) {
    e.aiTimer = gd.rng.nextInt(60);
    _randomVel(e, 0.25, gd.rng);
  }
  if (gd.frameCount % 150 == (e.hashCode & 0x7F) % 150) {
    const spd = 2.3;
    final dx = gd.player.x - e.x, dy = gd.player.y - e.y;
    final dist = dx.abs() + dy.abs();
    if (dist > 0) {
      spawnBullet(gd, e.x, e.y, dx / dist * spd, dy / dist * spd,
          BulletType.yellow, false);
    }
  }
}

/// TRIBBLER — random walk, splits on death (see enemyDie)
void _aiTribbler(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 279) {
    e.aiTimer = gd.rng.nextInt(50);
    _randomVel(e, 0.91, gd.rng);
  }
}

/// BUCKSHOT — curved walk + 8-way burst fire every ~60 frames
void _aiBuckshot(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 223) {
    e.aiTimer = gd.rng.nextInt(40);
    _randomVel(e, 1.54, gd.rng);
    final cs = gd.rng.nextDouble() * 2 * 0.0832 - 0.0832;
    e.curveSin = cs;
    e.curveCos = sqrt(max(0, 1 - cs * cs));
  }
  if (gd.frameCount % 60 == (e.hashCode & 0x3F) % 60) {
    const spd = 2.3;
    for (int d = 0; d < 8; d++) {
      spawnBullet(gd, e.x, e.y,
          dirDvx[d] * spd, dirDvy[d] * spd, BulletType.buckshot, false);
    }
  }
}

/// CLUSTER — harmless random walk; splits into Zippos on death (see enemyDie)
void _aiCluster(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 186) {
    e.aiTimer = gd.rng.nextInt(40);
    _randomVel(e, 0.70, gd.rng);
  }
}

/// STICKTIGHT — frequent changes, perpendicular orbit when close to player
void _aiSticktight(Enemy e, GameData gd) {
  e.aiTimer++;
  if (e.aiTimer >= 56) {
    e.aiTimer = gd.rng.nextInt(15);
    final dx = gd.player.x - e.x, dy = gd.player.y - e.y;
    if (dx.abs() < 24 && dy.abs() < 24) {
      // Perpendicular component to orbit player
      final px = -e.vy, py = e.vx;
      final mag = sqrt(px * px + py * py);
      if (mag > 0.01) {
        e.vx += px / mag * 0.3;
        e.vy += py / mag * 0.3;
      }
    } else {
      _randomVel(e, 0.56, gd.rng);
    }
  }
}

/// REPULSOR — always homes toward player, pushes player away within 96px
void _aiRepulsor(Enemy e, GameData gd) {
  _moveToward(e, gd.player.x, gd.player.y, enemySpeed[EnemyType.repulsor.index]);
  final dx = gd.player.x - e.x, dy = gd.player.y - e.y;
  final dist = dx.abs() + dy.abs();
  if (dist > 0 && dist < 96) {
    final force = 12.0 / dist;
    gd.player.vx += dx / dist * force;
    gd.player.vy += dy / dist * force;
  }
}

// ─── AI Dispatch Table ────────────────────────────────────────────────────────

typedef _AiFunc = void Function(Enemy, GameData);

const _aiTable = <_AiFunc>[
  _aiGrunger,    // 0  GRUNGER
  _aiZippo,      // 1  ZIPPO
  _aiZinger,     // 2  ZINGER
  _aiVince,      // 3  VINCE
  _aiMiner,      // 4  MINER
  _aiMeeby,      // 5  MEEBY
  _aiRetaliator, // 6  RETALIATOR
  _aiTerrier,    // 7  TERRIER
  _aiDoinger,    // 8  DOINGER
  _aiSnipe,      // 9  SNIPE
  _aiTribbler,   // 10 TRIBBLER
  _aiBuckshot,   // 11 BUCKSHOT
  _aiCluster,    // 12 CLUSTER
  _aiSticktight, // 13 STICKTIGHT
  _aiRepulsor,   // 14 REPULSOR
];

// ─── Enemy Spawn ──────────────────────────────────────────────────────────────

void enemySpawn(GameData gd, EnemyType type, double x, double y) {
  final e = Enemy(x, y, 0, 0, type);
  e.hp = enemyHp[type.index];
  e.speedScale = 100; // Normal difficulty

  // Curved motion init for Meeby and Sticktight
  if (type == EnemyType.meeby || type == EnemyType.sticktight) {
    final cs = gd.rng.nextDouble() * 2 * 0.0625 - 0.0625;
    e.curveSin = cs;
    e.curveCos = sqrt(max(0, 1 - cs * cs));
  }

  // Initial random velocity
  _randomVel(e, enemySpeed[type.index], gd.rng);

  gd.enemies.add(e);
}

// ─── Enemies Update ───────────────────────────────────────────────────────────

void enemiesUpdate(GameData gd) {
  for (final e in gd.enemies) {
    if (!e.active) continue;

    // Run AI
    _aiTable[e.type.index](e, gd);

    // Apply curved motion (Zippo, Meeby, Buckshot, Sticktight)
    if (e.curveSin != 0) {
      final nvx = e.vx * e.curveCos - e.vy * e.curveSin;
      final nvy = e.vy * e.curveCos + e.vx * e.curveSin;
      e.vx = nvx;
      e.vy = nvy;
    }

    // Integrate position
    e.x += e.vx;
    e.y += e.vy;

    // Boundary bounce
    if (e.x < 10) { e.x = 10; if (e.vx < 0) e.vx = -e.vx; }
    else if (e.x > worldW - 10) { e.x = worldW - 10; if (e.vx > 0) e.vx = -e.vx; }
    if (e.y < hudHeight + 10) { e.y = hudHeight + 10; if (e.vy < 0) e.vy = -e.vy; }
    else if (e.y > worldH - 10) { e.y = worldH - 10; if (e.vy > 0) e.vy = -e.vy; }

    // Wall tile collision — bounce off solid tiles
    if (tileIsSolid(gd, e.x, e.y)) {
      e.x -= e.vx;
      e.y -= e.vy;
      e.vx = -e.vx;
      e.vy = -e.vy;
    }

    // Animation frame cycling (8 frames per step, wraps per type anim count)
    e.animTimer++;
    if (e.animTimer >= 8) {
      e.animTimer = 0;
      e.animFrame = (e.animFrame + 1) % 4; // all enemies have 4 anim frames
    }
  }
}

// ─── Enemy Die ────────────────────────────────────────────────────────────────

void enemyDie(GameData gd, Enemy e) {
  if (!e.active) return;

  gd.player.score += enemyScore[e.type.index];
  spawnExplosion(gd, e.x, e.y);

  // Death effects
  switch (e.type) {
    case EnemyType.sticktight:
      // Radial 8-way bullet burst
      const spd = 2.3;
      for (int d = 0; d < 8; d++) {
        spawnBullet(gd, e.x, e.y,
            dirDvx[d] * spd, dirDvy[d] * spd, BulletType.buckshot, false);
      }
    case EnemyType.retaliator:
      // 4-way burst on death
      const spd = 2.0;
      spawnBullet(gd, e.x, e.y,  spd,  0,   BulletType.purple, false);
      spawnBullet(gd, e.x, e.y, -spd,  0,   BulletType.purple, false);
      spawnBullet(gd, e.x, e.y,  0,    spd, BulletType.purple, false);
      spawnBullet(gd, e.x, e.y,  0,   -spd, BulletType.purple, false);
    case EnemyType.tribbler:
      // Splits into 2 Grungers
      for (int i = 0; i < 2; i++) {
        if (gd.enemies.length < maxEnemies + 4) {
          enemySpawn(gd, EnemyType.grunger,
              e.x + (gd.rng.nextDouble() - 0.5) * 16,
              e.y + (gd.rng.nextDouble() - 0.5) * 16);
        }
      }
    case EnemyType.cluster:
      // Splits into 3 Zippos
      for (int i = 0; i < 3; i++) {
        if (gd.enemies.length < maxEnemies + 6) {
          enemySpawn(gd, EnemyType.zippo,
              e.x + (gd.rng.nextDouble() - 0.5) * 20,
              e.y + (gd.rng.nextDouble() - 0.5) * 20);
        }
      }
    default:
      break;
  }

  // Powerup drop (15% chance)
  maybeDropPowerup(gd, e.x, e.y);

  e.active = false;
}

// ─── Wire callbacks into world.dart ──────────────────────────────────────────

void initEnemyCallbacks() {
  enemySpawnCallback = (gd, type, x, y) => enemySpawn(gd, type, x, y);
  enemyDieCallback = (gd, e) => enemyDie(gd, e);
}
