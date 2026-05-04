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

// Blend is 0 at rest (each bubble reads as an independent card) and rises to
// PEAK only during the transition window so bubbles read as drops separating
// from / draining into the header. At rest the metaball bridges would show up
// as bright "thick top borders" on the bubbles below — so they must be off.
const double _kThreadBlendPeak = 28.0;

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
  AnimationStatus _status = AnimationStatus.dismissed;

  bool get _collapsed =>
      _status == AnimationStatus.dismissed ||
      _status == AnimationStatus.reverse;

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
    _ctrl.addStatusListener(_onStatusChanged);
    final hasAwaiting =
        widget.messages.any((m) => m.category == MessageCategory.awaitingReply);
    if (hasAwaiting) {
      _ctrl.value = 1.0;
      _status = _ctrl.status;
    }
  }

  void _onStatusChanged(AnimationStatus s) {
    if (mounted && s != _status) {
      setState(() => _status = s);
    }
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatusChanged);
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

  // Triangle wave (eased) over raw _ctrl.value: 0 → peak at t=0.5 → 0.
  // At rest (dismissed/completed) the controller doesn't tick AND we want
  // bubbles to read as fully separate cards (no metaball bridge between them).
  double _animBlend() {
    if (_status == AnimationStatus.dismissed ||
        _status == AnimationStatus.completed) {
      return 0;
    }
    final t = _ctrl.value;
    final tri = (1.0 - (2 * t - 1).abs()).clamp(0.0, 1.0);
    final eased = Curves.easeInOut.transform(tri);
    return _kThreadBlendPeak * eased;
  }

  // Per-bubble staggered slide+fade. Window starts at index*0.08, spans 60%
  // of the timeline, clamped. Reverse uses easeIn so bubbles drain back into
  // the header bottom-first.
  Widget _bubbleSlot({required int index, required Widget child}) {
    final t = _ctrl.value;
    final reversed = _status == AnimationStatus.reverse;
    final start = (index * 0.08).clamp(0.0, 0.4);
    final end = (start + 0.6).clamp(0.0, 1.0);
    final span = end - start;
    final local = span > 0 ? ((t - start) / span).clamp(0.0, 1.0) : 1.0;
    final curved = reversed
        ? Curves.easeInCubic.transform(local)
        : Curves.easeOutCubic.transform(local);
    return Opacity(
      opacity: curved,
      child: FractionalTranslation(
        translation: Offset(0, -1.0 * (1.0 - curved)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final messages = widget.messages;
    final typeDots = _typeDots;
    final title = _title;

    // Pre-build bubble subtrees once per parent rebuild — wrappers (Opacity +
    // FractionalTranslation) recreate each frame, but Flutter's reconciler
    // sees identical bubble widget instances and reuses them without
    // re-running messageBuilder.
    final List<Widget> bubbles = [
      for (var i = 0; i < messages.length; i++)
        LiquidGlass.grouped(
          shape: const LiquidRoundedSuperellipse(borderRadius: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: widget.messageBuilder(messages[i]),
          ),
        ),
    ];

    final Widget collapseStrip = GestureDetector(
      onTap: _collapseAndAnchor,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.expand_less,
              size: 13,
              color: Colors.white.withValues(alpha: 0.40),
            ),
            const SizedBox(width: 4),
            Text(
              'Згорнути',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );

    // Header is always 48px tall — fixed height lets us anchor the body
    // beneath it via Padding + Stack ordering instead of Column ordering.
    const double headerHeight = 48;

    final Widget header = LiquidGlass.grouped(
      shape: const LiquidRoundedSuperellipse(borderRadius: 10),
      child: GestureDetector(
        onTap: () => _collapsed ? _expand() : _collapseAndAnchor(),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: headerHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    title,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                ...typeDots.map(
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
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _collapsed ? '${messages.length} ↓' : '▲',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
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
    );

    return Padding(
      key: _tileKey,
      padding: const EdgeInsets.only(bottom: 16),
      child: LiquidGlassLayer(
        settings: _kThreadGlassSettings,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => LiquidGlassBlendGroup(
            blend: _animBlend(),
            child: child!,
          ),
          // Stack instead of Column forces paint order: body painted FIRST
          // (back), header painted LAST (front). On iOS Impeller the
          // ClipRect inside SizeTransition doesn't strictly clip
          // LiquidGlass shader output during animation — translated bubbles
          // could overlap the header. Stack-based z-order is the
          // platform-independent fix because it doesn't depend on shader
          // clipping behavior.
          child: Stack(
            alignment: AlignmentDirectional.topCenter,
            children: [
              if (_status != AnimationStatus.dismissed)
                Padding(
                  padding: const EdgeInsets.only(top: headerHeight),
                  child: SizeTransition(
                    axisAlignment: -1.0,
                    sizeFactor: _t,
                    child: ClipRect(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 6),
                        child: AnimatedBuilder(
                          animation: _ctrl,
                          builder: (context, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < bubbles.length; i++) ...[
                                if (i > 0) const SizedBox(height: 6),
                                _bubbleSlot(index: i, child: bubbles[i]),
                              ],
                              const SizedBox(height: 6),
                              collapseStrip,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              header,
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

  /// Builds the static-size preview shown on the top card while collapsed.
  /// Should return a bubble clamped to a few lines with ellipsis.
  final Widget Function(ChatMessage) previewMessageBuilder;

  const PackTile({
    super.key,
    required this.pack,
    required this.messageBuilder,
    required this.previewMessageBuilder,
  });

  @override
  State<PackTile> createState() => _PackTileState();
}

class _PackTileState extends State<PackTile> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _t;
  AnimationStatus _status = AnimationStatus.dismissed;

  bool get _collapsed =>
      _status == AnimationStatus.dismissed ||
      _status == AnimationStatus.reverse;

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
    _ctrl.addStatusListener(_onStatusChanged);
  }

  void _onStatusChanged(AnimationStatus s) {
    if (mounted && s != _status) {
      setState(() => _status = s);
    }
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatusChanged);
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

  double _animBlend() {
    if (_status == AnimationStatus.dismissed ||
        _status == AnimationStatus.completed) {
      return 0;
    }
    final t = _ctrl.value;
    final tri = (1.0 - (2 * t - 1).abs()).clamp(0.0, 1.0);
    final eased = Curves.easeInOut.transform(tri);
    return _kThreadBlendPeak * eased;
  }

  Widget _bubbleSlot({required int index, required Widget child}) {
    final t = _ctrl.value;
    final reversed = _status == AnimationStatus.reverse;
    final start = (index * 0.08).clamp(0.0, 0.4);
    final end = (start + 0.6).clamp(0.0, 1.0);
    final span = end - start;
    final local = span > 0 ? ((t - start) / span).clamp(0.0, 1.0) : 1.0;
    final curved = reversed
        ? Curves.easeInCubic.transform(local)
        : Curves.easeOutCubic.transform(local);
    return Opacity(
      opacity: curved,
      child: FractionalTranslation(
        translation: Offset(0, -1.0 * (1.0 - curved)),
        child: child,
      ),
    );
  }

  // Inner header content (without the LiquidGlass shell). Used twice in
  // build(): once as a hidden phantom inside the layout Column to reserve
  // vertical space, and once as the real (LiquidGlass-wrapped) overlay. This
  // duplication is what lets us put the real header on TOP of the body in
  // Stack paint order while the body still measures itself correctly.
  Widget _buildInnerHeader(Color accent) {
    final messages = widget.pack.messages;
    return GestureDetector(
      onTap: () => _collapsed ? _expand() : _collapse(),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: KeyedSubtree(
                key: ValueKey<bool>(_collapsed),
                child: _collapsed
                    ? widget.previewMessageBuilder(messages.last)
                    : widget.messageBuilder(messages.last),
              ),
            ),
            if (messages.length >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 10, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(8),
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
                      color: accent.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.pack.messages;
    final accent = _accent;

    final List<Widget> olderBubbles = [
      for (var i = 0; i < messages.length - 1; i++)
        LiquidGlass.grouped(
          shape: const LiquidRoundedSuperellipse(borderRadius: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: widget.messageBuilder(messages[i]),
          ),
        ),
    ];

    final Widget collapseStrip = GestureDetector(
      onTap: _collapse,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 24,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.expand_less,
              size: 13,
              color: accent.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              'Згорнути',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );

    // Phantom header reserves the same vertical layout space as the real
    // header but is not painted (Visibility.visible == false) and not
    // hit-tested (IgnorePointer). The real header is overlaid via Stack so
    // its paint order is AFTER the body — the body's translated bubbles
    // can't end up on top of it on iOS regardless of LiquidGlass shader
    // clipping behavior.
    final Widget phantomHeader = IgnorePointer(
      child: Visibility(
        visible: false,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: _buildInnerHeader(accent),
      ),
    );

    final Widget realHeader = LiquidGlass.grouped(
      shape: const LiquidRoundedSuperellipse(borderRadius: 12),
      child: _buildInnerHeader(accent),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LiquidGlassLayer(
        settings: _kThreadGlassSettings,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => LiquidGlassBlendGroup(
            blend: _animBlend(),
            child: child!,
          ),
          child: Stack(
            fit: StackFit.passthrough,
            alignment: AlignmentDirectional.topCenter,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  phantomHeader,
                  if (_status != AnimationStatus.dismissed)
                    SizeTransition(
                      axisAlignment: -1.0,
                      sizeFactor: _t,
                      child: ClipRect(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 6),
                          child: AnimatedBuilder(
                            animation: _ctrl,
                            builder: (context, _) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < olderBubbles.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 6),
                                  _bubbleSlot(index: i, child: olderBubbles[i]),
                                ],
                                const SizedBox(height: 6),
                                collapseStrip,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              realHeader,
            ],
          ),
        ),
      ),
    );
  }
}
