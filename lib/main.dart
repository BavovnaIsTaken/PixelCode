import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/hub/hub_screen.dart';
import 'services/server_process_service.dart';

final serverProcess = ServerProcessService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await serverProcess.start();
  runApp(const ProviderScope(child: AgentHubApp()));
}

class AgentHubApp extends StatefulWidget {
  const AgentHubApp({super.key});

  @override
  State<AgentHubApp> createState() => _AgentHubAppState();
}

class _AgentHubAppState extends State<AgentHubApp> {
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
      title: 'Agent Hub',
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
