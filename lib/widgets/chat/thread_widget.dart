import 'package:flutter/material.dart';

import '../../models/agent_message.dart';
import 'chat_grouping.dart';

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
        child: SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: Colors.white.withValues(alpha: 0.12)),
              Expanded(
                child: Container(
                  color: Colors.white.withValues(alpha: 0.02),
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

class _ThreadTileState extends State<ThreadTile> {
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = !widget.messages.any((m) => m.category == MessageCategory.awaitingReply);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        // Non-uniform border is valid here because borderRadius lives on
        // ClipRRect, not on the BoxDecoration below.
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: Border(
              left: BorderSide(color: accent, width: 3),
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 48px header
              GestureDetector(
                onTap: () => setState(() => _collapsed = !_collapsed),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
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
                              color: Colors.white.withValues(alpha: 0.75),
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
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _collapsed
                                ? '${widget.messages.length} ↓'
                                : '▲',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
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
              // Expandable content
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: _collapsed
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Column(
                              children: widget.messages
                                  .map(widget.messageBuilder)
                                  .toList(),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _collapsed = true),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.04),
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.expand_less,
                                    size: 13,
                                    color: Colors.white.withValues(alpha: 0.28),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Згорнути',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.28),
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
            ],
          ),
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
  bool _expanded = false;
  late final AnimationController _ctrl;
  late final Animation<double> _sizeFactor;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _sizeFactor = CurvedAnimation(
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
    setState(() => _expanded = true);
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
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _expanded = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.pack.messages;
    final accent = _accent;
    final peekCount = (messages.length - 1).clamp(0, 3);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_expanded)
            _CollapsedDeck(
              messages: messages,
              accent: accent,
              peekCount: peekCount,
              messageBuilder: widget.messageBuilder,
              onTap: _expand,
            )
          else
            _CollapseHandle(accent: accent, count: messages.length, onTap: _collapse),
          SizeTransition(
            sizeFactor: _sizeFactor,
            axisAlignment: -1,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: accent, width: 3),
                  right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: messages.map(widget.messageBuilder).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedDeck extends StatelessWidget {
  final List<ChatMessage> messages;
  final Color accent;
  final int peekCount;
  final Widget Function(ChatMessage) messageBuilder;
  final VoidCallback onTap;

  const _CollapsedDeck({
    required this.messages,
    required this.accent,
    required this.peekCount,
    required this.messageBuilder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Reserve space below the top card for peeking strips.
        padding: EdgeInsets.only(bottom: peekCount * 8.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Peek cards (deepest first in Z-order so top card renders on top).
            ...List.generate(peekCount, (pi) {
              final idx = pi + 1;
              return Positioned(
                bottom: -(idx * 8.0),
                left: idx * 3.0,
                right: idx * 3.0,
                height: 16,
                child: Opacity(
                  opacity: (1.0 - idx * 0.25).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      border: Border(
                        left: BorderSide(
                          color: accent.withValues(alpha: 0.55),
                          width: 3,
                        ),
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        right: BorderSide(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).reversed,
            // Top card (newest message).
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  border: Border(
                    left: BorderSide(color: accent, width: 3),
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                    right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (messages.length >= 2)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '×${messages.length}',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 10,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    messageBuilder(messages.last),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapseHandle extends StatelessWidget {
  final Color accent;
  final int count;
  final VoidCallback onTap;

  const _CollapseHandle({
    required this.accent,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          border: Border(
            left: BorderSide(color: accent, width: 3),
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.expand_less, size: 13, color: accent.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(
              'Згорнути',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Text(
              '$count повідомлень',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.28),
                fontSize: 10,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
