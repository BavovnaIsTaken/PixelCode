/// Overlay banner shown when this device is in viewer or takeover-pending mode.
///
/// ROOT-CAUSE NOTE: SessionBanner is a direct child of the Stack inside
/// _buildOffice(). That Stack has StackFit.loose (default) and sits inside
/// Column → Expanded, which gives loose cross-axis constraints (minWidth = 0).
///
/// Flutter sizes a loose Stack to the largest of its NON-positioned children.
/// If any non-positioned child is 0×0, the Stack width collapses to 0 and
/// the Positioned canvas becomes invisible.
///
/// Fix: SessionBanner.build() ALWAYS returns a Positioned widget so the Stack
/// has zero non-positioned children and always sizes to constraints.biggest.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/game_session_provider.dart';

class SessionBanner extends ConsumerWidget {
  const SessionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(gameSessionProvider);

    // Resolve the content to show (or nothing).
    Widget content = switch (session.mode) {
      GameSessionMode.viewer => _ViewerContent(
          primaryDevice: session.primaryDevice ?? 'інший пристрій',
          onTakeover: () => ref.read(gameSessionProvider.notifier).claimSession(),
        ),
      GameSessionMode.takeoverPending => const _TakeoverPendingContent(),
      GameSessionMode.primary || GameSessionMode.sole => session.takeoverRequestFrom != null
          ? _TakeoverRequestContent(
              fromDevice: session.takeoverRequestFrom!,
              onYield: () => ref.read(gameSessionProvider.notifier).releaseSession(),
              onDismiss: () => ref.read(gameSessionProvider.notifier).dismissTakeoverRequest(),
            )
          : const SizedBox.shrink(),
      GameSessionMode.offline => const SizedBox.shrink(),
    };

    // ALWAYS wrap in Positioned — even when content is SizedBox.shrink().
    // A Positioned with a 0×0 child takes zero hit-test area and is invisible,
    // but keeps the Stack free of non-positioned children so it never collapses.
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(child: content),
    );
  }
}

// ─── Viewer content ───────────────────────────────────────────────────────────

class _ViewerContent extends StatelessWidget {
  final String primaryDevice;
  final VoidCallback onTakeover;

  const _ViewerContent({required this.primaryDevice, required this.onTakeover});

  @override
  Widget build(BuildContext context) {
    return _BannerCard(
      color: const Color(0xCC1A1A2E),
      borderColor: const Color(0xFF4A90D9),
      children: [
        const Icon(Icons.visibility_rounded, size: 14, color: Color(0xFF4A90D9)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Перегляд з $primaryDevice',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onTakeover,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90D9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Перебрати',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Takeover pending content ─────────────────────────────────────────────────

class _TakeoverPendingContent extends StatelessWidget {
  const _TakeoverPendingContent();

  @override
  Widget build(BuildContext context) {
    return const _BannerCard(
      color: Color(0xCC1A1A2E),
      borderColor: Color(0xFFE8A838),
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation(Color(0xFFE8A838)),
          ),
        ),
        SizedBox(width: 8),
        Text(
          'Передача сесії…',
          style: TextStyle(
            color: Color(0xFFE8A838),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ─── Takeover request content (shown to primary) ──────────────────────────────

class _TakeoverRequestContent extends StatelessWidget {
  final String fromDevice;
  final VoidCallback onYield;
  final VoidCallback onDismiss;

  const _TakeoverRequestContent({
    required this.fromDevice,
    required this.onYield,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return _BannerCard(
      color: const Color(0xCC1A1A2E),
      borderColor: const Color(0xFFE8A838),
      children: [
        const Icon(Icons.swap_horiz_rounded, size: 14, color: Color(0xFFE8A838)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$fromDevice хоче перебрати',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onYield,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE8A838),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Передати',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onDismiss,
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white38),
        ),
      ],
    );
  }
}

// ─── Shared card ─────────────────────────────────────────────────────────────

class _BannerCard extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final List<Widget> children;

  const _BannerCard({
    required this.color,
    required this.borderColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
