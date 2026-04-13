/// Compact session picker for the title bar.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/project_persistence_service.dart';
import 'session_form_dialog.dart';

/// A compact dropdown in the title bar showing the active session.
///
/// [compact] should be `true` on mobile to reduce visual weight.
class SessionPicker extends ConsumerWidget {
  const SessionPicker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final connAsync = ref.watch(connectionStatusProvider);
    final connected = connAsync.valueOrNull ?? false;

    final profiles = session.profiles;
    final active = session.activeProfile;

    if (profiles.isEmpty) {
      return _AddSessionButton(compact: compact);
    }

    return _SessionDropdownButton(
      active: active,
      connected: connected,
      compact: compact,
      profiles: profiles,
      activeProfileId: session.activeProfileId,
    );
  }
}

// ─── "Add session" button shown when no profiles exist ───────────────────────

class _AddSessionButton extends ConsumerWidget {
  const _AddSessionButton({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _openAddDialog(context, ref),
      child: Container(
        height: compact ? 28 : 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF00C0D1).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF00C0D1).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: Color(0xFF00C0D1)),
            const SizedBox(width: 4),
            const Text(
              'Додати сесію',
              style: TextStyle(
                color: Color(0xFF00C0D1),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    final profile = await showSessionFormDialog(context);
    if (profile != null) {
      await ref.read(sessionProvider.notifier).addProfile(profile);
    }
  }
}

// ─── Main dropdown button ─────────────────────────────────────────────────────

class _SessionDropdownButton extends ConsumerWidget {
  const _SessionDropdownButton({
    required this.active,
    required this.connected,
    required this.compact,
    required this.profiles,
    required this.activeProfileId,
  });

  final SessionProfile? active;
  final bool connected;
  final bool compact;
  final List<SessionProfile> profiles;
  final String? activeProfileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showMenu(context, ref),
      child: Container(
        height: compact ? 28 : 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Connection dot
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 6),
            // Active session name
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                active?.name ?? 'Немає сесії',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.unfold_more_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final result = await showMenu<_MenuAction>(
      context: context,
      color: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 4,
        offset.dx + size.width,
        offset.dy + size.height + 4,
      ),
      items: [
        // Profile items
        for (final p in profiles)
          PopupMenuItem<_MenuAction>(
            value: _MenuAction.selectProfile(p.id),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _ProfileMenuItem(
              profile: p,
              isActive: p.id == activeProfileId,
            ),
          ),

        // Divider
        const PopupMenuDivider(height: 1),

        // Reconnect
        PopupMenuItem<_MenuAction>(
          value: const _MenuAction.reconnect(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.refresh_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                'Перепідключити',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        // Add session
        PopupMenuItem<_MenuAction>(
          value: const _MenuAction.addSession(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.add_rounded,
                size: 15,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Text(
                'Додати сесію',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (result == null || !context.mounted) return;

    switch (result) {
      case _SelectProfileAction(:final id):
        if (id != activeProfileId) {
          await _switchToProfile(context, ref, id);
        }
      case _ReconnectAction():
        await _reconnect(ref);
      case _AddSessionAction():
        if (context.mounted) {
          final profile = await showSessionFormDialog(context);
          if (profile != null) {
            await ref.read(sessionProvider.notifier).addProfile(profile);
            if (context.mounted) {
              await _switchToProfile(context, ref, profile.id);
            }
          }
        }
    }
  }

  Future<void> _switchToProfile(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    // 1. Set active profile in state
    await ref.read(sessionProvider.notifier).setActive(id);

    // 2. Stop current server
    final server = ref.read(serverProcessProvider);
    await server.stop();

    // 3. On desktop, start server with apiKey if available
    final newProfile = ref
        .read(sessionProvider)
        .profiles
        .firstWhere((p) => p.id == id);

    final isDesktop = !Platform.isIOS && !Platform.isAndroid;
    if (isDesktop && newProfile.hasApiKey) {
      final prefs = ref.read(sharedPrefsProvider);
      final projectPath = ProjectPersistenceService.loadCurrentProjectPath(prefs);
      await server.start(projectPath: projectPath, apiKey: newProfile.apiKey);
      // Wait for server to boot before connecting
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    // 4. Reconnect WebSocket to new profile URL
    if (context.mounted) {
      await ref.read(wsServiceProvider).connect(url: newProfile.wsUrl);
    }
  }

  Future<void> _reconnect(WidgetRef ref) async {
    final profile = ref.read(sessionProvider).activeProfile;
    if (profile == null) return;
    await ref.read(wsServiceProvider).connect(url: profile.wsUrl);
  }
}

// ─── Profile menu item ────────────────────────────────────────────────────────

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.profile,
    required this.isActive,
  });

  final SessionProfile profile;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Connection dot placeholder (always shown for alignment)
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? const Color(0xFF4ADE80)
                : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile.name,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              Text(
                '${profile.host}:${profile.port}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Sealed menu action type ──────────────────────────────────────────────────

sealed class _MenuAction {
  const _MenuAction();

  const factory _MenuAction.selectProfile(String id) = _SelectProfileAction;
  const factory _MenuAction.reconnect() = _ReconnectAction;
  const factory _MenuAction.addSession() = _AddSessionAction;
}

final class _SelectProfileAction extends _MenuAction {
  const _SelectProfileAction(this.id);
  final String id;
}

final class _ReconnectAction extends _MenuAction {
  const _ReconnectAction();
}

final class _AddSessionAction extends _MenuAction {
  const _AddSessionAction();
}
