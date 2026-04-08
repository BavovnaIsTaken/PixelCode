/// Computer type definitions — 6 variants from retro CRT to holographic display.
///
/// Each type provides text-based monitor sprites (8×6 grid) for off/on states,
/// plus frame/glow colors. The painter uses these for the text-sprite fallback
/// rendering path.
///
/// Sprite palette keys:
///   'm' = monitor frame/body
///   'g' = glow dim
///   'G' = glow bright
///   '.' = transparent
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';

// ─── 1. Ретро ЕОМ (CRT) ────────────────────────────────────────────────────

const computerCrt = ComputerType(
  id: 'crt',
  name: 'Ретро ЕОМ',
  nameEn: 'CRT Monitor',
  monitorOff: [
    'mmmmmmmm',
    'mm....mm',
    'mm....mm',
    'mm....mm',
    'mmmmmmmm',
    '..mmmm..',
  ],
  monitorOn0: [
    'mmmmmmmm',
    'mmgGGgmm',
    'mmGggGmm',
    'mmgGGgmm',
    'mmmmmmmm',
    '..mmmm..',
  ],
  monitorOn1: [
    'mmmmmmmm',
    'mmGggGmm',
    'mmgGGgmm',
    'mmGggGmm',
    'mmmmmmmm',
    '..mmmm..',
  ],
  monitorFrame: Color(0xFF3A3A30), // yellowed beige-grey
  monitorGlow: Color(0xFF33FF33),  // classic green phosphor
  monitorGlowDim: Color(0xFF1A8A1A),
);

// ─── 2. Ноутбук (Laptop) ───────────────────────────────────────────────────

const computerLaptop = ComputerType(
  id: 'laptop',
  name: 'Ноутбук',
  nameEn: 'Laptop',
  monitorOff: [
    '........',
    '..mmmm..',
    '..m..m..',
    '..mmmm..',
    '.mmmmmm.',
    '........',
  ],
  monitorOn0: [
    '........',
    '..mmmm..',
    '..mgGm..',
    '..mmmm..',
    '.mmmmmm.',
    '........',
  ],
  monitorOn1: [
    '........',
    '..mmmm..',
    '..mGgm..',
    '..mmmm..',
    '.mmmmmm.',
    '........',
  ],
  monitorFrame: Color(0xFF404050), // dark silver
  monitorGlow: Color(0xFF60A0FF),  // cool blue white
  monitorGlowDim: Color(0xFF3060A0),
);

// ─── 3. Монітор (Standard LCD) — default ───────────────────────────────────

const computerMonitor = ComputerType(
  id: 'monitor',
  name: 'Монітор',
  nameEn: 'LCD Monitor',
  monitorOff: [
    '..mmmm..',
    '.mmmmmm.',
    '.m....m.',
    '.m....m.',
    '.mmmmmm.',
    '...mm...',
  ],
  monitorOn0: [
    '..mmmm..',
    '.mmmmmm.',
    '.mgGGgm.',
    '.mGggGm.',
    '.mmmmmm.',
    '...mm...',
  ],
  monitorOn1: [
    '..mmmm..',
    '.mmmmmm.',
    '.mGggGm.',
    '.mgGGgm.',
    '.mmmmmm.',
    '...mm...',
  ],
  monitorFrame: Color(0xFF2A2A35), // dark grey
  monitorGlow: Color(0xFF00C0D1),  // teal cyan
  monitorGlowDim: Color(0xFF007A84),
);

// ─── 4. Моноблок (iMac-style All-in-One) ───────────────────────────────────

const computerAllInOne = ComputerType(
  id: 'allinone',
  name: 'Моноблок',
  nameEn: 'All-in-One',
  monitorOff: [
    '.mmmmmm.',
    '.m....m.',
    '.m....m.',
    '.m....m.',
    '.mmmmmm.',
    '...mm...',
  ],
  monitorOn0: [
    '.mmmmmm.',
    '.mGGGGm.',
    '.mGgGgm.',
    '.mGGGGm.',
    '.mmmmmm.',
    '...mm...',
  ],
  monitorOn1: [
    '.mmmmmm.',
    '.mgGgGm.',
    '.mGGGGm.',
    '.mgGgGm.',
    '.mmmmmm.',
    '...mm...',
  ],
  monitorFrame: Color(0xFF303040), // aluminium dark
  monitorGlow: Color(0xFFE0E8FF),  // crisp white-blue
  monitorGlowDim: Color(0xFF8090B0),
);

// ─── 5. Ігрова станція (Gaming Setup) ──────────────────────────────────────

const computerGaming = ComputerType(
  id: 'gaming',
  name: 'Ігрова станція',
  nameEn: 'Gaming Setup',
  monitorOff: [
    'mmmmmmmm',
    'm......m',
    'm......m',
    'm......m',
    'mmmmmmmm',
    '.mm..mm.',
  ],
  monitorOn0: [
    'mmmmmmmm',
    'mGgGgGgm',
    'mgGgGgGm',
    'mGgGgGgm',
    'mmmmmmmm',
    '.mm..mm.',
  ],
  monitorOn1: [
    'mmmmmmmm',
    'mgGgGgGm',
    'mGgGgGgm',
    'mgGgGgGm',
    'mmmmmmmm',
    '.mm..mm.',
  ],
  monitorFrame: Color(0xFF1A1A24), // stealth black
  monitorGlow: Color(0xFFFF3068),  // RGB hot pink
  monitorGlowDim: Color(0xFF8818A0), // purple undertone
);

// ─── 6. Голограма (Holographic Display) ─────────────────────────────────────

const computerHologram = ComputerType(
  id: 'hologram',
  name: 'Голограма',
  nameEn: 'Holographic Display',
  monitorOff: [
    '........',
    '...gg...',
    '........',
    '........',
    '...gg...',
    '...mm...',
  ],
  monitorOn0: [
    '..gGGg..',
    '.gGGGGg.',
    '.GGGGGG.',
    '.gGGGGg.',
    '..gGGg..',
    '...mm...',
  ],
  monitorOn1: [
    '..GggG..',
    '.GggggG.',
    '.gggggg.',
    '.GggggG.',
    '..GggG..',
    '...mm...',
  ],
  monitorFrame: Color(0xFF2A2A40), // subtle base
  monitorGlow: Color(0xFF00F0FF),  // cyan hologram
  monitorGlowDim: Color(0xFF0080A0),
);

// ─── All types ──────────────────────────────────────────────────────────────

const allComputerTypes = <ComputerType>[
  computerCrt,
  computerLaptop,
  computerMonitor,
  computerAllInOne,
  computerGaming,
  computerHologram,
];

ComputerType computerTypeById(String id) =>
    allComputerTypes.firstWhere((t) => t.id == id, orElse: () => computerMonitor);

/// Map [HardwareTier] to a visual computer type for rendering.
ComputerType computerForHardware(HardwareTier tier) => switch (tier) {
      HardwareTier.oldLaptop => computerCrt,
      HardwareTier.basicLaptop => computerLaptop,
      HardwareTier.desktopPC => computerMonitor,
      HardwareTier.gamingPC => computerGaming,
      HardwareTier.workstation => computerAllInOne,
      HardwareTier.serverRack => computerHologram,
    };
