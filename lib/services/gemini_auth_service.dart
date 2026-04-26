/// Wraps the `gemini-cli` to manage OAuth authentication with Google.
library;

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

  factory GeminiAuthStatus.fromJson(Map<String, dynamic> json) =>
      GeminiAuthStatus(
        loggedIn: json['loggedIn'] as bool? ?? false,
        email: json['email'] as String?,
        projectId: json['projectId'] as String?,
      );

  static const notLoggedIn = GeminiAuthStatus(loggedIn: false);
}

class GeminiAuthService {
  /// Finds the `gemini-cli` binary on PATH or in common locations.
  static String? _findGeminiBinary() {
    if (!Platform.isMacOS && !Platform.isLinux) return null;

    try {
      final result = Process.runSync('which', ['gemini-cli']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}

    return null;
  }

  static String? _binary;

  static String? get binary => _binary ??= _findGeminiBinary();

  /// Checks current Gemini auth status by running `gemini-cli auth status`.
  static Future<GeminiAuthStatus> checkStatus() async {
    final bin = binary;
    if (bin == null) return GeminiAuthStatus.notLoggedIn;

    try {
      final result = await Process.run(bin, ['auth', 'status']);
      if (result.exitCode != 0) return GeminiAuthStatus.notLoggedIn;

      final json =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      return GeminiAuthStatus.fromJson(json);
    } catch (_) {
      return GeminiAuthStatus.notLoggedIn;
    }
  }

  /// Launches `gemini-cli auth login` which opens the browser for OAuth.
  static Future<bool> login() async {
    final bin = binary;
    if (bin == null) return false;

    try {
      final result = await Process.run(
        '/bin/zsh',
        ['-l', '-c', '$bin auth login'],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Runs `gemini-cli auth logout`.
  static Future<bool> logout() async {
    final bin = binary;
    if (bin == null) return false;

    try {
      final result = await Process.run(bin, ['auth', 'logout']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
