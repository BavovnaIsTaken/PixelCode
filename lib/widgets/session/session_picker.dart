/// Session picker — IDE-style tabs on desktop, compact dropdown on mobile.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session_profile.dart';
import '../../providers/agent_provider.dart';
import '../../providers/session_provider.dart';
import 'session_form_dialog.dart';

/// Session picker for the title bar.
///
/// [compact] — `true` on mobile (shows a dropdown), `false` on desktop (IDE tabs).
class SessionPicker extends ConsumerWidget {
  const SessionPicker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) return const _MobileSessionPicker();
    return const _DesktopSessionTabs();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Desktop: IDE-style session tabs
// ═══════════════════════════════════════════════════════════════════════════════

class _DesktopSessionTabs extends ConsumerWidget {
  const _DesktopSessionTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final connAsync = ref.watch(connectionStatusProvider);
    final connected = connAsync.valueOrNull ?? false;
    final tunnelUrl = ref.watch(tunnelUrlProvider);

    final profiles = session.profiles;
    final activeId = session.activeProfileId;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Session tabs
        for (final p in profiles)
          _SessionTab(
            profile: p,
            isActive: p.id == activeId,
            isConnected: p.id == activeId && connected,
            hasTunnel: p.id == activeId && tunnelUrl != null,
          ),
        // "+" add button
        const SizedBox(width: 6),
        _AddTabButton(),
      ],
    );
  }
}

// ─── Single session tab ──────────────────────────────────────────────────────

class _SessionTab extends ConsumerWidget {
  const _SessionTab({
    required this.profile,
    required this.isActive,
    required this.isConnected,
    required this.hasTunnel,
  });

  final SessionProfile profile;
  final bool isActive;
  final bool isConnected;
  final bool hasTunnel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _onTap(context, ref),
      onSecondaryTapUp: (d) => _showContextMenu(context, ref, d.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10, right: 14),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isActive
                    ? const Color(0xFF00C0D1)
                    : Colors.transparent,
                width: 2,
              ),
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
                  color: isActive
                      ? (isConnected
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFEF4444))
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(width: 6),
              // Session name
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  profile.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: isActive
                        ? Colors.white.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              // Tunnel indicator
              if (hasTunnel) ...[
                const SizedBox(width: 5),
                Icon(
                  Icons.cloud_outlined,
                  size: 11,
                  color: const Color(0xFF4ADE80).withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    final currentActiveId = ref.read(sessionProvider).activeProfileId;
    if (profile.id != currentActiveId) {
      _switchToProfile(context, ref, profile.id);
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final result = await showMenu<_TabAction>(
      context: context,
      color: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        // Reconnect
        PopupMenuItem(
          value: _TabAction.reconnect,
          height: 36,
          child: _ContextMenuItem(
            icon: Icons.refresh_rounded,
            label: 'Перепідключити',
          ),
        ),
        // Edit
        PopupMenuItem(
          value: _TabAction.edit,
          height: 36,
          child: _ContextMenuItem(
            icon: Icons.edit_outlined,
            label: 'Редагувати',
          ),
        ),
        // Share connection info
        if (isActive)
          PopupMenuItem(
            value: _TabAction.share,
            height: 36,
            child: _ContextMenuItem(
              icon: Icons.share_outlined,
              label: 'Поділитися',
            ),
          ),
        const PopupMenuDivider(height: 1),
        // Delete
        PopupMenuItem(
          value: _TabAction.delete,
          height: 36,
          child: _ContextMenuItem(
            icon: Icons.close_rounded,
            iconColor: const Color(0xFFEF4444).withValues(alpha: 0.7),
            label: 'Видалити',
            labelColor: const Color(0xFFEF4444).withValues(alpha: 0.7),
          ),
        ),
      ],
    );

    if (result == null || !context.mounted) return;

    switch (result) {
      case _TabAction.reconnect:
        await ref
            .read(wsServiceProvider)
            .reconnect(url: profile.wsUrl);
      case _TabAction.edit:
        if (!context.mounted) return;
        final edited = await showSessionFormDialog(context, existing: profile);
        if (edited != null) {
          await ref.read(sessionProvider.notifier).updateProfile(edited);
          if (edited.id == ref.read(sessionProvider).activeProfileId) {
            await ref.read(wsServiceProvider).reconnect(url: edited.wsUrl);
          }
        }
      case _TabAction.share:
        if (!context.mounted) return;
        _showShareDialog(context);
      case _TabAction.delete:
        final profiles = ref.read(sessionProvider).profiles;
        if (profiles.length <= 1) return; // don't delete the last one
        await ref.read(sessionProvider.notifier).deleteProfile(profile.id);
        // If we deleted the active profile, switch to first remaining
        if (profile.id == ref.read(sessionProvider).activeProfileId ||
            ref.read(sessionProvider).activeProfile == null) {
          final remaining = ref.read(sessionProvider).profiles;
          if (remaining.isNotEmpty && context.mounted) {
            await _switchToProfile(context, ref, remaining.first.id);
          }
        }
    }
  }

  Future<void> _switchToProfile(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(sessionProvider.notifier).setActive(id);
    final newProfile = ref
        .read(sessionProvider)
        .profiles
        .firstWhere((p) => p.id == id);
    if (context.mounted) {
      await ref.read(wsServiceProvider).connect(url: newProfile.wsUrl);
    }
  }

  void _showShareDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _ShareConnectionDialog(),
    );
  }
}

