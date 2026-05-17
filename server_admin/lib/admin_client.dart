import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin HTTP client over the PixelCode server's `/admin/api/*` endpoints.
///
/// The server gates these to loopback-only (127.0.0.1), so on macOS the app
/// works against a local server out of the box. iOS support requires the
/// server to opt into a token-auth + non-loopback mode (not implemented yet
/// — until then, the iOS build is useful only for the same machine via a
/// reverse-tethered URL or future remote-admin token).
class AdminClient {
  AdminClient(this.baseUrl);

  /// Base URL like `http://localhost:9720`. No trailing slash.
  final String baseUrl;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<ServerStatus> status() async {
    final res = await http.get(_u('/admin/api/status')).timeout(const Duration(seconds: 4));
    _ensureOk(res);
    return ServerStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<ConfigSnapshot> getConfig() async {
    final res = await http.get(_u('/admin/api/config')).timeout(const Duration(seconds: 4));
    _ensureOk(res);
    return ConfigSnapshot.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<ConfigSaveResult> saveConfig(Map<String, dynamic> patch) async {
    final res = await http
        .post(
          _u('/admin/api/config'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(patch),
        )
        .timeout(const Duration(seconds: 4));
    _ensureOk(res);
    return ConfigSaveResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<ConnectedClientInfo>> clients() async {
    final res = await http.get(_u('/admin/api/clients')).timeout(const Duration(seconds: 4));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['clients'] as List<dynamic>)
        .map((e) => ConnectedClientInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<LogEntry>> logs({int limit = 200}) async {
    final res = await http
        .get(_u('/admin/api/logs', {'n': '$limit'}))
        .timeout(const Duration(seconds: 4));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final entries = (body['entries'] as List<dynamic>)
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return entries;
  }

  Future<void> restart() async {
    final res = await http.post(_u('/admin/api/restart')).timeout(const Duration(seconds: 4));
    _ensureOk(res);
  }

  Future<void> stop() async {
    final res = await http.post(_u('/admin/api/stop')).timeout(const Duration(seconds: 4));
    _ensureOk(res);
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String detail = res.body;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['error'] is String) detail = body['error'] as String;
    } catch (_) {}
    throw AdminException('HTTP ${res.statusCode}: $detail');
  }
}

class AdminException implements Exception {
  AdminException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Effective config — values currently in use by the running server.
/// Fields can come from config-file, env, or CLI flag (see source maps).
class ServerConfig {
  ServerConfig({
    required this.port,
    required this.projectCwd,
    this.otaHostname,
  });

  final int port;
  final String projectCwd;
  final String? otaHostname;

  factory ServerConfig.fromJson(Map<String, dynamic> j) => ServerConfig(
        port: (j['port'] as num).toInt(),
        projectCwd: j['projectCwd'] as String,
        otaHostname: j['otaHostname'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'port': port,
        'projectCwd': projectCwd,
        'otaHostname': otaHostname,
      };
}

class ServerStatus {
  ServerStatus({
    required this.pid,
    required this.uptimeMs,
    required this.bootedAt,
    required this.config,
    required this.configPath,
    required this.envOverrides,
    required this.flagOverrides,
    required this.clients,
    required this.mdnsActive,
    this.tailscaleUrl,
    this.metrics,
  });

  final int pid;
  final int uptimeMs;
  final DateTime bootedAt;
  final ServerConfig config;
  final String configPath;
  final List<String> envOverrides;
  final List<String> flagOverrides;
  final int clients;
  final bool mdnsActive;
  final String? tailscaleUrl;
  final ServerMetrics? metrics;

  factory ServerStatus.fromJson(Map<String, dynamic> j) => ServerStatus(
        pid: (j['pid'] as num).toInt(),
        uptimeMs: (j['uptimeMs'] as num).toInt(),
        bootedAt: DateTime.parse(j['bootedAt'] as String),
        config: ServerConfig.fromJson(j['config'] as Map<String, dynamic>),
        configPath: j['configPath'] as String,
        envOverrides: (j['envOverrides'] as List<dynamic>).cast<String>(),
        flagOverrides: (j['flagOverrides'] as List<dynamic>).cast<String>(),
        clients: (j['clients'] as num).toInt(),
        mdnsActive: j['mdnsActive'] as bool,
        tailscaleUrl: j['tailscaleUrl'] as String?,
        metrics: j['metrics'] is Map<String, dynamic>
            ? ServerMetrics.fromJson(j['metrics'] as Map<String, dynamic>)
            : null,
      );

  /// Where did a config field's effective value come from?
  ///   `'flag'` > `'env'` > `'file'`.
  String sourceOf(String key) {
    if (flagOverrides.contains(key)) return 'flag';
    if (envOverrides.contains(key)) return 'env';
    return 'file';
  }
}

/// Runtime metrics sampled at every `/admin/api/status` call.
class ServerMetrics {
  ServerMetrics({
    required this.rss,
    required this.heapUsed,
    required this.heapTotal,
    required this.external,
    required this.cpuPercent,
    required this.queuedTasks,
    required this.activeAgents,
    required this.nodeVersion,
    required this.platform,
  });

  final int rss;
  final int heapUsed;
  final int heapTotal;
  final int external;

  /// Single-core utilisation since previous poll (0–100+). Null on the first
  /// poll after server start (no prior sample to diff against).
  final double? cpuPercent;
  final int queuedTasks;
  final int activeAgents;
  final String nodeVersion;
  final String platform;

  factory ServerMetrics.fromJson(Map<String, dynamic> j) {
    final mem = (j['memory'] as Map<String, dynamic>?) ?? const {};
    return ServerMetrics(
      rss: (mem['rss'] as num?)?.toInt() ?? 0,
      heapUsed: (mem['heapUsed'] as num?)?.toInt() ?? 0,
      heapTotal: (mem['heapTotal'] as num?)?.toInt() ?? 0,
      external: (mem['external'] as num?)?.toInt() ?? 0,
      cpuPercent: (j['cpuPercent'] as num?)?.toDouble(),
      queuedTasks: (j['queuedTasks'] as num?)?.toInt() ?? 0,
      activeAgents: (j['activeAgents'] as num?)?.toInt() ?? 0,
      nodeVersion: j['nodeVersion'] as String? ?? '',
      platform: j['platform'] as String? ?? '',
    );
  }
}

class ConfigSnapshot {
  ConfigSnapshot({
    required this.file,
    required this.effective,
    required this.configPath,
    required this.envOverrides,
    required this.flagOverrides,
  });

  /// Persisted values (the source of truth for the form fields).
  final ServerConfig file;

  /// What the running process is actually using right now.
  final ServerConfig effective;
  final String configPath;
  final List<String> envOverrides;
  final List<String> flagOverrides;

  factory ConfigSnapshot.fromJson(Map<String, dynamic> j) => ConfigSnapshot(
        file: ServerConfig.fromJson(j['file'] as Map<String, dynamic>),
        effective: ServerConfig.fromJson(j['effective'] as Map<String, dynamic>),
        configPath: j['configPath'] as String,
        envOverrides: (j['envOverrides'] as List<dynamic>).cast<String>(),
        flagOverrides: (j['flagOverrides'] as List<dynamic>).cast<String>(),
      );
}

class ConfigSaveResult {
  ConfigSaveResult({
    required this.file,
    required this.restartRequired,
    this.note,
  });

  final ServerConfig file;
  final bool restartRequired;
  final String? note;

  factory ConfigSaveResult.fromJson(Map<String, dynamic> j) => ConfigSaveResult(
        file: ServerConfig.fromJson(j['file'] as Map<String, dynamic>),
        restartRequired: j['restartRequired'] as bool? ?? false,
        note: j['note'] as String?,
      );
}

class ConnectedClientInfo {
  ConnectedClientInfo({
    required this.clientId,
    required this.deviceName,
    required this.platform,
    required this.connectedAt,
    required this.isLocal,
  });

  final String clientId;
  final String deviceName;
  final String platform;
  final DateTime connectedAt;
  final bool isLocal;

  factory ConnectedClientInfo.fromJson(Map<String, dynamic> j) => ConnectedClientInfo(
        clientId: j['clientId'] as String? ?? '',
        deviceName: j['deviceName'] as String? ?? '',
        platform: j['platform'] as String? ?? 'unknown',
        connectedAt: DateTime.tryParse(j['connectedAt'] as String? ?? '') ?? DateTime.now(),
        isLocal: j['isLocal'] as bool? ?? false,
      );
}

class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
  });

  final DateTime timestamp;
  final String level;
  final String category;
  final String message;

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        timestamp: DateTime.parse(j['timestamp'] as String),
        level: j['level'] as String,
        category: j['category'] as String,
        message: j['message'] as String,
      );
}

// ─── Launcher API ──────────────────────────────────────────────────────────

/// Talks to the always-on launcher daemon at `/launcher/*`.
///
/// The launcher is what makes this admin app a "bootloader" — it stays
/// reachable even when the main server is offline, so the app can spawn,
/// kill, and restart server.ts on demand.
class LauncherClient {
  LauncherClient(this.baseUrl);

