# Multi-Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow switching between multiple PixelCode servers (each with its own API key) from any device — iPhone, work MacBook, home MacBook.

**Architecture:** Client-side session profiles stored in SharedPreferences. Each profile = name + host + port + optional API key. Selecting a profile reconnects WebSocket (and optionally restarts local server with the right API key on macOS). No server-side changes.

**Tech Stack:** Flutter, Riverpod, SharedPreferences, dart:io (Process), dart:convert (JSON)

**Spec:** `docs/superpowers/specs/2026-04-13-multi-session-design.md`

---

## File Structure

### New files:
- `lib/models/session_profile.dart` — SessionProfile data class with JSON serialization
- `lib/providers/session_provider.dart` — SessionProfilesNotifier (CRUD, persistence, active profile switching)
- `lib/widgets/session/session_picker.dart` — compact dropdown in title bar showing active session + status
- `lib/widgets/session/session_form_dialog.dart` — dialog for creating/editing a session profile

### Modified files:
- `lib/services/server_process_service.dart` — accept `apiKey` parameter, pass as env var
- `lib/services/agent_ws_service.dart` — remove hardcoded `_defaultUrl`, take URL from caller
- `lib/providers/settings_provider.dart` — remove `serverUrl` field, add migration helper
- `lib/providers/agent_provider.dart` — remove direct WS connect from providers
- `lib/screens/hub/hub_screen.dart` — replace `_ConnectionIndicator` usage with `SessionPicker`, remove serverUrl refs
- `lib/main.dart` — init profiles on startup, connect via active profile
- `lib/widgets/settings/settings_dialog.dart` — remove "З'єднання" section, add "Сесії" section

---

### Task 1: SessionProfile Model

**Files:**
- Create: `lib/models/session_profile.dart`

- [ ] **Step 1: Create the model**

```dart
// lib/models/session_profile.dart

/// A named connection profile for a PixelCode server.
///
/// On macOS the profile may include an [apiKey] so the local server
/// can be (re)started with the correct ANTHROPIC_API_KEY.
/// On iOS every profile is remote-only (no apiKey needed).
library;

import 'dart:convert';

class SessionProfile {
  final String id;
  final String name;
  final String host;
  final int port;
  final String? apiKey;

  const SessionProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 9720,
    this.apiKey,
  });

  String get wsUrl => 'ws://$host:$port';

  bool get hasApiKey => apiKey != null && apiKey!.isNotEmpty;

  SessionProfile copyWith({
    String? name,
    String? host,
    int? port,
    String? Function()? apiKey,
  }) =>
      SessionProfile(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        apiKey: apiKey != null ? apiKey() : this.apiKey,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        if (apiKey != null) 'apiKey': apiKey,
      };

  factory SessionProfile.fromJson(Map<String, dynamic> json) => SessionProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int? ?? 9720,
        apiKey: json['apiKey'] as String?,
      );

  static String encodeList(List<SessionProfile> profiles) =>
      jsonEncode(profiles.map((p) => p.toJson()).toList());

  static List<SessionProfile> decodeList(String json) =>
      (jsonDecode(json) as List)
          .cast<Map<String, dynamic>>()
          .map(SessionProfile.fromJson)
          .toList();
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/models/session_profile.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/models/session_profile.dart
git commit -m "feat: add SessionProfile model"
```

---

### Task 2: SessionProvider

**Files:**
- Create: `lib/providers/session_provider.dart`
- Read: `lib/providers/settings_provider.dart` (for sharedPrefsProvider, defaultServerUrl)

- [ ] **Step 1: Create the provider**

