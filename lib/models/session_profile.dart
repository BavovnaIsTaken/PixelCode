// lib/models/session_profile.dart

/// A named connection profile — where to connect, not how to run a server.
///
/// Server configuration (API key, auto-start) lives in [LocalServerConfig].
library;

import 'dart:convert';

class SessionProfile {
  final String id;
  final String name;
  final String host;
  final int port;

  const SessionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 9720,
  });

  String get wsUrl => 'ws://$host:$port';

  SessionProfile copyWith({
    String? name,
    String? host,
    int? port,
  }) =>
      SessionProfile(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
      };

  factory SessionProfile.fromJson(Map<String, dynamic> json) => SessionProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int? ?? 9720,
      );

  static String encodeList(List<SessionProfile> profiles) =>
      jsonEncode(profiles.map((p) => p.toJson()).toList());

  static List<SessionProfile> decodeList(String json) =>
      (jsonDecode(json) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionProfile.fromJson)
          .toList();
}
