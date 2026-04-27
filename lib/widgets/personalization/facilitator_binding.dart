/// Binds an agent to a facilitator (style/persona).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FacilitatorStyle { default_, technical, creative, strategic }

extension FacilitatorStyleLabel on FacilitatorStyle {
  String get label => switch (this) {
        FacilitatorStyle.default_ => 'Default',
        FacilitatorStyle.technical => 'Technical',
        FacilitatorStyle.creative => 'Creative',
        FacilitatorStyle.strategic => 'Strategic',
      };

  String get description => switch (this) {
        FacilitatorStyle.default_ => 'Balanced approach to all tasks',
        FacilitatorStyle.technical =>
          'Focus on architectural & implementation details',
        FacilitatorStyle.creative => 'Emphasis on design & exploration',
        FacilitatorStyle.strategic =>
          'Big-picture planning & risk analysis',
      };
}

/// Provider for agent's facilitator binding.
final agentFacilitatorProvider =
    StateProvider.family<FacilitatorStyle, String>(
        (ref, agentId) => FacilitatorStyle.default_);

class FacilitatorBindingWidget extends ConsumerWidget {
  final String agentId;
  final String agentName;
  final VoidCallback? onBindingChanged;

  const FacilitatorBindingWidget({
    required this.agentId,
    required this.agentName,
    this.onBindingChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedStyle = ref.watch(agentFacilitatorProvider(agentId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Facilitator Style',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButton<FacilitatorStyle>(
            isExpanded: true,
            value: selectedStyle,
            onChanged: (newStyle) {
              if (newStyle != null) {
                ref.read(agentFacilitatorProvider(agentId).notifier).state =
                    newStyle;
                onBindingChanged?.call();
              }
            },
            items: FacilitatorStyle.values
                .map((style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.label),
                    ))
                .toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedStyle.label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedStyle.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
