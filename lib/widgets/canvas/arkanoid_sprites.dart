/// Text-sprite catalog for the Arkanoid easter-egg.
///
/// All bricks are 14×6, paddle is 20×3, ball is 6×6, powerups are 14×5.
/// Glyph palette is intentionally distinct from `furniture_sprites.dart` —
/// shared letters here mean office-themed accent colors (monitor glow,
/// glass tint, trophy gold…). Resolver: [resolveArkanoidSpriteColor].
///
/// The painter centres sprites within the brick/paddle/ball/powerup hit
/// rect with `min(rectW/spriteW, rectH/spriteH)`, so aspect ratios above
/// only need to be *close* — letterboxing keeps them inside their slot.
library;

import 'package:flutter/material.dart';

// ─── Colour resolver ────────────────────────────────────────────────────────

Color resolveArkanoidSpriteColor(String key) => switch (key) {
      // ── Office monitor (normal bricks) ──
      'M' => const Color(0xFF2A2A35), // monitor frame (matte)
      'm' => const Color(0xFF1A1A22), // frame shadow
      'g' => const Color(0xFF00C0D1), // screen glow cyan
      'G' => const Color(0xFF7AF2FF), // screen highlight
      'p' => const Color(0xFF9B5BFF), // screen glow purple variant
      'P' => const Color(0xFFE0BFFF), // purple highlight
      'o' => const Color(0xFFFF8C42), // screen glow orange variant
      'O' => const Color(0xFFFFCFA8), // orange highlight
      'e' => const Color(0xFF44CC44), // screen glow green variant
      'E' => const Color(0xFFA8FFA8), // green highlight
      // ── Glass partition ──
      'l' => const Color(0xFF88CCFF), // glass body (lit)
      'L' => const Color(0xFFD0EEFF), // glass highlight
      'd' => const Color(0xFF4477AA), // glass edge / frame
      'c' => const Color(0xFFFFFFFF), // crack lines (high contrast white)
      // ── Trophy (gold brick) ──
      'Y' => const Color(0xFFFFCC00), // trophy gold
      'y' => const Color(0xFFB8860B), // gold shadow
      'Z' => const Color(0xFF6B4423), // wooden base
      // ── Fire extinguisher (blast brick / blast ball) ──
      'R' => const Color(0xFFCC2222), // canister red
      'r' => const Color(0xFF881111), // canister red shadow
      'H' => const Color(0xFFEEEEEE), // hose / label highlight
      'h' => const Color(0xFF888888), // hose shadow / nozzle
      'N' => const Color(0xFF222222), // nozzle dark
      // ── Filing cabinet (steel brick) ──
      'S' => const Color(0xFF8899AA), // steel face
      's' => const Color(0xFF556677), // steel shadow
      'k' => const Color(0xFF334455), // drawer line / handle dark
      'K' => const Color(0xFFCCCCDD), // handle highlight
      // ── Desk paddle ──
      'w' => const Color(0xFF8B6F47), // desk wood mid
      'W' => const Color(0xFFB89473), // desk wood highlight
      'b' => const Color(0xFF3E2B22), // desk wood shadow / edge
      // ── Coffee ball ──
      'C' => const Color(0xFFD9B48F), // ceramic cup wall
      'B' => const Color(0xFF6B4423), // coffee liquid
      'F' => const Color(0xFFFAE3C2), // ceramic highlight
      // ── Powerup capsule body ──
      '#' => const Color(0xFF0A0A1A), // capsule body (dark)
      '+' => const Color(0xFF44CC44), // expand green
      '*' => const Color(0xFFAA44FF), // multiball purple
      '@' => const Color(0xFFFFCC00), // sticky yellow
      '!' => const Color(0xFFFF4444), // laser red
      '~' => const Color(0xFF00CCFF), // thru cyan
      '%' => const Color(0xFFFF88AA), // life pink
      '<' => const Color(0xFF4488FF), // slow blue
      '>' => const Color(0xFFFF8800), // blast orange
      // ── Common: transparent + outline white ──
      'i' => const Color(0xFFFFFFFF), // inner icon white (on capsule)
      '.' => const Color(0x00000000),
      _ => const Color(0x00000000),
    };

// ─── Free-standing sprites referenced as top-level constants ────────────────

/// Office desk seen from the side — 20 cols × 3 rows. Matches the painter's
/// paddle hit rect (≈ 64×11 dp, scaled by `min(rectW/sw, rectH/sh)`).
const deskPaddleSprite = <String>[
  'bWWWWWWWWWWWWWWWWWWb',
  'bwwwwwwwwwwwwwwwwwwb',
  'b..b..b......b..b..b',
];

/// Coffee-cup-from-above — 6×6 disc shape used as the default ball.
const coffeeBallSprite6x6 = <String>[
  '.CCCC.',
  'CFFFFC',
  'CFBBFC',
  'CFBBFC',
  'CFFFFC',
  '.CCCC.',
];

/// Mini fire-extinguisher used as the blast-mode ball.
const fireExtinguisherSprite = <String>[
  '..NN..',
  '.HhhH.',
  'RRRRRR',
  'RrrrrR',
  'RRRRRR',
  '.rrrr.',
];

// ─── Catalog ───────────────────────────────────────────────────────────────

