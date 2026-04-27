/// Consent flow for agent learning/lesson recording.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for agent learning consent state.
final agentConsentProvider =
    StateProvider.family<bool, String>((ref, agentId) => true);

class ConsentFlowWidget extends ConsumerWidget {
  final String agentId;
  final String agentName;
  final VoidCallback? onConsentChanged;

  const ConsentFlowWidget({
    required this.agentId,
    required this.agentName,
    this.onConsentChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consentState = ref.watch(agentConsentProvider(agentId));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: consentState ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
        border: Border.all(
          color:
              consentState ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Learning Recording',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Allow $agentName to learn from its experiences',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: consentState,
                onChanged: (newValue) {
                  ref.read(agentConsentProvider(agentId).notifier).state =
                      newValue;
                  onConsentChanged?.call();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              consentState
                  ? '✓ Lessons are being recorded. The agent will improve over time.'
                  : '✗ Lessons are not being recorded. The agent will not learn from this session.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
