import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_client.dart';

void main() {
  runApp(const ServerAdminApp());
}

class ServerAdminApp extends StatelessWidget {
  const ServerAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelCode Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B8CFF),
          brightness: Brightness.dark,
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const DashboardScreen(),
    );
  }
}

// ─── Dashboard ──────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _prefsKey = 'launcherBaseUrl';
  static const _defaultLauncherUrl = 'http://127.0.0.1:9719';

  late final TextEditingController _urlController;
  LauncherClient _launcher = LauncherClient(_defaultLauncherUrl);
  AdminClient? _admin; // built dynamically once server.port is known.

  LauncherStatus? _launcherStatus;
  ServerStatus? _serverStatus;
  ConfigSnapshot? _config;
  List<LogEntry> _serverLogs = const [];
  List<BootLogEntry> _bootLogs = const [];
  String? _launcherError;
  bool _ready = false;
  bool _busy = false; // during start/stop/restart

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _defaultLauncherUrl);
    _restorePrefs();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && stored.isNotEmpty) {
      _urlController.text = stored;
      _launcher = LauncherClient(stored);
    }
    setState(() => _ready = true);
    _startPolling();
  }

  Future<void> _persistBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, url);
  }

  void _applyUrl(String raw) {
    final url = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty) return;
    setState(() {
      _launcher = LauncherClient(url);
      _admin = null;
      _launcherStatus = null;
      _serverStatus = null;
      _config = null;
      _serverLogs = const [];
      _bootLogs = const [];
      _launcherError = null;
    });
    _persistBaseUrl(url);
    _pollOnce();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollOnce();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final launcher = _launcher;
    LauncherStatus? lstatus;
    try {
      lstatus = await launcher.status();
    } catch (e) {
      if (!mounted || launcher != _launcher) return;
      setState(() {
        _launcherStatus = null;
        _serverStatus = null;
        _bootLogs = const [];
        _launcherError = e.toString();
      });
      return;
    }
    if (!mounted || launcher != _launcher) return;

    // Build/refresh the admin client whose port matches launcher's report.
    final adminUrl = launcher.adminBaseUrl(lstatus.serverPort);
    final admin = (_admin == null || _admin!.baseUrl != adminUrl) ? AdminClient(adminUrl) : _admin!;

    setState(() {
      _launcherStatus = lstatus;
      _admin = admin;
      _launcherError = null;
    });

    if (lstatus.serverRunning) {
      // Server is up — pull /admin/* details and structured logs.
      try {
        final results = await Future.wait([admin.status(), admin.logs(limit: 200)]);
        if (!mounted || launcher != _launcher) return;
        setState(() {
          _serverStatus = results[0] as ServerStatus;
          _serverLogs = results[1] as List<LogEntry>;
        });
        if (_config == null) await _refreshConfig();
      } catch (_) {
        if (!mounted) return;
        setState(() => _serverStatus = null);
      }
    } else {
      // Server is down — show launcher boot logs instead.
      try {
        final logs = await launcher.bootLogs(limit: 200);
        if (!mounted || launcher != _launcher) return;
        setState(() {
          _serverStatus = null;
          _bootLogs = logs;
          _serverLogs = const [];
        });
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> _refreshConfig() async {
    final admin = _admin;
    if (admin == null) return;
    try {
      final cfg = await admin.getConfig();
      if (!mounted) return;
      setState(() => _config = cfg);
    } catch (_) {
      // server probably went down between polls; ignore
    }
  }

  Future<void> _saveConfig({required bool thenRestart, required Map<String, dynamic> patch}) async {
    final admin = _admin;
    if (admin == null) {
      _toast('Server is offline — start it first to edit config', isError: true);
      return;
    }
    try {
      final result = await admin.saveConfig(patch);
      if (!mounted) return;
      _toast(thenRestart
          ? 'Saved — restarting…'
          : (result.restartRequired ? 'Saved (restart required)' : 'Saved'));
      await _refreshConfig();
      if (thenRestart) await _launcher.restart();
    } catch (e) {
      _toast('Save failed: $e', isError: true);
    }
  }

  Future<void> _start() => _runAction('Start', _launcher.start);
  Future<void> _stop() async {
    if (!await _confirm('Stop server?', 'The server process will exit; the launcher stays alive.')) return;
    await _runAction('Stop', _launcher.stop);
  }
  Future<void> _restart() async {
    if (!await _confirm('Restart server?', 'Server will be killed and respawned. Launcher stays alive throughout.')) return;
    await _runAction('Restart', _launcher.restart);
  }

  Future<void> _runAction(String label, Future<LauncherActionResult> Function() fn) async {
    setState(() => _busy = true);
    try {
      final result = await fn();
      if (!mounted) return;
      if (result.ok) {
        final note = result.note ?? (result.alreadyRunning == true ? 'already running' : '$label OK');
        _toast('$label: $note');
      } else {
        _toast('$label failed: ${result.error ?? "unknown"}', isError: true);
      }
      await _pollOnce();
    } catch (e) {
      _toast('$label failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHigh,
        showCloseIcon: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: _ConnectionBar(
        controller: _urlController,
        onSubmit: _applyUrl,
        launcherStatus: _launcherStatus,
        launcherError: _launcherError,
      ),
      body: RefreshIndicator(
        onRefresh: () async { await _pollOnce(); },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(
              launcher: _launcherStatus,
              launcherError: _launcherError,
              server: _serverStatus,
              busy: _busy,
              onStart: _start,
              onStop: _stop,
              onRestart: _restart,
            ),
            const SizedBox(height: 16),
            _ConfigCard(
              snapshot: _config,
              serverRunning: _launcherStatus?.serverRunning ?? false,
              onSave: (patch) => _saveConfig(thenRestart: false, patch: patch),
              onSaveAndRestart: (patch) => _saveConfig(thenRestart: true, patch: patch),
              onReload: _refreshConfig,
            ),
            const SizedBox(height: 16),
            _LogsCard(
              serverLogs: _serverLogs,
              bootLogs: _bootLogs,
              showingBoot: !(_launcherStatus?.serverRunning ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App-bar with launcher URL field ────────────────────────────────────────

class _ConnectionBar extends StatelessWidget implements PreferredSizeWidget {
  const _ConnectionBar({
    required this.controller,
    required this.onSubmit,
    required this.launcherStatus,
    required this.launcherError,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final LauncherStatus? launcherStatus;
  final String? launcherError;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final launcherUp = launcherStatus != null;
    final serverUp = launcherStatus?.serverRunning ?? false;

    Color dotColor;
    if (!launcherUp) {
      dotColor = launcherError != null ? scheme.error : scheme.outline;
    } else if (serverUp) {
      dotColor = Colors.green.shade400;
    } else {
      dotColor = Colors.amber.shade400; // launcher up, server down
    }

    return AppBar(
      titleSpacing: 16,
      toolbarHeight: 72,
      backgroundColor: scheme.surface,
      title: Row(
        children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          const Text('PixelCode Server', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmit,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'http://localhost:9719  (launcher URL)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  tooltip: 'Connect',
                  onPressed: () => onSubmit(controller.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status card ────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.launcher,
    required this.launcherError,
    required this.server,
    required this.busy,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  final LauncherStatus? launcher;
  final String? launcherError;
  final ServerStatus? server;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      title: 'Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (launcher == null && launcherError != null)
            _ErrorBlock(error: launcherError!)
          else if (launcher == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Connecting to launcher…'))
          else ...[
            _StateRow(
              label: 'Launcher',
              up: true,
              detail: ':${launcher!.launcherPort}  PID ${launcher!.launcherPid}  (phase: ${launcher!.phase.name})',
            ),
            const SizedBox(height: 4),
            _StateRow(
              label: 'Server',
              up: launcher!.serverRunning,
              detail: launcher!.serverRunning
                  ? ':${launcher!.serverPort}  PID ${launcher!.serverPid ?? "?"}'
                  : _offlineDetail(launcher!),
            ),
            const SizedBox(height: 12),
            if (server != null) ...[
              _kv('Working dir', server!.config.projectCwd, source: server!.sourceOf('projectCwd'), mono: true),
              _kv('OTA hostname', server!.config.otaHostname ?? '(auto)', source: server!.sourceOf('otaHostname')),
              _kv('Connected clients', '${server!.clients}'),
              _kv('mDNS', server!.mdnsActive ? 'active' : 'inactive'),
              _kv('Tailscale', server!.tailscaleUrl ?? '—', mono: true),
              _kv('Uptime', _fmtUptime(server!.uptimeMs)),
              _kv('Booted', server!.bootedAt.toLocal().toString()),
              _kv('Config file', server!.configPath, mono: true),
            ],
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (launcher != null && !launcher!.serverRunning)
                FilledButton.icon(
                  onPressed: busy ? null : onStart,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start'),
                ),
              if (launcher != null && launcher!.serverRunning) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : onRestart,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Restart'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onStop,
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                ),
              ],
              if (busy) const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _offlineDetail(LauncherStatus l) {
    if (l.lastExitCode != null) {
      final sig = l.lastSignal != null ? ' signal=${l.lastSignal}' : '';
      return 'offline — last exit ${l.lastExitCode}$sig';
    }
    return 'offline — never started this session';
  }

  static Widget _kv(String label, String value, {String? source, bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  value,
                  style: TextStyle(fontSize: 13, fontFamily: mono ? 'Menlo' : null),
                ),
                if (source != null && source != 'file') _SourceBadge(source: source),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtUptime(int ms) {
    final s = ms ~/ 1000;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ${s % 60}s';
    final h = m ~/ 60;
    if (h < 24) return '${h}h ${m % 60}m';
    return '${h ~/ 24}d ${h % 24}h';
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.up, required this.detail});
  final String label;
  final bool up;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final color = up ? Colors.green.shade400 : Colors.amber.shade400;
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Expanded(
          child: SelectableText(
            detail,
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final String source;
  @override
  Widget build(BuildContext context) {
    final color = source == 'env' ? Colors.orange : Colors.lightBlue;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
      child: Text(source, style: TextStyle(fontSize: 11, color: color, fontFamily: 'Menlo')),
    );
  }
}

// ─── Config card ────────────────────────────────────────────────────────────

class _ConfigCard extends StatefulWidget {
  const _ConfigCard({
    required this.snapshot,
    required this.serverRunning,
    required this.onSave,
    required this.onSaveAndRestart,
    required this.onReload,
  });

  final ConfigSnapshot? snapshot;
  final bool serverRunning;
  final Future<void> Function(Map<String, dynamic> patch) onSave;
  final Future<void> Function(Map<String, dynamic> patch) onSaveAndRestart;
  final VoidCallback onReload;

  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
  final _portCtrl = TextEditingController();
  final _cwdCtrl = TextEditingController();
  final _otaCtrl = TextEditingController();
  ConfigSnapshot? _shown;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _ConfigCard old) {
    super.didUpdateWidget(old);
    final snap = widget.snapshot;
    if (snap != null && snap != _shown) {
      _shown = snap;
      _portCtrl.text = '${snap.file.port}';
      _cwdCtrl.text = snap.file.projectCwd;
      _otaCtrl.text = snap.file.otaHostname ?? '';
    }
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _cwdCtrl.dispose();
    _otaCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _collectPatch() {
    final port = int.tryParse(_portCtrl.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Port must be a number in 1..65535')),
      );
      return null;
    }
    final cwd = _cwdCtrl.text.trim();
    if (cwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project cwd cannot be empty')),
      );
      return null;
    }
    final ota = _otaCtrl.text.trim();
    return {'port': port, 'projectCwd': cwd, 'otaHostname': ota.isEmpty ? null : ota};
  }

  Future<void> _run(Future<void> Function(Map<String, dynamic>) action) async {
    final patch = _collectPatch();
    if (patch == null) return;
    setState(() => _saving = true);
    try { await action(patch); } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final disabled = _saving || snap == null || !widget.serverRunning;
    return _Card(
      title: 'Configuration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.serverRunning)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Server is offline — config edits go through /admin/api/config, which needs the server running. '
                    'Start it first, then come back.',
                style: TextStyle(color: Colors.amber.shade300, fontSize: 12),
              ),
            ),
          _field(label: 'Port', controller: _portCtrl, hint: '9720', mono: true, disabled: disabled),
          _field(label: 'Project cwd', controller: _cwdCtrl, hint: '/path/to/project', mono: true, disabled: disabled),
          _field(label: 'OTA hostname', controller: _otaCtrl, hint: '(optional, e.g. mac.local)', mono: true, disabled: disabled),
          const SizedBox(height: 4),
          if (snap != null) ...[
            Text('Config file: ${snap.configPath}',
                style: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Menlo')),
            if (snap.envOverrides.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'env overrides active for: ${snap.envOverrides.join(", ")}',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: disabled ? null : () => _run(widget.onSave),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : () => _run(widget.onSaveAndRestart),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Save & Restart'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : widget.onReload,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Reload from disk'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool mono = false,
    bool disabled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !disabled,
              style: TextStyle(fontFamily: mono ? 'Menlo' : null, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Logs card ──────────────────────────────────────────────────────────────

class _LogsCard extends StatelessWidget {
  const _LogsCard({required this.serverLogs, required this.bootLogs, required this.showingBoot});
  final List<LogEntry> serverLogs;
  final List<BootLogEntry> bootLogs;
  final bool showingBoot;

  Color _levelColor(BuildContext context, String level) {
    final scheme = Theme.of(context).colorScheme;
    switch (level) {
      case 'warn': return Colors.orange;
      case 'error': return scheme.error;
      default: return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = showingBoot ? 'Boot logs (server stdout/stderr from launcher)' : 'Server logs';
    final isEmpty = showingBoot ? bootLogs.isEmpty : serverLogs.isEmpty;
    return _Card(
      title: title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  showingBoot ? '(no boot logs yet — try Start)' : '(no log entries yet)',
                  style: const TextStyle(color: Colors.white38),
                ),
              )
            : showingBoot
                ? _bootList(context)
                : _serverList(context),
      ),
    );
  }

  Widget _serverList(BuildContext context) {
    return ListView.builder(
      reverse: true,
      itemCount: serverLogs.length,
      itemBuilder: (context, i) {
        final e = serverLogs[serverLogs.length - 1 - i];
        final ts = e.timestamp.toIso8601String().substring(11, 23);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(text: '$ts ', style: const TextStyle(color: Colors.white38)),
              TextSpan(text: '[${e.category}] ', style: const TextStyle(color: Color(0xFF5B8CFF))),
              TextSpan(text: e.message, style: TextStyle(color: _levelColor(context, e.level))),
            ]),
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.4),
          ),
        );
      },
    );
  }

  Widget _bootList(BuildContext context) {
    return ListView.builder(
      reverse: true,
      itemCount: bootLogs.length,
      itemBuilder: (context, i) {
        final e = bootLogs[bootLogs.length - 1 - i];
        final ts = e.timestamp.toIso8601String().substring(11, 23);
        final color = e.stream == 'stderr' ? Colors.orange : Colors.white70;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(text: '$ts ', style: const TextStyle(color: Colors.white38)),
              TextSpan(text: '${e.stream.padRight(6)} ', style: TextStyle(color: color.withValues(alpha: 0.6))),
              TextSpan(text: e.line, style: TextStyle(color: color)),
            ]),
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.4),
          ),
        );
      },
    );
  }
}

// ─── Shared widgets ────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        border: Border.all(color: scheme.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cannot reach launcher',
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SelectableText(error, style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
          const SizedBox(height: 8),
          const Text(
            'Hint: launch it with `pixelcode-server start`. It will keep running in the '
            'background and you can drive start/stop/restart from this app.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
