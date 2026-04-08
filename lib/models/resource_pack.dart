/// Resource pack data models — rooms, computers, and character skins.
///
/// Each category has multiple tiers/variants that can be mixed and matched.
/// Room themes control wall/floor colors, computer types define monitor
/// sprites, and character skins provide palette variations.
library;

import 'package:flutter/material.dart';

// ─── Room Theme ─────────────────────────────────────────────────────────────

class RoomTheme {
  final String id;
  final String name;
  final String nameEn;
  final int tier; // 1–5
  final Color wallBase;
  final Color wallTop;
  final Color wallInner;
  final Color floorDark;
  final Color floorLight;
  final Color floorGrid;
  final Color deskSurface;
  final Color deskEdge;
  final Color accentColor;
  final double vignetteAlpha;

  const RoomTheme({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.tier,
    required this.wallBase,
    required this.wallTop,
    required this.wallInner,
    required this.floorDark,
    required this.floorLight,
    required this.floorGrid,
    required this.deskSurface,
    required this.deskEdge,
    required this.accentColor,
    this.vignetteAlpha = 0.4,
  });
}

// ─── Computer Type ──────────────────────────────────────────────────────────

class ComputerType {
  final String id;
  final String name;
  final String nameEn;
  final List<String> monitorOff;
  final List<String> monitorOn0;
  final List<String> monitorOn1;
  final Color monitorFrame;
  final Color monitorGlow;
  final Color monitorGlowDim;

  const ComputerType({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.monitorOff,
    required this.monitorOn0,
    required this.monitorOn1,
    required this.monitorFrame,
    required this.monitorGlow,
    required this.monitorGlowDim,
  });

  Color resolveKey(String key, {bool active = false}) => switch (key) {
        'm' => monitorFrame,
        'g' => active ? monitorGlowDim : monitorFrame,
        'G' => active ? monitorGlow : monitorFrame,
        _ => Colors.transparent,
      };
}

// ─── Character Skin ─────────────────────────────────────────────────────────

class SkinPalette {
  final Color hair;
  final Color skin;
  final Color skinLight;
  final Color eye;
  final Color clothes;
  final Color pants;
  final Color boots;

  const SkinPalette({
    required this.hair,
    required this.skin,
    required this.skinLight,
    required this.eye,
    required this.clothes,
    required this.pants,
    required this.boots,
  });

  Color resolve(String key) => switch (key) {
        'h' => hair,
        's' => skin,
        'f' => skinLight,
        'e' => eye,
        'c' => clothes,
        'p' => pants,
        'b' => boots,
        _ => Colors.transparent,
      };
}

class CharacterSkin {
  final String id;
  final String name;
  final String nameEn;
  final Map<String, SkinPalette> palettes; // agentId → palette
  final Color Function(String agentId)? accentOverride;

  const CharacterSkin({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.palettes,
    this.accentOverride,
  });
}