/// Static catalog of brick + powerup sprites. Bricks are 14×6 (≈ 2.15:1
/// aspect, matching the painter's brick rect) and powerups are 14×5 (≈ 2.8:1,
/// matching the capsule rect).
class ArkanoidSprites {
  ArkanoidSprites._();

  // ── Monitor bricks (per-row variants for visual rhythm) ──────────────────
  static const List<List<String>> monitorBrickVariants = <List<String>>[
    // Cyan monitor
    <String>[
      'mMMMMMMMMMMMMm',
      'MMggggggggggMM',
      'MMgGgggggggGgM',
      'MMggggggggggMM',
      'MMggggggggggMM',
      'mMMMMMMMMMMMMm',
    ],
    // Purple monitor
    <String>[
      'mMMMMMMMMMMMMm',
      'MMppppppppppMM',
      'MMpPpppppppPpM',
      'MMppppppppppMM',
      'MMppppppppppMM',
      'mMMMMMMMMMMMMm',
    ],
    // Orange monitor
    <String>[
      'mMMMMMMMMMMMMm',
      'MMooooooooooMM',
      'MMoOoooooooOoM',
      'MMooooooooooMM',
      'MMooooooooooMM',
      'mMMMMMMMMMMMMm',
    ],
    // Green monitor
    <String>[
      'mMMMMMMMMMMMMm',
      'MMeeeeeeeeeeMM',
      'MMeEeeeeeeeEeM',
      'MMeeeeeeeeeeMM',
      'MMeeeeeeeeeeMM',
      'mMMMMMMMMMMMMm',
    ],
  ];

  // ── Glass partition (2-hit) ──────────────────────────────────────────────
  static const List<String> glassPartition = <String>[
    'dddddddddddddd',
    'dlllLlllllllld',
    'dllllllllLllld',
    'dlllllllllllld',
    'dlLlllllllllld',
    'dddddddddddddd',
  ];

  // ── Cracked glass (1-hit, after first crack) ─────────────────────────────
  static const List<String> crackedGlass = <String>[
    'dddddddddddddd',
    'dllc.lllllllld',
    'dl.ccclllllLld',
    'dllllc..llllld',
    'dlLllcclllllld',
    'dddddddddddddd',
  ];

  // ── Trophy (gold brick) ──────────────────────────────────────────────────
  static const List<String> trophy = <String>[
    '..YYYYYYYYYY..',
    '.YYyyyyyyyyYY.',
    '.YYyYYYYYYyYY.',
    '..yyyyyyyyyy..',
    '....YYYYYY....',
    '...ZZZZZZZZ...',
  ];

  // ── Fire extinguisher (blast brick) ──────────────────────────────────────
  static const List<String> fireExtinguisher = <String>[
    '......NN......',
    '....HhhhH.....',
    '...RRRRRRR....',
    '...RrrrrRr....',
    '...RRRRRRR....',
    '....rrrrr.....',
  ];

  // ── Filing cabinet (steel brick) ─────────────────────────────────────────
  static const List<String> filingCabinet = <String>[
    'SSSSSSSSSSSSSS',
    'SkkkkSkkkkSkkk',
    'SSSSSSSSSSSSSS',
    'SkkkkSkkkkSkkk',
    'SSSSSSSSSSSSSS',
    'ssssssssssssss',
  ];

  // ── Powerups (14×5) — capsule background "#" + 1-glyph icon body ────────
  // Capsule: rounded body with the powerup color filling the inside
  // and a single bright glyph in the centre.

  static const List<String> expandPowerup = <String>[
    '.############.',
    '#++++++++++++#',
    '#+i+i+++++i+i#',
    '#++++++++++++#',
    '.############.',
  ];

  static const List<String> multiballPowerup = <String>[
    '.############.',
    '#************#',
    '#*i*i**i**i*i#',
    '#************#',
    '.############.',
  ];

  static const List<String> stickyPowerup = <String>[
    '.############.',
    '#@@@@@@@@@@@@#',
    '#@i@@iiii@@i@#',
    '#@@@@@@@@@@@@#',
    '.############.',
  ];

  static const List<String> laserPowerup = <String>[
    '.############.',
    '#!!!!!!!!!!!!#',
    '#i!!!!ii!!!!i#',
    '#!!!!!!!!!!!!#',
    '.############.',
  ];

  static const List<String> thruPowerup = <String>[
    '.############.',
    '#~~~~~~~~~~~~#',
    '#i~~i~~~~i~~i#',
    '#~~~~~~~~~~~~#',
    '.############.',
  ];

  static const List<String> lifePowerup = <String>[
    '.############.',
    '#%%%%%%%%%%%%#',
    '#%i%%i%%i%%i%#',
    '#%%%%%%%%%%%%#',
    '.############.',
  ];

  static const List<String> slowPowerup = <String>[
    '.############.',
    '#<<<<<<<<<<<<#',
    '#i<<i<<<<i<<i#',
    '#<<<<<<<<<<<<#',
    '.############.',
  ];

  static const List<String> blastPowerup = <String>[
    '.############.',
    '#>>>>>>>>>>>>#',
    '#i>>i>>>>i>>i#',
    '#>>>>>>>>>>>>#',
    '.############.',
  ];
}
