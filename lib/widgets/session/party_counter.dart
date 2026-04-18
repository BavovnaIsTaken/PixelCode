/// "Party counter" — RPG-style connected devices indicator for the title bar.
///
/// Shows a pixel-person icon + device count. Clicking opens a popover with
/// device details (hostname, platform, duration, role).
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
                  // Pixel person icon
                  _PixelPersonIcon(
                    color: isMultiplayer ? activeColor : dimColor,
                    size: 12,
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

// ─── Pixel person icon (12x12 hand-drawn) ────────────────────────────────────

class _PixelPersonIcon extends StatelessWidget {
  const _PixelPersonIcon({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _PixelPersonPainter(color: color),
      ),
    );
  }
}

class _PixelPersonPainter extends CustomPainter {
  _PixelPersonPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final px = size.width / 8; // 8x8 grid

    // Head (2x2 centered)
    canvas.drawRect(Rect.fromLTWH(3 * px, 0, 2 * px, 2 * px), p);
    // Neck
    canvas.drawRect(Rect.fromLTWH(3.5 * px, 2 * px, px, px), p);
    // Shoulders + body (4 wide)
    canvas.drawRect(Rect.fromLTWH(2 * px, 3 * px, 4 * px, px), p);
    // Torso (2 wide centered)
    canvas.drawRect(Rect.fromLTWH(3 * px, 4 * px, 2 * px, 2 * px), p);
    // Arms
    canvas.drawRect(Rect.fromLTWH(1 * px, 3 * px, px, 2 * px), p);
    canvas.drawRect(Rect.fromLTWH(6 * px, 3 * px, px, 2 * px), p);
    // Legs
    canvas.drawRect(Rect.fromLTWH(3 * px, 6 * px, px, 2 * px), p);
    canvas.drawRect(Rect.fromLTWH(4 * px, 6 * px, px, 2 * px), p);
  }

  @override
  bool shouldRepaint(_PixelPersonPainter old) => old.color != color;
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
    final ownId = ref.read(connectedDevicesProvider.notifier).ownClientId;
    final tc = context.appColors;

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
                width: 280,
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
                    // Client rows
                    for (final client in clients)
                      _ClientRow(
                        client: client,
                        isOwn: client.clientId == ownId,
                      ),
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

// ─── Single client row ───────────────────────────────────────────────────────

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.isOwn});

  final ConnectedClient client;
  final bool isOwn;

  IconData get _platformIcon => switch (client.platform) {
        'macos' || 'linux' || 'windows' => Icons.desktop_mac_outlined,
        'ios' => Icons.phone_iphone,
        'android' => Icons.phone_android,
        'web' => Icons.language,
        _ => Icons.devices_other,
      };

  String get _roleLabel => client.isLocal ? 'host' : 'remote';

  String get _durationLabel {
    final diff = DateTime.now().difference(client.connectedAt);
    if (diff.inSeconds < 60) return 'щойно';
    if (diff.inMinutes < 60) return '${diff.inMinutes}хв';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    // ignore: unnecessary_brace_in_string_interps
    if (m == 0) return '${h}год';
    return '$hгод $mхв';
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;
    const accent = Color(0xFF4ADE80);

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
        children: [
          // Platform icon
          Icon(
            _platformIcon,
            size: 14,
            color: isOwn ? tc.textHigh : tc.textLow,
          ),
          const SizedBox(width: 8),
          // Hostname
          Expanded(
            child: Text(
              client.hostname,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: isOwn ? tc.textHigh : tc.textMedium,
                fontSize: 12,
                fontWeight: isOwn ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Role badge
          Text(
            _roleLabel,
            style: TextStyle(
              color: tc.textLow,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Duration
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
