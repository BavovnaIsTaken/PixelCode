import 'dart:ui' show Color;

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/resource_pack.dart';

void main() {
  // ─── SkinPalette.resolve ──────────────────────────────────────────────────

  group('SkinPalette.resolve', () {
    const palette = SkinPalette(
      hair: Color(0xFF111111),
      skin: Color(0xFF222222),
      skinLight: Color(0xFF333333),
      eye: Color(0xFF444444),
      clothes: Color(0xFF555555),
      pants: Color(0xFF666666),
      boots: Color(0xFF777777),
    );

    test("'h' returns hair", () => expect(palette.resolve('h'), palette.hair));
    test("'s' returns skin", () => expect(palette.resolve('s'), palette.skin));
    test("'f' returns skinLight", () => expect(palette.resolve('f'), palette.skinLight));
    test("'e' returns eye", () => expect(palette.resolve('e'), palette.eye));
    test("'c' returns clothes", () => expect(palette.resolve('c'), palette.clothes));
    test("'p' returns pants", () => expect(palette.resolve('p'), palette.pants));
    test("'b' returns boots", () => expect(palette.resolve('b'), palette.boots));
    test('unknown key returns transparent', () =>
        expect(palette.resolve('?'), Colors.transparent));
  });

  // ─── ComputerType.resolveKey ──────────────────────────────────────────────

  group('ComputerType.resolveKey', () {
    final computer = ComputerType(
      id: 'test_computer',
      name: 'Test',
      nameEn: 'Test',
      monitorOff: [],
      monitorOn0: [],
      monitorOn1: [],
      monitorFrame: const Color(0xFFAAAAAA),
      monitorGlow: const Color(0xFF00FF00),
      monitorGlowDim: const Color(0xFF00AA00),
    );

    test("'m' returns monitorFrame", () {
      expect(computer.resolveKey('m'), computer.monitorFrame);
    });

    test("'g' inactive returns monitorFrame", () {
      expect(computer.resolveKey('g', active: false), computer.monitorFrame);
    });

    test("'g' active returns monitorGlowDim", () {
      expect(computer.resolveKey('g', active: true), computer.monitorGlowDim);
    });

    test("'G' inactive returns monitorFrame", () {
      expect(computer.resolveKey('G', active: false), computer.monitorFrame);
    });

    test("'G' active returns monitorGlow", () {
      expect(computer.resolveKey('G', active: true), computer.monitorGlow);
    });

    test('unknown key returns transparent', () {
      expect(computer.resolveKey('z'), Colors.transparent);
    });
  });

  // ─── CharacterSkin ────────────────────────────────────────────────────────

  group('CharacterSkin', () {
    test('can be instantiated with required fields', () {
      final palette = SkinPalette(
        hair: const Color(0xFF000000),
        skin: const Color(0xFF111111),
        skinLight: const Color(0xFF222222),
        eye: const Color(0xFF333333),
        clothes: const Color(0xFF444444),
        pants: const Color(0xFF555555),
        boots: const Color(0xFF666666),
      );
      final skin = CharacterSkin(
        id: 'test_skin',
        name: 'Тест',
        nameEn: 'Test',
        palettes: {'coder#1': palette},
      );
      expect(skin.id, 'test_skin');
      expect(skin.accentOverride, isNull);
      expect(skin.palettes.containsKey('coder#1'), isTrue);
    });
  });
}
