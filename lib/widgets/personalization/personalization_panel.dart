/// Displays agent lessons, traits, and learning history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_traits_provider.dart';

class PersonalizationPanel extends ConsumerWidget {
  final String agentId;
  final String agentName;

  const PersonalizationPanel({
    required this.agentId,
    required this.agentName,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strengthsAsync =
        ref.watch(agentTraitsByTypeProvider((agentId, TraitType.strength)));
    final weaknessesAsync =
        ref.watch(agentTraitsByTypeProvider((agentId, TraitType.weakness)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agentName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Learning & Traits',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildTraitSection(context, 'Strengths', strengthsAsync,
                    TraitType.strength),
                _buildTraitSection(context, 'Weaknesses', weaknessesAsync,
                    TraitType.weakness),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTraitSection(
    BuildContext context,
    String title,
    AsyncValue<List<AgentTrait>> traitsAsync,
    TraitType type,
  ) {
    return traitsAsync.when(
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Error: $err'),
      ),
      data: (traits) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '$title (${traits.length})',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (traits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'No ${title.toLowerCase()} yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...traits.map((trait) => _buildTraitTile(context, trait)),
        ],
      ),
    );
  }

  Widget _buildTraitTile(BuildContext context, AgentTrait trait) {
    final emphasisColor = switch (trait.emphasis) {
      TraitEmphasis.critical => Colors.red,
      TraitEmphasis.important => Colors.orange,
      TraitEmphasis.note => Colors.grey,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: emphasisColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: emphasisColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trait.tag,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: emphasisColor,
                    ),
              ),
              Text(
                '×${trait.frequency}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            trait.lesson,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Last: ${trait.lastSeen.toString().split('.')[0]}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
          ),
        ],
      ),
    );
  }
}
