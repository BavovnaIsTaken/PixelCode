// XQuest 2 — Types, enums, constants, and data classes
// Ported from xquest.h (SGDK/C Sega Genesis)

import 'dart:math';

// ─── World / Display Constants ───────────────────────────────────────────────

const worldW = 392.0;
const worldH = 320.0;
const screenW = 320.0;
const playFieldH = 208.0;
const hudHeight = 16.0;
const tileW = 16;
const tileH = 16;
const mapTilesW = 25; // worldW / tileW ceil
const mapTilesH = 20; // worldH / tileH ceil

// Camera
const camMaxX = worldW - screenW; // 72
const camMaxY = worldH - playFieldH; // 112
const camBorderH = 140.0;
const camBorderV = 104.0;

// ─── Pool Sizes ──────────────────────────────────────────────────────────────

const maxGems = 64;
const maxEnemies = 24;
const maxBullets = 32;
const maxMines = 20;
const maxPowerCharges = 4;
const maxExplosions = 16;

// ─── Player Constants ────────────────────────────────────────────────────────

const initialLives = 3;
const maxSmartbombs = 9;
const shipHitW = 10.0;
const shipHitH = 10.0;
const shipCollisionR = 6.0;
const missileSpeed = 5.0;
const missileR = 1.5;
const maxSpeed = 10.0; // Manhattan speed clamp
const fireCooldown = 8; // frames
const rapidFireCooldown = 4;
const invulnDuration = 120; // frames post-death
const dyingDuration = 40;
const scoreExtraLifeBase = 15000;

// ─── Enums ───────────────────────────────────────────────────────────────────

enum Direction {
  right, upRight, up, upLeft, left, downLeft, down, downRight, none;
}

const dirDvx = <double>[1, 1, 0, -1, -1, -1, 0, 1];
const dirDvy = <double>[0, -1, -1, -1, 0, 1, 1, 1];

enum EnemyType {
  grunger,
  zippo,
  zinger,
  vince,
  miner,
  meeby,
  retaliator,
  terrier,
  doinger,
  snipe,
  tribbler,
  buckshot,
  cluster,
  sticktight,
  repulsor;
}

enum BulletType { player, green, yellow, purple, buckshot }

enum GamePhase { title, running, paused, levelComplete, gameOver }

enum PowerUpId {
  shield,
  rapidFire,
  multiFire,
  assFire,
  aimedFire,
  heavyFire,
  bounce;
}

// ─── Data Classes ────────────────────────────────────────────────────────────

class Player {
  double x, y;
  double vx = 0, vy = 0;
  int lives = initialLives;
  int smartbombs = 3;
  int score = 0;
  int shootCooldown = 0;
  int invincible = 0; // frames remaining
  int dying = 0; // frames remaining in death anim
  bool active = true;
  int nextLifeScore = scoreExtraLifeBase;
  int direction = 0; // 0-23 rotation frame index for ship sprite

  Player(this.x, this.y);
}

class Enemy {
  double x, y;
  double vx, vy;
  EnemyType type;
  int hp = 1;
  bool active = true;
  int aiTimer = 0;
  int aiState = 0;
  int animFrame = 0;
  int animTimer = 0;
  // Curved motion (Meeby, Sticktight)
  double curveSin = 0;
  double curveCos = 1;
  // Difficulty speed scale (100 = normal)
  int speedScale = 100;

  Enemy(this.x, this.y, this.vx, this.vy, this.type);
}

class Bullet {
  double x, y;
  double vx, vy;
  bool active = true;
  bool isPlayer;
  BulletType bulletType;

  Bullet(this.x, this.y, this.vx, this.vy, this.bulletType, {this.isPlayer = true});
}

class Gem {
  double x, y;
  bool active = true;
  bool collected = false;

  Gem(this.x, this.y);
}

class Mine {
  double x, y;
  bool active = true;

  Mine(this.x, this.y);
}

class PowerCharge {
  double x, y;
  bool active = true;
  int lifetime = 600; // 10 sec

