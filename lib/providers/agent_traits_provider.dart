/// Provides agent traits/lessons for UI display.
/// Derives from [traitsProvider] (WS-backed) in [agent_provider.dart].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';

/// All traits for a specific agent, sorted by frequency descending.
final agentTraitsProvider =
    Provider.family<List<AgentTrait>, String>((ref, agentId) {
  return ref
      .watch(traitsProvider)
      .where((t) => t.agentId == agentId)
      .toList()
    ..sort((a, b) => b.frequency.compareTo(a.frequency));
});

/// Filter traits by type (strength vs weakness).
final agentTraitsByTypeProvider =
    Provider.family<List<AgentTrait>, (String, TraitType)>((ref, args) {
  final (agentId, type) = args;
  return ref
      .watch(agentTraitsProvider(agentId))
      .where((t) => t.type == type)
      .toList();
});

class TopicAffinityEntry {
  final LessonCategory category;
  final int strengthCount;
  final int weaknessCount;
  final int totalFrequency;

  const TopicAffinityEntry({
    required this.category,
    required this.strengthCount,
    required this.weaknessCount,
    required this.totalFrequency,
  });

  int get totalCount => strengthCount + weaknessCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicAffinityEntry &&
          runtimeType == other.runtimeType &&
          category == other.category &&
          strengthCount == other.strengthCount &&
          weaknessCount == other.weaknessCount &&
          totalFrequency == other.totalFrequency;

  @override
  int get hashCode =>
      category.hashCode ^
      strengthCount.hashCode ^
      weaknessCount.hashCode ^
      totalFrequency.hashCode;
}

/// Topic affinities aggregated from agent's traits by category.
/// Sorted by totalFrequency descending.
final agentTopicAffinitiesProvider = Provider.family<List<TopicAffinityEntry>, String>(
  (ref, agentId) {
    final traits = ref.watch(agentTraitsProvider(agentId));
    final map = <LessonCategory, ({int s, int w, int freq})>{};

    for (final trait in traits) {
      final category = trait.parsedCategory;
      if (category == null) continue;

      final current = map[category] ?? (s: 0, w: 0, freq: 0);
      map[category] = trait.type == TraitType.strength
          ? (s: current.s + 1, w: current.w, freq: current.freq + trait.frequency)
          : (s: current.s, w: current.w + 1, freq: current.freq + trait.frequency);
    }

    return map.entries
        .map((e) => TopicAffinityEntry(
              category: e.key,
              strengthCount: e.value.s,
              weaknessCount: e.value.w,
              totalFrequency: e.value.freq,
            ))
        .toList()
      ..sort((a, b) => b.totalFrequency.compareTo(a.totalFrequency));
  },
);