  /// Base URL like `http://localhost:9719`. No trailing slash.
  final String baseUrl;

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<LauncherStatus> status() async {
    final res = await http.get(_u('/launcher/status')).timeout(const Duration(seconds: 4));
    _ensureOk(res);
    return LauncherStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<LauncherActionResult> start() => _action('start');
  Future<LauncherActionResult> stop() => _action('stop');
  Future<LauncherActionResult> restart() => _action('restart');

  Future<LauncherActionResult> _action(String name) async {
    final res = await http.post(_u('/launcher/$name')).timeout(const Duration(seconds: 30));
    _ensureOk(res);
    return LauncherActionResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<BootLogEntry>> bootLogs({int limit = 200}) async {
    final res = await http
        .get(_u('/launcher/logs', {'n': '$limit'}))
        .timeout(const Duration(seconds: 4));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['entries'] as List<dynamic>)
        .map((e) => BootLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String detail = res.body;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['error'] is String) detail = body['error'] as String;
    } catch (_) {}
    throw AdminException('HTTP ${res.statusCode}: $detail');
  }

  /// Convenience: derive the matching admin (server) base URL from this
  /// launcher's host plus a known server port. Same scheme + host, swap port.
  String adminBaseUrl(int serverPort) {
    final uri = Uri.parse(baseUrl);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: serverPort,
    ).toString();
  }
}

