/// Persistence for any `FacilitatorOutput` — one output per project,
/// regardless of style (QuestLine, MissionBriefing, MilestoneTree, etc).
///
/// Filesystem layout:
///   {appSupport}/pixelcode/projects/{storageKey}/facilitator_output.json
///
/// The on-disk JSON carries a `format` discriminator (set by every
/// `FacilitatorOutput.serialize()`) so the loader can route to the right
/// `fromJson`. New output formats register a decoder via
/// [registerDecoder] — keeps this service open/closed for new styles.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/facilitator_output.dart';
import '../models/quest_line.dart';

typedef OutputDecoder = FacilitatorOutput Function(Map<String, dynamic> json);

class FacilitatorOutputPersistenceService {
  // Decoders are mutable to allow new styles to register without touching
  // this file. Default registry: Game Master (QuestLine).
  static final Map<OutputFormat, OutputDecoder> _decoders = {
    OutputFormat.questLine: (json) => QuestLine.fromJson(json),
  };

  /// Register (or replace) a decoder for an output format. Called by each
  /// concrete output shape's library at import time.
  static void registerDecoder(OutputFormat format, OutputDecoder decoder) {
    _decoders[format] = decoder;
  }

  static String _storageKey(String projectPath) =>
      projectPath.replaceAll('/', '-').replaceAll(RegExp('^-'), '');

  static Future<Directory> _projectDir(String projectPath) async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(
        '${appDir.path}/pixelcode/projects/${_storageKey(projectPath)}');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _outputFile(String projectPath) async {
    final dir = await _projectDir(projectPath);
    return File('${dir.path}/facilitator_output.json');
  }

  /// Load the facilitator output for a project, or `null` if none exists
  /// or its format has no registered decoder.
  static Future<FacilitatorOutput?> load(String projectPath) async {
    try {
      final file = await _outputFile(projectPath);
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      if (raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final formatKey = json['format'] as String? ?? 'quest_line';
      final format = OutputFormat.fromKey(formatKey);
      final decoder = _decoders[format];
      if (decoder == null) return null;
      return decoder(json);
    } catch (_) {
      return null;
    }
  }

  /// Save any `FacilitatorOutput` atomically (write-then-rename).
  /// The output's `serialize()` already includes the format discriminator.
  ///
  /// `projectPath` is provided explicitly because `FacilitatorOutput` is
  /// style-agnostic and doesn't carry a path field; the caller knows
  /// which project this output belongs to.
  static Future<void> save(
    String projectPath,
    FacilitatorOutput output,
  ) async {
    final file = await _outputFile(projectPath);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(output.serialize(), flush: true);
    await tmp.rename(file.path);
  }

  /// Delete the saved output. Used when starting fresh or resetting the
  /// project's facilitator state.
  static Future<void> delete(String projectPath) async {
    final file = await _outputFile(projectPath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Returns the on-disk path where the output is (or would be) stored.
  static Future<String> resolvePath(String projectPath) async {
    final file = await _outputFile(projectPath);
    return file.path;
  }
}
