// lib/models/session_profile.dart

/// A named connection profile for a PixelCode server.
///
/// On macOS the profile may include an [apiKey] so the local server
/// can be (re)started with the correct ANTHROPIC_API_KEY.
/// On iOS every profile is remote-only (no apiKey needed).
library;

import 'dart:convert';

class SessionProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String? apiKey;

  const SessionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 9720,
    this.apiKey,
  });

  String get wsUrl => 'ws://$host:$port';

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;

  SessionProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? Function()? apiKey,
  }) =>
      SessionProfile(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        apiKey: apiKey != null ? apiKey() : this.apiKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        if (apiKey != null) 'apiKey': apiKey,
      };

  factory SessionProfile.fromJson(Map<String, dynamic> json) => SessionProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int? ?? 9720,
        apiKey: json['apiKey'] as String?,
      );

  static String encodeList(List<SessionProfile> profiles) =>
      jsonEncode(profiles.map((p) => p.toJson()).toList());

  static List<SessionProfile> decodeList(String json) =>
      (jsonDecode(json) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionProfile.fromJson)
          .toList();
}
