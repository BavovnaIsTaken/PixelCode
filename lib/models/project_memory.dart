/// Project memory — accumulated team knowledge about a project.
///
/// Memories decay over time: recent ones are detailed, older ones compress,
/// and very old ones are dropped — mimicking how a human team remembers.
library;

import 'dart:convert';
import 'dart:math';

enum MemoryTier { fresh, recent, old }

class ProjectMemoryEntry {
  final String summary;
  final DateTime timestamp;
  final String? sessionId;

  const ProjectMemoryEntry({
    required this.summary,
    required this.timestamp,
    this.sessionId,
  });

  MemoryTier get tier {
    final age = DateTime.now().difference(timestamp);
    if (age.inHours < 24) return MemoryTier.fresh;
    if (age.inDays < 7) return MemoryTier.recent;
    return MemoryTier.old;
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'timestamp': timestamp.toIso8601String(),
        if (sessionId != null) 'sessionId': sessionId,
      };

  factory ProjectMemoryEntry.fromJson(Map<String, dynamic> json) =>
      ProjectMemoryEntry(
        summary: json['summary'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        sessionId: json['sessionId'] as String?,
      );

  ProjectMemoryEntry _truncateTo(int maxWords) {
    final words = summary.split(RegExp(r'\s+'));
    if (words.length <= maxWords) return this;
    final truncated = words.take(maxWords).join(' ');
    return ProjectMemoryEntry(
      summary: '$truncated...',
      timestamp: timestamp,
      sessionId: sessionId,
    );
  }

  /// Apply time-based decay to a list of memories.
  ///
  /// - Fresh (< 24h): full text, up to 200 words
  /// - Recent (< 7 days): truncated to ~50 words
  /// - Old (< 30 days): truncated to ~20 words
  /// - Older than 30 days: dropped
  /// - Total budget: ~2400 characters
  static List<ProjectMemoryEntry> applyDecay(List<ProjectMemoryEntry> entries) {
    final now = DateTime.now();
    final alive = entries
        .where((e) => now.difference(e.timestamp).inDays < 30)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final decayed = <ProjectMemoryEntry>[];
    int freshCount = 0;
    int totalChars = 0;
    const maxChars = 2400;

    for (final entry in alive) {
      if (totalChars >= maxChars) break;

      ProjectMemoryEntry processed;
      switch (entry.tier) {
        case MemoryTier.fresh:
          freshCount++;
          processed = freshCount <= 3 ? entry._truncateTo(200) : entry._truncateTo(50);
        case MemoryTier.recent:
          processed = entry._truncateTo(50);
        case MemoryTier.old:
          processed = entry._truncateTo(20);
      }

      final remaining = maxChars - totalChars;
      if (processed.summary.length > remaining) {
        // Fit what we can
        processed = ProjectMemoryEntry(
          summary: processed.summary.substring(0, min(remaining, processed.summary.length)),
          timestamp: processed.timestamp,
          sessionId: processed.sessionId,
        );
      }

      totalChars += processed.summary.length;
      decayed.add(processed);
    }

    return decayed;
  }

  /// Format memories for injection into agent system prompt.
  static String formatForPrompt(List<ProjectMemoryEntry> memories) {
    if (memories.isEmpty) return '';

    final buf = StringBuffer();
    for (final m in memories) {
      final age = DateTime.now().difference(m.timestamp);
      final timeAgo = _humanizeAge(age);
      buf.writeln('- [$timeAgo] ${m.summary}');
    }
    return buf.toString().trimRight();
  }

  static String _humanizeAge(Duration age) {
    if (age.inHours < 1) return 'just now';
    if (age.inHours < 24) return '${age.inHours}h ago';
    if (age.inDays < 7) return '${age.inDays}d ago';
    final weeks = age.inDays ~/ 7;
    return '${weeks}w ago';
  }

  static List<ProjectMemoryEntry> listFromJson(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list
        .map((e) => ProjectMemoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<ProjectMemoryEntry> entries) {
    return jsonEncode(entries.map((e) => e.toJson()).toList());
  }
}
