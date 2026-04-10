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

  /// Resolves the server directory from the project root.
  /// In debug mode, `Directory.current` is the project root.
  /// In release, falls back to the executable's parent directory.
  static String get _serverDir {
    return '${Directory.current.path}/server';
  }

  /// Starts the Node.js server if it is not already running.
  /// If [projectPath] is provided, it will be used as PROJECT_CWD.
  Future<void> start({String? projectPath}) async {
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
