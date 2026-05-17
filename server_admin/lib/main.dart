import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_client.dart';
import 'theme.dart';
import 'services/setup_service.dart';
import 'services/server_control_service.dart';
import 'pages/dashboard_page.dart';
import 'pages/setup_page.dart';
import 'pages/config_page.dart';
import 'pages/logs_page.dart';
import 'pages/clients_page.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SetupService()),
        ChangeNotifierProvider(create: (_) => ServerControlService()),
      ],
      child: const PixelDockApp(),
    ),
  );
}

class PixelDockApp extends StatelessWidget {
  const PixelDockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelDock',
      debugShowCheckedModeBanner: false,
      theme: buildPixelTheme(),
      home: const MainScreen(),
    );
  }
}

// ─── Main screen ─────────────────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
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
  List<ConnectedClientInfo> _clients = const [];
  String? _launcherError;
  bool _ready = false;
  String? _inFlightAction; // 'start' | 'stop' | 'restart' | null
  int _selectedIndex = 0;

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
      _clients = const [];
      _launcherError = null;
    });
    _persistBaseUrl(url);
    _pollOnce();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollOnce();
    _pollTimer =
        Timer.periodic(const Duration(milliseconds: 2500), (_) => _pollOnce());
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
    final admin = (_admin == null || _admin!.baseUrl != adminUrl)
        ? AdminClient(adminUrl)
        : _admin!;

    setState(() {
      _launcherStatus = lstatus;
      _admin = admin;
      _launcherError = null;
    });

    if (lstatus.serverRunning) {
      try {
        final results = await Future.wait([
          admin.status(),
          admin.logs(limit: 200),
          admin.clients(),
        ]);
        if (!mounted || launcher != _launcher) return;
        setState(() {
          _serverStatus = results[0] as ServerStatus;
          _serverLogs = results[1] as List<LogEntry>;
          _clients = results[2] as List<ConnectedClientInfo>;
        });
        if (_config == null) await _refreshConfig();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _serverStatus = null;
          _clients = const [];
        });
      }
    } else {
      try {
        final logs = await launcher.bootLogs(limit: 200);
        if (!mounted || launcher != _launcher) return;
        setState(() {
          _serverStatus = null;
          _bootLogs = logs;
          _serverLogs = const [];
          _clients = const [];
        });
      } catch (_) {}
    }
  }

  Future<void> _refreshConfig() async {
    final admin = _admin;
    if (admin == null) return;
    try {
      final cfg = await admin.getConfig();
      if (!mounted) return;
      setState(() => _config = cfg);
    } catch (_) {}
  }

  Future<void> _saveConfig({
    required bool thenRestart,
    required Map<String, dynamic> patch,
  }) async {
    final admin = _admin;
    if (admin == null) {
      _toast('Server is offline — start it first to edit config',
          isError: true);
      return;
    }
    try {
      final result = await admin.saveConfig(patch);
      if (!mounted) return;
      _toast(thenRestart
          ? 'Saved — restarting…'
          : (result.restartRequired ? 'Saved (restart required)' : 'Saved'));
      await _refreshConfig();
      if (thenRestart) { await _launcher.restart(); }
    } catch (e) {
      _toast('Save failed: $e', isError: true);
    }
  }

  Future<void> _start() => _runAction(
        action: 'start',
        label: 'Start',
        fn: _launcher.start,
        expectsRunning: true,
      );

  Future<void> _stop() async {
    if (!await _confirm('Stop server?',
        'The server process will exit; the launcher stays alive.')) { return; }
    await _runAction(
      action: 'stop',
      label: 'Stop',
      fn: _launcher.stop,
      expectsRunning: false,
    );
  }

  Future<void> _restart() async {
    if (!await _confirm('Restart server?',
        'Server will be killed and respawned. Launcher stays alive throughout.')) {
      return;
    }
    await _runAction(
      action: 'restart',
      label: 'Restart',
      fn: _launcher.restart,
      expectsRunning: true,
    );
  }

  Future<void> _runAction({
    required String action,
    required String label,
    required Future<LauncherActionResult> Function() fn,
    required bool expectsRunning,
  }) async {
    if (_inFlightAction != null) return;
    setState(() => _inFlightAction = action);
    try {
      final result = await fn();
      if (!mounted) return;

      if (!result.ok) {
        _toast('$label failed: ${result.error ?? "unknown"}', isError: true);
        await _pollOnce();
        return;
      }

      await _pollOnce();
      if (!mounted) return;

      // Server spawned but readiness probe is still pending — keep the
      // button in its in-flight state and watch for liveness up to 30s.
      // If liveness still doesn't arrive, surface a developer-friendly
      // hint pulled from the launcher's boot log.
      if (expectsRunning && result.ready == false) {
        final live = await _waitForServerRunning(
          timeout: const Duration(seconds: 30),
        );
        if (!mounted) return;
        if (!live) {
          final hint = await _lastBootError();
          _toast(
            'Server failed to come up within 30s — open LOGS tab'
            '${hint != null ? '\n$hint' : ''}',
            isError: true,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _toast('$label failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _inFlightAction = null);
    }
  }

  Future<bool> _waitForServerRunning({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      await _pollOnce();
      if (!mounted) return false;
      if (_launcherStatus?.serverRunning == true) return true;
    }
    return false;
  }

  Future<String?> _lastBootError() async {
    try {
      final logs = await _launcher.bootLogs(limit: 60);
      // Flatten stderr lines in arrival order, drop empties.
      final stderr = <String>[];
      for (final entry in logs) {
        if (entry.stream != 'stderr') continue;
        for (final raw in entry.line.split('\n')) {
          final l = raw.trim();
          if (l.isNotEmpty) stderr.add(l);
        }
      }
      if (stderr.isEmpty) return null;

      // Prefer the first line that looks like an exception summary
      // ("Error: ...", "TypeError: ...", "SyntaxError: ..."). The very last
      // stderr line is usually a Node version footer ("Node.js v24.7.0"),
      // which is useless on its own.
      final exceptionRe =
          RegExp(r'^[A-Z][a-zA-Z]*(Error|Exception): ');
      String pick = stderr.firstWhere(
        exceptionRe.hasMatch,
        orElse: () => stderr.lastWhere(
          (l) => !RegExp(r'^Node\.js v').hasMatch(l),
          orElse: () => stderr.last,
        ),
      );
      if (pick.length > 200) pick = '${pick.substring(0, 200)}…';
      return pick;
    } catch (_) {}
    return null;
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
        title: Text(title,
            style: pixelFont(size: 11, color: PixelPalette.accent)),
        content:
            Text(body, style: const TextStyle(color: PixelPalette.textHigh)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: pixelFont(size: 9, color: PixelPalette.textMed)),
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
        backgroundColor: isError
            ? PixelPalette.error.withValues(alpha: 0.85)
            : PixelPalette.surfaceHi,
        showCloseIcon: true,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: _PixelAppBar(
        controller: _urlController,
        onSubmit: _applyUrl,
        launcherStatus: _launcherStatus,
        launcherError: _launcherError,
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) =>
                setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: PixelPalette.surfaceDim,
            indicatorColor: PixelPalette.surfaceHi,
            selectedIconTheme:
                const IconThemeData(color: PixelPalette.ice),
            unselectedIconTheme:
                const IconThemeData(color: PixelPalette.textMed),
            selectedLabelTextStyle:
                pixelFont(size: 7, color: PixelPalette.ice),
            unselectedLabelTextStyle:
                pixelFont(size: 7, color: PixelPalette.textMed),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.speed_outlined),
                selectedIcon: Icon(Icons.speed),
                label: Text('DASH'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.build_circle_outlined),
                selectedIcon: Icon(Icons.build_circle),
                label: Text('SETUP'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('CONFIG'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.terminal),
                label: Text('LOGS'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.devices_outlined),
                selectedIcon: Icon(Icons.devices),
                label: Text('CLIENTS'),
              ),
            ],
          ),
          const VerticalDivider(
              thickness: 1, width: 1, color: PixelPalette.divider),
          Expanded(child: _buildPage()),
        ],
      ),
    );
  }

  Widget _buildPage() => switch (_selectedIndex) {
        0 => DashboardPage(
            launcher: _launcherStatus,
            launcherError: _launcherError,
            server: _serverStatus,
            inFlightAction: _inFlightAction,
            onStart: _start,
            onStop: _stop,
            onRestart: _restart,
            onRefresh: _pollOnce,
          ),
        1 => const SetupPage(),
        2 => ConfigPage(
            snapshot: _config,
            serverRunning: _launcherStatus?.serverRunning ?? false,
            onSave: (p) => _saveConfig(thenRestart: false, patch: p),
            onSaveAndRestart: (p) =>
                _saveConfig(thenRestart: true, patch: p),
            onReload: _refreshConfig,
          ),
        3 => LogsPage(
            serverLogs: _serverLogs,
            bootLogs: _bootLogs,
            showingBoot: !(_launcherStatus?.serverRunning ?? false),
          ),
        4 => ClientsPage(
            clients: _clients,
            serverRunning: _launcherStatus?.serverRunning ?? false,
          ),
        _ => const SizedBox.shrink(),
      };
}

