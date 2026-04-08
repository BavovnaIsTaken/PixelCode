import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/agent_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/hub/hub_screen.dart';
import 'services/project_persistence_service.dart';
import 'services/server_process_service.dart';

final serverProcess = ServerProcessService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Use the last opened project path, or fall back to the current directory.
  final savedPath = ProjectPersistenceService.loadCurrentProjectPath(prefs);
  await serverProcess.start(projectPath: savedPath);

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

class PixelCodeApp extends StatefulWidget {
  const PixelCodeApp({super.key});

  @override
  State<PixelCodeApp> createState() => _PixelCodeAppState();
}

class _PixelCodeAppState extends State<PixelCodeApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await serverProcess.stop();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    serverProcess.stop();
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
      home: const HubScreen(),
    );
  }
}
