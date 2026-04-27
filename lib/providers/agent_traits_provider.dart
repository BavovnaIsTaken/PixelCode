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
