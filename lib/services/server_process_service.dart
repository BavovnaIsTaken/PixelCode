/// Manages the Node.js server process lifecycle.
///
/// Starts the server automatically when the app launches
/// and kills it when the app is disposed.
library;

import 'dart:async';
import 'dart:io';

class ServerProcessService {
  Process? _process;
  final _logController = StreamController<ServerProcessLog>.broadcast();
  final _runningController = StreamController<bool>.broadcast();
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _disposed = false;

  /// Stream of server process logs (stdout/stderr).
  Stream<ServerProcessLog> get logs => _logController.stream;

  /// Emits `true` when the server starts, `false` when it stops.
  Stream<bool> get runningStatus => _runningController.stream;

  /// Whether the server process is currently running.
  bool get isRunning => _process != null;

  /// Resolves the server directory by walking up the directory tree from the
  /// executable path looking for a `server/package.json`. Falls back to
  /// `Directory.current` if nothing is found (terminal debug mode).
  static String get _serverDir {
    // Walk up from the executable (handles .app bundles at any nesting depth).
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 12; i++) {
      final candidate = '${dir.path}/server';
      if (File('$candidate/package.json').existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached filesystem root
      dir = parent;
    }
    // Fallback — will be caught by the existsSync check in start()
    return '${Directory.current.path}/server';
  }

  /// Finds the newest Claude Code VS Code extension native binary.
  ///
  /// Scans `~/.vscode/extensions/` for `anthropic.claude-code-*` directories,
  /// sorts by version descending, and returns the path to the first
  /// `resources/native-binary/claude` binary that exists on disk.
  /// Returns `null` on non-macOS or if no extension is installed.
  static String? _findClaudeNativeBinary() {
    if (!Platform.isMacOS) return null;

    final arch = Platform.version.contains('arm') ? 'darwin-arm64' : 'darwin-x64';
    final extensionsDir = Directory(
      '${Platform.environment['HOME']}/.vscode/extensions',
    );
    if (!extensionsDir.existsSync()) return null;

    final candidates = extensionsDir
        .listSync()
        .whereType<Directory>()
        .where((d) {
          final name = d.uri.pathSegments
              .lastWhere((s) => s.isNotEmpty, orElse: () => '');
          return name.startsWith('anthropic.claude-code-') &&
              name.endsWith(arch);
        })
        .toList();

    if (candidates.isEmpty) return null;

    // Sort descending by version segment: "anthropic.claude-code-2.1.107-darwin-arm64"
    // split('-') → ['anthropic.claude', 'code', '2.1.107', 'darwin', 'arm64']
    candidates.sort((a, b) {
      String ver(Directory d) {
        final parts = d.uri.pathSegments
            .lastWhere((s) => s.isNotEmpty)
            .split('-');
        return parts.length > 2 ? parts[2] : '';
      }
      return ver(b).compareTo(ver(a));
    });

    for (final dir in candidates) {
      final binary = File('${dir.path}/resources/native-binary/claude');
      if (binary.existsSync()) return binary.path;
    }
    return null;
  }

