import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/services/facilitator_style_loader.dart';

/// Loader that reads from disk (the real `assets/facilitators/*.json`)
/// instead of the Flutter asset bundle. The bundle isn't initialized in
/// pure unit tests, so we point at the source files directly.
Future<String> _diskLoader(String key) async {
  return File(key).readAsString();
}

void main() {
  group('defaultStyleIds', () {
    test('contains exactly the 3 MVP styles in expected order', () {
      expect(defaultStyleIds, ['game_master', 'marina', 'drill_sergeant']);
    });
  });

  group('loadById (real asset files)', () {
    test('game_master parses, lands on Green / questLine', () async {
      final s =
          await FacilitatorStyleLoader.loadById('game_master', loader: _diskLoader);
      expect(s.id, 'game_master');
      expect(s.laloux, Laloux.green);
      expect(s.outputMapper, OutputFormat.questLine);
      expect(s.lexicon['task'], 'quest');
      expect(s.intakeTemplate, isNotEmpty);
      // Soft-tone, verbose-ish.
      expect(s.toneModifiers.aggression, lessThan(0.3));
      expect(s.toneModifiers.verbosity, greaterThan(0.5));
    });

    test('marina parses, lands on Amber / milestoneTree', () async {
      final s =
          await FacilitatorStyleLoader.loadById('marina', loader: _diskLoader);
      expect(s.id, 'marina');
      expect(s.laloux, Laloux.amber);
      expect(s.outputMapper, OutputFormat.milestoneTree);
      expect(s.lexicon['task'], 'task');
      expect(s.lexicon['sprint'], 'iteration');
      // High formality.
      expect(s.toneModifiers.formality, greaterThan(0.7));
    });

    test('drill_sergeant parses, lands on Red / missionBriefing', () async {
      final s = await FacilitatorStyleLoader.loadById('drill_sergeant',
          loader: _diskLoader);
      expect(s.id, 'drill_sergeant');
      expect(s.laloux, Laloux.red);
      expect(s.outputMapper, OutputFormat.missionBriefing);
      expect(s.lexicon['task'], 'mission');
      // High aggression, low verbosity.
      expect(s.toneModifiers.aggression, greaterThan(0.8));
      expect(s.toneModifiers.verbosity, lessThan(0.3));
    });
  });

  group('loadDefaults (real asset files)', () {
    test('returns all 3 styles with distinct ids and Laloux levels', () async {
      final styles =
          await FacilitatorStyleLoader.loadDefaults(loader: _diskLoader);
      expect(styles, hasLength(3));
      expect(
        styles.map((s) => s.id).toList(),
        defaultStyleIds,
      );
      // 3 distinct Laloux levels — that's the contrast point of the MVP set.
      final lalouxSet = styles.map((s) => s.laloux).toSet();
      expect(lalouxSet, hasLength(3));
    });

    test('every style has a non-empty personaPrompt and at least 1 ceremony',
        () async {
      final styles =
          await FacilitatorStyleLoader.loadDefaults(loader: _diskLoader);
      for (final s in styles) {
        expect(s.personaPrompt.length, greaterThan(50),
            reason: '${s.id} personaPrompt too short');
        expect(s.ceremonySchedule, isNotEmpty,
            reason: '${s.id} has no ceremonies');
      }
    });

    test('every style has a non-empty intakeTemplate', () async {
      final styles =
          await FacilitatorStyleLoader.loadDefaults(loader: _diskLoader);
      for (final s in styles) {
        expect(s.intakeTemplate, isNotEmpty,
            reason: '${s.id} has no intake questions');
      }
    });

    test('every style has at least one ScopeDimension-mapped intake question',
        () async {
      // Otherwise the scope scorer can't be calibrated by the interview.
      final styles =
          await FacilitatorStyleLoader.loadDefaults(loader: _diskLoader);
      for (final s in styles) {
        final scoring = s.intakeTemplate
            .where((q) => q.mapsTo != ScopeDimension.none);
        expect(scoring, isNotEmpty,
            reason: '${s.id} has no scoring intake questions');
      }
    });
  });

  group('loadById (in-memory loader)', () {
    test('uses the injected AssetLoader for tests', () async {
      Future<String> fake(String key) async => jsonEncode({
            'id': 'fake',
            'displayName': 'Fake',
            'tagline': '',
            'laloux': 'teal',
            'personaPrompt': 'p',
            'outputMapper': 'koan_entry',
            'toneModifiers': {'aggression': 0.0, 'formality': 0.5, 'verbosity': 0.5},
          });
      final s = await FacilitatorStyleLoader.loadById('fake', loader: fake);
      expect(s.id, 'fake');
      expect(s.laloux, Laloux.teal);
      expect(s.outputMapper, OutputFormat.koanEntry);
    });
  });
}
