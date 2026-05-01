import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/models/project.dart';
import 'package:pixelcode/providers/active_facilitator_style_provider.dart';
import 'package:pixelcode/providers/project_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

const _drillSergeantJson = '''
{
  "id": "drill_sergeant",
  "displayName": "Drill Sergeant",
  "tagline": "",
  "laloux": "red",
  "personaPrompt": "",
  "lexicon": {
    "backlog": "queue",
    "in_progress": "active",
    "testing": "QA",
    "done": "complete"
  },
  "outputMapper": "missionBriefing",
  "toneModifiers": {}
}
''';

const _gameMasterJson = '''
{
  "id": "game_master",
  "displayName": "Game Master",
  "tagline": "",
  "laloux": "green",
  "personaPrompt": "",
  "lexicon": {
    "backlog": "questboard",
    "done": "forged"
  },
  "outputMapper": "questLine",
  "toneModifiers": {}
}
''';

class _FakeProjectNotifier extends ProjectNotifier {
  Project? _seed;
  _FakeProjectNotifier(this._seed);
  @override
  Project? build() => _seed;
  void setProject(Project? p) {
    _seed = p;
    state = p;
  }
}

Future<ProviderContainer> _makeContainer({
  Project? project,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      projectProvider.overrideWith(() => _FakeProjectNotifier(project)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<String> _fakeAssetLoader(String key) async {
  if (key.endsWith('drill_sergeant.json')) return _drillSergeantJson;
  if (key.endsWith('game_master.json')) return _gameMasterJson;
  throw Exception('No fixture for $key');
}

void main() {
  group('ActiveFacilitatorStyleNotifier', () {
    test('starts as null when no project is selected', () async {
      final c = await _makeContainer();
      final v = await c.read(activeFacilitatorStyleProvider.future);
      expect(v, isNull);
    });

    test('starts as null when project has no persisted styleId', () async {
      final c = await _makeContainer(
        project: Project(
            path: '/tmp/p', name: 'p', lastOpened: DateTime(2026, 4, 28)),
      );
      final v = await c.read(activeFacilitatorStyleProvider.future);
      expect(v, isNull);
    });

    test('loads persisted style on startup via the asset loader', () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(path): 'drill_sergeant',
        },
      );
      // Inject the fake loader before the provider builds.
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      // Force a rebuild now that the loader is in place.
      c.invalidate(activeFacilitatorStyleProvider);
      final v = await c.read(activeFacilitatorStyleProvider.future);
      expect(v, isNotNull);
      expect(v!.id, 'drill_sergeant');
      expect(v.lexicon['backlog'], 'queue');
    });

    test('returns null (does NOT throw) when persisted id is unknown',
        () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(path):
              'ghost_style_renamed',
        },
      );
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      c.invalidate(activeFacilitatorStyleProvider);
      final v = await c.read(activeFacilitatorStyleProvider.future);
      expect(v, isNull);
    });

    test('surfaces lost id via lostFacilitatorStyleIdProvider when asset is missing',
        () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(path):
              'ghost_style_renamed',
        },
      );
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      c.invalidate(activeFacilitatorStyleProvider);
      // Settle the provider's first build.
      await c.read(activeFacilitatorStyleProvider.future);
      expect(
        c.read(lostFacilitatorStyleIdProvider),
        'ghost_style_renamed',
        reason: 'UI must be able to prompt the user to re-pick',
      );
    });

    test('lost-id marker clears once the user picks a new style', () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(path): 'ghost_style',
        },
      );
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      c.invalidate(activeFacilitatorStyleProvider);
      await c.read(activeFacilitatorStyleProvider.future);
      expect(c.read(lostFacilitatorStyleIdProvider), 'ghost_style');

      final replacement = FacilitatorStyle.fromJson({
        'id': 'game_master',
        'displayName': 'GM',
        'tagline': '',
        'laloux': 'green',
        'personaPrompt': '',
        'outputMapper': 'questLine',
        'toneModifiers': <String, dynamic>{},
      });
      await c
          .read(activeFacilitatorStyleProvider.notifier)
          .setStyle(replacement);

      expect(c.read(lostFacilitatorStyleIdProvider), isNull,
          reason: 'marker is the user-facing problem; setStyle resolves it');
    });

    test('lost-id marker also clears via clear()', () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(path): 'ghost_style',
        },
      );
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      c.invalidate(activeFacilitatorStyleProvider);
      await c.read(activeFacilitatorStyleProvider.future);
      expect(c.read(lostFacilitatorStyleIdProvider), 'ghost_style');

      await c.read(activeFacilitatorStyleProvider.notifier).clear();
      expect(c.read(lostFacilitatorStyleIdProvider), isNull);
    });

    test('setStyle persists styleId and updates state', () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
      );
      // Wait for initial build to settle as null.
      await c.read(activeFacilitatorStyleProvider.future);

      final style = FacilitatorStyle.fromJson({
        'id': 'game_master',
        'displayName': 'GM',
        'tagline': '',
        'laloux': 'green',
        'personaPrompt': '',
        'outputMapper': 'questLine',
        'toneModifiers': <String, dynamic>{},
      });
      await c
          .read(activeFacilitatorStyleProvider.notifier)
          .setStyle(style);

      // State updated synchronously.
      expect(c.read(activeFacilitatorStyleProvider).valueOrNull?.id,
          'game_master');

      // Persisted to SharedPreferences under the per-project key.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ActiveFacilitatorStyleNotifier.prefsKeyFor(path)),
        'game_master',
      );
    });

    test('clear removes the persisted styleId and resets state', () async {
      const path = '/tmp/p';
      final c = await _makeContainer(
        project: Project(
            path: path, name: 'p', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(path): 'drill_sergeant',
        },
      );
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      c.invalidate(activeFacilitatorStyleProvider);
      await c.read(activeFacilitatorStyleProvider.future);

      await c.read(activeFacilitatorStyleProvider.notifier).clear();

      expect(c.read(activeFacilitatorStyleProvider).valueOrNull, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ActiveFacilitatorStyleNotifier.prefsKeyFor(path)),
        isNull,
      );
    });

    test('persistence is per-project (different paths do not collide)',
        () async {
      // Project A has Drill Sergeant; switching to Project B yields null.
      final pathA = '/tmp/A';
      final pathB = '/tmp/B';
      final c = await _makeContainer(
        project: Project(
            path: pathA, name: 'A', lastOpened: DateTime(2026, 4, 28)),
        initialPrefs: {
          ActiveFacilitatorStyleNotifier.prefsKeyFor(pathA): 'drill_sergeant',
        },
      );
      c
          .read(activeFacilitatorStyleProvider.notifier)
          .debugSetAssetLoader(_fakeAssetLoader);
      c.invalidate(activeFacilitatorStyleProvider);
      final vA = await c.read(activeFacilitatorStyleProvider.future);
      expect(vA?.id, 'drill_sergeant');

      // Switch to project B — no persisted id, expect null.
      (c.read(projectProvider.notifier) as _FakeProjectNotifier).setProject(
        Project(path: pathB, name: 'B', lastOpened: DateTime(2026, 4, 28)),
      );
      final vB = await c.read(activeFacilitatorStyleProvider.future);
      expect(vB, isNull);
    });
  });
}
