# Claude Auth Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Account" section to settings with Claude subscription OAuth login/logout, status display, pixel-art avatar, and editable nickname.

**Architecture:** New `ClaudeAuthService` wraps the `claude` CLI (`auth status`, `auth login --claudeai`, `auth logout`) via `Process.run`. A Riverpod `AsyncNotifier` exposes auth state. The settings dialog gets a new first section with avatar (CustomPainter pixel art), nickname field (persisted in AppSettings), and login/logout button.

**Tech Stack:** Flutter, Riverpod, dart:io Process, CustomPainter, SharedPreferences

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/services/claude_auth_service.dart` | Create | Wraps `claude` CLI: checkStatus, login, logout |
| `lib/providers/claude_auth_provider.dart` | Create | AsyncNotifier for auth state, exposes refresh |
| `lib/providers/settings_provider.dart` | Modify | Add `nickname` field to AppSettings |
| `lib/widgets/settings/settings_dialog.dart` | Modify | Add "Account" section at top |
| `lib/widgets/settings/claude_avatar.dart` | Create | Pixel-art Claude avatar with glitch effect |

---

### Task 1: ClaudeAuthService

**Files:**
- Create: `lib/services/claude_auth_service.dart`

- [ ] **Step 1: Create the auth service**

```dart
/// Wraps the `claude` CLI to manage OAuth authentication.
library;

import 'dart:convert';
import 'dart:io';

class ClaudeAuthStatus {
  final bool loggedIn;
  final String? email;
  final String? orgName;
  final String? subscriptionType;
  final String? authMethod;

  const ClaudeAuthStatus({
    required this.loggedIn,
    this.email,
    this.orgName,
    this.subscriptionType,
    this.authMethod,
  });

  factory ClaudeAuthStatus.fromJson(Map<String, dynamic> json) =>
      ClaudeAuthStatus(
        loggedIn: json['loggedIn'] as bool? ?? false,
        email: json['email'] as String?,
        orgName: json['orgName'] as String?,
        subscriptionType: json['subscriptionType'] as String?,
        authMethod: json['authMethod'] as String?,
      );

  static const notLoggedIn = ClaudeAuthStatus(loggedIn: false);
}

class ClaudeAuthService {
  /// Finds the `claude` binary — prefers the VS Code extension native binary,
  /// falls back to `claude` on PATH.
  static String? _findClaudeBinary() {
    if (!Platform.isMacOS && !Platform.isLinux) return null;

    // Try VS Code extension binary first (same logic as ServerProcessService)
    final home = Platform.environment['HOME'];
    if (home != null) {
      final arch = Platform.version.contains('arm')
          ? 'darwin-arm64'
          : 'darwin-x64';
      final extensionsDir = Directory('$home/.vscode/extensions');
      if (extensionsDir.existsSync()) {
        final candidates = extensionsDir
            .listSync()
            .whereType<Directory>()
            .where((d) {
              final name = d.uri.pathSegments
                  .lastWhere((s) => s.isNotEmpty, orElse: () => '');
              return name.startsWith('anthropic.claude-code-') &&
                  name.endsWith(arch);
            })
            .toList();

        candidates.sort((a, b) {
          String ver(Directory d) {
            final parts = d.uri.pathSegments
                .lastWhere((s) => s.isNotEmpty)
                .split('-');
            return parts.length > 2 ? parts[2] : '';
          }
          return ver(b).compareTo(ver(a));
        });

        for (final dir in candidates) {
          final binary = File('${dir.path}/resources/native-binary/claude');
          if (binary.existsSync()) return binary.path;
        }
      }
    }

    // Fallback: claude on PATH
    final result = Process.runSync('which', ['claude']);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
    return null;
  }

  static String? _binary;

  static String? get binary => _binary ??= _findClaudeBinary();

