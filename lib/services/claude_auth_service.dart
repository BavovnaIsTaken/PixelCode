/// Wraps the `claude` CLI to manage OAuth authentication.
library;

import 'dart:convert';
import 'dart:io';

class ClaudeAuthStatus {
  final bool loggedIn;
  final String? email;
  final String? orgName;
  final String? subscriptionType;
  final String? authMethod;

  const ClaudeAuthStatus({
    required this.loggedIn,
    this.email,
    this.orgName,
    this.subscriptionType,
    this.authMethod,
  });

  factory ClaudeAuthStatus.fromJson(Map<String, dynamic> json) =>
      ClaudeAuthStatus(
        loggedIn: json['loggedIn'] as bool? ?? false,
        email: json['email'] as String?,
        orgName: json['orgName'] as String?,
        subscriptionType: json['subscriptionType'] as String?,
        authMethod: json['authMethod'] as String?,
      );

  static const notLoggedIn = ClaudeAuthStatus(loggedIn: false);
}

class ClaudeAuthService {
  /// Finds the `claude` binary — prefers the VS Code extension native binary,
  /// falls back to `claude` on PATH.
  static String? _findClaudeBinary() {
    if (!Platform.isMacOS && !Platform.isLinux) return null;

    final home = Platform.environment['HOME'];
    if (home != null) {
      final arch =
          Platform.version.contains('arm') ? 'darwin-arm64' : 'darwin-x64';
      final extensionsDir = Directory('$home/.vscode/extensions');
      if (extensionsDir.existsSync()) {
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
      }
    }

    // Fallback: claude on PATH
    final result = Process.runSync('which', ['claude']);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
    return null;
  }

  static String? _binary;

  static String? get binary => _binary ??= _findClaudeBinary();

  /// Checks current auth status by running `claude auth status`.
  static Future<ClaudeAuthStatus> checkStatus() async {
    final bin = binary;
    if (bin == null) return ClaudeAuthStatus.notLoggedIn;

    try {
      final result = await Process.run(bin, ['auth', 'status']);
      if (result.exitCode != 0) return ClaudeAuthStatus.notLoggedIn;

      final json =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      return ClaudeAuthStatus.fromJson(json);
    } catch (_) {
      return ClaudeAuthStatus.notLoggedIn;
    }
  }

  /// Launches `claude auth login --claudeai` which opens the browser for OAuth.
  static Future<bool> login() async {
    final bin = binary;
    if (bin == null) return false;

    try {
      final result = await Process.run(
        '/bin/zsh',
        ['-l', '-c', '$bin auth login --claudeai'],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Runs `claude auth logout`.
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
