/// Pure helpers for parsing and formatting agent instance IDs.
///
/// Server tracks per-instance metrics under composite IDs like `tech-lead#1`
/// (role + `#` + instance number). UI surfaces need to split off the role for
/// color/label lookups while keeping the suffix for display.
library;

const _roleShortLabels = <String, String>{
  'manager': 'MGR',
  'tech-lead': 'TL',
  'coder': 'DEV',
  'reviewer': 'REV',
  'tester': 'QA',
  'security': 'SEC',
  'ui-ux-designer': 'UI',
  'llm-specialist': 'LLM',
  'character-artist': 'ART',
};

/// Strips the `#N` instance suffix, returning the role key.
///
/// `tech-lead#1` → `tech-lead`; `tech-lead` → `tech-lead`; `` → ``.
/// A leading `#` (no role) is returned as-is — callers handle empty role.
String agentRoleOf(String agentId) {
  final hash = agentId.indexOf('#');
  return hash > 0 ? agentId.substring(0, hash) : agentId;
}

/// Returns the `#N` suffix (including `#`) or empty string if none.
///
/// `tech-lead#1` → `#1`; `tech-lead` → ``.
String agentInstanceSuffixOf(String agentId) {
  final hash = agentId.indexOf('#');
  return hash > 0 ? agentId.substring(hash) : '';
}

/// Maps full agent ID to a short display label, preserving instance suffix.
///
/// `tech-lead#1` → `TL#1`; `coder` → `DEV`; unknown role passes through.
String shortAgentLabel(String agentId) {
  final role = agentRoleOf(agentId);
  final suffix = agentInstanceSuffixOf(agentId);
  final short = _roleShortLabels[role] ?? role;
  return '$short$suffix';
}
