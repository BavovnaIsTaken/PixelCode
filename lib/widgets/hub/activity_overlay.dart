/// Bottom-edge peek button + draggable sheet that hosts the three telemetry
/// panels (Team Metrics, Comm Graph, Activity Log).
///
/// The sheet is invoked via [showAppBottomSheet], which gives us the standard
/// PixelCode modal bottom-sheet pattern: scrim, theme-aware surface colour,
/// side margins on wide viewports, drag handle, slide-up animation. Same
/// pattern as the Roster "Пам'ять агента" sheet — no second implementation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../providers/agent_provider.dart';
import '../../providers/build_mode_provider.dart';
import 'app_bottom_sheet.dart';
import 'bottom_notch_painter.dart';
import 'office_telemetry_panels.dart';

// ─── Peek button (bottom notch) ─────────────────────────────────────────────

/// Pulsing-dot threshold — a new activity event within this window flips the
/// indicator on. Matches the "is the team busy right now" mental model the
/// game-designer specced (≈recent past, not an all-time counter).
const _kLiveWindow = Duration(seconds: 60);

class ActivityPeekButton extends ConsumerStatefulWidget {
  final VoidCallback onTap;

  /// Whether the host knows the sheet is currently open. Drives the icon
  /// swap. The host owns this because `showModalBottomSheet` returns a Future
  /// resolved on dismiss — the host wires that to a `setState`.
  final bool isOpen;

  const ActivityPeekButton({
    super.key,
    required this.onTap,
    this.isOpen = false,
  });

  @override
  ConsumerState<ActivityPeekButton> createState() =>
      _ActivityPeekButtonState();
}

class _ActivityPeekButtonState extends ConsumerState<ActivityPeekButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide while the player is in Build Mode — BuildMenu owns the bottom edge
    // there (kBottomSheetHeight=200 sheet on narrow viewports, chat slot on
    // wide), and two affordances stacked at the bottom create thumb-conflict.
    final inBuildMode =
        ref.watch(buildModeProvider.select((m) => m.active));

    final events = ref.watch(activityLogProvider);
    final now = DateTime.now();
    final recentCount = events
        .where((e) => now.difference(e.timestamp) <= _kLiveWindow)
        .length;
    final hasLive = recentCount > 0;

    final tc = context.appColors;

    return IgnorePointer(
      ignoring: inBuildMode,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: inBuildMode ? 0 : 1,
        child: SizedBox(
          width: 210,
          height: 28,
          child: CustomPaint(
            painter: BottomNotchPainter(
              fillColor: tc.surface,
              strokeColor: tc.divider,
              bottomBarInset: 24,
              flareRadius: 14,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isOpen
                                ? Icons.expand_more
                                : Icons.monitor_heart_outlined,
                            size: 13,
                            color: widget.isOpen
                                ? tc.accent
                                : tc.textMedium,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Активність',
                            style: TextStyle(
                              color: widget.isOpen
                                  ? tc.accent
                                  : tc.textMedium,
                              fontSize: 11,
                              fontWeight: widget.isOpen
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          if (hasLive) ...[
                            const SizedBox(width: 8),
                            _PulsingDot(
                              animation: _pulse,
                              color: tc.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$recentCount',
                              style: TextStyle(
                                color: tc.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _PulsingDot({required this.animation, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        // 1.0 → 1.4 scale, 0.85 → 0.5 alpha. Curve eased so the dot never
        // sits at full intensity, which would compete with the row text.
        final t = Curves.easeInOut.transform(animation.value);
        final scale = 1.0 + 0.4 * t;
        final alpha = 0.5 + 0.35 * (1 - t);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: alpha),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// ─── Sheet body ─────────────────────────────────────────────────────────────

/// Opens the activity overlay as a standard modal bottom sheet. Returns the
/// `Future` from [showAppBottomSheet] so the caller can flip its `isOpen`
/// flag when the sheet is dismissed.
Future<void> showActivityOverlay(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    initialSize: 0.55,
    minSize: 0.3,
    maxSize: 0.92,
    maxWidth: 900,
    showCloseButton: true,
    builder: (ctx, scrollController) =>
        ActivityOverlayBody(scrollController: scrollController),
  );
}

class ActivityOverlayBody extends ConsumerWidget {
  final ScrollController scrollController;

  const ActivityOverlayBody({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(metricsProvider);
    final activityLog = ref.watch(activityLogProvider);
    final commEvents = ref.watch(commGraphProvider);
    final tc = context.appColors;

    final isEmpty =
        metrics.isEmpty && activityLog.isEmpty && commEvents.isEmpty;

    return SingleChildScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEmpty)
            // Reading-width pattern (Material 3): cap the text column instead
            // of scaling padding. 480px ≈ 65 chars at fontSize 12 — comfy
            // single-paragraph width. On phones (< ~528px) the cap is wider
            // than the sheet, so the inner 24px padding takes over; on
            // desktop the column stays bounded and the side margin grows.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 48),
                  child: Text(
                    'Немає активності — запусти задачу, і тут зʼявляться '
                    'метрики, комунікації між агентами та журнал подій.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: tc.textLow,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            )
          else ...[
            if (metrics.isNotEmpty) TeamMetricsBar(metrics: metrics),
            if (commEvents.isNotEmpty) CommGraphPanel(events: commEvents),
            ActivityLogPanel(
              events: activityLog,
              fillHeight: false,
              onClear: () =>
                  ref.read(activityLogProvider.notifier).clear(),
            ),
          ],
        ],
      ),
    );
  }
}
