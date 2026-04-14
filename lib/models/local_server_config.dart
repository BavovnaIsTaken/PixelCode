/// Configuration for the local Node.js server process (macOS/desktop only).
///
/// Separates server concerns from session/connection concerns:
/// [SessionProfile] = where to connect, [LocalServerConfig] = how to run.
library;

import 'dart:convert';

class LocalServerConfig {
  final String? apiKey;
  final int port;

  /// Whether to start the server automatically when the app launches.
  final bool autoStart;

  const LocalServerConfig({
    this.apiKey,
    this.port = 9720,
    this.autoStart = false,
  });

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;

  LocalServerConfig copyWith({
    String? Function()? apiKey,
    int? port,
    bool? autoStart,
  }) =>
      LocalServerConfig(
        apiKey: apiKey != null ? apiKey() : this.apiKey,
        port: port ?? this.port,
        autoStart: autoStart ?? this.autoStart,
      );

  Map<String, dynamic> toJson() => {
        if (apiKey != null) 'apiKey': apiKey,
        'port': port,
        'autoStart': autoStart,
      };

  factory LocalServerConfig.fromJson(Map<String, dynamic> json) =>
      LocalServerConfig(
        apiKey: json['apiKey'] as String?,
        port: json['port'] as int? ?? 9720,
        autoStart: json['autoStart'] as bool? ?? false,
      );

  String encode() => jsonEncode(toJson());

  static LocalServerConfig decode(String raw) =>
      LocalServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