// ─── App bar ──────────────────────────────────────────────────────────────────

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

  // VS Code-style extended titlebar: Flutter draws under the system title bar
  // (enabled by fullSizeContentView in MainFlutterWindow.swift). The duck logo
  // sits in the same left column as the traffic-light buttons (below them),
  // and the PIXELDOCK title spans the full vertical extent — buttons + gap +
  // logo height — to the right of that column.
  static const double _topInsetMac = 28;
  static const double _topInsetDefault = 12;
  static const double _logoSize = 56;
  static const double _gapBelowButtons = 6;
  static const double _bottomPad = 8;
  static const double _titleTopPad = 14;

  double get _topInset => Platform.isMacOS ? _topInsetMac : _topInsetDefault;
  double get _totalHeight =>
      _topInset + _gapBelowButtons + _logoSize + _bottomPad;

  @override
  Size get preferredSize => Size.fromHeight(_totalHeight);

  @override
  Widget build(BuildContext context) {
    final launcherUp = launcherStatus != null;
    final serverUp = launcherStatus?.serverRunning ?? false;

    final Color dotColor;
    final String tag;
    if (!launcherUp) {
      dotColor = launcherError != null
          ? PixelPalette.error
          : PixelPalette.textLow;
      tag = launcherError != null ? 'launcher offline' : 'connecting…';
    } else if (serverUp) {
      dotColor = PixelPalette.success;
      tag = 'server :${launcherStatus!.serverPort}';
    } else {
      dotColor = PixelPalette.gold;
      tag =
          'launcher :${launcherStatus!.launcherPort}  •  server idle';
    }

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      toolbarHeight: _totalHeight,
      backgroundColor: PixelPalette.background,
      flexibleSpace: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 16, _bottomPad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: _logoSize,
                  height: _logoSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PixelPalette.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset('assets/logo.png',
                      filterQuality: FilterQuality.none),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: _titleTopPad),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('PIXEL',
                            style: pixelFont(
                                size: 34,
                                color: PixelPalette.accent,
                                letterSpacing: 2.5)),
                        const SizedBox(width: 6),
                        Text('DOCK',
                            style: pixelFont(
                                size: 34,
                                color: PixelPalette.gold,
                                letterSpacing: 2.5)),
                      ],
                    ),
                    const SizedBox(height: 4),
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
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 320,
                child: TextField(
                  controller: controller,
                  onSubmitted: onSubmit,
                  style: const TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      color: PixelPalette.textHigh),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: PixelPalette.surfaceDim,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: PixelPalette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          const BorderSide(color: PixelPalette.accent),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6)),
                    hintText: 'launcher URL',
                    hintStyle: const TextStyle(
                        color: PixelPalette.textLow, fontFamily: 'Menlo'),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward,
                          size: 16, color: PixelPalette.accent),
                      tooltip: 'Connect',
                      onPressed: () => onSubmit(controller.text),
                    ),
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
