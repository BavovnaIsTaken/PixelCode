// XQuest 2 — Level definitions, probability tables, enemy stats
// Ported verbatim from game.c (SGDK/C Sega Genesis)

import 'xquest2_types.dart';

// ─── Enemy Stats ─────────────────────────────────────────────────────────────
// Indexed by EnemyType.index

const enemyHp = <int>[
  1,  // grunger
  1,  // zippo
  1,  // zinger
  20, // vince — rebounds=TRUE in original, simulated as high HP
  1,  // miner
  1,  // meeby
  5,  // retaliator — hits=5 in original
  1,  // terrier
  1,  // doinger
  1,  // snipe
  1,  // tribbler
  1,  // buckshot
  1,  // cluster
  1,  // sticktight
  1,  // repulsor
];

const enemySpeed = <double>[
  0.8,  // grunger
  2.0,  // zippo
  1.2,  // zinger
  1.0,  // vince
  0.6,  // miner
  0.7,  // meeby
  1.0,  // retaliator
  1.8,  // terrier
  0.9,  // doinger
  0.4,  // snipe
  1.0,  // tribbler
  1.5,  // buckshot
  0.5,  // cluster
  1.6,  // sticktight
  1.2,  // repulsor
];

const enemyScore = <int>[
  200,  // grunger
  300,  // zippo
  300,  // zinger
  500,  // vince
  500,  // miner
  600,  // meeby
  2000, // retaliator
  1000, // terrier
  1000, // doinger
  1000, // snipe
  1250, // tribbler
  500,  // buckshot
  1500, // cluster
  5000, // sticktight
  2000, // repulsor
];

// Approximate collision half-sizes per enemy type (for AABB)
const enemyHitW = <double>[
  11, 11, 16, 16, 12, 20, 11, 21, 12, 9, 14, 11, 9, 11, 12,
];
const enemyHitH = <double>[
  11, 11, 16, 16, 12, 20, 13, 8, 12, 9, 14, 11, 9, 11, 12,
];

// ─── 50 Level Definitions ────────────────────────────────────────────────────
// Ported verbatim from game.c g_levels[MAX_LEVEL_DATA]
// eReleaseProb: original float × 65536 (e.g. 0.005 × 65536 = 328)