```dart
// lib/providers/session_provider.dart

/// Manages session profiles — CRUD, persistence, active profile switching.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_profile.dart';
import 'settings_provider.dart';

const _keyProfiles = 'session_profiles';
const _keyActiveProfileId = 'session_active_profile_id';

class SessionState {
  final List<SessionProfile> profiles;
  final String? activeProfileId;

  const SessionState({this.profiles = const [], this.activeProfileId});

  SessionProfile? get activeProfile {
    if (activeProfileId == null) return null;
    final idx = profiles.indexWhere((p) => p.id == activeProfileId);
    return idx >= 0 ? profiles[idx] : null;
  }

  SessionState copyWith({
    List<SessionProfile>? profiles,
    String? Function()? activeProfileId,
  }) =>
      SessionState(
        profiles: profiles ?? this.profiles,
        activeProfileId: activeProfileId != null
            ? activeProfileId()
            : this.activeProfileId,
      );
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    final prefs = ref.read(sharedPrefsProvider);
    return _load(prefs);
  }

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  SessionState _load(SharedPreferences prefs) {
    final raw = prefs.getString(_keyProfiles);
    final profiles =
        raw != null ? SessionProfile.decodeList(raw) : <SessionProfile>[];
    final activeId = prefs.getString(_keyActiveProfileId);
    return SessionState(profiles: profiles, activeProfileId: activeId);
  }

  Future<void> _save() async {
    await _prefs.setString(
      _keyProfiles,
      SessionProfile.encodeList(state.profiles),
    );
    final activeId = state.activeProfileId;
    if (activeId != null) {
      await _prefs.setString(_keyActiveProfileId, activeId);
    } else {
      await _prefs.remove(_keyActiveProfileId);
    }
  }

  Future<void> addProfile(SessionProfile profile) async {
    state = state.copyWith(profiles: [...state.profiles, profile]);
    // Auto-activate if it's the first profile
    if (state.profiles.length == 1) {
      state = state.copyWith(activeProfileId: () => profile.id);
    }
    await _save();
  }

  Future<void> updateProfile(SessionProfile profile) async {
    state = state.copyWith(
      profiles: [
        for (final p in state.profiles)
          if (p.id == profile.id) profile else p,
      ],
    );
    await _save();
  }

  Future<void> deleteProfile(String id) async {
    state = state.copyWith(
      profiles: state.profiles.where((p) => p.id != id).toList(),
      activeProfileId: () =>
          state.activeProfileId == id ? null : state.activeProfileId,
    );
    await _save();
  }

  Future<void> setActive(String id) async {
    state = state.copyWith(activeProfileId: () => id);
    await _save();
  }

  /// Migrate from the old single-URL setting if no profiles exist yet.
  Future<void> migrateFromLegacy() async {
    if (state.profiles.isNotEmpty) return;
    final prefs = _prefs;
    final oldUrl = prefs.getString('settings_server_url');
    if (oldUrl == null || oldUrl.isEmpty) return;

    // Parse ws://host:port
    final uri = Uri.tryParse(oldUrl);
    if (uri == null) return;

    final profile = SessionProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Default',
      host: uri.host,
      port: uri.port > 0 ? uri.port : 9720,
    );
    await addProfile(profile);
    await prefs.remove('settings_server_url');
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/providers/session_provider.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/providers/session_provider.dart
git commit -m "feat: add SessionProvider with CRUD and persistence"
```

---

### Task 3: Update ServerProcessService

**Files:**
- Modify: `lib/services/server_process_service.dart`

- [ ] **Step 1: Add apiKey parameter to start() and restart()**

In `server_process_service.dart`, change the `start()` method signature and environment block, and the `restart()` method:

Replace `Future<void> start({String? projectPath}) async {` block's environment section. The full updated method:

