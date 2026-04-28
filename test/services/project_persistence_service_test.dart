import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/project.dart';
import 'package:pixelcode/services/project_persistence_service.dart';

Project _project(String path, {String? name}) => Project(
      path: path,
      name: name ?? path.split('/').last,
      lastOpened: DateTime(2026, 1, 1),
    );

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  group('ProjectPersistenceService.loadRecentProjects', () {
    test('returns empty list when prefs are empty', () async {
      final p = await _prefs();
      expect(ProjectPersistenceService.loadRecentProjects(p), isEmpty);
    });

    test('returns empty list on corrupted JSON', () async {
      SharedPreferences.setMockInitialValues({'recent_projects': 'bad-json'});
      final p = await SharedPreferences.getInstance();
      expect(ProjectPersistenceService.loadRecentProjects(p), isEmpty);
    });
  });

  group('ProjectPersistenceService.addToRecent', () {
    test('adds project to the front of the list', () async {
      final p = await _prefs();
      await ProjectPersistenceService.addToRecent(p, _project('/a'));
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded, hasLength(1));
      expect(loaded.first.path, '/a');
    });

    test('new project appears first', () async {
      final p = await _prefs();
      await ProjectPersistenceService.addToRecent(p, _project('/a'));
      await ProjectPersistenceService.addToRecent(p, _project('/b'));
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded.first.path, '/b');
    });

    test('duplicate path is moved to front not duplicated', () async {
      final p = await _prefs();
      await ProjectPersistenceService.addToRecent(p, _project('/a'));
      await ProjectPersistenceService.addToRecent(p, _project('/b'));
      await ProjectPersistenceService.addToRecent(p, _project('/a'));
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded.first.path, '/a');
      expect(loaded.where((pr) => pr.path == '/a'), hasLength(1));
    });
  });

  group('ProjectPersistenceService.saveRecentProjects', () {
    test('caps list at 10 projects', () async {
      final p = await _prefs();
      final projects = List.generate(15, (i) => _project('/p$i'));
      await ProjectPersistenceService.saveRecentProjects(p, projects);
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded, hasLength(10));
      expect(loaded.first.path, '/p0');
    });

    test('round-trips project name', () async {
      final p = await _prefs();
      await ProjectPersistenceService.saveRecentProjects(
          p, [_project('/foo', name: 'My Project')]);
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded.first.name, 'My Project');
    });
  });

  group('ProjectPersistenceService.currentProjectPath', () {
    test('loadCurrentProjectPath returns null when not set', () async {
      final p = await _prefs();
      expect(ProjectPersistenceService.loadCurrentProjectPath(p), isNull);
    });

    test('saveCurrentProjectPath + load round-trip', () async {
      final p = await _prefs();
      await ProjectPersistenceService.saveCurrentProjectPath(p, '/my/path');
      expect(ProjectPersistenceService.loadCurrentProjectPath(p), '/my/path');
    });
  });

  group('ProjectPersistenceService.renameProject', () {
    test('updates name for matching path', () async {
      final p = await _prefs();
      await ProjectPersistenceService.addToRecent(p, _project('/foo', name: 'Old'));
      await ProjectPersistenceService.renameProject(p, '/foo', 'New');
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded.first.name, 'New');
    });

    test('does nothing for unknown path', () async {
      final p = await _prefs();
      await ProjectPersistenceService.addToRecent(p, _project('/foo'));
      await ProjectPersistenceService.renameProject(p, '/bar', 'New');
      final loaded = ProjectPersistenceService.loadRecentProjects(p);
      expect(loaded.first.path, '/foo');
    });
  });
}
