/// Room theme definitions — 5 tiers mapped to [OfficeLevel] from game economy.
///
/// Each theme provides wall, floor, desk, and accent colors that the
/// painter uses to render the office environment.
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import '../../models/resource_pack.dart';

// ─── Tier 1: Гараж — OfficeLevel.garage ─────────────────────────────────────

const _garage = RoomTheme(
  id: 'garage',
  name: 'Гараж',
  nameEn: 'Garage',
  tier: 1,
  wallBase: Color(0xFF1C1610),    // dim brownish
  wallTop: Color(0xFF2A2018),     // lighter dirty brown
  wallInner: Color(0xFF151008),   // very dark
  floorDark: Color(0xFF141210),   // stained concrete dark
  floorLight: Color(0xFF181614),  // stained concrete light
  floorGrid: Color(0xFF1E1A16),   // dirty grout
  deskSurface: Color(0xFF3E3424), // worn-out wood
  deskEdge: Color(0xFF2A2218),    // rotting edge
  accentColor: Color(0xFF8B7355), // dim amber
  vignetteAlpha: 0.55,            // darker corners — gloomy
);

// ─── Tier 2: Маленький офіс — OfficeLevel.smallOffice ──────────────────────

const _smallOffice = RoomTheme(
  id: 'smallOffice',
  name: 'Маленький офіс',
  nameEn: 'Small Office',
  tier: 2,
  wallBase: Color(0xFF1A1A26),    // neutral grey-navy
  wallTop: Color(0xFF252538),     // lighter accent
  wallInner: Color(0xFF161624),   // dark base
  floorDark: Color(0xFF131318),   // carpet dark
  floorLight: Color(0xFF17171E),  // carpet light
  floorGrid: Color(0xFF1C1C26),   // seam
  deskSurface: Color(0xFF4A4438), // cheap laminate
  deskEdge: Color(0xFF36322A),    // laminate edge
  accentColor: Color(0xFFB0A890), // warm fluorescent
  vignetteAlpha: 0.45,
);

// ─── Tier 3: Модерн офіс — OfficeLevel.modernOffice ────────────────────────

const _modernOffice = RoomTheme(
  id: 'modernOffice',
  name: 'Модерн офіс',
  nameEn: 'Modern Office',
  tier: 3,
  wallBase: Color(0xFF1A1A2E),    // dark navy
  wallTop: Color(0xFF252540),     // navy highlight
  wallInner: Color(0xFF16162A),   // deep navy
  floorDark: Color(0xFF131320),   // dark checker
  floorLight: Color(0xFF171728),  // light checker
  floorGrid: Color(0xFF1C1C30),   // subtle grid
  deskSurface: Color(0xFF5C4033), // warm wood
  deskEdge: Color(0xFF3E2B22),    // dark trim
  accentColor: Color(0xFF00C0D1), // cyan
  vignetteAlpha: 0.4,
);

// ─── Tier 4: Тех хаб — OfficeLevel.techHub ─────────────────────────────────

const _techHub = RoomTheme(
  id: 'techHub',
  name: 'Тех хаб',
  nameEn: 'Tech Hub',
  tier: 4,
  wallBase: Color(0xFF0E1A1E),    // dark teal
  wallTop: Color(0xFF1A2E34),     // neon tint highlight
  wallInner: Color(0xFF0A1418),   // near-black teal
  floorDark: Color(0xFF0C1418),   // dark carbon
  floorLight: Color(0xFF101A1E),  // carbon light
  floorGrid: Color(0xFF142028),   // subtle cyan seam
  deskSurface: Color(0xFF303038), // smoked glass
  deskEdge: Color(0xFF48485A),    // chrome trim
  accentColor: Color(0xFF00E5FF), // bright cyan
  vignetteAlpha: 0.35,
);

// ─── Tier 5: Кампус — OfficeLevel.campus ────────────────────────────────────

const _campus = RoomTheme(
  id: 'campus',
  name: 'Кампус',
  nameEn: 'Campus',
  tier: 5,
  wallBase: Color(0xFF1E1E28),    // refined charcoal
  wallTop: Color(0xFF2E2E42),     // subtle warm steel
  wallInner: Color(0xFF181824),   // deep base
  floorDark: Color(0xFF161622),   // marble dark
  floorLight: Color(0xFF1C1C2E),  // marble light
  floorGrid: Color(0xFF222236),   // marble vein
  deskSurface: Color(0xFF4A4050), // premium glass-wood
  deskEdge: Color(0xFF5A5068),    // polished edge
  accentColor: Color(0xFFD4AF37), // gold
  vignetteAlpha: 0.25,            // bright, airy
);

// ─── Tier 4-alt: Галера — OfficeLevel.galley ────────────────────────────────

const _galley = RoomTheme(
  id: 'galley',
  name: 'Галера',
  nameEn: 'War Galley',
  tier: 4,
  wallBase: Color(0xFF1A1208),    // tarred oak hull, near-black warm brown
  wallTop: Color(0xFF2E1E0A),     // top planksheer caught by lantern light
  wallInner: Color(0xFF0E0A04),   // inner hull, deepest shadow
  floorDark: Color(0xFF1C1408),   // deck seam between planks
  floorLight: Color(0xFF2A1E0E),  // weathered oak plank surface
  floorGrid: Color(0xFF221A0C),   // plank groove, mid-tone warm brown
  deskSurface: Color(0xFF382810), // desk a touch richer than the deck
  deskEdge: Color(0xFF221A08),    // dark trim
  accentColor: Color(0xFFCD7F32), // bronze — antique metallic warm
  vignetteAlpha: 0.30,            // open night sky, lighter than techHub
);

// ─── Lookup ─────────────────────────────────────────────────────────────────

const _themesByLevel = <OfficeLevel, RoomTheme>{
  OfficeLevel.garage: _garage,
  OfficeLevel.smallOffice: _smallOffice,
  OfficeLevel.modernOffice: _modernOffice,
  OfficeLevel.techHub: _techHub,
  OfficeLevel.campus: _campus,
  OfficeLevel.galley: _galley,
};

/// Get the room theme for a given office level.
RoomTheme roomThemeForLevel(OfficeLevel level) =>
    _themesByLevel[level] ?? _modernOffice;

const allRoomThemes = <RoomTheme>[
  _garage,
  _smallOffice,
  _modernOffice,
  _techHub,
  _campus,
  _galley,
];
