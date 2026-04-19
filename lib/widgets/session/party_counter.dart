/// "Party counter" — RPG-style connected devices indicator for the title bar.
///
/// Shows a pixel-person icon + device count. Clicking opens a popover with
/// devices grouped into "This device" (server host machine) and "Other devices".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../providers/agent_provider.dart';
import '../../providers/connected_devices_provider.dart';

class PartyCounter extends ConsumerStatefulWidget {
  const PartyCounter({super.key});

  @override
  ConsumerState<PartyCounter> createState() => _PartyCounterState();
}

class _PartyCounterState extends ConsumerState<PartyCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _bounceAnim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -2), weight: 40),
    TweenSequenceItem(tween: Tween(begin: -2, end: 0), weight: 60),
  ]).animate(CurvedAnimation(parent: _bounceCtrl, curve: Curves.easeOut));

  int _prevCount = 0;
  OverlayEntry? _popover;

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _removePopover();
    super.dispose();
  }

  void _removePopover() {
    _popover?.remove();
    _popover = null;
  }

  void _togglePopover() {
    if (_popover != null) {
      _removePopover();
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _popover = OverlayEntry(
      builder: (_) => _DevicesPopover(
        anchor: Offset(offset.dx, offset.dy + size.height + 4),
        onDismiss: _removePopover,
      ),
    );
    Overlay.of(context).insert(_popover!);
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(connectedDevicesProvider);
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;
    final count = clients.length;

    // Bounce animation on count change
    if (count != _prevCount && count > _prevCount && _prevCount > 0) {
      _bounceCtrl.forward(from: 0);
    }
    _prevCount = count;

    // Hide when disconnected or no clients
    if (!isConnected || count == 0) return const SizedBox.shrink();

    final showCount = count >= 2;
    final isMultiplayer = count >= 2;
    // Session tab accent color (green for connected)
    const activeColor = Color(0xFF4ADE80);
    final dimColor = activeColor.withValues(alpha: 0.4);

    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _bounceAnim.value),
        child: child,
      ),
      child: Tooltip(
        message: count == 1
            ? 'Тільки ви на цій сесії'
            : '$count пристроїв підключено',
        waitDuration: const Duration(milliseconds: 500),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _togglePopover,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cable,
                    size: 14,
                    color: isMultiplayer ? activeColor : dimColor,
                  ),
                  // Count (only when 2+)
                  if (showCount) ...[
                    const SizedBox(width: 3),
                    Text(
                      count > 9 ? '9+' : '$count',
                      style: TextStyle(
                        color: isMultiplayer
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Devices popover ─────────────────────────────────────────────────────────

class _DevicesPopover extends ConsumerStatefulWidget {
  const _DevicesPopover({required this.anchor, required this.onDismiss});

  final Offset anchor;
  final VoidCallback onDismiss;

  @override
  ConsumerState<_DevicesPopover> createState() => _DevicesPopoverState();
}

class _DevicesPopoverState extends ConsumerState<_DevicesPopover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  )..forward();

  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    // Update durations every 30s while open
    _durationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (mounted) setState(() {}); },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(connectedDevicesProvider);
    final notifier = ref.read(connectedDevicesProvider.notifier);
    final ownId = notifier.ownClientId;
    final serverInfo = ref.watch(serverInfoProvider);
    final tc = context.appColors;

    final hostMachineDevices = clients.where((c) => c.isHostMachine).toList();
    final remoteDevices = clients.where((c) => !c.isHostMachine).toList()
      ..sort((a, b) {
        if (a.clientId == ownId) return -1;
        if (b.clientId == ownId) return 1;
        return 0;
      });

    return Stack(
      children: [
        // Dismiss layer
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
          ),
        ),
        // Popover
        Positioned(
          left: widget.anchor.dx - 140,
          top: widget.anchor.dy,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final t = Curves.easeOut.transform(_ctrl.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, -4 * (1 - t)),
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 300,
                decoration: BoxDecoration(
                  color: tc.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: tc.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Row(
                        children: [
                          Text(
                            'Підключені пристрої',
                            style: TextStyle(
                              color: tc.textMedium,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${clients.length}',
                            style: TextStyle(
                              color: tc.textLow,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: tc.divider),
                    // Host machine section
                    if (hostMachineDevices.isNotEmpty ||
                        serverInfo != null) ...[
                      _SectionHeader(
                        label: 'Цей пристрій (сервер)',
                        colors: tc,
                      ),
                      if (hostMachineDevices.isEmpty && serverInfo != null)
                        _ServerOnlyRow(
                          deviceName: serverInfo.hostname,
                          colors: tc,
                        )
                      else
                        for (final client in hostMachineDevices)
                          _ClientRow(
                            client: client,
                            isOwn: client.clientId == ownId,
                            showServerBadge: true,
                          ),
                    ],
                    // Remote devices section
                    if (remoteDevices.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Інші пристрої',
                        colors: tc,
                      ),
                      for (final client in remoteDevices)
                        _ClientRow(
                          client: client,
                          isOwn: client.clientId == ownId,
                          showServerBadge: false,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.colors});

  final String label;
  final ThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: colors.textLow,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Server-only row (host machine runs server but no loopback client) ───────

class _ServerOnlyRow extends StatelessWidget {
  const _ServerOnlyRow({required this.deviceName, required this.colors});

  final String deviceName;
  final ThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, size: 14, color: colors.textLow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              deviceName.isEmpty ? 'Сервер' : deviceName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textMedium, fontSize: 12),
            ),
          ),
          Text(
            'сервер',
            style: TextStyle(
              color: colors.textLow,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single client row ───────────────────────────────────────────────────────

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    required this.client,
    required this.isOwn,
    required this.showServerBadge,
  });

  final ConnectedClient client;
  final bool isOwn;

  /// If true, this row is in the "host machine" section and gets a
  /// "сервер + клієнт" badge instead of the usual platform label.
  final bool showServerBadge;

  IconData get _platformIcon => switch (client.platform) {
        'macos' || 'linux' || 'windows' => Icons.desktop_mac_outlined,
        'ios' => Icons.phone_iphone,
        'android' => Icons.phone_android,
        'web' => Icons.language,
        _ => Icons.devices_other,
      };

  String get _durationLabel {
    final diff = DateTime.now().difference(client.connectedAt);
    if (diff.inSeconds < 60) return 'щойно';
    if (diff.inMinutes < 60) return '${diff.inMinutes}хв';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (m == 0) return '$hгод';
    return '$hгод $mхв';
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;
    const accent = Color(0xFF4ADE80);

    final primary = client.displayName;
    final showSubtitle =
        client.nickname.isNotEmpty && client.deviceName.isNotEmpty &&
            client.nickname != client.deviceName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isOwn ? accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            _platformIcon,
            size: 14,
            color: isOwn ? tc.textHigh : tc.textLow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: isOwn ? tc.textHigh : tc.textMedium,
                    fontSize: 12,
                    fontWeight: isOwn ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (showSubtitle)
                  Text(
                    client.deviceName,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: tc.textLow,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (showServerBadge)
            Text(
              'сервер + клієнт',
              style: TextStyle(
                color: accent.withValues(alpha: 0.9),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          const SizedBox(width: 8),
          Text(
            _durationLabel,
            style: TextStyle(
              color: tc.textLow,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
