/// Persistence for project metadata and team memories.
///
/// Recent projects list → SharedPreferences (small, flat).
/// Per-project memories → JSON files in Application Support (scalable).
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/project.dart';
import '../models/project_memory.dart';

const _kRecentProjects = 'recent_projects';
const _kCurrentProjectPath = 'current_project_path';
const _maxRecentProjects = 10;

class ProjectPersistenceService {
  // ─── Recent projects (SharedPreferences) ─────────────────────────────────

  static List<Project> loadRecentProjects(SharedPreferences prefs) {
    final raw = prefs.getString(_kRecentProjects);
    if (raw == null) return [];
    try {
      return Project.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecentProjects(
    SharedPreferences prefs,
    List<Project> projects,
  ) async {
    final trimmed = projects.take(_maxRecentProjects).toList();
    await prefs.setString(_kRecentProjects, Project.listToJson(trimmed));
  }

  static Future<void> addToRecent(
    SharedPreferences prefs,
    Project project,
  ) async {
    final existing = loadRecentProjects(prefs);
    existing.removeWhere((p) => p.path == project.path);
    existing.insert(0, project);
    await saveRecentProjects(prefs, existing);
  }

  static String? loadCurrentProjectPath(SharedPreferences prefs) {
    return prefs.getString(_kCurrentProjectPath);
  }

  static Future<void> saveCurrentProjectPath(
    SharedPreferences prefs,
    String path,
  ) async {
    await prefs.setString(_kCurrentProjectPath, path);
  }

  // ─── Per-project memories (Application Support) ──────────────────────────

  static Future<Directory> _memoryDir(String projectPath) async {
    final appDir = await getApplicationSupportDirectory();
    final storageKey =
        projectPath.replaceAll('/', '-').replaceAll(RegExp('^-'), '');
    final dir =
        Directory('${appDir.path}/pixelcode/projects/$storageKey');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _memoryFile(String projectPath) async {
    final dir = await _memoryDir(projectPath);
    return File('${dir.path}/memory.json');
  }

  static Future<List<ProjectMemoryEntry>> loadMemories(
    String projectPath,
  ) async {
    try {
      final file = await _memoryFile(projectPath);
      if (!file.existsSync()) return [];
      final raw = await file.readAsString();
      return ProjectMemoryEntry.listFromJson(raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMemory(
    String projectPath,
    ProjectMemoryEntry entry,
  ) async {
    final existing = await loadMemories(projectPath);
    existing.insert(0, entry);
    await saveAllMemories(projectPath, existing);
  }

  static Future<void> saveAllMemories(
    String projectPath,
    List<ProjectMemoryEntry> entries,
  ) async {
    final file = await _memoryFile(projectPath);
    await file.writeAsString(ProjectMemoryEntry.listToJson(entries));
  }

  /// Update the custom name for a project in the recent list.
  static Future<void> renameProject(
    SharedPreferences prefs,
    String projectPath,
    String newName,
  ) async {
    final projects = loadRecentProjects(prefs);
    final idx = projects.indexWhere((p) => p.path == projectPath);
    if (idx >= 0) {
      projects[idx] = projects[idx].copyWith(name: newName);
      await saveRecentProjects(prefs, projects);
    }
  }
}
