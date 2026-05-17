/// Banner surfaced above the chat when one or more agent runs were promoted
/// to `interrupted` while the client was offline (server respawn, breaker
/// trip, timeout). Reads [agentRunsProvider.interruptedUnacknowledged] and
/// filters to the currently-selected agent so the affordance lands where
/// the user would expect to continue the conversation.
///
/// Why this exists (C.2): "did my work survive the restart?" is the only
/// reconnect question the persistent run store can answer that the chat
/// snapshot alone cannot. Without this banner the interrupted status only
/// shows up in the JSONL store — invisible to the user.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';
import '../../providers/agent_runs_provider.dart';

class InterruptedRunsBanner extends ConsumerWidget {
  const InterruptedRunsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the underlying state so the surface rebuilds when new runs
    // arrive OR when the user acks one (both flip the unmodifiable list).
    ref.watch(agentRunsProvider);
    final notifier = ref.read(agentRunsProvider.notifier);
    final selected = ref.watch(selectedAgentProvider);
    final relevant = notifier.interruptedUnacknowledged
        .where((r) => r.agentId == selected)
        .toList(growable: false);
    if (relevant.isEmpty) return const SizedBox.shrink();
    return _BannerSurface(runs: relevant, notifier: notifier);
  }
}

class _BannerSurface extends StatelessWidget {
  final List<AgentRunSnapshot> runs;
  final AgentRunsNotifier notifier;
  const _BannerSurface({required this.runs, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final count = runs.length;
    // Multi-run wording reads better in Ukrainian as "виконання" (singular,
    // here implicit-collective) — keeps the chip compact without losing
    // accuracy. Number is shown only when > 1 so the common case stays clean.
    final headline = count == 1
        ? 'Виконання перервано — продовжити з історії'
        : 'Перервано $count виконань — переглянути';
    return Material(
      color: const Color(0xFF3A2412),
      child: InkWell(
        onTap: () => _showDetails(context, runs, notifier),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.replay_circle_filled_outlined,
                color: Color(0xFFFFB36F),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: Color(0xFFFFE2C2),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: notifier.ackAll,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFB36F),
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Сховати', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    List<AgentRunSnapshot> runs,
    AgentRunsNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1F1611),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Перервані виконання',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Сервер перезапустився, доки запит виконувався. '
                  'Текст відповіді нижче — те, що встигло згенеруватися.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: runs.length,
                    separatorBuilder: (_, _) => const Divider(
                      color: Colors.white12,
                      height: 18,
                    ),
                    itemBuilder: (_, i) => _RunRow(run: runs[i]),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        notifier.ackAll();
                        Navigator.of(sheetCtx).pop();
                      },
                      child: const Text('Зрозуміло'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RunRow extends StatelessWidget {
  final AgentRunSnapshot run;
  const _RunRow({required this.run});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (run.userMessageSnippet?.isNotEmpty == true)
          Text(
            run.userMessageSnippet!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (run.partialOutput?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              run.partialOutput!,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (run.reason?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(
            'Причина: ${run.reason!}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
