/// Loads and manages PNG character sprite sheets from pixel-agents.
///
/// Each sprite sheet (char_0.png–char_5.png) is 112×96:
///   7 frames × 16px wide,  3 direction rows × 32px tall.
///
/// Frame columns:  0=walk1, 1=walk2, 2=walk3, 3=type1, 4=type2, 5=read1, 6=read2
/// Direction rows:  0=DOWN, 1=UP, 2=RIGHT  (LEFT = flip RIGHT)
/// Walk cycle:  [0, 1, 2, 1]
/// Idle:        frame 1 (walk2 standing pose)
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'office_game_state.dart';

// Sprite frame dimensions (pixels in the PNG).
const kSpriteW = 16;
const kSpriteH = 32;
const _charCount = 6;

/// Manages all loaded character sprite sheets + furniture images.
class SpriteManager {
  final List<ui.Image> _chars = [];
  final Map<String, ui.Image> _furniture = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    // Characters
    for (int i = 0; i < _charCount; i++) {
      _chars.add(await _loadImage('assets/characters/char_$i.png'));
    }

    // Furniture
    for (final name in [
      'PC_FRONT_OFF',
      'PC_FRONT_ON_1',
      'PC_FRONT_ON_2',
      'PC_FRONT_ON_3',
      'CUSHIONED_CHAIR_BACK',
      'DESK_FRONT',
      'PLANT',
    ]) {
      _furniture[name] = await _loadImage('assets/furniture/$name.png');
    }

    _loaded = true;
  }

  static Future<ui.Image> _loadImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec =
        await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Character sprite sheet by palette index (0-5). Wraps for 7th agent.
  ui.Image? charSheet(int paletteIndex) =>
      _loaded ? _chars[paletteIndex % _chars.length] : null;

  /// Furniture image by name.
  ui.Image? furniture(String name) => _furniture[name];
}

// ─── Frame helpers ──────────────────────────────────────────────────────────

/// Source rectangle for one frame in the sprite sheet.
ui.Rect charFrameRect(int frameCol, int dirRow) {
  return ui.Rect.fromLTWH(
    frameCol * kSpriteW.toDouble(),
    dirRow * kSpriteH.toDouble(),
    kSpriteW.toDouble(),
    kSpriteH.toDouble(),
  );
}

/// Walk frame columns: [walk1, walk2, walk3, walk2].
const _walkCols = [0, 1, 2, 1];

/// Resolve frame column + direction row + mirrored flag for a character.
({int col, int row, bool mirror}) charSpriteFrame(GameCharacter ch) {
  final isLeft = ch.dir == CharDirection.left;

  int col;
  switch (ch.state) {
    case CharState.walk:
      if (ch.isOnSkateboard) {
        col = 1; // standing pose for ride (closest match in PNG sheet)
      } else {
        col = _walkCols[ch.frame % 4];
      }
    case CharState.idle:
      col = 1; // standing pose
    case CharState.skateMount:
    case CharState.skateDismount:
      col = 1; // standing pose (mount/dismount uses text sprites for detail)
    case CharState.typing:
      if (ch.isReading) {
        col = 5 + (ch.frame % 2); // read1 / read2
      } else {
        col = 3 + (ch.frame % 2); // type1 / type2
      }
  }

  final dir = isLeft ? CharDirection.right : ch.dir;
  final row = switch (dir) {
    CharDirection.down => 0,
    CharDirection.up => 1,
    CharDirection.right => 2,
    CharDirection.left => 2,
  };

  return (col: col, row: row, mirror: isLeft);
}