  /// Starts the Node.js server if it is not already running.
  /// If [projectPath] is provided, it will be used as PROJECT_CWD.
  Future<void> start({String? projectPath}) async {
    // Process.start is not supported on iOS/Android (OS sandbox restriction).
    if (Platform.isIOS || Platform.isAndroid) {
      _emitLog('info', 'Server process not supported on mobile platforms');
      return;
    }

    if (_process != null) return;

    final serverDir = _serverDir;
    if (!Directory(serverDir).existsSync()) {
      _emitLog('error', 'server/ directory not found at $serverDir');
      return;
    }

    _emitLog('info', 'Starting server in $serverDir');

    final claudeBinary = _findClaudeNativeBinary();
    if (claudeBinary != null) {
      _emitLog('info', 'Using Claude binary: $claudeBinary');
    } else {
      _emitLog('warn', 'No Claude Code extension binary found — relying on PATH');
    }

    // Launch via shell so that PATH from the user's profile is inherited.
    // This ensures node/npm/npx are found even when the app is launched
    // from Finder or Xcode rather than from the terminal.
    try {
      _process = await Process.start(
        '/bin/zsh',
        ['-l', '-c', 'npm run dev'],
        workingDirectory: serverDir,
        environment: {
          ...Platform.environment,
          'PORT': '9720',
          'PROJECT_CWD': projectPath ?? Directory.current.path,
          // Point the SDK to the newest installed VS Code native binary so it
          // authenticates via claude.ai Pro (OAuth) rather than a bare API key.
          'CLAUDE_CODE_EXECPATH': ?claudeBinary,
        },
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _emitLog('error', 'Server process start timed out after 10s');
      return;
    } catch (e) {
      _emitLog('error', 'Failed to start server: $e');
      return;
    }

    _stdoutSub = _process!.stdout
        .transform(const SystemEncoding().decoder)
        .listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) _emitLog('info', line.trim());
      }
    });
    _stderrSub = _process!.stderr
        .transform(const SystemEncoding().decoder)
        .listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) _emitLog('warn', line.trim());
      }
    });

    if (!_runningController.isClosed) _runningController.add(true);

    _process!.exitCode.then((code) {
      if (_disposed) return;
      _emitLog(code == 0 ? 'info' : 'error', 'Server exited with code $code');
      _process = null;
      if (!_runningController.isClosed) _runningController.add(false);
    });
  }

  void _emitLog(String level, String message) {
    if (_logController.isClosed) return;
    _logController.add(ServerProcessLog(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    ));
  }

  /// Kills the server process and its entire process tree (zsh → npm → node).
  Future<void> stop() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final proc = _process;
    if (proc == null) return;
    _process = null;

    // Process.killPid only sends a signal to a single PID. When the server
    // is launched via `/bin/zsh -l -c 'npm run dev'`, the tree looks like
    // zsh → npm → node. Killing only zsh leaves npm/node alive as orphans
    // and the app hangs because the Dart VM waits for them.
    //
    // Strategy: kill the descendants bottom-up, then the root.
    await _killProcessTree(proc.pid);
  }

  /// Collects all descendant PIDs of [pid] (leaves first).
  static Future<List<int>> _collectProcessTree(int pid) async {
    final pids = <int>[];
    try {
      final result = await Process.run('pgrep', ['-P', '$pid']);
      if (result.exitCode == 0) {
        final childPids = (result.stdout as String)
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map(int.tryParse)
            .whereType<int>();
        for (final child in childPids) {
          pids.addAll(await _collectProcessTree(child));
        }
      }
    } catch (_) {}
    pids.add(pid);
    return pids;
  }

  /// Kills the entire process tree: SIGTERM first, then SIGKILL after a timeout
  /// if any process is still alive.
  static Future<void> _killProcessTree(int pid) async {
    final pids = await _collectProcessTree(pid);

    // Send SIGTERM to all.
    for (final p in pids) {
      try {
        Process.killPid(p, ProcessSignal.sigterm);
      } catch (_) {}
    }

    // Wait up to 2 seconds for processes to exit, then SIGKILL survivors.
    await Future<void>.delayed(const Duration(seconds: 2));
    for (final p in pids) {
      try {
        Process.killPid(p, ProcessSignal.sigkill);
      } catch (_) {
        // Already exited — expected.
      }
    }
  }

  /// Restarts the server process, optionally with a new project path.
  Future<void> restart({String? projectPath}) async {
    _emitLog('info', 'Restarting server…');
    await stop();
    // Give the OS a moment to release the port.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await start(projectPath: projectPath);
  }

  /// Kills the server and closes the log stream. Call only on final disposal.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _logController.close();
    await _runningController.close();
  }
}

class ServerProcessLog {
  final DateTime timestamp;
  final String level;
  final String message;

  const ServerProcessLog({
    required this.timestamp,
    required this.level,
    required this.message,
  });
}
