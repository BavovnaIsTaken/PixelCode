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

  /// Whether this host requires a secure WebSocket (tunnel or known secure domain).
  bool get isSecure =>
      host.endsWith('.trycloudflare.com') ||
      host.endsWith('.ts.net') ||
      host.startsWith('wss://');

  String get wsUrl {
    // If the host is already a full wss:// URL (e.g. from tunnel), use directly
    if (host.startsWith('wss://')) return host;
    if (host.startsWith('ws://')) return host;
    // Cloudflare tunnel domains → wss:// (port 443 implicit)
    if (isSecure) return 'wss://$host';
    return 'ws://$host:$port';
  }

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
