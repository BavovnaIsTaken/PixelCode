// XQuest 2 — Powerup system
// Ported from powerup.c (SGDK/C Sega Genesis)

import 'dart:math';
import 'xquest2_types.dart';

// ─── Duration ranges (frames @ 60fps) ─────────────────────────────────────────
// Shield:    10-25s  (600-1500f)
// AimedFire: 30-90s  (1800-5400f)
// RapidFire, MultiFire, AssFire, HeavyFire: 60-150s (3600-9000f)
// Bounce:    30-90s  (1800-5400f)

const _puDurMin = <int>[600,  3600, 3600, 3600, 1800, 3600, 1800];
const _puDurRan = <int>[900,  5400, 5400, 5400, 3600, 5400, 3600];

// ─── Query / Award / Tick ────────────────────────────────────────────────────

bool powerupActive(GameData gd, PowerUpId id) =>
    gd.powerupTimer[id.index] > 0;

void powerupAward(GameData gd, PowerUpId id, [Random? rng]) {
  final r = rng ?? Random();
  final duration = _puDurMin[id.index] + r.nextInt(_puDurRan[id.index] + 1);
  final newVal = gd.powerupTimer[id.index] + duration;
  gd.powerupTimer[id.index] = newVal.clamp(0, 65535);
}

void powerupTick(GameData gd) {
  for (int i = 0; i < gd.powerupTimer.length; i++) {
    if (gd.powerupTimer[i] > 0) gd.powerupTimer[i]--;
  }
}

// ─── Drop pickup update ───────────────────────────────────────────────────────

void powerUpDropsUpdate(GameData gd) {
  for (final d in gd.powerUpDrops) {
    if (!d.active) continue;
    d.lifetime--;
    if (d.lifetime <= 0) {
      d.active = false;
      continue;
    }
    // Collect check
    final p = gd.player;
    if (!p.active) continue;
    final dx = d.x - p.x, dy = d.y - p.y;
    if (dx * dx + dy * dy < 20 * 20) {
      powerupAward(gd, d.type, gd.rng);
      d.active = false;
    }
  }
}

// Award random powerup from XQ2 drop table (15% drop from enemy kill)
const _dropTable = <PowerUpId>[
  PowerUpId.rapidFire, PowerUpId.rapidFire, PowerUpId.rapidFire,
  PowerUpId.multiFire, PowerUpId.multiFire, PowerUpId.multiFire,
  PowerUpId.heavyFire, PowerUpId.heavyFire, PowerUpId.heavyFire,
  PowerUpId.assFire,   PowerUpId.assFire,   PowerUpId.assFire,
  PowerUpId.aimedFire, PowerUpId.aimedFire,
  PowerUpId.bounce,    PowerUpId.bounce,
  PowerUpId.shield,
];

void maybeDropPowerup(GameData gd, double x, double y) {
  if (gd.rng.nextInt(100) >= 15) return; // 15% chance
  final type = _dropTable[gd.rng.nextInt(_dropTable.length)];
  for (final d in gd.powerUpDrops) {
    if (!d.active) {
      d.x = x; d.y = y; d.type = type; d.active = true; d.lifetime = 300;
      return;
    }
  }
  gd.powerUpDrops.add(PowerUpDrop(x, y, type));
}
