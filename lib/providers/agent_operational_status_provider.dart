/// Single source of truth for "is this agent operationally busy right now".
///
/// Combines two server-driven streams that today disagree on edge cases
/// (abnormal query termination, websocket reconnect, watchdog cleanup):
///
/// - [activeAgentsProvider] — registry-authoritative `active_agents` snapshot.
///   Updated transactionally when the server registers/unregisters a chat
///   query or sub-agent dispatch. Empty entry list ⇒ idle by construction.
///
/// - [agentsProvider] — push-driven `agent_status` cache. Holds the granular
///   label (Reading / Typing / Thinking / Running) for the "what is it
///   doing" indicator. Sticky: a missed idle event leaves the last status
///   in place indefinitely.
///
/// The combined rule: if the agent is NOT a member of the active set, the
/// operational status is forced to [AgentStatus.idle], regardless of what
/// the last `agent_status` push said. Otherwise the granular push label is
/// passed through verbatim — so consumers still see "Reading char_0.png"
/// instead of just a generic "busy" dot.
///
/// Consumers: chat-header indicator ([ChatPanel]), pixel-office canvas
/// sprite labels ([AgentCanvas]), and any future surface that mixes
/// "running yes/no" with "what specifically". Settings → Активні агенти
/// reads [activeAgentsProvider] directly and does not go through this
/// provider — its concern is the list, not the label.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import 'active_agents_provider.dart';
import 'agent_provider.dart';

/// Set of agentIds the server currently considers operationally active.
///
/// Derived once per [activeAgentsProvider] change so the per-agent provider
/// below doesn't reconstruct the set on every keystroke.
final activeAgentIdsProvider = Provider<Set<String>>((ref) {
  final entries = ref.watch(activeAgentsProvider);
  return {for (final e in entries) e.agentId};
});

/// Operational status for a specific agentId. Forces idle when the agent is
/// not in the server's active set, even if the local `agent_status` cache
/// still holds a stale non-idle value.
final agentOperationalStatusProvider =
    Provider.family<AgentStatus, String>((ref, agentId) {
  final active = ref.watch(activeAgentIdsProvider);
  final pushed = ref.watch(agentsProvider)[agentId]?.status ?? AgentStatus.idle;
  if (!active.contains(agentId)) return AgentStatus.idle;
  return pushed;
});

/// Map of every known agentId → reconciled operational status.
///
/// Useful for the chat-header fallback loop, which iterates the whole roster
/// to find ANY busy peer of the selected agent. Keyed off [agentsProvider]
/// because that map holds the full hired roster; the active set just filters
/// it.
final agentOperationalStatusesProvider =
    Provider<Map<String, AgentStatus>>((ref) {
  final active = ref.watch(activeAgentIdsProvider);
  final agents = ref.watch(agentsProvider);
  final out = <String, AgentStatus>{};
  for (final entry in agents.entries) {
    if (!active.contains(entry.key)) {
      out[entry.key] = AgentStatus.idle;
    } else {
      out[entry.key] = entry.value.status;
    }
  }
  return out;
});

/// Same shape as [agentsProvider] but with `.status` (and the dependent
/// `activeTools`) reconciled against the active set. Use this when a
/// consumer needs the full [AgentState] (info, currentTask, activeSince,
/// etc.) — surfaces like the pixel-office canvas read multiple fields off
/// the same struct, so we hand them a corrected map rather than asking
/// every call site to override `.status` locally.
///
/// Idle-forced entries also reset `activeTools` to empty and drop
/// `currentTask` / `activeSince`, mirroring what the dispatch-side
/// handlers do at line 605-610 of agent_provider.dart on SubagentStop.
final reconciledAgentsProvider =
    Provider<Map<String, AgentState>>((ref) {
  final active = ref.watch(activeAgentIdsProvider);
  final agents = ref.watch(agentsProvider);
  final out = <String, AgentState>{};
  for (final entry in agents.entries) {
    final state = entry.value;
    if (state.status == AgentStatus.idle || active.contains(entry.key)) {
      out[entry.key] = state;
      continue;
    }
    out[entry.key] = AgentState(
      info: state.info,
      status: AgentStatus.idle,
    );
  }
  return out;
});
