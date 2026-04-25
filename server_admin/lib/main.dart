import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_client.dart';
import 'theme.dart';

void main() {
  runApp(const ServerAdminApp());
}

class ServerAdminApp extends StatelessWidget {
  const ServerAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelDock',
      debugShowCheckedModeBanner: false,
      theme: buildPixelTheme(),
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
  AdminClient? _admin;

  LauncherStatus? _launcherStatus;
  ServerStatus? _serverStatus;
  ConfigSnapshot? _config;
  List<LogEntry> _serverLogs = const [];
  List<BootLogEntry> _bootLogs = const [];
  String? _launcherError;
  bool _ready = false;
  bool _busy = false;

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

    final adminUrl = launcher.adminBaseUrl(lstatus.serverPort);
    final admin = (_admin == null || _admin!.baseUrl != adminUrl) ? AdminClient(adminUrl) : _admin!;

    setState(() {
      _launcherStatus = lstatus;
      _admin = admin;
      _launcherError = null;
    });

    if (lstatus.serverRunning) {
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
      try {
        final logs = await launcher.bootLogs(limit: 200);
        if (!mounted || launcher != _launcher) return;
        setState(() {
          _serverStatus = null;
          _bootLogs = logs;
          _serverLogs = const [];
        });
      } catch (_) {/* ignore */}
    }
  }

  Future<void> _refreshConfig() async {
    final admin = _admin;
    if (admin == null) return;
    try {
      final cfg = await admin.getConfig();
      if (!mounted) return;
      setState(() => _config = cfg);
    } catch (_) {/* ignore */}
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
        backgroundColor: PixelPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: PixelPalette.border),
        ),
        title: Text(title, style: pixelFont(size: 11, color: PixelPalette.accent)),
        content: Text(body, style: const TextStyle(color: PixelPalette.textHigh)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: pixelFont(size: 9, color: PixelPalette.textMed)),
          ),
          FilledButton(
            style: pixelFilledStyle(color: PixelPalette.accent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? PixelPalette.error.withValues(alpha: 0.85) : PixelPalette.surfaceHi,
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
      appBar: _PixelAppBar(
        controller: _urlController,
        onSubmit: _applyUrl,
        launcherStatus: _launcherStatus,
        launcherError: _launcherError,
      ),
      body: RefreshIndicator(
        color: PixelPalette.accent,
        backgroundColor: PixelPalette.surface,
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
            const SizedBox(height: 14),
            _ConfigCard(
              snapshot: _config,
              serverRunning: _launcherStatus?.serverRunning ?? false,
              onSave: (patch) => _saveConfig(thenRestart: false, patch: patch),
              onSaveAndRestart: (patch) => _saveConfig(thenRestart: true, patch: patch),
              onReload: _refreshConfig,
            ),
            const SizedBox(height: 14),
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

// ─── App-bar ────────────────────────────────────────────────────────────────

class _PixelAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PixelAppBar({
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
  Size get preferredSize => const Size.fromHeight(86);

  @override
  Widget build(BuildContext context) {
    final launcherUp = launcherStatus != null;
    final serverUp = launcherStatus?.serverRunning ?? false;

    Color dotColor;
    String tag;
    if (!launcherUp) {
      dotColor = launcherError != null ? PixelPalette.error : PixelPalette.textLow;
      tag = launcherError != null ? 'launcher offline' : 'connecting…';
    } else if (serverUp) {
      dotColor = PixelPalette.success;
      tag = 'server :${launcherStatus!.serverPort}';
    } else {
      dotColor = PixelPalette.gold;
      tag = 'launcher :${launcherStatus!.launcherPort}  •  server idle';
    }

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      toolbarHeight: 86,
      backgroundColor: PixelPalette.background,
      flexibleSpace: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Pixel-art logo (the same icon used for the .app bundle).
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: PixelPalette.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/logo.png',
                  filterQuality: FilterQuality.none, // keep pixels crisp
                ),
              ),
              const SizedBox(width: 14),
              // Wordmark + status tag.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text('PIXEL', style: pixelFont(size: 14, color: PixelPalette.accent, letterSpacing: 1.5)),
                      const SizedBox(width: 4),
                      Text('DOCK', style: pixelFont(size: 14, color: PixelPalette.gold, letterSpacing: 1.5)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      GlowDot(color: dotColor, size: 8),
                      const SizedBox(width: 8),
                      Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 12,
                          color: PixelPalette.textMed,
                          fontFamily: 'Menlo',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              // Launcher URL field (compact).
              SizedBox(
                width: 320,
                child: TextField(
                  controller: controller,
                  onSubmitted: onSubmit,
                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, color: PixelPalette.textHigh),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: PixelPalette.surfaceDim,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: PixelPalette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: PixelPalette.accent),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    hintText: 'launcher URL',
                    hintStyle: const TextStyle(color: PixelPalette.textLow, fontFamily: 'Menlo'),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 16, color: PixelPalette.accent),
                      tooltip: 'Connect',
                      onPressed: () => onSubmit(controller.text),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
    return PixelCard(
      title: 'Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (launcher == null && launcherError != null)
            _ErrorBlock(error: launcherError!)
          else if (launcher == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Connecting to launcher…', style: TextStyle(color: PixelPalette.textMed)),
            )
          else ...[
            _ProcRow(
              label: 'LAUNCHER',
              up: true,
              detail: ':${launcher!.launcherPort}  PID ${launcher!.launcherPid}  (${launcher!.phase.name})',
            ),
            const SizedBox(height: 8),
            _ProcRow(
              label: 'SERVER',
              up: launcher!.serverRunning,
              detail: launcher!.serverRunning
                  ? ':${launcher!.serverPort}  PID ${launcher!.serverPid ?? "?"}'
                  : _offlineDetail(launcher!),
            ),
            if (server != null) ...[
              const SizedBox(height: 16),
              const Divider(color: PixelPalette.divider, height: 1),
              const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (launcher != null && !launcher!.serverRunning)
                FilledButton.icon(
                  onPressed: busy ? null : onStart,
                  style: pixelFilledStyle(color: PixelPalette.success),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('START'),
                ),
              if (launcher != null && launcher!.serverRunning) ...[
                OutlinedButton.icon(
                  onPressed: busy ? null : onRestart,
                  style: pixelOutlinedStyle(foreground: PixelPalette.accent),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('RESTART'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onStop,
                  style: pixelOutlinedStyle(foreground: PixelPalette.error),
                  icon: const Icon(Icons.power_settings_new, size: 16),
                  label: const Text('STOP'),
                ),
              ],
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: PixelPalette.accent),
                  ),
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
            width: 150,
            child: Text(label,
                style: pixelFont(size: 8, color: PixelPalette.textMed, letterSpacing: 1.2)),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: PixelPalette.textHigh,
                    fontFamily: mono ? 'Menlo' : null,
                  ),
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

class _ProcRow extends StatelessWidget {
  const _ProcRow({required this.label, required this.up, required this.detail});
  final String label;
  final bool up;
  final String detail;
  @override
  Widget build(BuildContext context) {
    final color = up ? PixelPalette.success : PixelPalette.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: PixelPalette.surfaceDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PixelPalette.border),
      ),
      child: Row(
        children: [
          GlowDot(color: color, size: 9),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text(label, style: pixelFont(size: 9, color: color, letterSpacing: 1.4)),
          ),
          Expanded(
            child: SelectableText(
              detail,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, color: PixelPalette.textMed),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final String source;
  @override
  Widget build(BuildContext context) {
    final color = source == 'env' ? PixelPalette.warn : PixelPalette.accent;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(source.toUpperCase(),
          style: pixelFont(size: 7, color: color, letterSpacing: 1.2)),
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
    return PixelCard(
      title: 'Configuration',
      titleColor: PixelPalette.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.serverRunning)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PixelPalette.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: PixelPalette.gold.withValues(alpha: 0.5)),
              ),
              child: Text(
                'Server is offline — config edits go through /admin/api/config '
                    'which needs the server running. Start it first.',
                style: TextStyle(color: PixelPalette.gold.withValues(alpha: 0.9), fontSize: 12),
              ),
            ),
          _field(label: 'PORT', controller: _portCtrl, hint: '9720', disabled: disabled),
          _field(label: 'PROJECT CWD', controller: _cwdCtrl, hint: '/path/to/project', disabled: disabled),
          _field(label: 'OTA HOSTNAME', controller: _otaCtrl, hint: '(optional, e.g. mac.local)', disabled: disabled),
          const SizedBox(height: 6),
          if (snap != null) ...[
            Text('Config file: ${snap.configPath}',
                style: const TextStyle(color: PixelPalette.textLow, fontSize: 11, fontFamily: 'Menlo')),
            if (snap.envOverrides.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'env overrides: ${snap.envOverrides.join(", ")}',
                  style: const TextStyle(color: PixelPalette.warn, fontSize: 11),
                ),
              ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: disabled ? null : () => _run(widget.onSave),
                style: pixelFilledStyle(color: PixelPalette.accent),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('SAVE'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : () => _run(widget.onSaveAndRestart),
                style: pixelOutlinedStyle(foreground: PixelPalette.accent),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('SAVE & RESTART'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : widget.onReload,
                style: pixelOutlinedStyle(foreground: PixelPalette.textMed),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('RELOAD'),
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
    bool disabled = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: pixelFont(size: 8, color: PixelPalette.textMed, letterSpacing: 1.4)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !disabled,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 13, color: PixelPalette.textHigh),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: PixelPalette.surfaceDim,
                hintText: hint,
                hintStyle: const TextStyle(color: PixelPalette.textLow, fontFamily: 'Menlo'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: PixelPalette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: PixelPalette.accent),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: PixelPalette.border.withValues(alpha: 0.5)),
                ),
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

  Color _levelColor(String level) {
    switch (level) {
      case 'warn': return PixelPalette.warn;
      case 'error': return PixelPalette.error;
      default: return PixelPalette.textHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = showingBoot ? 'Boot logs' : 'Server logs';
    final subtitle = showingBoot ? '(stdout/stderr from launcher)' : '(structured log ring)';
    final isEmpty = showingBoot ? bootLogs.isEmpty : serverLogs.isEmpty;
    return PixelCard(
      title: title,
      titleColor: showingBoot ? PixelPalette.gold : PixelPalette.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(subtitle,
                style: const TextStyle(color: PixelPalette.textLow, fontSize: 11, fontFamily: 'Menlo')),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF08080B),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: PixelPalette.border),
            ),
            constraints: const BoxConstraints(maxHeight: 360, minHeight: 80),
            child: isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      showingBoot ? '(no boot logs yet — try Start)' : '(no log entries yet)',
                      style: const TextStyle(color: PixelPalette.textLow),
                    ),
                  )
                : showingBoot ? _bootList() : _serverList(),
          ),
        ],
      ),
    );
  }

  Widget _serverList() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(10),
      itemCount: serverLogs.length,
      itemBuilder: (context, i) {
        final e = serverLogs[serverLogs.length - 1 - i];
        final ts = e.timestamp.toIso8601String().substring(11, 23);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(text: '$ts ', style: const TextStyle(color: PixelPalette.textLow)),
              TextSpan(text: '[${e.category}] ', style: const TextStyle(color: PixelPalette.accent)),
              TextSpan(text: e.message, style: TextStyle(color: _levelColor(e.level))),
            ]),
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.45),
          ),
        );
      },
    );
  }

  Widget _bootList() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(10),
      itemCount: bootLogs.length,
      itemBuilder: (context, i) {
        final e = bootLogs[bootLogs.length - 1 - i];
        final ts = e.timestamp.toIso8601String().substring(11, 23);
        final color = e.stream == 'stderr' ? PixelPalette.warn : PixelPalette.textHigh;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(text: '$ts ', style: const TextStyle(color: PixelPalette.textLow)),
              TextSpan(
                text: '${e.stream.padRight(6)} ',
                style: TextStyle(color: color.withValues(alpha: 0.55)),
              ),
              TextSpan(text: e.line, style: TextStyle(color: color)),
            ]),
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.45),
          ),
        );
      },
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PixelPalette.error.withValues(alpha: 0.1),
        border: Border.all(color: PixelPalette.error),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAUNCHER UNREACHABLE',
              style: pixelFont(size: 10, color: PixelPalette.error, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          SelectableText(error,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, color: PixelPalette.textHigh)),
          const SizedBox(height: 10),
          const Text(
            'Hint: open a terminal and run `pixelcode-server start`. The launcher '
            'stays alive in the background and you drive everything else from here.',
            style: TextStyle(color: PixelPalette.textMed, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
