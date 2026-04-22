/// Header widget showing daily token budget as a game resource.
///
/// Mirrors real Claude API consumption: total tokens used today (with cap)
/// plus per-tier counters for Opus/Sonnet. When any cap is exceeded the
/// Energy provider silently downgrades the requested model — the meter is
/// the player's signal that this is happening.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/energy_provider.dart';

class EnergyMeter extends ConsumerWidget {
  const EnergyMeter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(energyProvider);
    final ratio = e.tokenUsageRatio;
    final tokenColor = ratio > 0.9
        ? Colors.redAccent
        : ratio > 0.7
            ? Colors.orangeAccent
            : Colors.greenAccent;

    return Tooltip(
      message:
          'Денний ліміт токенів.\nOpus ${e.opusTasksUsedToday}/${e.opusCapPerDay} · '
          'Sonnet ${e.sonnetTasksUsedToday}/${e.sonnetCapPerDay}\n'
          'При вичерпанні тир падає до Haiku.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪫', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 3),
          Text(
            '${_fmtK(e.tokensUsedToday)}/${_fmtK(e.dailyTokenCap)}',
            style: TextStyle(
              color: tokenColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          _TierBadge(
            label: 'O',
            used: e.opusTasksUsedToday,
            cap: e.opusCapPerDay,
            color: const Color(0xFFFFD54F),
          ),
          const SizedBox(width: 3),
          _TierBadge(
            label: 'S',
            used: e.sonnetTasksUsedToday,
            cap: e.sonnetCapPerDay,
            color: const Color(0xFF81D4FA),
          ),
        ],
      ),
    );
  }

  static String _fmtK(int v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return v.toString();
  }
}

class _TierBadge extends StatelessWidget {
  final String label;
  final int used;
  final int cap;
  final Color color;

  const _TierBadge({
    required this.label,
    required this.used,
    required this.cap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final exhausted = used >= cap;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: exhausted ? 0.0 : 0.1),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: exhausted ? 0.25 : 0.45)),
      ),
      child: Text(
        '$label $used/$cap',
        style: TextStyle(
          color: exhausted ? Colors.white.withValues(alpha: 0.3) : color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