const levels = <LevelDef>[
  /* 1  */ LevelDef(numCrystals: 15, numMines: 0,  maxEnemies: 20, eReleaseProb: 328,  parTime: 20, newmanScore: 15000),
  /* 2  */ LevelDef(numCrystals: 16, numMines: 3,  maxEnemies: 4,  eReleaseProb: 328,  parTime: 20, newmanScore: 15000),
  /* 3  */ LevelDef(numCrystals: 17, numMines: 4,  maxEnemies: 5,  eReleaseProb: 328,  parTime: 20, newmanScore: 15000),
  /* 4  */ LevelDef(numCrystals: 18, numMines: 5,  maxEnemies: 6,  eReleaseProb: 328,  parTime: 25, newmanScore: 15000),
  /* 5  */ LevelDef(numCrystals: 19, numMines: 6,  maxEnemies: 7,  eReleaseProb: 328,  parTime: 25, newmanScore: 15000),
  /* 6  */ LevelDef(numCrystals: 20, numMines: 6,  maxEnemies: 8,  eReleaseProb: 328,  parTime: 30, newmanScore: 15000),
  /* 7  */ LevelDef(numCrystals: 21, numMines: 7,  maxEnemies: 9,  eReleaseProb: 328,  parTime: 30, newmanScore: 15000),
  /* 8  */ LevelDef(numCrystals: 22, numMines: 7,  maxEnemies: 10, eReleaseProb: 393,  parTime: 35, newmanScore: 20000),
  /* 9  */ LevelDef(numCrystals: 23, numMines: 8,  maxEnemies: 10, eReleaseProb: 393,  parTime: 35, newmanScore: 20000),
  /* 10 */ LevelDef(numCrystals: 24, numMines: 8,  maxEnemies: 10, eReleaseProb: 393,  parTime: 40, newmanScore: 20000),
  /* 11 */ LevelDef(numCrystals: 24, numMines: 9,  maxEnemies: 10, eReleaseProb: 393,  parTime: 40, newmanScore: 20000),
  /* 12 */ LevelDef(numCrystals: 25, numMines: 9,  maxEnemies: 10, eReleaseProb: 458,  parTime: 45, newmanScore: 20000),
  /* 13 */ LevelDef(numCrystals: 25, numMines: 10, maxEnemies: 10, eReleaseProb: 458,  parTime: 45, newmanScore: 40000),
  /* 14 */ LevelDef(numCrystals: 26, numMines: 10, maxEnemies: 10, eReleaseProb: 524,  parTime: 45, newmanScore: 40000),
  /* 15 */ LevelDef(numCrystals: 26, numMines: 10, maxEnemies: 10, eReleaseProb: 524,  parTime: 50, newmanScore: 40000),
  /* 16 */ LevelDef(numCrystals: 27, numMines: 11, maxEnemies: 10, eReleaseProb: 589,  parTime: 50, newmanScore: 40000),
  /* 17 */ LevelDef(numCrystals: 27, numMines: 11, maxEnemies: 10, eReleaseProb: 589,  parTime: 50, newmanScore: 40000),
  /* 18 */ LevelDef(numCrystals: 28, numMines: 11, maxEnemies: 10, eReleaseProb: 655,  parTime: 55, newmanScore: 40000),
  /* 19 */ LevelDef(numCrystals: 28, numMines: 12, maxEnemies: 10, eReleaseProb: 655,  parTime: 55, newmanScore: 40000),
  /* 20 */ LevelDef(numCrystals: 29, numMines: 12, maxEnemies: 10, eReleaseProb: 655,  parTime: 55, newmanScore: 40000),
  /* 21 */ LevelDef(numCrystals: 29, numMines: 12, maxEnemies: 10, eReleaseProb: 655,  parTime: 60, newmanScore: 70000),
  /* 22 */ LevelDef(numCrystals: 30, numMines: 13, maxEnemies: 10, eReleaseProb: 655,  parTime: 60, newmanScore: 70000),
  /* 23 */ LevelDef(numCrystals: 30, numMines: 13, maxEnemies: 10, eReleaseProb: 655,  parTime: 60, newmanScore: 70000),
  /* 24 */ LevelDef(numCrystals: 31, numMines: 13, maxEnemies: 10, eReleaseProb: 655,  parTime: 60, newmanScore: 70000),
  /* 25 */ LevelDef(numCrystals: 31, numMines: 13, maxEnemies: 10, eReleaseProb: 655,  parTime: 65, newmanScore: 70000),
  /* 26 */ LevelDef(numCrystals: 32, numMines: 14, maxEnemies: 10, eReleaseProb: 655,  parTime: 65, newmanScore: 70000),
  /* 27 */ LevelDef(numCrystals: 32, numMines: 14, maxEnemies: 11, eReleaseProb: 655,  parTime: 65, newmanScore: 70000),
  /* 28 */ LevelDef(numCrystals: 33, numMines: 14, maxEnemies: 11, eReleaseProb: 655,  parTime: 65, newmanScore: 70000),
  /* 29 */ LevelDef(numCrystals: 33, numMines: 14, maxEnemies: 12, eReleaseProb: 655,  parTime: 70, newmanScore: 70000),
  /* 30 */ LevelDef(numCrystals: 34, numMines: 15, maxEnemies: 12, eReleaseProb: 655,  parTime: 70, newmanScore: 70000),
  /* 31 */ LevelDef(numCrystals: 34, numMines: 15, maxEnemies: 13, eReleaseProb: 655,  parTime: 70, newmanScore: 70000),
  /* 32 */ LevelDef(numCrystals: 35, numMines: 15, maxEnemies: 13, eReleaseProb: 655,  parTime: 70, newmanScore: 70000),
  /* 33 */ LevelDef(numCrystals: 35, numMines: 15, maxEnemies: 14, eReleaseProb: 655,  parTime: 75, newmanScore: 100000),
  /* 34 */ LevelDef(numCrystals: 36, numMines: 16, maxEnemies: 14, eReleaseProb: 655,  parTime: 75, newmanScore: 100000),
  /* 35 */ LevelDef(numCrystals: 36, numMines: 16, maxEnemies: 15, eReleaseProb: 655,  parTime: 75, newmanScore: 100000),
  /* 36 */ LevelDef(numCrystals: 37, numMines: 16, maxEnemies: 15, eReleaseProb: 655,  parTime: 75, newmanScore: 100000),
  /* 37 */ LevelDef(numCrystals: 37, numMines: 16, maxEnemies: 16, eReleaseProb: 1638, parTime: 80, newmanScore: 100000),
  /* 38 */ LevelDef(numCrystals: 38, numMines: 17, maxEnemies: 16, eReleaseProb: 720,  parTime: 80, newmanScore: 100000),
  /* 39 */ LevelDef(numCrystals: 38, numMines: 17, maxEnemies: 17, eReleaseProb: 786,  parTime: 80, newmanScore: 100000),
  /* 40 */ LevelDef(numCrystals: 39, numMines: 17, maxEnemies: 17, eReleaseProb: 786,  parTime: 80, newmanScore: 100000),
  /* 41 */ LevelDef(numCrystals: 39, numMines: 17, maxEnemies: 18, eReleaseProb: 852,  parTime: 85, newmanScore: 100000),
  /* 42 */ LevelDef(numCrystals: 40, numMines: 18, maxEnemies: 18, eReleaseProb: 852,  parTime: 85, newmanScore: 100000),
  /* 43 */ LevelDef(numCrystals: 40, numMines: 18, maxEnemies: 19, eReleaseProb: 917,  parTime: 85, newmanScore: 100000),
  /* 44 */ LevelDef(numCrystals: 40, numMines: 18, maxEnemies: 19, eReleaseProb: 917,  parTime: 85, newmanScore: 100000),
  /* 45 */ LevelDef(numCrystals: 40, numMines: 18, maxEnemies: 20, eReleaseProb: 983,  parTime: 90, newmanScore: 100000),
  /* 46 */ LevelDef(numCrystals: 40, numMines: 19, maxEnemies: 20, eReleaseProb: 1048, parTime: 90, newmanScore: 100000),
  /* 47 */ LevelDef(numCrystals: 40, numMines: 19, maxEnemies: 20, eReleaseProb: 1048, parTime: 90, newmanScore: 100000),
  /* 48 */ LevelDef(numCrystals: 40, numMines: 19, maxEnemies: 20, eReleaseProb: 1114, parTime: 90, newmanScore: 100000),
  /* 49 */ LevelDef(numCrystals: 40, numMines: 19, maxEnemies: 20, eReleaseProb: 1114, parTime: 90, newmanScore: 100000),
  /* 50 */ LevelDef(numCrystals: 40, numMines: 20, maxEnemies: 20, eReleaseProb: 1179, parTime: 90, newmanScore: 100000),
];

