/// Agent trait memory — persistent learning from mistakes and successes.
///
/// Each lesson has a frequency: the more often a pattern is observed,
/// the stronger the memory becomes, influencing agent behavior.
library;

class AgentTrait {
  final String id;
  final String agentId;
  final TraitType type;
  final String category;
  final String tag;
  final String lesson;
  final int frequency;
  final DateTime firstSeen;
  final DateTime lastSeen;

  const AgentTrait({
    required this.id,
    required this.agentId,
    required this.type,
    required this.category,
    required this.tag,
    required this.lesson,
    required this.frequency,
    required this.firstSeen,
    required this.lastSeen,
  });

  /// Emphasis level based on observation frequency.
  TraitEmphasis get emphasis {
    if (frequency >= 5) return TraitEmphasis.critical;
    if (frequency >= 3) return TraitEmphasis.important;
    return TraitEmphasis.note;
  }

  factory AgentTrait.fromJson(Map<String, dynamic> json) => AgentTrait(
        id: json['id'] as String,
        agentId: json['agentId'] as String,
        type: (json['type'] as String) == 'strength'
            ? TraitType.strength
            : TraitType.weakness,
        category: json['category'] as String,
        tag: json['tag'] as String,
        lesson: json['lesson'] as String,
        frequency: json['frequency'] as int? ?? 1,
        firstSeen: DateTime.parse(json['firstSeen'] as String),
        lastSeen: DateTime.parse(json['lastSeen'] as String),
      );
}

enum TraitType { strength, weakness }

enum TraitEmphasis { note, important, critical }