  /// Checks current auth status by running `claude auth status`.
  static Future<ClaudeAuthStatus> checkStatus() async {
    final bin = binary;
    if (bin == null) return ClaudeAuthStatus.notLoggedIn;

    try {
      final result = await Process.run(bin, ['auth', 'status']);
      if (result.exitCode != 0) return ClaudeAuthStatus.notLoggedIn;

      final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      return ClaudeAuthStatus.fromJson(json);
    } catch (_) {
      return ClaudeAuthStatus.notLoggedIn;
    }
  }

  /// Launches `claude auth login --claudeai` which opens the browser for OAuth.
  /// Returns true if the process started successfully.
  static Future<bool> login() async {
    final bin = binary;
    if (bin == null) return false;

    try {
      // Launch login in a shell so the browser opens properly
      final result = await Process.run(
        '/bin/zsh',
        ['-l', '-c', '$bin auth login --claudeai'],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Runs `claude auth logout`.
  static Future<bool> logout() async {
    final bin = binary;
    if (bin == null) return false;

    try {
      final result = await Process.run(bin, ['auth', 'logout']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze lib/services/claude_auth_service.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/services/claude_auth_service.dart
git commit -m "feat: add ClaudeAuthService — wraps claude CLI for OAuth"
```

---

### Task 2: Claude Auth Provider

**Files:**
- Create: `lib/providers/claude_auth_provider.dart`

- [ ] **Step 1: Create the provider**

```dart
/// Riverpod provider for Claude OAuth auth state.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/claude_auth_service.dart';

export '../services/claude_auth_service.dart' show ClaudeAuthStatus;

class ClaudeAuthNotifier extends AsyncNotifier<ClaudeAuthStatus> {
  @override
  Future<ClaudeAuthStatus> build() => ClaudeAuthService.checkStatus();

  /// Re-check auth status (e.g. after login/logout).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await ClaudeAuthService.checkStatus());
  }

  /// Launch OAuth login flow, then refresh status.
  Future<void> login() async {
    await ClaudeAuthService.login();
    await refresh();
  }

  /// Logout, then refresh status.
  Future<void> logout() async {
    await ClaudeAuthService.logout();
    await refresh();
  }
}

final claudeAuthProvider =
    AsyncNotifierProvider<ClaudeAuthNotifier, ClaudeAuthStatus>(
  ClaudeAuthNotifier.new,
);
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze lib/providers/claude_auth_provider.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/providers/claude_auth_provider.dart
git commit -m "feat: add claudeAuthProvider — async notifier for auth state"
```

---

### Task 3: Add nickname to AppSettings

**Files:**
- Modify: `lib/providers/settings_provider.dart`

- [ ] **Step 1: Add nickname field to AppSettings and SettingsNotifier**

In `settings_provider.dart`, add `nickname` to the model, `copyWith`, `build()`, and a setter:

```dart
// In AppSettings class:
const _keyNickname = 'settings_nickname';

class AppSettings {
  final bool showArkanoidButton;
  final double deskHeight;
  final String nickname;

  const AppSettings({
    this.showArkanoidButton = false,
    this.deskHeight = 74.0,
    this.nickname = '',
  });

  AppSettings copyWith({
    bool? showArkanoidButton,
    double? deskHeight,
    String? nickname,
  }) =>
      AppSettings(
        showArkanoidButton: showArkanoidButton ?? this.showArkanoidButton,
        deskHeight: deskHeight ?? this.deskHeight,
        nickname: nickname ?? this.nickname,
      );
}

// In SettingsNotifier.build():
//   nickname: prefs.getString(_keyNickname) ?? '',

// Add to SettingsNotifier:
//   Future<void> setNickname(String value) async {
//     final prefs = ref.read(sharedPrefsProvider);
//     await prefs.setString(_keyNickname, value);
//     state = state.copyWith(nickname: value);
//   }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze lib/providers/settings_provider.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/providers/settings_provider.dart
git commit -m "feat: add nickname field to AppSettings"
```

---

### Task 4: Pixel-art Claude avatar widget

**Files:**
- Create: `lib/widgets/settings/claude_avatar.dart`

- [ ] **Step 1: Create the pixel-art avatar with glitch effect**

The avatar is a 48x48 widget using `CustomPainter` to draw a pixel-art "sparkle" (Claude's ✦ symbol) on an 8x8 grid. When `isActive` is true, uses cyan/teal colors with occasional glitch-shift animation; when false, uses grey tones.

```dart
/// Pixel-art Claude avatar with glitch animation.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class ClaudeAvatar extends StatefulWidget {
  final bool isActive;
  final double size;

  const ClaudeAvatar({super.key, this.isActive = false, this.size = 48});

  @override
  State<ClaudeAvatar> createState() => _ClaudeAvatarState();
}

class _ClaudeAvatarState extends State<ClaudeAvatar> {
  Timer? _glitchTimer;
  double _glitchOffsetX = 0;
  double _glitchOffsetY = 0;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _startGlitchLoop();
  }

  @override
  void didUpdateWidget(ClaudeAvatar old) {
    super.didUpdateWidget(old);
    if (widget.isActive != old.isActive) {
      _glitchTimer?.cancel();
      _startGlitchLoop();
    }
  }

  void _startGlitchLoop() {
    if (!widget.isActive) {
      _glitchTimer?.cancel();
      _glitchOffsetX = 0;
      _glitchOffsetY = 0;
      return;
    }
    _glitchTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      setState(() {
        _glitchOffsetX = (_rng.nextDouble() - 0.5) * 3;
        _glitchOffsetY = (_rng.nextDouble() - 0.5) * 2;
      });
      // Reset after brief flash
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() { _glitchOffsetX = 0; _glitchOffsetY = 0; });
      });
    });
  }

  @override
  void dispose() {
    _glitchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.translate(
        offset: Offset(_glitchOffsetX, _glitchOffsetY),
        child: CustomPaint(
          painter: _ClaudePixelPainter(isActive: widget.isActive),
        ),
      ),
    );
  }
}