  PowerCharge(this.x, this.y);
}

class Explosion {
  double x, y;
  bool active = true;
  int frame = 0;
  int timer = 0;

  Explosion(this.x, this.y);
}

class PowerUpDrop {
  double x, y;
  bool active = true;
  PowerUpId type;
  int lifetime = 300; // 5 sec
  String get letter {
    switch (type) {
      case PowerUpId.shield: return 'S';
      case PowerUpId.aimedFire: return 'A';
      case PowerUpId.rapidFire: return 'R';
      case PowerUpId.multiFire: return 'M';
      case PowerUpId.assFire: return 'F';
      case PowerUpId.heavyFire: return 'H';
      case PowerUpId.bounce: return 'B';
    }
  }

  PowerUpDrop(this.x, this.y, this.type);
}

// ─── Level Definition ────────────────────────────────────────────────────────

class LevelDef {
  final int numCrystals;
  final int numMines;
  final int maxEnemies;
  final int eReleaseProb; // spawn probability x65536 per frame per type
  final int parTime; // seconds
  final int newmanScore; // score for extra life

  const LevelDef({
    required this.numCrystals,
    required this.numMines,
    required this.maxEnemies,
    required this.eReleaseProb,
    required this.parTime,
    required this.newmanScore,
  });
}

// ─── Game Data (master state) ────────────────────────────────────────────────

class GameData {
  late Player player;
  final List<Enemy> enemies = [];
  final List<Bullet> bullets = [];
  final List<Gem> gems = [];
  final List<Mine> mines = [];
  final List<PowerCharge> powerCharges = [];
  final List<Explosion> explosions = [];
  final List<PowerUpDrop> powerUpDrops = [];

  int level = 1;
  int gemsRemaining = 0;
  bool gateOpen = false;
  int gateAnimFrame = 0;
  int gateAnimTimer = 0;
  double gateX = worldW / 2; // gate center X
  int levelTimer = 0; // frames elapsed in level

  GamePhase phase = GamePhase.title;

  // Camera
  double camX = camMaxX / 2;
  double camY = camMaxY / 2;

  // Powerup timers (frames remaining, 0 = inactive)
  final List<int> powerupTimer = List.filled(PowerUpId.values.length, 0);

  // Tile map (20 rows x 25 cols, 0=floor, 1=wall)
  final List<List<int>> tilemap = List.generate(
    mapTilesH, (_) => List.filled(mapTilesW, 0),
  );

  // Stars (background, static)
  late List<double> starX;
  late List<double> starY;

  // Frame counter
  int frameCount = 0;

  // Level complete timer (for brief display)
  int levelCompleteTimer = 0;

  // Score display for time bonus
  int lastTimeBonus = 0;

  // Random
  final Random rng = Random();

  GameData() {
    player = Player(worldW / 2, worldH / 2);
    _initStars();
  }

  void _initStars() {
    starX = List.generate(80, (_) => rng.nextDouble() * worldW);
    starY = List.generate(80, (_) => rng.nextDouble() * worldH);
  }

  void reset() {
    player = Player(worldW / 2, worldH / 2);
    enemies.clear();
    bullets.clear();
    gems.clear();
    mines.clear();
    powerCharges.clear();
    explosions.clear();
    powerUpDrops.clear();
    level = 1;
    gemsRemaining = 0;
    gateOpen = false;
    gateAnimFrame = 0;
    gateAnimTimer = 0;
    gateX = worldW / 2;
    levelTimer = 0;
    phase = GamePhase.running;
    camX = camMaxX / 2;
    camY = camMaxY / 2;
    for (int i = 0; i < powerupTimer.length; i++) {
      powerupTimer[i] = 0;
    }
    for (int r = 0; r < mapTilesH; r++) {
      for (int c = 0; c < mapTilesW; c++) {
        tilemap[r][c] = 0;
      }
    }
    frameCount = 0;
    levelCompleteTimer = 0;
    lastTimeBonus = 0;
  }
}
