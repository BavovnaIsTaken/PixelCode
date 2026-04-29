/// Single source of truth for kanban-column display labels.
///
/// Resolution order:
///   1. Active [FacilitatorStyle.lexicon] override (e.g. Game Master:
///      backlog → "questboard"; Drill Sergeant: in_progress → "active").
///   2. Canonical hardcoded fallback (current Ukrainian copy on
///      [TaskColumn.label]).
///
/// Lexicon files are not required to define every key. Missing keys
/// silently fall through to the canonical label — that lets us add new
/// columns (or new ceremonies) without coordinating an asset update.
library;

import '../models/facilitator_style.dart';
import '../models/task_board.dart';

/// Returns the player-facing label for a kanban column, swapped to the
/// active facilitator style's lexicon when one is registered for that
/// column. Pure — safe to call from anywhere.
///
/// Pass `null` to opt out of lexicon swap (e.g. an admin/diagnostics
/// surface that should always show canonical names).
String kanbanColumnLabel(TaskColumn column, FacilitatorStyle? style) {
  if (style == null) return column.label;
  final override = style.lexicon[column.key];
  if (override == null || override.isEmpty) return column.label;
  return override;
}
