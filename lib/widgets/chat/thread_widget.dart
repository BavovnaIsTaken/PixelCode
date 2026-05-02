import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../models/agent_message.dart';
import 'chat_grouping.dart';

const double _kGlassSigma = 18.0;

const _kThreadGlassSettings = LiquidGlassSettings(
  thickness: 24,
  blur: 12,
  glassColor: Color(0x33FFFFFF),
  lightIntensity: 1.4,
  ambientStrength: 0.6,
  saturation: 1.2,
  refractiveIndex: 1.35,
  chromaticAberration: 0.02,
);

const double _kThreadBlend = 30.0;

// ─── ThreadSkeleton ──────────────────────────────────────────────────────────

/// Fixed-height 48px placeholder inserted while an agent is active but before
/// the first message of a thread arrives. Prevents scroll jumps.
class ThreadSkeleton extends StatelessWidget {
  const ThreadSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _kGlassSigma, sigmaY: _kGlassSigma),
          child: SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: Colors.white.withValues(alpha: 0.12)),
                Expanded(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 100,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 28,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ─── StatusGroupWidget ────────────────────────────────────────────────────────

/// Collapses a run of [MessageCategory.status] messages into a single
/// "N технічних дій" row, expandable on tap.
class StatusGroupWidget extends StatefulWidget {
  final List<ChatMessage> messages;

  const StatusGroupWidget({super.key, required this.messages});

  @override
  State<StatusGroupWidget> createState() => _StatusGroupWidgetState();
}

class _StatusGroupWidgetState extends State<StatusGroupWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.messages.length} технічних дій',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.33),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.messages
                        .map(
                          (msg) => Padding(
                            padding: const EdgeInsets.only(left: 18, bottom: 2),
                            child: Text(
                              msg.text,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.38),
                                fontSize: 11,
                                fontFamily: 'monospace',
                                height: 1.4,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ─── ThreadTile ───────────────────────────────────────────────────────────────

/// A collapsible thread widget. Shows a 48px header when collapsed; expands
/// with an animated slide to show all thread messages rendered by [messageBuilder].
///
/// Threads containing an [MessageCategory.awaitingReply] message start expanded
/// so the user sees the pending question immediately.
class ThreadTile extends StatefulWidget {
  final String threadId;
  final List<ChatMessage> messages;

  /// Called for each message inside the thread. Typically returns a `_ChatBubble`.
  final Widget Function(ChatMessage) messageBuilder;

  const ThreadTile({
    super.key,
    required this.threadId,
    required this.messages,
    required this.messageBuilder,
  });

  @override
  State<ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends State<ThreadTile> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  final _tileKey = GlobalKey();

  bool get _collapsed =>
      _ctrl.status == AnimationStatus.dismissed ||
      _ctrl.status == AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _t = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final hasAwaiting =
        widget.messages.any((m) => m.category == MessageCategory.awaitingReply);
    if (hasAwaiting) _ctrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _expand() {
    _ctrl.forward();
  }

  void _collapseAndAnchor() {
    _ctrl.reverse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: 0.0,
        );
      }
    });
  }

  Color get _accent {
    if (widget.messages.any((m) => m.category == MessageCategory.awaitingReply)) {
      return const Color(0xFF00C0D1);
    }
    if (widget.messages.any((m) => m.category == MessageCategory.taskLinked)) {
      return const Color(0xFFFFC107);
    }
    return Colors.white.withValues(alpha: 0.22);
  }

  String get _title {
    for (final msg in widget.messages) {
      if (msg.category == MessageCategory.status) continue;
      if (msg.category == MessageCategory.taskLinked) continue;
      final t = msg.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (t.isEmpty) continue;
      return t.length > 52 ? '${t.substring(0, 49)}…' : t;
    }
    final first = widget.messages.isNotEmpty ? widget.messages.first.text.trim() : '';
    return first.isEmpty ? 'Тред' : (first.length > 40 ? '${first.substring(0, 37)}…' : first);
  }

  List<Color> get _typeDots {
    final seen = <MessageCategory?>{};
    return widget.messages
        .where((m) => seen.add(m.category))
        .take(3)
        .map((m) => switch (m.category) {
              MessageCategory.awaitingReply => const Color(0xFF00C0D1),
              MessageCategory.status => Colors.white.withValues(alpha: 0.28),
              MessageCategory.taskLinked => const Color(0xFFFFC107),
              MessageCategory.packBreak || null => Colors.white.withValues(alpha: 0.22),
            })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final messages = widget.messages;
    final peekCount = (messages.length - 1).clamp(0, 3);

    return Padding(
      key: _tileKey,
      padding: const EdgeInsets.only(bottom: 8),
      child: LiquidGlassLayer(
        settings: _kThreadGlassSettings,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            // Peek strips visible only at start of expansion; fade out as t→0.4.
            final peekOpacity = (1.0 - (t / 0.4)).clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // ─── Peek strips below header (Stack-positioned, blend-grouped) ───
                if (peekCount > 0 && peekOpacity > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: peekOpacity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: List.generate(peekCount, (pi) {
                            final idx = pi + 1;
                            return Positioned(
                              top: 48.0 - 6.0 + (idx - 1) * 6.0,
                              left: idx * 4.0,
                              right: idx * 4.0,
                              height: 14,
                              child: LiquidGlassBlendGroup(
                                child: LiquidGlass.grouped(
                                  shape: const LiquidRoundedSuperellipse(
                                    borderRadius: 8,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            );
                          }).reversed.toList(),
                        ),
                      ),
                    ),
                  ),
                // ─── Main blend group: header + expanding message column ───
                LiquidGlassBlendGroup(
                  blend: _kThreadBlend,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header card (always visible).
                      LiquidGlass.grouped(
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 8,
                        ),
                        child: GestureDetector(
                          onTap: _collapsed ? _expand : _collapseAndAnchor,
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            height: 48,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.account_tree_outlined,
                                    size: 12,
                                    color: accent.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _title,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.85),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ..._typeDots.map(
                                    (c) => Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(left: 3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: c,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _collapsed
                                          ? '${messages.length} ↓'
                                          : '▲',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.55),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Expanding message column. Each message is its own glass
                      // shape inside the same blend group — when collapsed they
                      // collapse into the header (metaball merge); as height
                      // grows they "drip" out one by one.
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: t,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < messages.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 4),
                                  LiquidGlass.grouped(
                                    shape: const LiquidRoundedSuperellipse(
                                      borderRadius: 8,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      child: widget
                                          .messageBuilder(messages[i]),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: _collapseAndAnchor,
                                  behavior: HitTestBehavior.opaque,
                                  child: SizedBox(
                                    height: 24,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.expand_less,
                                          size: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.40),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Згорнути',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.40),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── PackTile ─────────────────────────────────────────────────────────────────

/// A collapsible deck widget for a [MessagePack].
///
/// Collapsed: shows the newest message as the top card with older messages
/// peeking as thin strips behind it. Tap to expand.
/// Expanded: accordion reveals all messages with an animated [SizeTransition].
class PackTile extends StatefulWidget {
  final MessagePack pack;

  /// Called for each message inside the pack. Typically returns a `_ChatBubble`.
  final Widget Function(ChatMessage) messageBuilder;

  const PackTile({
    super.key,
    required this.pack,
    required this.messageBuilder,
  });

  @override
  State<PackTile> createState() => _PackTileState();
}

class _PackTileState extends State<PackTile> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;

  bool get _collapsed =>
      _ctrl.status == AnimationStatus.dismissed ||
      _ctrl.status == AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _t = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accent {
    final parts = widget.pack.senderId.split(':');
    return agentColorFor(parts.length > 1 ? parts.last : parts.first);
  }

  void _expand() {
    _ctrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _collapse() {
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.pack.messages;
    final accent = _accent;
    final peekCount = (messages.length - 1).clamp(0, 3);

    return Padding(
      padding: EdgeInsets.only(bottom: 8 + (peekCount * 8.0)),
      child: LiquidGlassLayer(
        settings: _kThreadGlassSettings,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            final peekOpacity = (1.0 - (t / 0.4)).clamp(0.0, 1.0);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Peek strips behind top card — solid tinted layers giving the
                // bubble a "stack of cards" depth. Visible only when collapsed.
                if (peekCount > 0 && peekOpacity > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: peekOpacity,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: List.generate(peekCount, (pi) {
                            final idx = pi + 1;
                            return Positioned(
                              bottom: -(idx * 8.0),
                              left: idx * 6.0,
                              right: idx * 6.0,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: accent
                                      .withValues(alpha: 0.10 + idx * 0.03),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).reversed.toList(),
                        ),
                      ),
                    ),
                  ),
                // Main blend group: top card + expanding column of older messages.
                LiquidGlassBlendGroup(
                  blend: _kThreadBlend,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top card (newest message). Always visible.
                      LiquidGlass.grouped(
                        shape: const LiquidRoundedSuperellipse(borderRadius: 12),
                        child: GestureDetector(
                          onTap: _collapsed ? _expand : _collapse,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                widget.messageBuilder(messages.last),
                                if (messages.length >= 2)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        8, 0, 10, 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: accent
                                                .withValues(alpha: 0.28),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '×${messages.length}',
                                            style: TextStyle(
                                              color: accent,
                                              fontSize: 11,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          _collapsed
                                              ? Icons.keyboard_arrow_down
                                              : Icons.keyboard_arrow_up,
                                          size: 14,
                                          color: accent
                                              .withValues(alpha: 0.55),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Older messages spill out of the top card as t→1.
                      ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: t,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < messages.length - 1; i++) ...[
                                  if (i > 0) const SizedBox(height: 4),
                                  LiquidGlass.grouped(
                                    shape: const LiquidRoundedSuperellipse(
                                      borderRadius: 12,
                                    ),
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 4),
                                      child: widget
                                          .messageBuilder(messages[i]),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: _collapse,
                                  behavior: HitTestBehavior.opaque,
                                  child: SizedBox(
                                    height: 24,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.expand_less,
                                          size: 13,
                                          color: accent
                                              .withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Згорнути',
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.45),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
