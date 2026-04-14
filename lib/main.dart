import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/agent_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/hub/hub_screen.dart';
import 'services/project_persistence_service.dart';
import 'services/server_process_service.dart';

final serverProcess = ServerProcessService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        serverProcessProvider.overrideWithValue(serverProcess),
      ],
      child: const PixelCodeApp(),
    ),
  );
}

class PixelCodeApp extends ConsumerStatefulWidget {
  const PixelCodeApp({super.key});

  @override
  ConsumerState<PixelCodeApp> createState() => _PixelCodeAppState();
}

class _PixelCodeAppState extends ConsumerState<PixelCodeApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await serverProcess.dispose();
        return AppExitResponse.exit;
      },
    );
    _initSession();
  }

  Future<void> _initSession() async {
    final session = ref.read(sessionProvider.notifier);
    await session.migrateFromLegacy();

    // Auto-start local server on desktop
    if (!Platform.isIOS && !Platform.isAndroid) {
      final savedPath = ProjectPersistenceService.loadCurrentProjectPath(
        ref.read(sharedPrefsProvider),
      );
      serverProcess.start(projectPath: savedPath);
      // Wait for server to boot before connecting
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    // Connect WebSocket to the active session, or fallback to local server
    final profile = ref.read(sessionProvider).activeProfile;
    final wsUrl = profile?.wsUrl ?? 'ws://localhost:9720';
    ref.read(wsServiceProvider).connect(url: wsUrl);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    serverProcess.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PixelCode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E11),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C0D1),
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: const HubScreen(),
    );
  }
}
