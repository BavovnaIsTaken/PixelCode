/// Manages the Node.js server process lifecycle.
///
/// Starts the server automatically when the app launches
/// and kills it when the app is disposed.
library;

import 'dart:io';

class ServerProcessService {
  Process? _process;

  /// Resolves the server directory from the project root.
  /// In debug mode, `Directory.current` is the project root.
  /// In release, falls back to the executable's parent directory.
  static String get _serverDir {
    return '${Directory.current.path}/server';
  }

  /// Starts the Node.js server if it is not already running.
  Future<void> start() async {
    if (_process != null) return;

    final serverDir = _serverDir;
    if (!Directory(serverDir).existsSync()) {
      // ignore: avoid_print
      print('[ServerProcess] server/ directory not found at $serverDir');
      return;
    }

    // ignore: avoid_print
    print('[ServerProcess] Starting server in $serverDir');

    // Launch via shell so that PATH from the user's profile is inherited.
    // This ensures node/npm/npx are found even when the app is launched
    // from Finder or Xcode rather than from the terminal.
    _process = await Process.start(
      '/bin/zsh',
      ['-l', '-c', 'npm run dev'],
      workingDirectory: serverDir,
      environment: {
        ...Platform.environment,
        'PORT': '9720',
      },
    );

    _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
      // ignore: avoid_print
      print('[Server] $data');
    });
    _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
      // ignore: avoid_print
      print('[Server:err] $data');
    });

    _process!.exitCode.then((code) {
      // ignore: avoid_print
      print('[ServerProcess] Server exited with code $code');
      _process = null;
    });
  }

  /// Kills the server process and its children (npm spawns node).
  Future<void> stop() async {
    final proc = _process;
    if (proc == null) return;
    _process = null;
    // Kill the process group so child processes (node) are also terminated.
    Process.killPid(proc.pid, ProcessSignal.sigterm);
  }
}
