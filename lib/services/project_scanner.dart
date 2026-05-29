/// Lightweight project context scanner for the "existing project" onboarding
/// path. Gathers README, git log, and top-level directory structure so the
/// facilitator agent can seed tasks without the user filling in an intake form.
library;

import 'dart:io';

class ScannedProjectContext {
  final String readme;
  final String gitLog;
  final String directoryStructure;
  final String pubspecInfo;

  const ScannedProjectContext({
    required this.readme,
    required this.gitLog,
    required this.directoryStructure,
    required this.pubspecInfo,
  });

  /// Assembles the free-text project description sent to the backend.
  String toDescription() {
    final parts = <String>[];
    if (pubspecInfo.isNotEmpty) parts.add(pubspecInfo);
    if (readme.isNotEmpty) parts.add(readme);
    return parts.isEmpty ? '(no description available)' : parts.join('\n\n---\n\n');
  }

  /// Extra key-value context appended to the intake answers map.
  Map<String, String> toAnswers() => {
        if (gitLog.isNotEmpty) 'git_history': gitLog,
        if (directoryStructure.isNotEmpty)
          'directory_structure': directoryStructure,
      };
}

class ProjectScanner {
  static const _readmeMaxChars = 1500;
  static const _gitLogMaxLines = 25;
  static const _excludedDirs = {
    '.git', 'build', '.dart_tool', 'node_modules',
    '.idea', '.gradle', '__pycache__', '.vscode',
  };

  static Future<ScannedProjectContext> scan(String projectPath) async {
    final results = await Future.wait([
      _readReadme(projectPath),
      _readGitLog(projectPath),
      _readDirStructure(projectPath),
      _readPubspec(projectPath),
    ]);
    return ScannedProjectContext(
      readme: results[0],
      gitLog: results[1],
      directoryStructure: results[2],
      pubspecInfo: results[3],
    );
  }

  static Future<String> _readReadme(String projectPath) async {
    for (final name in [
      'README.md', 'README.MD', 'README.rst', 'README.txt', 'README',
    ]) {
      final file = File('$projectPath/$name');
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          return content.length > _readmeMaxChars
              ? content.substring(0, _readmeMaxChars)
              : content;
        } catch (_) {}
      }
    }
    return '';
  }

  static Future<String> _readGitLog(String projectPath) async {
    try {
      final result = await Process.run(
        'git',
        ['log', '--oneline', '-$_gitLogMaxLines'],
        workingDirectory: projectPath,
      );
      if (result.exitCode == 0) return (result.stdout as String).trim();
    } catch (_) {}
    return '';
  }

  static Future<String> _readDirStructure(String projectPath) async {
    try {
      final entries = Directory(projectPath).listSync()
        ..sort((a, b) => a.path.compareTo(b.path));
      final lines = entries
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .where((name) => !name.startsWith('.') && !_excludedDirs.contains(name))
          .map((name) {
            final isDir = Directory('$projectPath/$name').existsSync();
            return isDir ? '$name/' : name;
          })
          .toList();
      return lines.join('\n');
    } catch (_) {
      return '';
    }
  }

  static Future<String> _readPubspec(String projectPath) async {
    final file = File('$projectPath/pubspec.yaml');
    if (!file.existsSync()) return '';
    try {
      final lines = await file.readAsLines();
      return lines
          .where((l) => l.startsWith('name:') || l.startsWith('description:'))
          .take(2)
          .join('\n');
    } catch (_) {
      return '';
    }
  }
}
