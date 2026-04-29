/// Agent export/import service.
///
/// Converts a live [AgentGameData] into a portable [AgentBlueprint] JSON
/// (stripped of runtime state: instanceId, level, xp, hardware, provider)
/// and back into [CustomAgentSpawnData] so the standard spawn flow can
/// re-create the agent on the recipient's team.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/game_economy.dart';
import '../widgets/personalization/custom_agent_spawn_form.dart';

const _kBlueprintVersion = '1';
const _kExportSubdir = 'PixelCode';

/// Portable agent definition — everything needed to recreate an agent,
/// minus per-player runtime state (instanceId, level, xp, hardware, provider).
class AgentBlueprint {
  final String version;
  final String roleType;
  final String nickname;
  final String? customSystemPrompt;
  final String? personalityPreset;
  final Map<SkillType, int> skills;
  final String? characterId;
  final DateTime exportedAt;

  const AgentBlueprint({
    required this.version,
    required this.roleType,
    required this.nickname,
    required this.skills,
    required this.exportedAt,
    this.customSystemPrompt,
    this.personalityPreset,
    this.characterId,
  });

  /// Build blueprint from a live agent — strips runtime-only fields.
  factory AgentBlueprint.fromAgent(AgentGameData agent) => AgentBlueprint(
        version: _kBlueprintVersion,
        roleType: agent.roleType,
        nickname: agent.nickname,
        customSystemPrompt: agent.customSystemPrompt,
        personalityPreset: agent.personalityPreset,
        skills: Map<SkillType, int>.from(agent.skills),
        characterId: agent.characterId,
        exportedAt: DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'pixelcodeAgent': version,
        'roleType': roleType,
        'nickname': nickname,
        if (customSystemPrompt != null) 'customSystemPrompt': customSystemPrompt,
        if (personalityPreset != null) 'personalityPreset': personalityPreset,
        'skills': {
          for (final e in skills.entries) e.key.index.toString(): e.value,
        },
        if (characterId != null) 'characterId': characterId,
        'exportedAt': exportedAt.toIso8601String(),
      };

  factory AgentBlueprint.fromJson(Map<String, dynamic> json) {
    final version = json['pixelcodeAgent'] as String?;
    if (version == null) {
      throw const FormatException('Missing pixelcodeAgent version field');
    }
    if (version != _kBlueprintVersion) {
      throw FormatException('Unsupported agent blueprint version: $version');
    }

    final rawSkills =
        (json['skills'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final skills = <SkillType, int>{};
    for (final e in rawSkills.entries) {
      final idx = int.tryParse(e.key);
      if (idx != null && idx < SkillType.values.length) {
        skills[SkillType.values[idx]] = (e.value as num).toInt();
      }
    }

    return AgentBlueprint(
      version: version,
      roleType: json['roleType'] as String,
      nickname: json['nickname'] as String,
      customSystemPrompt: json['customSystemPrompt'] as String?,
      personalityPreset: json['personalityPreset'] as String?,
      skills: skills,
      characterId: json['characterId'] as String?,
      exportedAt: DateTime.parse(json['exportedAt'] as String),
    );
  }
}

/// Handles serialization to/from JSON strings and file I/O.
class AgentExportService {
  const AgentExportService();

  /// Serialize [blueprint] to a pretty-printed JSON string.
  String exportToString(AgentBlueprint blueprint) =>
      const JsonEncoder.withIndent('  ').convert(blueprint.toJson());

  /// Parse and validate a JSON string into an [AgentBlueprint].
  /// Throws [FormatException] on invalid JSON or unsupported version.
  AgentBlueprint importFromString(String jsonString) {
    final dynamic raw;
    try {
      raw = jsonDecode(jsonString);
    } catch (_) {
      throw const FormatException('Invalid JSON — could not parse agent blueprint');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Agent blueprint must be a JSON object');
    }
    return AgentBlueprint.fromJson(raw);
  }

  /// Convert an [AgentBlueprint] into [CustomAgentSpawnData] so the
  /// standard [spawnCustomAgent] flow can re-create the agent.
  CustomAgentSpawnData toSpawnData(AgentBlueprint blueprint) =>
      CustomAgentSpawnData(
        nickname: blueprint.nickname,
        systemPrompt: blueprint.customSystemPrompt ?? '',
        selectedRole: blueprint.roleType,
        personalityPreset: blueprint.personalityPreset ?? 'balanced',
        skillWeights: blueprint.skills.isEmpty
            ? {for (final s in SkillType.values) s: 3}
            : blueprint.skills,
      );

  /// Write [blueprint] to `<documents>/PixelCode/<nickname>.agent.json`.
  /// Returns the absolute file path on success.
  ///
  /// Pass [outputDir] to override the target directory (used in tests to
  /// avoid calling [getApplicationDocumentsDirectory]).
  Future<String> exportToFile(
    AgentBlueprint blueprint, {
    Directory? outputDir,
  }) async {
    final exportDir = outputDir ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}/$_kExportSubdir',
        );
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);

    final safeName = blueprint.nickname
        .replaceAll(RegExp(r'[^\w\- ]'), '_')
        .trim()
        .replaceAll(' ', '_');
    final file = File('${exportDir.path}/$safeName.agent.json');
    file.writeAsStringSync(exportToString(blueprint));
    return file.path;
  }

  /// Read a `.agent.json` file at [filePath] and return the blueprint.
  Future<AgentBlueprint> importFromFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    return importFromString(file.readAsStringSync());
  }
}
