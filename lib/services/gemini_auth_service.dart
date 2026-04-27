/// Google OAuth state for the local `gemini` CLI.
///
/// The official `gemini` CLI (https://github.com/google-gemini/gemini-cli) does
/// NOT expose an `auth login/logout/status` subcommand — authentication runs
/// interactively on first launch and credentials are persisted under
/// `~/.gemini/`. This service therefore inspects the filesystem instead of
/// invoking the CLI, and triggers login by spawning a terminal window with
/// `gemini` so the OAuth flow can use a TTY.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class GeminiAuthStatus {
  final bool loggedIn;
  final String? email;
  final String? projectId;

  const GeminiAuthStatus({
    required this.loggedIn,
    this.email,
    this.projectId,
  });

  static const notLoggedIn = GeminiAuthStatus(loggedIn: false);
}

class GeminiAuthService {
  static const _binaryCandidates = <String>[
    '/opt/homebrew/bin/gemini',
    '/usr/local/bin/gemini',
    '/opt/homebrew/opt/node/bin/gemini',
  ];

  static String? _binaryCache;
  static bool _binaryProbed = false;

  /// Override for tests — points at a fake `~/.gemini` directory.
  static String? geminiHomeOverride;

  /// Locates the `gemini` binary on PATH or in known install locations.
  /// The official package installs as `gemini` (not `gemini-cli`).
  static String? findBinary() {
    if (_binaryProbed) return _binaryCache;
    _binaryProbed = true;

    if (Platform.isMacOS || Platform.isLinux) {
      try {
        final result = Process.runSync('/bin/zsh', ['-l', '-c', 'which gemini']);
        if (result.exitCode == 0) {
          final path = (result.stdout as String).trim();
          if (path.isNotEmpty && File(path).existsSync()) {
            return _binaryCache = path;
          }
        }
      } catch (_) {}
    }

    for (final candidate in _binaryCandidates) {
      if (File(candidate).existsSync()) {
        return _binaryCache = candidate;
      }
    }
    return _binaryCache = null;
  }

  /// Resets cached binary lookup. Tests use this to re-probe after mutating PATH.
  static void resetBinaryCache() {
    _binaryCache = null;
    _binaryProbed = false;
  }

  static Directory get _geminiHome {
    if (geminiHomeOverride != null) return Directory(geminiHomeOverride!);
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return Directory('$home/.gemini');
  }

  static File get oauthCredsFile => File('${_geminiHome.path}/oauth_creds.json');
  static File get accountsFile =>
      File('${_geminiHome.path}/google_accounts.json');
  static File get projectsFile => File('${_geminiHome.path}/projects.json');

  /// Reads `~/.gemini/*.json` to determine login state. Does not invoke the CLI.
  /// A refresh_token in `oauth_creds.json` counts as logged-in even if the
  /// access_token has expired — the CLI will silently refresh on next use.
  static Future<GeminiAuthStatus> checkStatus() async {
    try {
      final creds = oauthCredsFile;
      if (!creds.existsSync()) return GeminiAuthStatus.notLoggedIn;

      final credsJson =
          jsonDecode(await creds.readAsString()) as Map<String, dynamic>;
      final hasRefresh = (credsJson['refresh_token'] as String?)?.isNotEmpty ?? false;
      final hasAccess = (credsJson['access_token'] as String?)?.isNotEmpty ?? false;
      if (!hasRefresh && !hasAccess) return GeminiAuthStatus.notLoggedIn;

      String? email;
      if (accountsFile.existsSync()) {
        try {
          final accounts = jsonDecode(await accountsFile.readAsString())
              as Map<String, dynamic>;
          email = accounts['active'] as String?;
        } catch (_) {}
      }

      String? projectId;
      if (projectsFile.existsSync()) {
        try {
          final projects = jsonDecode(await projectsFile.readAsString())
              as Map<String, dynamic>;
          final map = projects['projects'] as Map<String, dynamic>?;
          if (map != null && map.isNotEmpty) {
            final cwd = Directory.current.path;
            projectId = (map[cwd] ?? map.values.first) as String?;
          }
        } catch (_) {}
      }

      return GeminiAuthStatus(
        loggedIn: true,
        email: email,
        projectId: projectId,
      );
    } catch (_) {
      return GeminiAuthStatus.notLoggedIn;
    }
  }

  /// Opens a new terminal window running `gemini`, so the OAuth flow has a TTY.
  /// Returns false on Windows (no robust headless flow yet) or when the binary
  /// is missing — caller should surface a "run `gemini` manually" hint.
  static Future<bool> login() async {
    final bin = findBinary();
    if (bin == null) return false;

    try {
      if (Platform.isMacOS) {
        final script =
            'tell application "Terminal" to do script "${bin.replaceAll('"', '\\"')}"\n'
            'tell application "Terminal" to activate';
        final result = await Process.run('osascript', ['-e', script]);
        return result.exitCode == 0;
      }
      if (Platform.isLinux) {
        for (final term in ['x-terminal-emulator', 'gnome-terminal', 'konsole', 'xterm']) {
          try {
            final result = await Process.run('which', [term]);
            if (result.exitCode == 0) {
              await Process.start(term, ['-e', bin], mode: ProcessStartMode.detached);
              return true;
            }
          } catch (_) {}
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Removes cached OAuth credentials. The next `gemini` invocation will
  /// re-prompt for authentication.
  static Future<bool> logout() async {
    var ok = false;
    try {
      if (oauthCredsFile.existsSync()) {
        await oauthCredsFile.delete();
        ok = true;
      }
      if (accountsFile.existsSync()) {
        await accountsFile.delete();
        ok = true;
      }
    } catch (_) {
      return false;
    }
    return ok;
  }
}
