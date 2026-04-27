/// Self-Play Training Progress Widget — shows agent training progress and stats improvements.
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';

class SelfPlayProgressWidget extends StatelessWidget {
  final String agentId;
  final String agentName;
  final int completedRuns;
  final int totalRuns;
  final AgentGameData? beforeStats;
  final AgentGameData? afterStats;
  final bool isTraining;
  final VoidCallback? onCancel;

  const SelfPlayProgressWidget({
    required this.agentId,
    required this.agentName,
    required this.completedRuns,
    required this.totalRuns,
    this.beforeStats,
    this.afterStats,
    this.isTraining = false,
    this.onCancel,
    super.key,
  });

  double get _progressPercent =>
      totalRuns > 0 ? (completedRuns / totalRuns).clamp(0.0, 1.0) : 0.0;

  String get _statusMessage {
    if (isTraining && completedRuns < totalRuns) {
      return 'Training in progress...';
    }
    if (completedRuns >= totalRuns) {
      return 'Training complete! ✓';
    }
    return 'Ready to train';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        border: Border.all(
          color: Colors.purple.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Self-Play Training',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),

          // Agent name
          Text(
            'Agent: $agentName',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),

          // Progress display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: theme.textTheme.labelMedium,
              ),
              Text(
                '$completedRuns / $totalRuns runs',
                key: const Key('progress-counter'),
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const Key('progress-bar'),
              value: _progressPercent,
              minHeight: 8,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                isTraining && completedRuns < totalRuns
                    ? Colors.orange
                    : Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Status message
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _statusMessage,
              key: const Key('status-message'),
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 16),

          // Before/After stats
          if (beforeStats != null && afterStats != null) ...[
            Text(
              'Stats Improvement',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatComparison(
                  label: 'Level',
                  before: beforeStats!.level,
                  after: afterStats!.level,
                ),
                _StatComparison(
                  label: 'Avg Skill',
                  before: beforeStats!.avgSkill,
                  after: afterStats!.avgSkill,
                ),
                _StatComparison(
                  label: 'XP',
                  before: beforeStats!.xp,
                  after: afterStats!.xp,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Cancel button (only show if training)
          if (isTraining && onCancel != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('cancel-training'),
                onPressed: onCancel,
                child: const Text('Cancel Training'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatComparison extends StatelessWidget {
  final String label;
  final num before;
  final num after;

  const _StatComparison({
    required this.label,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final improvement = after - before;
    final isImproved = improvement > 0;

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '$before → $after',
          key: Key('stat-$label'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: isImproved ? Colors.green : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (improvement != 0) ...[
          const SizedBox(height: 2),
          Text(
            '${isImproved ? '+' : ''}${improvement.toInt()}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isImproved ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}
