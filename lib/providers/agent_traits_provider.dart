/// Provides agent traits/lessons for UI display.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/agent_trait.dart';

/// Mock provider — returns sample traits for an agent.
/// In production, this would fetch from server/local storage.
final agentTraitsProvider =
    FutureProvider.family<List<AgentTrait>, String>((ref, agentId) async {
  // Placeholder: return empty list. Real implementation would fetch from service.
  return [];
});

/// Filter traits by type (strength vs weakness).
final agentTraitsByTypeProvider = FutureProvider.family<List<AgentTrait>,
    (String agentId, TraitType type)>((ref, args) async {
  final (agentId, type) = args;
  final allTraits = await ref.watch(agentTraitsProvider(agentId).future);
  return allTraits.where((t) => t.type == type).toList();
});