class _ClaudePixelPainter extends CustomPainter {
  final bool isActive;

  _ClaudePixelPainter({required this.isActive});

  // 8x8 pixel grid representing a sparkle/star (Claude's ✦)
  // 1 = filled, 0 = empty
  static const _grid = [
    [0, 0, 0, 1, 1, 0, 0, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 1, 1, 1, 1, 1, 1, 0],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [1, 1, 1, 1, 1, 1, 1, 1],
    [0, 1, 1, 1, 1, 1, 1, 0],
    [0, 0, 1, 1, 1, 1, 0, 0],
    [0, 0, 0, 1, 1, 0, 0, 0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / 8;
    final cellH = size.height / 8;

    final bgPaint = Paint()
      ..color = isActive
          ? const Color(0xFF00C0D1).withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.05);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(size.width * 0.15),
      ),
      bgPaint,
    );

    final fillPaint = Paint();
    final glowColor = isActive
        ? const Color(0xFF00C0D1)
        : Colors.white.withValues(alpha: 0.25);

    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        if (_grid[row][col] == 1) {
          // Distance from center affects brightness
          final dx = (col - 3.5).abs() / 3.5;
          final dy = (row - 3.5).abs() / 3.5;
          final dist = (dx + dy) / 2;
          final alpha = isActive ? (1.0 - dist * 0.5) : (0.3 - dist * 0.1);

          fillPaint.color = glowColor.withValues(alpha: alpha.clamp(0.1, 1.0));
          canvas.drawRect(
            Rect.fromLTWH(col * cellW + 0.5, row * cellH + 0.5, cellW - 1, cellH - 1),
            fillPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ClaudePixelPainter old) => old.isActive != isActive;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze lib/widgets/settings/claude_avatar.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/settings/claude_avatar.dart
git commit -m "feat: add pixel-art Claude avatar with glitch effect"
```

---

### Task 5: Add Account section to settings dialog

**Files:**
- Modify: `lib/widgets/settings/settings_dialog.dart`

- [ ] **Step 1: Add imports**

Add at the top of `settings_dialog.dart`:

```dart
import '../../providers/claude_auth_provider.dart';
import 'claude_avatar.dart';
```

- [ ] **Step 2: Add the Account section widget**

Insert a new `_AccountSection` widget and place it as the first section in `_SettingsContent.build()`, before the Sessions section. The section contains:

1. Row with `ClaudeAvatar` + nickname (editable via inline TextField) + auth status line
2. Login or Logout button below

```dart
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _editingNickname = false;
  late TextEditingController _nicknameController;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: ref.read(settingsProvider).nickname,
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(claudeAuthProvider);
    final nickname = ref.watch(settingsProvider).nickname;
    final isLoggedIn = authAsync.valueOrNull?.loggedIn ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Обліковий запис'),
        const SizedBox(height: 16),

        // Avatar + info row
        Row(
          children: [
            ClaudeAvatar(isActive: isLoggedIn, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nickname row
                  if (_editingNickname)
                    SizedBox(
                      height: 28,
                      child: TextField(
                        controller: _nicknameController,
                        autofocus: true,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: Color(0xFF00C0D1)),
                          ),
                        ),
                        onSubmitted: (value) {
                          ref.read(settingsProvider.notifier).setNickname(value.trim());
                          setState(() => _editingNickname = false);
                        },
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () {
                        _nicknameController.text = nickname;
                        setState(() => _editingNickname = true);
                      },
                      child: Row(
                        children: [
                          Text(
                            nickname.isEmpty ? 'Без імені' : nickname,
                            style: TextStyle(
                              color: Colors.white.withValues(
                                alpha: nickname.isEmpty ? 0.35 : 0.9,
                              ),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontStyle: nickname.isEmpty
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 4),

                  // Auth status line
                  authAsync.when(
                    loading: () => Row(
                      children: [
                        SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Перевірка...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    error: (_, __) => Row(
                      children: [
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Помилка перевірки',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    data: (status) {
                      if (!status.loggedIn) {
                        return Row(
                          children: [
                            Container(
                              width: 7, height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Не авторизовано',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      }
                      final plan = status.subscriptionType ?? status.authMethod ?? 'Claude';
                      final org = status.orgName;
                      final label = org != null ? '$plan · $org' : plan;
                      return Row(
                        children: [
                          Container(
                            width: 7, height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF4ADE80),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Login / Logout button
        SizedBox(
          width: double.infinity,
          height: 44,
          child: authAsync.when(
            loading: () => FilledButton(
              onPressed: null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
            error: (_, __) => OutlinedButton.icon(
              onPressed: () => ref.read(claudeAuthProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Спробувати знову'),
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
            data: (status) {
              if (status.loggedIn) {
                return OutlinedButton(
                  onPressed: () => ref.read(claudeAuthProvider.notifier).logout(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.5),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Вийти'),
                );
              }
              return FilledButton.icon(
                onPressed: () => ref.read(claudeAuthProvider.notifier).login(),
                icon: const Icon(Icons.login_rounded, size: 16),
                label: const Text('Увійти через Claude'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00C0D1),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }
}
```

- [ ] **Step 3: Wire up in _SettingsContent.build()**

In `_SettingsContent.build()`, insert `const _AccountSection()` as the first child in the Column, before the Sessions section header:

```dart
// Inside _SettingsContent build() Column children:
const _AccountSection(),  // <-- NEW, first item
// ── Section: Sessions ──  (existing code continues)
_SectionHeader(title: 'Сесії'),
```

- [ ] **Step 4: Verify it compiles**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter analyze lib/widgets/settings/settings_dialog.dart`
Expected: No errors

- [ ] **Step 5: Test manually**

Run: `cd /Users/danylooliinyk/Projects/PixelCode && flutter run -d macos`

1. Open Settings — verify "Обліковий запис" section appears first
2. Verify avatar shows in cyan (logged in) or grey (not logged in)
3. Tap nickname to edit, type a name, press Enter — verify it persists
4. Verify auth status shows subscription info
5. Test Login/Logout buttons

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/settings/settings_dialog.dart
git commit -m "feat: add Account section with Claude auth, avatar, nickname"
```
