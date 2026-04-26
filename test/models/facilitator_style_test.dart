import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';

void main() {
  group('Laloux', () {
    test('round-trip key/fromKey for every variant', () {
      for (final l in Laloux.values) {
        expect(Laloux.fromKey(l.key), l);
      }
    });

    test('unknown key falls back to red', () {
      expect(Laloux.fromKey('nonsense'), Laloux.red);
    });

    test('label includes both key and human descriptor', () {
      expect(Laloux.amber.label, 'Amber — Conformist');
      expect(Laloux.green.label, 'Green — Pluralistic');
    });
  });

  group('CeremonyKind / CeremonyCadence', () {
    test('CeremonyKind round-trip', () {
      for (final k in CeremonyKind.values) {
        expect(CeremonyKind.fromKey(k.key), k);
      }
    });

    test('CeremonyKind on_demand uses snake_case key (not "onDemand")', () {
      expect(CeremonyKind.onDemand.key, 'on_demand');
      expect(CeremonyKind.fromKey('on_demand'), CeremonyKind.onDemand);
    });

    test('CeremonyCadence round-trip', () {
      for (final c in CeremonyCadence.values) {
        expect(CeremonyCadence.fromKey(c.key), c);
      }
    });

    test('CeremonyCadence on_event key matches', () {
      expect(CeremonyCadence.onEvent.key, 'on_event');
    });
  });

  group('CeremonySpec serde', () {
    test('round-trips with triggerEvent set', () {
      const original = CeremonySpec(
        kind: CeremonyKind.briefing,
        cadence: CeremonyCadence.onEvent,
        triggerEvent: 'sprint_end',
      );
      final restored = CeremonySpec.fromJson(original.toJson());
      expect(restored.kind, CeremonyKind.briefing);
      expect(restored.cadence, CeremonyCadence.onEvent);
      expect(restored.triggerEvent, 'sprint_end');
    });

    test('triggerEvent is omitted from JSON when null', () {
      const c = CeremonySpec(
        kind: CeremonyKind.standup,
        cadence: CeremonyCadence.daily,
      );
      expect(c.toJson().containsKey('triggerEvent'), false);
    });
  });

  group('ScopeDimension', () {
    test('round-trip key/fromKey', () {
      for (final d in ScopeDimension.values) {
        expect(ScopeDimension.fromKey(d.key), d);
      }
    });

    test('snake_case keys for multi-word dimensions', () {
      expect(ScopeDimension.entityCount.key, 'entity_count');
      expect(ScopeDimension.interactionSurface.key, 'interaction_surface');
    });
  });

  group('IntakeQuestion', () {
    test('serde round-trips choice question with options', () {
      const original = IntakeQuestion(
        id: 'q1',
        prompt: 'Roll for accounts: solo or party?',
        inputKind: IntakeInputKind.choice,
        choices: ['solo', 'party'],
        mapsTo: ScopeDimension.auth,
      );
      final restored = IntakeQuestion.fromJson(original.toJson());
      expect(restored.id, 'q1');
      expect(restored.inputKind, IntakeInputKind.choice);
      expect(restored.choices, ['solo', 'party']);
      expect(restored.mapsTo, ScopeDimension.auth);
    });

    test('text question with no choices omits choices key', () {
      const q = IntakeQuestion(id: 'q', prompt: 'Describe.');
      expect(q.toJson().containsKey('choices'), false);
    });
  });

  group('ToneModifiers', () {
    test('clamps values into 0..1', () {
      final t = ToneModifiers.fromJson({
        'aggression': 5.0,
        'formality': -3.0,
        'verbosity': 0.7,
      });
      expect(t.aggression, 1.0);
      expect(t.formality, 0.0);
      expect(t.verbosity, 0.7);
    });

    test('missing fields default to 0.5', () {
      final t = ToneModifiers.fromJson(const {});
      expect(t.aggression, 0.5);
      expect(t.formality, 0.5);
      expect(t.verbosity, 0.5);
    });
  });

  group('FacilitatorStyle', () {
    FacilitatorStyle build() => FacilitatorStyle(
          id: 'game_master',
          displayName: 'Game Master',
          tagline: 'Quest-line з наративом і reveal-ом.',
          laloux: Laloux.green,
          personaPrompt: 'You narrate the build as a tabletop campaign.',
          lexicon: const {
            'task': 'quest',
            'milestone': 'act',
            'sprint': 'campaign',
          },
          ceremonySchedule: const [
            CeremonySpec(
                kind: CeremonyKind.briefing,
                cadence: CeremonyCadence.onEvent,
                triggerEvent: 'act_start'),
          ],
          intakeTemplate: const [
            IntakeQuestion(
              id: 'who',
              prompt: 'Solo adventurer or party of heroes?',
              inputKind: IntakeInputKind.choice,
              choices: ['solo', 'party'],
              mapsTo: ScopeDimension.auth,
            ),
          ],
          outputMapper: OutputFormat.questLine,
          toneModifiers: const ToneModifiers(
            aggression: 0.1,
            formality: 0.2,
            verbosity: 0.7,
          ),
        );

    test('translate substitutes via lexicon', () {
      final s = build();
      expect(s.translate('task'), 'quest');
      expect(s.translate('milestone'), 'act');
    });

    test('translate falls back to canonical when no override', () {
      final s = build();
      expect(s.translate('blocker'), 'blocker');
    });

    test('encode → decode preserves all fields', () {
      final original = build();
      final restored = FacilitatorStyle.decode(original.encode());

      expect(restored.id, 'game_master');
      expect(restored.displayName, 'Game Master');
      expect(restored.laloux, Laloux.green);
      expect(restored.outputMapper, OutputFormat.questLine);
      expect(restored.lexicon['task'], 'quest');
      expect(restored.ceremonySchedule.first.triggerEvent, 'act_start');
      expect(restored.intakeTemplate.first.choices, ['solo', 'party']);
      expect(restored.intakeTemplate.first.mapsTo, ScopeDimension.auth);
      expect(restored.toneModifiers.verbosity, 0.7);
    });

    test('decode tolerates missing optional collections', () {
      final minimal = FacilitatorStyle.fromJson({
        'id': 'x',
        'displayName': 'X',
        'tagline': '',
        'laloux': 'red',
        'personaPrompt': 'p',
        'outputMapper': 'mission_briefing',
        'toneModifiers': const <String, dynamic>{},
      });
      expect(minimal.lexicon, isEmpty);
      expect(minimal.ceremonySchedule, isEmpty);
      expect(minimal.intakeTemplate, isEmpty);
      expect(minimal.outputMapper, OutputFormat.missionBriefing);
    });
  });
}
