/// FacilitatorStyle — preset that defines *how* the manager-agent leads
/// development work. A style does NOT change the team roster or technical
/// decisions (tech-lead retains veto — see FACILITATOR_SYSTEM §6); it
/// influences only:
///
///   - Lexicon (label substitution: "task" → "mission" / "story" / "quest")
///   - Tone (aggression / formality / verbosity)
///   - Ceremony rhythm (standup / retro / journal / none)
///   - Output format shape (which `FacilitatorOutput` impl is produced)
///
/// Styles are static JSON presets (see `assets/facilitators/*.json`)
/// loaded by `FacilitatorStyleLoader`. Marketplace-distributed styles
/// (Q4 2026, Section E) use the same shape.
///
/// See `docs/FACILITATOR_SYSTEM.md` for the design.
library;

import 'dart:convert';

import 'facilitator_output.dart';

// ─── Laloux level ───────────────────────────────────────────────────────────

/// Laloux organizational paradigm. Used both as part of the style's
/// identity and as a marketplace filter dimension.
enum Laloux {
  red,    // Impulsive — wolf pack, force ("Drill Sergeant")
  amber,  // Conformist — formal hierarchy, process ("Marina")
  orange, // Achievement — meritocratic, KPIs ("Scrum Master")
  green,  // Pluralistic — values, community ("Game Master")
  teal;   // Evolutionary — self-management, purpose ("Stoic Mentor")

  String get key => name;

  String get label => switch (this) {
        Laloux.red => 'Red — Impulsive',
        Laloux.amber => 'Amber — Conformist',
        Laloux.orange => 'Orange — Achievement',
        Laloux.green => 'Green — Pluralistic',
        Laloux.teal => 'Teal — Evolutionary',
      };

  static Laloux fromKey(String key) => switch (key) {
        'amber' => Laloux.amber,
        'orange' => Laloux.orange,
        'green' => Laloux.green,
        'teal' => Laloux.teal,
        _ => Laloux.red,
      };
}

// ─── Ceremony schedule ──────────────────────────────────────────────────────

enum CeremonyKind {
  standup,    // brief status check
  retro,      // looking back at completed work
  review,     // status report (Marina-style)
  briefing,   // mission/sprint kickoff
  journal,    // reflection prompt (Stoic-style)
  onDemand,   // user-initiated only
  none;       // no scheduled ceremony

  String get key => switch (this) {
        CeremonyKind.standup => 'standup',
        CeremonyKind.retro => 'retro',
        CeremonyKind.review => 'review',
        CeremonyKind.briefing => 'briefing',
        CeremonyKind.journal => 'journal',
        CeremonyKind.onDemand => 'on_demand',
        CeremonyKind.none => 'none',
      };

  static CeremonyKind fromKey(String key) => switch (key) {
        'retro' => CeremonyKind.retro,
        'review' => CeremonyKind.review,
        'briefing' => CeremonyKind.briefing,
        'journal' => CeremonyKind.journal,
        'on_demand' => CeremonyKind.onDemand,
        'none' => CeremonyKind.none,
        _ => CeremonyKind.standup,
      };
}

enum CeremonyCadence {
  daily,
  weekly,
  biweekly,
  monthly,
  onEvent,    // triggered by a runtime event (sprint end, act close, etc.)
  never;

  String get key => switch (this) {
        CeremonyCadence.daily => 'daily',
        CeremonyCadence.weekly => 'weekly',
        CeremonyCadence.biweekly => 'biweekly',
        CeremonyCadence.monthly => 'monthly',
        CeremonyCadence.onEvent => 'on_event',
        CeremonyCadence.never => 'never',
      };

  static CeremonyCadence fromKey(String key) => switch (key) {
        'weekly' => CeremonyCadence.weekly,
        'biweekly' => CeremonyCadence.biweekly,
        'monthly' => CeremonyCadence.monthly,
        'on_event' => CeremonyCadence.onEvent,
        'never' => CeremonyCadence.never,
        _ => CeremonyCadence.daily,
      };
}

class CeremonySpec {
  final CeremonyKind kind;
  final CeremonyCadence cadence;
  /// For `onEvent` cadence: the runtime event name that fires it
  /// (e.g. "sprint_end", "act_complete", "task_completed").
  final String? triggerEvent;

  const CeremonySpec({
    required this.kind,
    required this.cadence,
    this.triggerEvent,
  });

  factory CeremonySpec.fromJson(Map<String, dynamic> json) => CeremonySpec(
        kind: CeremonyKind.fromKey(json['kind'] as String? ?? 'standup'),
        cadence:
            CeremonyCadence.fromKey(json['cadence'] as String? ?? 'daily'),
        triggerEvent: json['triggerEvent'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.key,
        'cadence': cadence.key,
        if (triggerEvent != null) 'triggerEvent': triggerEvent,
      };
}

// ─── Intake template ────────────────────────────────────────────────────────

/// Maps an intake question to a ScopeScore dimension so the same scope
/// scorer (server-side) calibrates output size across all styles.
enum ScopeDimension {
  entityCount,
  interactionSurface,
  auth,
  integrations,
  realtime,
  none;

  String get key => switch (this) {
        ScopeDimension.entityCount => 'entity_count',
        ScopeDimension.interactionSurface => 'interaction_surface',
        ScopeDimension.auth => 'auth',
        ScopeDimension.integrations => 'integrations',
        ScopeDimension.realtime => 'realtime',
        ScopeDimension.none => 'none',
      };

