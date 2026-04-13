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

  /// Stream of server process logs (stdout/stderr).
  Stream<ServerProcessLog> get logs => _logController.stream;

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
        },
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _emitLog('error', 'Server process start timed out after 10s');
      return;
    } catch (e) {
      _emitLog('error', 'Failed to start server: $e');
      return;
    }

    _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) _emitLog('info', line.trim());
      }
    });
    _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) _emitLog('warn', line.trim());
      }
    });

    _process!.exitCode.then((code) {
      _emitLog(code == 0 ? 'info' : 'error', 'Server exited with code $code');
      _process = null;
    });
  }

  void _emitLog(String level, String message) {
    _logController.add(ServerProcessLog(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    ));
  }

  /// Kills the server process and its children (npm spawns node).
  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    _process = null;
    // Kill the process group so child processes (node) are also terminated.
    Process.killPid(proc.pid, ProcessSignal.sigterm);
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
    await stop();
    await _logController.close();
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