```dart
  /// Starts the Node.js server if it is not already running.
  /// If [projectPath] is provided, it will be used as PROJECT_CWD.
  /// If [apiKey] is provided, it will be set as ANTHROPIC_API_KEY.
  Future<void> start({String? projectPath, String? apiKey}) async {
    // Process.start is not supported on iOS/Android (OS sandbox restriction).
    if (Platform.isIOS || Platform.isAndroid) {
      _emitLog('info', 'Server process not supported on mobile platforms');
      return;
    }

    if (_process != null) return;

    final serverDir = _serverDir;
    if (!Directory(serverDir).existsSync()) {
      _emitLog('error', 'server/ directory not found at $serverDir');
      return;
    }

    _emitLog('info', 'Starting server in $serverDir');

    // Launch via shell so that PATH from the user's profile is inherited.
    // This ensures node/npm/npx are found even when the app is launched
    // from Finder or Xcode rather than from the terminal.
    try {
      _process = await Process.start(
        '/bin/zsh',
        ['-l', '-c', 'npm run dev'],
        workingDirectory: serverDir,
        environment: {
          ...Platform.environment,
          'PORT': '9720',
          'PROJECT_CWD': projectPath ?? Directory.current.path,
          if (apiKey != null && apiKey.isNotEmpty) 'ANTHROPIC_API_KEY': apiKey,
        },
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _emitLog('error', 'Server process start timed out after 10s');
      return;
    } catch (e) {
      _emitLog('error', 'Failed to start server: $e');
      return;
    }

    _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) _emitLog('info', line.trim());
      }
    });
    _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) _emitLog('warn', line.trim());
      }
    });

    _process!.exitCode.then((code) {
      _emitLog(code == 0 ? 'info' : 'error', 'Server exited with code $code');
      _process = null;
    });
  }
```

And update `restart()`:

```dart
  /// Restarts the server process, optionally with a new project path and API key.
  Future<void> restart({String? projectPath, String? apiKey}) async {
    _emitLog('info', 'Restarting server…');
    await stop();
    // Give the OS a moment to release the port.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await start(projectPath: projectPath, apiKey: apiKey);
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/services/server_process_service.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/services/server_process_service.dart
git commit -m "feat: ServerProcessService accepts apiKey for environment"
```

---

### Task 4: Update AgentWsService

**Files:**
- Modify: `lib/services/agent_ws_service.dart`

- [ ] **Step 1: Remove hardcoded default URL**

Remove the `_defaultUrl` constant and all default parameter values that reference it. The URL must always be passed explicitly now.

Changes:
1. Remove `static const _defaultUrl = 'ws://100.x.y.z:9720';`
2. `connect({String url = _defaultUrl})` → `connect({required String url})`
3. `reconnect({String url = _defaultUrl})` → `reconnect({required String url})`
4. `_scheduleReconnect(String url)` stays the same (already takes explicit url)

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/services/agent_ws_service.dart`
Expected: No errors (callers will break, but we fix them in Task 6)

- [ ] **Step 3: Commit**

```bash
git add lib/services/agent_ws_service.dart
git commit -m "refactor: remove hardcoded default URL from AgentWsService"
```

---

### Task 5: Update settings_provider

**Files:**
- Modify: `lib/providers/settings_provider.dart`

- [ ] **Step 1: Remove serverUrl from AppSettings**

Remove:
- `const _keyServerUrl = 'settings_server_url';`
- `const defaultServerUrl = 'ws://100.x.y.z:9720';`
- `serverUrl` field from `AppSettings`
- `serverUrl` from `copyWith`
- `setServerUrl` method from `SettingsNotifier`
- `serverUrl` loading from `build()`

The resulting file:

```dart
/// App settings with persistence via SharedPreferences.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys ───────────────────────────────────────────────────────────────────

const _keyShowArkanoidButton = 'settings_show_arkanoid_button';
const _keyDeskHeight = 'settings_desk_height';

// ─── Settings model ─────────────────────────────────────────────────────────

class AppSettings {
  final bool showArkanoidButton;
  final double deskHeight;

  const AppSettings({
    this.showArkanoidButton = false,
    this.deskHeight = 74.0,
  });

  AppSettings copyWith({
    bool? showArkanoidButton,
    double? deskHeight,
  }) =>
      AppSettings(
        showArkanoidButton: showArkanoidButton ?? this.showArkanoidButton,
        deskHeight: deskHeight ?? this.deskHeight,
      );
}

