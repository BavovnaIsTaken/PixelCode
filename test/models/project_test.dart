import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/project.dart';

void main() {
  // ─── storageKey ───────────────────────────────────────────────────────────

  group('storageKey', () {
    test('replaces slashes with dashes', () {
      final project = Project(
        path: '/Users/dan/MyApp',
        name: 'MyApp',
        lastOpened: _epoch,
      );
      expect(project.storageKey, 'Users-dan-MyApp');
    });

    test('strips leading dash produced by leading slash', () {
      final project = Project(
        path: '/absolute/path',
        name: 'path',
        lastOpened: _epoch,
      );
      // leading '/' → '-absolute-path' → strip leading '-' → 'absolute-path'
      expect(project.storageKey, 'absolute-path');
    });

    test('no leading slash: no stripping', () {
      final project = Project(
        path: 'relative/path',
        name: 'path',
        lastOpened: _epoch,
      );
      expect(project.storageKey, 'relative-path');
    });

    test('single-segment path (no slashes)', () {
      final project = Project(
        path: 'myproject',
        name: 'myproject',
        lastOpened: _epoch,
      );
      expect(project.storageKey, 'myproject');
    });

    test('deeply nested path', () {
      final project = Project(
        path: '/a/b/c/d',
        name: 'd',
        lastOpened: _epoch,
      );
      expect(project.storageKey, 'a-b-c-d');
    });
  });

  // ─── displayName ──────────────────────────────────────────────────────────

  group('displayName', () {
    test('returns name when set', () {
      final project = Project(
        path: '/Users/dan/MyApp',
        name: 'Custom Name',
        lastOpened: _epoch,
      );
      expect(project.displayName, 'Custom Name');
    });

    test('falls back to last path segment when name is empty', () {
      final project = Project(
        path: '/Users/dan/MyApp',
        name: '',
        lastOpened: _epoch,
      );
      expect(project.displayName, 'MyApp');
    });

    test('last path segment for deeply nested path', () {
      final project = Project(
        path: '/a/b/c/Folder',
        name: '',
        lastOpened: _epoch,
      );
      expect(project.displayName, 'Folder');
    });

    test('single-segment path with empty name', () {
      final project = Project(
        path: 'myproject',
        name: '',
        lastOpened: _epoch,
      );
      expect(project.displayName, 'myproject');
    });
  });

  // ─── copyWith ─────────────────────────────────────────────────────────────

  group('copyWith', () {
    final base = Project(
      path: '/Users/dan/App',
      name: 'App',
      lastOpened: DateTime(2026, 1, 1),
    );

    test('preserves unchanged fields', () {
      final copy = base.copyWith(name: 'NewName');
      expect(copy.path, base.path);
      expect(copy.lastOpened, base.lastOpened);
    });

    test('changes name', () {
      final copy = base.copyWith(name: 'Renamed');
      expect(copy.name, 'Renamed');
    });

    test('changes path', () {
      final copy = base.copyWith(path: '/new/path');
      expect(copy.path, '/new/path');
    });

    test('changes lastOpened', () {
      final newDate = DateTime(2026, 6, 1);
      final copy = base.copyWith(lastOpened: newDate);
      expect(copy.lastOpened, newDate);
    });
  });

  // ─── fromJson / toJson ────────────────────────────────────────────────────

  group('fromJson / toJson', () {
    test('round-trip preserves all fields', () {
      final project = Project(
        path: '/Users/dan/MyApp',
        name: 'MyApp',
        lastOpened: DateTime.parse('2026-03-15T10:30:00.000Z'),
      );

      final json = project.toJson();
      final restored = Project.fromJson(json);

      expect(restored.path, project.path);
      expect(restored.name, project.name);
      expect(
        restored.lastOpened.toIso8601String(),
        project.lastOpened.toIso8601String(),
      );
    });

    test('fromJson uses empty string for missing name', () {
      final json = {
        'path': '/some/path',
        'lastOpened': '2026-01-01T00:00:00.000Z',
      };
      final project = Project.fromJson(json);
      expect(project.name, '');
    });

    test('toJson includes all three fields', () {
      final project = Project(
        path: '/p',
        name: 'P',
        lastOpened: DateTime(2026, 1, 1),
      );
      final json = project.toJson();
      expect(json.containsKey('path'), isTrue);
      expect(json.containsKey('name'), isTrue);
      expect(json.containsKey('lastOpened'), isTrue);
    });
  });

  // ─── fromPath ─────────────────────────────────────────────────────────────

  group('fromPath', () {
    test('sets name to last path segment', () {
      final project = Project.fromPath('/Users/dan/AwesomeApp');
      expect(project.name, 'AwesomeApp');
      expect(project.path, '/Users/dan/AwesomeApp');
    });

    test('sets lastOpened to roughly now', () {
      final before = DateTime.now();
      final project = Project.fromPath('/some/path');
      final after = DateTime.now();
      expect(
        project.lastOpened.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(project.lastOpened.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('single-segment path uses full path as name', () {
      final project = Project.fromPath('myproject');
      expect(project.name, 'myproject');
    });
  });

  // ─── listFromJson / listToJson ────────────────────────────────────────────

  group('listFromJson / listToJson', () {
    test('empty list round-trips', () {
      final json = Project.listToJson([]);
      final result = Project.listFromJson(json);
      expect(result, isEmpty);
    });

    test('list with multiple projects round-trips', () {
      final projects = [
        Project(
          path: '/a/ProjectA',
          name: 'ProjectA',
          lastOpened: DateTime(2026, 1, 1),
        ),
        Project(
          path: '/b/ProjectB',
          name: 'ProjectB',
          lastOpened: DateTime(2026, 2, 1),
        ),
      ];

      final json = Project.listToJson(projects);
      final result = Project.listFromJson(json);

      expect(result.length, 2);
      expect(result[0].path, '/a/ProjectA');
      expect(result[0].name, 'ProjectA');
      expect(result[1].path, '/b/ProjectB');
    });

    test('order is preserved', () {
      final projects = List.generate(
        5,
        (i) => Project(
          path: '/p/$i',
          name: 'P$i',
          lastOpened: DateTime(2026, 1, i + 1),
        ),
      );

      final result = Project.listFromJson(Project.listToJson(projects));
      for (int i = 0; i < 5; i++) {
        expect(result[i].path, '/p/$i');
      }
    });
  });

  // ─── Equality ─────────────────────────────────────────────────────────────

  group('equality', () {
    test('two projects with same path are equal', () {
      final a = Project(
        path: '/same/path',
        name: 'A',
        lastOpened: DateTime(2026, 1, 1),
      );
      final b = Project(
        path: '/same/path',
        name: 'B',
        lastOpened: DateTime(2026, 6, 1),
      );
      expect(a, equals(b));
    });

    test('two projects with different paths are not equal', () {
      final a = Project(
        path: '/path/A',
        name: 'Same',
        lastOpened: DateTime(2026, 1, 1),
      );
      final b = Project(
        path: '/path/B',
        name: 'Same',
        lastOpened: DateTime(2026, 1, 1),
      );
      expect(a, isNot(equals(b)));
    });

    test('hashCode matches for equal projects', () {
      final a = Project(path: '/p', name: 'X', lastOpened: DateTime(2026, 1, 1));
      final b = Project(path: '/p', name: 'Y', lastOpened: DateTime(2026, 2, 1));
      expect(a.hashCode, b.hashCode);
    });

    test('can be used as Set key — deduplication by path', () {
      final a = Project(path: '/p', name: 'X', lastOpened: DateTime(2026, 1, 1));
      final b = Project(path: '/p', name: 'Y', lastOpened: DateTime(2026, 2, 1));
      final c = Project(path: '/q', name: 'Z', lastOpened: DateTime(2026, 1, 1));
      final set = {a, b, c};
      expect(set.length, 2);
    });
  });
}

// DateTime has no const constructor — use a fixed parsed value instead.
final _epoch = DateTime.parse('2026-01-01T00:00:00.000Z');