// ─── "+" button to add a new tab ─────────────────────────────────────────────

class _AddTabButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddTabButton> createState() => _AddTabButtonState();
}

class _AddTabButtonState extends ConsumerState<_AddTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00C0D1);
    final restColor = Colors.white.withValues(alpha: 0.35);
    return GestureDetector(
      onTap: _addSession,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _hovered ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 75),
          builder: (context, t, _) => Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12 * t),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 16,
              color: Color.lerp(restColor, accent, t),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addSession() async {
    final profile = await showSessionFormDialog(context);
    if (profile != null) {
      await ref.read(sessionProvider.notifier).addProfile(profile);
      if (mounted) {
        await ref.read(sessionProvider.notifier).setActive(profile.id);
        await ref.read(wsServiceProvider).connect(url: profile.wsUrl);
      }
    }
  }
}

// ─── Context menu item ───────────────────────────────────────────────────────

class _ContextMenuItem extends StatelessWidget {
  const _ContextMenuItem({
    required this.icon,
    required this.label,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor ?? Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: labelColor ?? Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

enum _TabAction { reconnect, edit, share, delete }

// ─── Share connection dialog ─────────────────────────────────────────────────

class _ShareConnectionDialog extends ConsumerWidget {
  const _ShareConnectionDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(serverInfoProvider);
    final localIp = info?.localIps.firstOrNull;
    final port = info?.port ?? 9720;
    final tunnel = info?.tunnelUrl;
    final hostName = info?.hostname ?? '';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.share_outlined,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Підключення до сервера',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18,
                        color: Colors.white.withValues(alpha: 0.5)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (hostName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  hostName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Local network
              if (localIp != null) ...[
                Text(
                  'Локальна мережа (WiFi)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                _CopyableUrl(
                  icon: Icons.wifi,
                  label: '$localIp:$port',
                  copyValue: localIp,
                  hint: 'Хост для iPhone в тій самій мережі',
                ),
                const SizedBox(height: 16),
              ],

              // Tunnel (remote)
              if (tunnel != null) ...[
                Text(
                  'Віддалений доступ (з будь-якої мережі)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                _CopyableUrl(
                  icon: Icons.cloud_outlined,
                  iconColor: const Color(0xFF4ADE80),
                  label: tunnel.replaceFirst('wss://', ''),
                  copyValue: tunnel.replaceFirst('wss://', ''),
                  hint: 'Хост для iPhone з іншої мережі',
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_outlined, size: 14,
                          color: Colors.white.withValues(alpha: 0.25)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tunnel не активний. Встановіть cloudflared для віддаленого доступу.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              // Instructions
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C0D1).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF00C0D1).withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  'На iPhone: відкрий PixelCode → + Сесія → '
                  'сервер з\'явиться автоматично (в одній WiFi) '
                  'або вставь хост вручну.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    height: 1.4,
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

class _CopyableUrl extends StatelessWidget {
  const _CopyableUrl({
    required this.icon,
    required this.label,
    required this.copyValue,
    required this.hint,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String copyValue;
  final String hint;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: copyValue));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Скопійовано'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16,
                color: iconColor ?? const Color(0xFF00C0D1).withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    hint,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 14,
                color: Colors.white.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Mobile: compact dropdown (same style as before)
// ═══════════════════════════════════════════════════════════════════════════════

class _MobileSessionPicker extends ConsumerWidget {
  const _MobileSessionPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final connAsync = ref.watch(connectionStatusProvider);
    final connected = connAsync.valueOrNull ?? false;

    final profiles = session.profiles;
    final active = session.activeProfile;

    if (profiles.isEmpty) {
      return _MobileAddButton(onTap: () => _openAddDialog(context, ref));
    }

    return GestureDetector(
      onTap: () => _showMenu(context, ref, profiles, session.activeProfileId),
      child: Container(
        height: 28,
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
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                active?.name ?? 'Немає сесії',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
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

  Future<void> _openAddDialog(BuildContext context, WidgetRef ref) async {
    final profile = await showSessionFormDialog(context);
    if (profile != null) {
      await ref.read(sessionProvider.notifier).addProfile(profile);
    }
  }

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    List<SessionProfile> profiles,
    String? activeProfileId,
  ) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final tunnelUrl = ref.read(tunnelUrlProvider);

    final result = await showMenu<String>(
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
        for (final p in profiles)
          PopupMenuItem(
            value: 'select:${p.id}',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.id == activeProfileId
                        ? const Color(0xFF4ADE80)
                        : Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.name,
                    style: TextStyle(
                      color: p.id == activeProfileId
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.55),
                      fontSize: 13,
                      fontWeight: p.id == activeProfileId
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (tunnelUrl != null) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'tunnel',
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.cloud_outlined, size: 14,
                    color: const Color(0xFF4ADE80).withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tunnelUrl.replaceFirst('wss://', ''),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.copy_rounded, size: 12,
                    color: Colors.white.withValues(alpha: 0.3)),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'reconnect',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: _ContextMenuItem(
            icon: Icons.refresh_rounded,
            label: 'Перепідключити',
          ),
        ),
        PopupMenuItem(
          value: 'add',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: _ContextMenuItem(
            icon: Icons.add_rounded,
            label: 'Додати сесію',
          ),
        ),
      ],
    );

    if (result == null || !context.mounted) return;

    if (result.startsWith('select:')) {
      final id = result.substring(7);
      if (id != activeProfileId) {
        await ref.read(sessionProvider.notifier).setActive(id);
        final p = ref.read(sessionProvider).profiles.firstWhere((p) => p.id == id);
        await ref.read(wsServiceProvider).connect(url: p.wsUrl);
      }
    } else if (result == 'tunnel') {
      await Clipboard.setData(ClipboardData(text: tunnelUrl ?? ''));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL скопійовано'), duration: Duration(seconds: 2)),
        );
      }
    } else if (result == 'reconnect') {
      final profile = ref.read(sessionProvider).activeProfile;
      if (profile != null) {
        await ref.read(wsServiceProvider).reconnect(url: profile.wsUrl);
      }
    } else if (result == 'add') {
      if (context.mounted) await _openAddDialog(context, ref);
    }
  }
}

class _MobileAddButton extends StatelessWidget {
  const _MobileAddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(left: 6, right: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF00C0D1).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF00C0D1).withValues(alpha: 0.4),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 14, color: Color(0xFF00C0D1)),
            SizedBox(width: 4),
            Text(
              'Сесія',
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
}