// ─── SharedPreferences instance ─────────────────────────────────────────────

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden at startup');
});

// ─── Settings notifier ──────────────────────────────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.read(sharedPrefsProvider);
    return AppSettings(
      showArkanoidButton: prefs.getBool(_keyShowArkanoidButton) ?? false,
      deskHeight: prefs.getDouble(_keyDeskHeight) ?? 74.0,
    );
  }

  Future<void> setShowArkanoidButton(bool value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_keyShowArkanoidButton, value);
    state = state.copyWith(showArkanoidButton: value);
  }

  Future<void> setDeskHeight(double value) async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setDouble(_keyDeskHeight, value);
    state = state.copyWith(deskHeight: value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/providers/settings_provider.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/providers/settings_provider.dart
git commit -m "refactor: remove serverUrl from settings (replaced by session profiles)"
```

---

### Task 6: Wire up main.dart and HubScreen init

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/hub/hub_screen.dart` (initState only — UI changes come in Task 10)

This task connects the session provider to startup logic and fixes compilation errors from Tasks 4-5.

- [ ] **Step 1: Update main.dart**

Replace the full file:

```dart
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

    final profile = ref.read(sessionProvider).activeProfile;
    if (profile == null) return; // no profiles yet — first-run wizard will handle

    final savedPath = ProjectPersistenceService.loadCurrentProjectPath(
      ref.read(sharedPrefsProvider),
    );

    // Start local server if this profile has an API key and we're on desktop
    if (profile.hasApiKey && !Platform.isIOS && !Platform.isAndroid) {
      serverProcess.start(projectPath: savedPath, apiKey: profile.apiKey);
    }

    // Connect WebSocket
    ref.read(wsServiceProvider).connect(url: profile.wsUrl);
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
```

- [ ] **Step 2: Update HubScreen.initState — remove WS connect (now handled by main.dart)**

In `hub_screen.dart`, replace initState:

```dart
  @override
  void initState() {
    super.initState();
    _loadLogoImage();
    _scheduleGlitch();
    // WS connection is now managed by main.dart via session profiles.
    // No explicit connect() call needed here.
  }
```

- [ ] **Step 3: Fix all `ref.read(settingsProvider).serverUrl` references in hub_screen.dart**

These occur in `_ConnectionIndicator` callbacks in `_buildTitleBar` and `_buildMobileTitleBar`. For now, replace them with the active profile URL. In `_buildTitleBar`:

Replace the `_ConnectionIndicator` block's `onReconnect` and `onRestartServer` callbacks in **both** `_buildTitleBar` and `_buildMobileTitleBar` to use session provider:

```dart
          _ConnectionIndicator(
            isConnected: isConnected,
            onReconnect: () {
              final profile = ref.read(sessionProvider).activeProfile;
              if (profile != null) {
                ref.read(wsServiceProvider).reconnect(url: profile.wsUrl);
              }
            },
            onRestartServer: () async {
              final profile = ref.read(sessionProvider).activeProfile;
              if (profile == null) return;
              final project = ref.read(projectProvider);
              await ref
                  .read(serverProcessProvider)
                  .restart(
                    projectPath: project?.path,
                    apiKey: profile.apiKey,
                  );
              await Future<void>.delayed(const Duration(seconds: 2));
              if (mounted) {
                ref.read(wsServiceProvider).reconnect(url: profile.wsUrl);
              }
            },
          ),
```

And the same for `_buildMobileTitleBar` version (with `compact: true`).

Also add import at top of hub_screen.dart:
```dart
import '../../providers/session_provider.dart';
```

- [ ] **Step 4: Verify everything compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/screens/hub/hub_screen.dart
git commit -m "feat: wire up session profiles to startup and WS connection"
```

---

### Task 7: Session Form Dialog

**Files:**
- Create: `lib/widgets/session/session_form_dialog.dart`

- [ ] **Step 1: Create the form dialog**

```dart
// lib/widgets/session/session_form_dialog.dart

/// Dialog for creating or editing a session profile.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/session_profile.dart';

/// Shows the session form dialog and returns the created/edited profile,
/// or null if the user cancelled.
Future<SessionProfile?> showSessionFormDialog(
  BuildContext context, {
  SessionProfile? existing,
}) {
  return showDialog<SessionProfile>(
    context: context,
    builder: (_) => _SessionFormDialog(existing: existing),
  );
}

class _SessionFormDialog extends StatefulWidget {
  final SessionProfile? existing;
  const _SessionFormDialog({this.existing});

  @override
  State<_SessionFormDialog> createState() => _SessionFormDialogState();
}

class _SessionFormDialogState extends State<_SessionFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _apiKeyCtrl;
  bool _showApiKey = false;

  bool get _isEditing => widget.existing != null;
  bool get _isDesktop => !Platform.isIOS && !Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _hostCtrl = TextEditingController(text: widget.existing?.host ?? '');
    _portCtrl = TextEditingController(
      text: (widget.existing?.port ?? 9720).toString(),
    );
    _apiKeyCtrl = TextEditingController(text: widget.existing?.apiKey ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _nameCtrl.text.trim().isNotEmpty && _hostCtrl.text.trim().isNotEmpty;

  void _submit() {
    if (!_isValid) return;
    final profile = SessionProfile(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 9720,
      apiKey: _apiKeyCtrl.text.trim().isEmpty ? null : _apiKeyCtrl.text.trim(),
    );
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1A1A1F);
    const fieldBg = Color(0xFF0E0E11);
    const accent = Color(0xFF00C0D1);
    final dimText = Colors.white.withValues(alpha: 0.35);
    final labelStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );

    InputDecoration fieldDecor(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            fontFamily: 'monospace',
          ),
          filled: true,
          fillColor: fieldBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: accent),
          ),
        );

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                _isEditing ? 'Редагувати сесію' : 'Нова сесія',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),

              // Name
              Text('Назва', style: labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: fieldDecor('Робочий MacBook'),
              ),
              const SizedBox(height: 16),

              // Host
              Text('Хост (Tailscale IP)', style: labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _hostCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                decoration: fieldDecor('100.x.y.z'),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 16),

              // Port
              Text('Порт', style: labelStyle),
              const SizedBox(height: 6),
              TextField(
                controller: _portCtrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                decoration: fieldDecor('9720'),
                keyboardType: TextInputType.number,
              ),

              // API Key (only on desktop)
              if (_isDesktop) ...[
                const SizedBox(height: 16),
                Text('API Key', style: labelStyle),
                const SizedBox(height: 4),
                Text(
                  'ANTHROPIC_API_KEY для локального сервера. '
                  'Залиш порожнім для віддалених сесій.',
                  style: TextStyle(color: dimText, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: !_showApiKey,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                  decoration: fieldDecor('sk-ant-...').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showApiKey
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      onPressed: () =>
                          setState(() => _showApiKey = !_showApiKey),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Скасувати',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isValid ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.3),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(_isEditing ? 'Зберегти' : 'Додати'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/widgets/session/session_form_dialog.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/session/session_form_dialog.dart
git commit -m "feat: add session form dialog for creating/editing profiles"
```

---

### Task 8: Session Picker Widget

**Files:**
- Create: `lib/widgets/session/session_picker.dart`

This is the compact dropdown that goes in the title bar. Shows the active session name + connection dot. Tap opens a list of all sessions with status indicators.

- [ ] **Step 1: Create the widget**

```dart
// lib/widgets/session/session_picker.dart

/// Compact session picker for the title bar.
///
/// Shows the active session name with a connection indicator.
/// Tap to switch sessions or add a new one.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../providers/session_provider.dart';
import '../../services/project_persistence_service.dart';
import '../session/session_form_dialog.dart';
import '../../providers/settings_provider.dart';

class SessionPicker extends ConsumerWidget {
  final bool compact;
  const SessionPicker({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;
    final active = session.activeProfile;

    if (active == null) {
      return _AddSessionButton(compact: compact);
    }

    final dotColor = isConnected ? const Color(0xFF00C0D1) : Colors.red;

    return GestureDetector(
      onTap: () => _showSessionMenu(context, ref, session, isConnected),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  active.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.unfold_more,
                size: 14,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSessionMenu(
    BuildContext context,
    WidgetRef ref,
    SessionState session,
    bool isConnected,
  ) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset(0, box.size.height));

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + 4,
        offset.dx + box.size.width,
        offset.dy + 4,
      ),
      color: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      items: [
        // Existing profiles
        for (final profile in session.profiles)
          PopupMenuItem(
            value: profile.id,
            height: 40,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: profile.id == session.activeProfileId
                        ? (isConnected
                            ? const Color(0xFF00C0D1)
                            : Colors.red)
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    profile.name,
                    style: TextStyle(
                      color: profile.id == session.activeProfileId
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: profile.id == session.activeProfileId
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                Text(
                  '${profile.host}:${profile.port}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

        // Divider
        const PopupMenuItem(
          enabled: false,
          height: 1,
          child: Divider(color: Color(0xFF2A2A30), height: 1),
        ),

        // Reconnect
        PopupMenuItem(
          value: '_reconnect',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.refresh,
                size: 15,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Text(
                'Перепідключити',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        // Add new
        PopupMenuItem(
          value: '_add',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.add,
                size: 15,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Text(
                'Додати сесію',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == '_add') {
        _addSession(context, ref);
      } else if (value == '_reconnect') {
        _reconnect(ref);
      } else {
        _switchSession(ref, value);
      }
    });
  }

  Future<void> _addSession(BuildContext context, WidgetRef ref) async {
    final profile = await showSessionFormDialog(context);
    if (profile == null) return;
    await ref.read(sessionProvider.notifier).addProfile(profile);
    _switchSession(ref, profile.id);
  }

  void _reconnect(WidgetRef ref) {
    final profile = ref.read(sessionProvider).activeProfile;
    if (profile != null) {
      ref.read(wsServiceProvider).reconnect(url: profile.wsUrl);
    }
  }

  Future<void> _switchSession(WidgetRef ref, String profileId) async {
    final notifier = ref.read(sessionProvider.notifier);
    await notifier.setActive(profileId);

    final profile = ref.read(sessionProvider).activeProfile;
    if (profile == null) return;

    // Stop current server & WS
    final server = ref.read(serverProcessProvider);
    await server.stop();

    // Start local server if profile has API key and we're on desktop
    if (profile.hasApiKey && !Platform.isIOS && !Platform.isAndroid) {
      final prefs = ref.read(sharedPrefsProvider);
      final savedPath = ProjectPersistenceService.loadCurrentProjectPath(prefs);
      await server.start(projectPath: savedPath, apiKey: profile.apiKey);
      // Give the server a moment to start
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    // Reconnect WebSocket to the new profile
    ref.read(wsServiceProvider).reconnect(url: profile.wsUrl);
  }
}

class _AddSessionButton extends ConsumerWidget {
  final bool compact;
  const _AddSessionButton({required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final profile = await showSessionFormDialog(context);
        if (profile == null) return;
        await ref.read(sessionProvider.notifier).addProfile(profile);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF00C0D1).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: compact ? 14 : 16,
                color: const Color(0xFF00C0D1),
              ),
              const SizedBox(width: 4),
              Text(
                'Додати сесію',
                style: TextStyle(
                  color: const Color(0xFF00C0D1),
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/widgets/session/session_picker.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/session/session_picker.dart
git commit -m "feat: add SessionPicker dropdown for title bar"
```

---

### Task 9: Update Settings Dialog

**Files:**
- Modify: `lib/widgets/settings/settings_dialog.dart`

Replace the "З'єднання" section (URL field + save/reset buttons) with a "Сесії" section that shows the list of profiles with edit/delete.

- [ ] **Step 1: Replace the connection section**

In `_SettingsContentState`:

1. Remove `_urlController`, `_dirty`, `_saving` fields and their `initState`/`dispose`
2. Remove `_save()` and `_reset()` methods
3. Add import for session_provider and session_form_dialog
4. Replace the "З'єднання" section in `build()` with a "Сесії" section

The full updated `_SettingsContent` widget:

```dart
class _SettingsContent extends ConsumerWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section: Sessions ──────────────────────────────────────────
        _SectionHeader(title: 'Сесії'),
        const SizedBox(height: 12),
        Text(
          'Серверні профілі для підключення. '
          'Оберіть активну сесію в заголовку вікна.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),

        // Profile list
        for (final profile in session.profiles) ...[
          _SessionProfileTile(
            profile: profile,
            isActive: profile.id == session.activeProfileId,
            isConnected: profile.id == session.activeProfileId && isConnected,
            onEdit: () => _editProfile(context, ref, profile),
            onDelete: session.profiles.length > 1
                ? () => _deleteProfile(context, ref, profile)
                : null,
          ),
          const SizedBox(height: 8),
        ],

        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => _addProfile(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Додати сесію'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00C0D1),
              side: BorderSide(
                color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),

        // ── Section: Ergonomics ────────────────────────────────────────
        const SizedBox(height: 32),
        _SectionHeader(title: 'Ергономіка робочого місця'),
        const SizedBox(height: 12),
        Text(
          'Висота робочого столу',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Мікрорегулювання висоти для оптимальної ергономічної '
          'позиції під час кодування.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        _DeskHeightControl(
          value: ref.watch(settingsProvider).deskHeight,
          onChanged: (v) =>
              ref.read(settingsProvider.notifier).setDeskHeight(v),
        ),

        // ── Danger zone ─────────────────────────────────────────────
        const SizedBox(height: 32),
        _SectionHeader(title: 'Небезпечна зона'),
        const SizedBox(height: 12),
        Text(
          'Видаляє всі кешовані SDK-сесії з диска. '
          'Поточний контекст розмови буде втрачено.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            onPressed: () => _confirmClearSessions(context, ref),
            icon: const Icon(Icons.cleaning_services_rounded, size: 16),
            label: const Text('Очистити всі SDK-сесії'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00C0D1),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addProfile(BuildContext context, WidgetRef ref) async {
    final profile = await showSessionFormDialog(context);
    if (profile == null) return;
    await ref.read(sessionProvider.notifier).addProfile(profile);
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    SessionProfile profile,
  ) async {
    final updated = await showSessionFormDialog(context, existing: profile);
    if (updated == null) return;
    await ref.read(sessionProvider.notifier).updateProfile(updated);
  }

  void _deleteProfile(
    BuildContext context,
    WidgetRef ref,
    SessionProfile profile,
  ) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F27),
        title: Text(
          'Видалити "${profile.name}"?',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Скасувати',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(sessionProvider.notifier).deleteProfile(profile.id);
            },
            child: const Text(
              'Видалити',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearSessions(BuildContext context, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F27),
        title: const Text(
          'Очистити всі SDK-сесії?',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: Text(
          'Усі кешовані сесії буде видалено з диска. '
          'Поточний контекст розмови буде втрачено.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Скасувати',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(wsServiceProvider).clearSessions();
              ref.read(chatProvider.notifier).newChat();
            },
            child: const Text(
              'Очистити',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
  }
}
```

Also add a new `_SessionProfileTile` widget in the same file:

```dart
class _SessionProfileTile extends StatelessWidget {
  final SessionProfile profile;
  final bool isActive;
  final bool isConnected;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _SessionProfileTile({
    required this.profile,
    required this.isActive,
    required this.isConnected,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isActive
        ? (isConnected ? const Color(0xFF00C0D1) : Colors.red)
        : Colors.white.withValues(alpha: 0.15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00C0D1).withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00C0D1).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: isActive ? 0.9 : 0.6),
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.host}:${profile.port}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: Icon(
              Icons.edit_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}
```

Imports to add at top of settings_dialog.dart:
```dart
import '../../models/session_profile.dart';
import '../../providers/session_provider.dart';
import '../session/session_form_dialog.dart';
```

The `_SettingsContent` changes from `ConsumerStatefulWidget` to `ConsumerWidget` (no longer needs controllers).

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && dart analyze lib/widgets/settings/settings_dialog.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/settings/settings_dialog.dart
git commit -m "feat: replace Connection section with Sessions section in settings"
```

---

### Task 10: Update HubScreen — Add SessionPicker

**Files:**
- Modify: `lib/screens/hub/hub_screen.dart`

Replace the `_ConnectionIndicator` in both `_buildTitleBar` and `_buildMobileTitleBar` with the new `SessionPicker`. Keep `_ConnectionIndicator` class in the file as it's still used by `SessionPicker` implicitly (connection dot logic is now in picker).

- [ ] **Step 1: Add import and replace in desktop title bar**

Add import:
```dart
import '../../widgets/session/session_picker.dart';
```

In `_buildTitleBar`, replace the `_ConnectionIndicator` block (lines ~529-547) and the separator after it with:

```dart
          const SessionPicker(),
          const SizedBox(width: 12),
```

Remove the `const SizedBox(width: 16)` and vertical divider that was between ConnectionIndicator and ProjectSelector.

- [ ] **Step 2: Replace in mobile title bar**

In `_buildMobileTitleBar`, replace the `_ConnectionIndicator` block (lines ~381-399) with:

```dart
          const SessionPicker(compact: true),
```

- [ ] **Step 3: Remove unused `_ConnectionIndicator` class**

Delete the `_ConnectionIndicator` class entirely (it's no longer referenced anywhere — the session picker handles connection status display).

- [ ] **Step 4: Remove the unused `settingsProvider` import usage**

The `settingsProvider.serverUrl` references were already removed in Task 6. Verify no remaining references to `settingsProvider.serverUrl` in the file. The `settingsProvider` import can stay — it's still used for `showArkanoidButton` and `deskHeight`.

- [ ] **Step 5: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze`
Expected: No errors

- [ ] **Step 6: Run the app and verify**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter run -d macos`

Verify:
1. App starts. If no profiles exist, "Додати сесію" button appears in title bar.
2. Click "Додати сесію" → form dialog opens.
3. Create a profile (name: "Test", host: "100.x.y.z", port: 9720) → saves.
4. Session picker appears in title bar with profile name and connection dot.
5. Click picker → dropdown shows profile list + "Додати сесію" + "Перепідключити".
6. Open Settings → "Сесії" section shows profiles with edit/delete buttons.
7. Edit a profile → changes are saved.
8. Add a second profile → both appear in dropdown. Switching reconnects WebSocket.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/hub/hub_screen.dart
git commit -m "feat: replace ConnectionIndicator with SessionPicker in title bar"
```

---

### Task 11: Final integration test

- [ ] **Step 1: Full compile check**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze`
Expected: No errors

- [ ] **Step 2: Test on macOS — local session with API key**

1. Create a profile with API key → server should start with that key
2. Chat with agents → should work normally
3. Switch to another profile (different host) → server stops, WS reconnects to new host

- [ ] **Step 3: Test migration**

1. Manually set old `settings_server_url` in SharedPreferences (or just test fresh install)
2. App should auto-migrate to a "Default" profile

- [ ] **Step 4: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: integration fixes for multi-session"
```
