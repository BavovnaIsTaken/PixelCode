/// Agent trait memory — persistent learning from mistakes and successes.
///
/// Each lesson has a frequency: the more often a pattern is observed,
/// the stronger the memory becomes, influencing agent behavior.
library;

enum LessonCategory {
  codeQuality,
  architecture,
  testing,
  security,
  communication,
  delegation,
  problemSolving,
  toolsUsage;

  static LessonCategory? fromString(String value) => switch (value) {
    'code_quality' => codeQuality,
    'architecture' => architecture,
    'testing' => testing,
    'security' => security,
    'communication' => communication,
    'delegation' => delegation,
    'problem_solving' => problemSolving,
    'tools_usage' => toolsUsage,
    _ => null,
  };

  String get displayName => switch (this) {
    codeQuality => 'Code Quality',
    architecture => 'Architecture',
    testing => 'Testing',
    security => 'Security',
    communication => 'Communication',
    delegation => 'Delegation',
    problemSolving => 'Problem Solving',
    toolsUsage => 'Tools & Usage',
  };
}

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

  LessonCategory? get parsedCategory => LessonCategory.fromString(category);

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentTrait &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          agentId == other.agentId &&
          type == other.type &&
          category == other.category &&
          tag == other.tag &&
          lesson == other.lesson &&
          frequency == other.frequency &&
          firstSeen == other.firstSeen &&
          lastSeen == other.lastSeen;

  @override
  int get hashCode =>
      id.hashCode ^
      agentId.hashCode ^
      type.hashCode ^
      category.hashCode ^
      tag.hashCode ^
      lesson.hashCode ^
      frequency.hashCode ^
      firstSeen.hashCode ^
      lastSeen.hashCode;
}

enum TraitType { strength, weakness }

enum TraitEmphasis { note, important, critical }