  static ScopeDimension fromKey(String key) => switch (key) {
        'entity_count' => ScopeDimension.entityCount,
        'interaction_surface' => ScopeDimension.interactionSurface,
        'auth' => ScopeDimension.auth,
        'integrations' => ScopeDimension.integrations,
        'realtime' => ScopeDimension.realtime,
        _ => ScopeDimension.none,
      };
}

enum IntakeInputKind {
  text,
  choice;

  String get key => name;

  static IntakeInputKind fromKey(String key) =>
      key == 'choice' ? IntakeInputKind.choice : IntakeInputKind.text;
}

class IntakeQuestion {
  final String id;
  /// Style-flavored prompt text. Lexicon is already applied (the JSON
  /// preset author writes it in the style's voice).
  final String prompt;
  final IntakeInputKind inputKind;
  /// For `choice` input — labels shown to the user.
  final List<String> choices;
  /// Which scope dimension this question informs. `none` for purely
  /// narrative/flavor questions that don't feed scoring.
  final ScopeDimension mapsTo;

  const IntakeQuestion({
    required this.id,
    required this.prompt,
    this.inputKind = IntakeInputKind.text,
    this.choices = const [],
    this.mapsTo = ScopeDimension.none,
  });

  factory IntakeQuestion.fromJson(Map<String, dynamic> json) => IntakeQuestion(
        id: json['id'] as String,
        prompt: json['prompt'] as String? ?? '',
        inputKind:
            IntakeInputKind.fromKey(json['inputKind'] as String? ?? 'text'),
        choices: (json['choices'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        mapsTo: ScopeDimension.fromKey(json['mapsTo'] as String? ?? 'none'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'inputKind': inputKind.key,
        if (choices.isNotEmpty) 'choices': choices,
        'mapsTo': mapsTo.key,
      };
}

// ─── Tone modifiers ─────────────────────────────────────────────────────────

class ToneModifiers {
  /// 0 = pacifist, 1 = drill sergeant.
  final double aggression;

  /// 0 = casual, 1 = corporate.
  final double formality;

  /// 0 = terse, 1 = elaborate.
  final double verbosity;

  const ToneModifiers({
    required this.aggression,
    required this.formality,
    required this.verbosity,
  });

  factory ToneModifiers.fromJson(Map<String, dynamic> json) => ToneModifiers(
        aggression: _readDouble(json['aggression']),
        formality: _readDouble(json['formality']),
        verbosity: _readDouble(json['verbosity']),
      );

  Map<String, dynamic> toJson() => {
        'aggression': aggression,
        'formality': formality,
        'verbosity': verbosity,
      };

  static double _readDouble(Object? raw) {
    final v = (raw as num?)?.toDouble() ?? 0.5;
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v;
  }
}

// ─── Facilitator Style ──────────────────────────────────────────────────────

class FacilitatorStyle {
  /// Stable id (e.g. "game_master"). Used in persistence + marketplace.
  final String id;
  final String displayName;
  final String tagline;
  final Laloux laloux;

  /// Persona prompt fragment injected into manager-agent context.
  /// Must NOT contain technical decision-making — see FACILITATOR_SYSTEM §6.
  final String personaPrompt;

  /// Canonical→styled translation (e.g. `"task" → "mission"`). Pure
  /// string-level swap, applied on the client before display. Zero LLM
  /// cost.
  final Map<String, String> lexicon;

  final List<CeremonySpec> ceremonySchedule;
  final List<IntakeQuestion> intakeTemplate;

  /// Which `FacilitatorOutput` shape this style produces.
  final OutputFormat outputMapper;

  final ToneModifiers toneModifiers;

  const FacilitatorStyle({
    required this.id,
    required this.displayName,
    required this.tagline,
    required this.laloux,
    required this.personaPrompt,
    this.lexicon = const {},
    this.ceremonySchedule = const [],
    this.intakeTemplate = const [],
    required this.outputMapper,
    required this.toneModifiers,
  });

  /// Apply the style's lexicon to a canonical token. Falls back to the
  /// canonical word if no override is registered.
  String translate(String canonical) => lexicon[canonical] ?? canonical;

  factory FacilitatorStyle.fromJson(Map<String, dynamic> json) =>
      FacilitatorStyle(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        tagline: json['tagline'] as String? ?? '',
        laloux: Laloux.fromKey(json['laloux'] as String? ?? 'red'),
        personaPrompt: json['personaPrompt'] as String? ?? '',
        lexicon: (json['lexicon'] as Map?)
                ?.map((k, v) => MapEntry(k as String, v as String)) ??
            const {},
        ceremonySchedule: (json['ceremonySchedule'] as List?)
                ?.map((c) => CeremonySpec.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
        intakeTemplate: (json['intakeTemplate'] as List?)
                ?.map(
                    (q) => IntakeQuestion.fromJson(q as Map<String, dynamic>))
                .toList() ??
            const [],
        outputMapper:
            OutputFormat.fromKey(json['outputMapper'] as String? ?? 'quest_line'),
        toneModifiers: ToneModifiers.fromJson(
            json['toneModifiers'] as Map<String, dynamic>? ?? const {}),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'tagline': tagline,
        'laloux': laloux.key,
        'personaPrompt': personaPrompt,
        'lexicon': lexicon,
        'ceremonySchedule':
            ceremonySchedule.map((c) => c.toJson()).toList(),
        'intakeTemplate': intakeTemplate.map((q) => q.toJson()).toList(),
        'outputMapper': outputMapper.key,
        'toneModifiers': toneModifiers.toJson(),
      };

  String encode() => jsonEncode(toJson());

  factory FacilitatorStyle.decode(String raw) =>
      FacilitatorStyle.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
