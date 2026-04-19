/// Per-agent work log entry — records a session of work on a task.
library;

class WorkLogEntry {
  final String agentId;
  final DateTime startedAt;
  final int durationSeconds;

  const WorkLogEntry({
    required this.agentId,
    required this.startedAt,
    required this.durationSeconds,
  });
}
