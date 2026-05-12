/// Smoke tests for the Arkanoid sprite catalog — guards against typos in
/// the sprite strings (rows of unequal length crash the painter) and
/// regressions in the color resolver.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/canvas/arkanoid_sprites.dart';

void main() {
  // Helper: every row of a sprite must have the same length, otherwise the
  // painter would draw a ragged hit-rect.
  void expectRectangular(String name, List<String> sprite) {
    expect(sprite, isNotEmpty, reason: '$name has no rows');
    final w = sprite.first.length;
    for (var i = 0; i < sprite.length; i++) {
      expect(sprite[i].length, w,
          reason: '$name row $i has length ${sprite[i].length}, expected $w');
    }
  }

  group('resolveArkanoidSpriteColor', () {
    test('"." resolves to transparent (alpha == 0)', () {
      expect(resolveArkanoidSpriteColor('.').a, 0);
    });

    test('unknown glyph falls back to transparent (negative)', () {
      expect(resolveArkanoidSpriteColor('?').a, 0);
      expect(resolveArkanoidSpriteColor(' ').a, 0);
    });

    test('monitor + glass + trophy + steel keys all return opaque colors', () {
      for (final key in const ['M', 'g', 'l', 'Y', 'S', 'R', 'C', 'B', 'w']) {
        final c = resolveArkanoidSpriteColor(key);
        expect(c.a, greaterThan(0), reason: 'key=$key should be opaque');
      }
    });

    test('powerup glyphs map to distinct, opaque colors', () {
      final keys = const ['+', '*', '@', '!', '~', '%', '<', '>'];
      final colors = <Color>{};
      for (final k in keys) {
        final c = resolveArkanoidSpriteColor(k);
        expect(c.a, greaterThan(0), reason: 'key=$k should be opaque');
        colors.add(c);
      }
      expect(colors.length, keys.length, reason: 'powerup colors must differ');
    });
  });

  group('Free-standing sprites are rectangular', () {
    test('deskPaddleSprite is rectangular', () {
      expectRectangular('deskPaddleSprite', deskPaddleSprite);
    });
    test('coffeeBallSprite6x6 is rectangular and 6×6', () {
      expectRectangular('coffeeBallSprite6x6', coffeeBallSprite6x6);
      expect(coffeeBallSprite6x6.length, 6);
      expect(coffeeBallSprite6x6.first.length, 6);
    });
    test('fireExtinguisherSprite is rectangular', () {
      expectRectangular('fireExtinguisherSprite', fireExtinguisherSprite);
    });
  });

  group('ArkanoidSprites catalog is rectangular', () {
    test('every monitor variant is rectangular', () {
      expect(ArkanoidSprites.monitorBrickVariants, isNotEmpty);
      for (var i = 0; i < ArkanoidSprites.monitorBrickVariants.length; i++) {
        expectRectangular(
            'monitorBrickVariants[$i]', ArkanoidSprites.monitorBrickVariants[i]);
      }
    });

    test('brick sprites are rectangular', () {
      expectRectangular('glassPartition', ArkanoidSprites.glassPartition);
      expectRectangular('crackedGlass', ArkanoidSprites.crackedGlass);
      expectRectangular('trophy', ArkanoidSprites.trophy);
      expectRectangular('fireExtinguisher', ArkanoidSprites.fireExtinguisher);
      expectRectangular('filingCabinet', ArkanoidSprites.filingCabinet);
    });

    test('powerup sprites are rectangular', () {
      expectRectangular('expandPowerup', ArkanoidSprites.expandPowerup);
      expectRectangular('multiballPowerup', ArkanoidSprites.multiballPowerup);
      expectRectangular('stickyPowerup', ArkanoidSprites.stickyPowerup);
      expectRectangular('laserPowerup', ArkanoidSprites.laserPowerup);
      expectRectangular('thruPowerup', ArkanoidSprites.thruPowerup);
      expectRectangular('lifePowerup', ArkanoidSprites.lifePowerup);
      expectRectangular('slowPowerup', ArkanoidSprites.slowPowerup);
      expectRectangular('blastPowerup', ArkanoidSprites.blastPowerup);
    });
  });

  group('Sprite glyphs all have color mappings (no silent transparency)', () {
    // Every glyph used in a sprite — apart from "." (intentional transparent
    // background) — must resolve to an opaque color, otherwise the artwork
    // ends up with invisible holes that look like bugs at runtime.
    void expectAllGlyphsMapped(String name, List<String> sprite) {
      final unmapped = <String>{};
      for (final row in sprite) {
        for (final glyph in row.split('')) {
          if (glyph == '.') continue;
          if (resolveArkanoidSpriteColor(glyph).a == 0) {
            unmapped.add(glyph);
          }
        }
      }
      expect(unmapped, isEmpty,
          reason: '$name uses glyphs without color mapping: $unmapped');
    }

    test('every brick sprite has all glyphs mapped', () {
      for (var i = 0; i < ArkanoidSprites.monitorBrickVariants.length; i++) {
        expectAllGlyphsMapped(
            'monitor[$i]', ArkanoidSprites.monitorBrickVariants[i]);
      }
      expectAllGlyphsMapped('glassPartition', ArkanoidSprites.glassPartition);
      expectAllGlyphsMapped('crackedGlass', ArkanoidSprites.crackedGlass);
      expectAllGlyphsMapped('trophy', ArkanoidSprites.trophy);
      expectAllGlyphsMapped(
          'fireExtinguisher', ArkanoidSprites.fireExtinguisher);
      expectAllGlyphsMapped('filingCabinet', ArkanoidSprites.filingCabinet);
    });

    test('every powerup sprite has all glyphs mapped', () {
      expectAllGlyphsMapped('expandPowerup', ArkanoidSprites.expandPowerup);
      expectAllGlyphsMapped(
          'multiballPowerup', ArkanoidSprites.multiballPowerup);
      expectAllGlyphsMapped('stickyPowerup', ArkanoidSprites.stickyPowerup);
      expectAllGlyphsMapped('laserPowerup', ArkanoidSprites.laserPowerup);
      expectAllGlyphsMapped('thruPowerup', ArkanoidSprites.thruPowerup);
      expectAllGlyphsMapped('lifePowerup', ArkanoidSprites.lifePowerup);
      expectAllGlyphsMapped('slowPowerup', ArkanoidSprites.slowPowerup);
      expectAllGlyphsMapped('blastPowerup', ArkanoidSprites.blastPowerup);
    });

    test('paddle + ball sprites have all glyphs mapped', () {
      expectAllGlyphsMapped('deskPaddleSprite', deskPaddleSprite);
      expectAllGlyphsMapped('coffeeBallSprite6x6', coffeeBallSprite6x6);
      expectAllGlyphsMapped('fireExtinguisherSprite', fireExtinguisherSprite);
    });
  });
}
