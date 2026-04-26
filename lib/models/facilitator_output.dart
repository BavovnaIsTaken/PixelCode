/// FacilitatorOutput — the canonical contract that every facilitator
/// style produces. Different styles emit different shapes:
///
///   - Game Master   → QuestLine
///   - Drill Sergeant→ MissionBriefing
///   - Marina        → MilestoneTree
///   - Scrum Master  → SprintBacklog
///   - Stoic Mentor  → KoanEntry
///
/// All shapes converge on the kanban board (the project invariant) via
/// [FacilitatorOutput.toKanbanTasks]. Style is a transformation layer
/// over the same source of truth.
///
/// See `docs/FACILITATOR_SYSTEM.md` §3 for the design.
library;

import 'task_board.dart';

// ─── Output format discriminator ────────────────────────────────────────────

enum OutputFormat {
  questLine,
  missionBriefing,
  milestoneTree,
  sprintBacklog,
  koanEntry;

  String get key => switch (this) {
        OutputFormat.questLine => 'quest_line',
        OutputFormat.missionBriefing => 'mission_briefing',
        OutputFormat.milestoneTree => 'milestone_tree',
        OutputFormat.sprintBacklog => 'sprint_backlog',
        OutputFormat.koanEntry => 'koan_entry',
      };

  static OutputFormat fromKey(String key) => switch (key) {
        'mission_briefing' => OutputFormat.missionBriefing,
        'milestone_tree' => OutputFormat.milestoneTree,
        'sprint_backlog' => OutputFormat.sprintBacklog,
        'koan_entry' => OutputFormat.koanEntry,
        _ => OutputFormat.questLine,
      };
}

// ─── Progress aggregate (style-agnostic) ────────────────────────────────────

/// Style-agnostic progress view. Each format computes this differently
/// (quests done / sprint completed / milestones reached / missions
/// debriefed / koans answered) but the shape is identical so the UI can
/// render a single progress widget regardless of style.
class ProgressView {
  /// 0.0–1.0 fraction of the work that's done.
  final double fraction;

  /// Total earned reward XP (XP belongs to the agent — see FACILITATOR_SYSTEM §5).
  final int earnedXp;

  /// Total potential XP if everything completes.
  final int totalXp;

  /// Whether the entire output is finished.
  final bool isComplete;

  /// Free-form one-line label, style-flavored ("3 of 6 quests forged",
  /// "Sprint 2 of 4", "Mission 1/3 complete"). Caller is responsible
  /// for localization / styling — this carries the raw text.
  final String label;

  const ProgressView({
    required this.fraction,
    required this.earnedXp,
    required this.totalXp,
    required this.isComplete,
    required this.label,
  });
}

// ─── The contract ───────────────────────────────────────────────────────────

/// Every facilitator output shape must implement this contract.
///
/// **Kanban is the invariant** — `toKanbanTasks()` is the bridge between
/// any style-specific shape and the project's working state. It produces
/// the *seed* set of cards (initial population). Subsequent edits live
/// on the board itself; ceremonies (sprint rollover, new act, etc.) can
/// mint additional cards via the same contract.
abstract interface class FacilitatorOutput {
  /// Format discriminator used by persistence + marketplace.
  OutputFormat get format;

  /// Canonical kanban representation. Lossy by design — hierarchy,
  /// dependencies, and style-specific metadata stay on the source
  /// object; the board only needs the working set.
  List<TaskCard> toKanbanTasks();

  /// Style-agnostic progress aggregate.
  ProgressView toCanonicalProgress();

  /// JSON encoding for persistence + marketplace export. Implementations
  /// MUST include their `OutputFormat` discriminator so the loader can
  /// route to the right `fromJson`.
  String serialize();
}