// ─── Per-level Enemy Probability Weights ─────────────────────────────────────
// g_level_probs[50][15] — columns: GR ZP ZI VI MI ME RE TE DO SN TR BK CL ST RP
// Ported verbatim from game.c

const levelProbs = <List<int>>[
  /* 1  */ [60,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 2  */ [100, 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 3  */ [0,   100, 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 4  */ [15,  85,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 5  */ [0,   0,   100, 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 6  */ [15,  15,  70,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 7  */ [0,   0,   0,   100, 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 8  */ [15,  15,  15,  55,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 9  */ [0,   0,   0,   0,   0,   100, 0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 10 */ [15,  15,  15,  15,  0,   50,  0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 11 */ [0,   0,   0,   0,   0,   0,   100, 0,   0,   0,   0,   0,   0,   0,   0],
  /* 12 */ [10,  10,  10,  10,  0,   10,  60,  0,   0,   0,   0,   0,   0,   0,   0],
  /* 13 */ [0,   0,   0,   0,   0,   0,   0,   100, 0,   0,   0,   0,   0,   0,   0],
  /* 14 */ [10,  10,  10,  10,  0,   10,  3,   60,  0,   0,   0,   0,   0,   0,   0],
  /* 15 */ [0,   0,   0,   0,   0,   0,   0,   0,   100, 0,   0,   0,   0,   0,   0],
  /* 16 */ [10,  10,  10,  10,  0,   10,  3,   3,   60,  0,   0,   0,   0,   0,   0],
  /* 17 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   100, 0,   0,   0,   0,   0],
  /* 18 */ [10,  10,  10,  10,  0,   10,  10,  3,   3,   60,  0,   0,   0,   0,   0],
  /* 19 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   100, 0,   0,   0,   0],
  /* 20 */ [10,  10,  10,  10,  0,   10,  10,  5,   3,   3,   60,  0,   0,   0,   0],
  /* 21 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   100, 0],
  /* 22 */ [10,  10,  10,  10,  0,   10,  10,  10,  5,   3,   3,   0,   0,   60,  0],
  /* 23 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   100, 0,   0,   0],
  /* 24 */ [10,  10,  10,  10,  0,   10,  10,  10,  5,   5,   3,   3,   0,   60,  0],
  /* 25 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   100],
  /* 26 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  5,   5,   3,   0,   3,   60],
  /* 27 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  5,   5,   5,   0,   3,   3],
  /* 28 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  5,   5,   0,   3,   3],
  /* 29 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  5,   0,   3,   3],
  /* 30 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   5,   5],
  /* 31 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 32 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 33 */ [0,   100, 0,   100, 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0],
  /* 34 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 35 */ [0,   0,   0,   0,   0,   50,  0,   0,   0,   0,   0,   0,   0,   50,  0],
  /* 36 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 37 */ [0,   0,   0,   0,   0,   0,   50,  0,   0,   0,   0,   50,  0,   0,   0],
  /* 38 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 39 */ [0,   0,   0,   0,   0,   0,   0,   50,  0,   50,  0,   0,   0,   0,   0],
  /* 40 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 41 */ [0,   0,   0,   0,   0,   0,   0,   0,   50,  0,   50,  0,   0,   0,   0],
  /* 42 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 43 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   50,  50],
  /* 44 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 45 */ [0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   50,  50],
  /* 46 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 47 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 48 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 49 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
  /* 50 */ [10,  10,  10,  10,  0,   10,  10,  10,  10,  10,  10,  10,  0,   10,  10],
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

LevelDef levelDef(int level) {
  final idx = (level - 1).clamp(0, levels.length - 1);
  return levels[idx];
}

List<int> levelProbsFor(int level) {
  final idx = (level - 1).clamp(0, levelProbs.length - 1);
  return levelProbs[idx];
}

/// Weighted random enemy type selection from probability table.
/// Returns null if all weights are zero.
EnemyType? pickEnemyType(List<int> probs, int Function(int) nextInt) {
  final total = probs.fold(0, (a, b) => a + b);
  if (total == 0) return null;
  var roll = nextInt(total);
  for (int i = 0; i < probs.length; i++) {
    roll -= probs[i];
    if (roll < 0) return EnemyType.values[i];
  }
  return EnemyType.values.first;
}
