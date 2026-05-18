/// Pure helpers extracted from `AgentWsService` so the parts of the
/// connection lifecycle that aren't tangled with `dart:io` can be unit
/// tested.
///
/// Anything I/O-bound (`WebSocket.connect`, `InternetAddress.lookup`,
/// `HttpClient`) stays in the service. Anything that's a string/byte/JSON
/// transformation lives here.
library;

import 'dart:convert';
import 'dart:math';

/// True when the host requires the DoH fallback path. Tailscale's
/// `*.ts.net` hostnames are the only ones the service currently treats
/// as "system DNS may not know about this".
bool needsDohRoute(String host) => host.endsWith('.ts.net');

/// Parses a DoH JSON response body and returns the first A-record IP
/// when present, or null when the response has no Answer section, the
/// section is empty, or the payload isn't valid JSON.
///
/// Kept tolerant on purpose: a malformed answer from Google should fall
/// back to "no override" rather than crash the whole connect path.
String? parseDohAnswer(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;
    final answers = json['Answer'];
    if (answers is! List || answers.isEmpty) return null;
    final first = answers.first;
    if (first is! Map<String, dynamic>) return null;
    final ip = first['data'];
    return ip is String ? ip : null;
  } catch (_) {
    return null;
  }
}

/// 32-hex-char client id from 16 random bytes. Pulled out of the service
/// so the format invariant (length, lowercase hex, padded zero-bytes)
/// can be verified directly. `rng` injected for determinism in tests.
String generateClientId([Random? rng]) {
  final r = rng ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Format a single line for the in-app connection terminal: `[HH:MM:SS] msg`.
/// Uses the time portion of the ISO-8601 representation so the format
/// matches whatever the runtime's `toIso8601String()` produces (UTC or
/// local — the service writes whatever `DateTime.now()` is configured
/// to emit, and the widget displays it verbatim).
String formatConnectionLogLine(DateTime now, String msg) {
  final ts = now.toIso8601String().substring(11, 19);
  return '[$ts] $msg';
}
