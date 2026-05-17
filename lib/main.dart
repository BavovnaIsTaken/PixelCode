import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/agent_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/hub/hub_screen.dart';
import 'services/agent_ws_service.dart';
import 'services/localization_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localization.initialize();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    RestartWidget(
      child: ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const PixelCodeApp(),
      ),
    ),
  );
}

class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restart(BuildContext context) =>
      context.findAncestorStateOfType<RestartWidgetState>()?.restart();

  @override
  State<RestartWidget> createState() => RestartWidgetState();
}

class RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

class PixelCodeApp extends ConsumerStatefulWidget {
  const PixelCodeApp({super.key});

  @override
  ConsumerState<PixelCodeApp> createState() => _PixelCodeAppState();
}

class _PixelCodeAppState extends ConsumerState<PixelCodeApp> {
  late final AppLifecycleListener _lifecycleListener;
  late final AgentWsService _wsService;
  String _activeWsUrl = 'ws://localhost:9720';

  @override
  void initState() {
    super.initState();
    _wsService = ref.read(wsServiceProvider);
    // Eagerly subscribe before connect() so broadcast stream logs aren't lost
    // when the console panel is closed (provider would otherwise be lazy-init'd).
    ref.read(debugLogProvider);
    _lifecycleListener = AppLifecycleListener(
      onHide: _onAppBackground,
      onResume: _onAppForeground,
      onExitRequested: () async {
        await _wsService.dispose();
        return AppExitResponse.exit;
      },
    );
    _initSession();
  }

  // Called when the app goes to background (iOS suspend / Android kill).
  // Sends a clean WebSocket close frame so the server knows the client left.
  void _onAppBackground() => _wsService.disconnect();

  // Called when the app returns to foreground.
  // Forces a fresh connection so stale/frozen sockets are replaced immediately.
  void _onAppForeground() => _wsService.reconnect(url: _activeWsUrl);

  Future<void> _initSession() async {
    try {
      await ref.read(settingsProvider.notifier).incrementLaunchCount();
      final session = ref.read(sessionProvider.notifier);
      await session.migrateFromLegacy();

      if (!Platform.isIOS && !Platform.isAndroid) {
        // Make sure desktop has a default profile pointing at the local
        // launcher-managed server. Spawning the server itself is now the
        // launcher daemon's job (see server/src/launcher.ts) — this app is
        // a pure WebSocket client.
        await session.ensureDefaultDesktopProfile();
      }

      // Connect WebSocket to the active session, or fallback to local server.
      final profile = ref.read(sessionProvider).activeProfile;
      _activeWsUrl = profile?.wsUrl ?? 'ws://localhost:9720';
      await ref.read(wsServiceProvider).connect(url: _activeWsUrl);
    } catch (e) {
      debugPrint('[PixelCode] Init session failed: $e');
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _wsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(appThemeDataProvider);
    final colors = ref.watch(activeThemeColorsProvider);

    if (Platform.isAndroid) {
      final isDark =
          ThemeData.estimateBrightnessForColor(colors.background) ==
              Brightness.dark;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        systemNavigationBarColor: colors.background,
        systemNavigationBarContrastEnforced: false,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ));
    }

    return MaterialApp(
      title: 'ПіксельКод',
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: const HubScreen(),
    );
  }
}
