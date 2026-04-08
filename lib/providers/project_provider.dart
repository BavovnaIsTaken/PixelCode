/// Riverpod providers for project switching and team memory.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/project.dart';
import '../models/project_memory.dart';
import '../services/project_persistence_service.dart';
import 'agent_provider.dart';
import 'settings_provider.dart';

// ─── Current project ────────────────────────────────────────────────────────

class ProjectNotifier extends Notifier<Project?> {
  @override
  Project? build() {
    final prefs = ref.read(sharedPrefsProvider);
    final path = ProjectPersistenceService.loadCurrentProjectPath(prefs);
    if (path == null) {
      // First launch — use the current working directory
      final cwd = Directory.current.path;
      return Project.fromPath(cwd);
    }
    // Restore saved project (find custom name from recent list)
    final recent = ProjectPersistenceService.loadRecentProjects(prefs);
    final saved = recent.where((p) => p.path == path).firstOrNull;
    return saved ?? Project.fromPath(path);
  }

  /// Switch to a different project. Generates a summary for the current one,
  /// then moves to the new project with loaded memories.
  Future<void> switchProject(String newPath, {String? customName}) async {
    final prefs = ref.read(sharedPrefsProvider);
    final ws = ref.read(wsServiceProvider);

    // 1. Generate and save summary for the current project
    final current = state;
    if (current != null) {
      await _generateAndSaveSummary(current.path);
    }

    // 2. Create new project object
    final project = Project(
      path: newPath,
      name: customName ?? newPath.split('/').last,
      lastOpened: DateTime.now(),
    );

    // 3. Save to recent projects & set as current
    await ProjectPersistenceService.addToRecent(prefs, project);
    await ProjectPersistenceService.saveCurrentProjectPath(prefs, newPath);

    // 4. Tell server to switch working directory
    ws.setProject(newPath);

    // 5. Load memories for the new project, apply decay, send to server
    final memories = await ProjectPersistenceService.loadMemories(newPath);
    final decayed = ProjectMemoryEntry.applyDecay(memories);
    final memoryText = ProjectMemoryEntry.formatForPrompt(decayed);
    if (memoryText.isNotEmpty) {
      ws.setProjectContext(memoryText);
    }

    // 6. Clear chat for a fresh session
    ref.read(chatProvider.notifier).newChat();

    // 7. Update state
    state = project;

    // 8. Refresh recent projects provider
    ref.invalidate(recentProjectsProvider);
  }

  /// Update the custom name for the current project.
  Future<void> renameProject(String newName) async {
    final current = state;
    if (current == null) return;

    final prefs = ref.read(sharedPrefsProvider);
    await ProjectPersistenceService.renameProject(prefs, current.path, newName);
    state = current.copyWith(name: newName);
    ref.invalidate(recentProjectsProvider);
  }

  /// Set the initial project on first app launch (called from main.dart).
  Future<void> setInitialProject(String path) async {
    final prefs = ref.read(sharedPrefsProvider);
    final project = Project.fromPath(path);
    await ProjectPersistenceService.addToRecent(prefs, project);
    await ProjectPersistenceService.saveCurrentProjectPath(prefs, path);
    state = project;

    // Load and send memories if returning to a known project
    final ws = ref.read(wsServiceProvider);
    final memories = await ProjectPersistenceService.loadMemories(path);
    final decayed = ProjectMemoryEntry.applyDecay(memories);
    final memoryText = ProjectMemoryEntry.formatForPrompt(decayed);
    if (memoryText.isNotEmpty) {
      // Wait for connection, then send context
      ws.connectionStatus.firstWhere((connected) => connected).then((_) {
        ws.setProjectContext(memoryText);
      });
    }

    ref.invalidate(recentProjectsProvider);
  }

  /// Ask the server to summarize the current session, then save it to disk.
  Future<void> _generateAndSaveSummary(String projectPath) async {
    final ws = ref.read(wsServiceProvider);
    if (!ws.isConnected) return;

    final completer = Completer<String>();
    StreamSubscription<ServerMessage>? sub;

    sub = ws.messages.listen((msg) {
      if (msg is SummaryResultMessage) {
        sub?.cancel();
        completer.complete(msg.summary);
      }
    });

    ws.generateSummary();

    try {
      final summary = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => '',
      );

      if (summary.isNotEmpty) {
        final entry = ProjectMemoryEntry(
          summary: summary,
          timestamp: DateTime.now(),
        );
        await ProjectPersistenceService.saveMemory(projectPath, entry);
      }
    } finally {
      sub.cancel();
    }
  }
}

final projectProvider = NotifierProvider<ProjectNotifier, Project?>(
  ProjectNotifier.new,
);

// ─── Recent projects ────────────────────────────────────────────────────────

class RecentProjectsNotifier extends Notifier<List<Project>> {
  @override
  List<Project> build() {
    final prefs = ref.read(sharedPrefsProvider);
    return ProjectPersistenceService.loadRecentProjects(prefs);
  }
}

final recentProjectsProvider =
    NotifierProvider<RecentProjectsNotifier, List<Project>>(
  RecentProjectsNotifier.new,
);