/// Phases the launcher reports for itself.
///   idle      — child not running and not transitioning.
///   starting  — child spawned, readiness probe in flight.
///   running   — child healthy.
///   stopping  — SIGTERM sent, waiting for exit.
///   crashed   — child exited with non-zero (and not 75); needs explicit start.
enum LauncherPhase { idle, starting, running, stopping, crashed }

class LauncherStatus {
  LauncherStatus({
    required this.phase,
    required this.launcherPid,
    required this.launcherPort,
    required this.serverRunning,
    required this.serverPort,
    this.serverPid,
    this.serverStartedAt,
    this.serverExitedAt,
    this.lastExitCode,
    this.lastSignal,
    required this.bootLogCount,
  });

  final LauncherPhase phase;
  final int launcherPid;
  final int launcherPort;
  final bool serverRunning;
  final int serverPort;
  final int? serverPid;
  final DateTime? serverStartedAt;
  final DateTime? serverExitedAt;
  final int? lastExitCode;
  final String? lastSignal;
  final int bootLogCount;

  factory LauncherStatus.fromJson(Map<String, dynamic> j) {
    final l = j['launcher'] as Map<String, dynamic>;
    final s = j['server'] as Map<String, dynamic>;
    return LauncherStatus(
      phase: _parsePhase(l['phase'] as String?),
      launcherPid: (l['pid'] as num).toInt(),
      launcherPort: (l['port'] as num).toInt(),
      serverRunning: s['running'] as bool,
      serverPort: (s['port'] as num).toInt(),
      serverPid: (s['pid'] as num?)?.toInt(),
      serverStartedAt: s['startedAt'] is String ? DateTime.parse(s['startedAt'] as String) : null,
      serverExitedAt: s['exitedAt'] is String ? DateTime.parse(s['exitedAt'] as String) : null,
      lastExitCode: (s['lastExitCode'] as num?)?.toInt(),
      lastSignal: s['lastSignal'] as String?,
      bootLogCount: (s['bootLogCount'] as num).toInt(),
    );
  }

  static LauncherPhase _parsePhase(String? raw) {
    switch (raw) {
      case 'starting': return LauncherPhase.starting;
      case 'running': return LauncherPhase.running;
      case 'stopping': return LauncherPhase.stopping;
      case 'crashed': return LauncherPhase.crashed;
      default: return LauncherPhase.idle;
    }
  }
}

class LauncherActionResult {
  LauncherActionResult({
    required this.ok,
    this.alreadyRunning,
    this.ready,
    this.pid,
    this.note,
    this.error,
  });

  final bool ok;
  final bool? alreadyRunning;
  final bool? ready;
  final int? pid;
  final String? note;
  final String? error;

  factory LauncherActionResult.fromJson(Map<String, dynamic> j) => LauncherActionResult(
        ok: j['ok'] as bool? ?? false,
        alreadyRunning: j['alreadyRunning'] as bool?,
        ready: j['ready'] as bool?,
        pid: (j['pid'] as num?)?.toInt(),
        note: j['note'] as String?,
        error: j['error'] as String?,
      );
}

class BootLogEntry {
  BootLogEntry({required this.timestamp, required this.stream, required this.line});
  final DateTime timestamp;
  final String stream; // 'stdout' | 'stderr'
  final String line;

  factory BootLogEntry.fromJson(Map<String, dynamic> j) => BootLogEntry(
        timestamp: DateTime.parse(j['ts'] as String),
        stream: j['stream'] as String,
        line: j['line'] as String,
      );
}
