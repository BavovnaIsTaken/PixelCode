import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/utils/kanban_labels.dart';

FacilitatorStyle _styleWithLexicon(Map<String, String> lexicon) =>
    FacilitatorStyle.fromJson({
      'id': 'test',
      'displayName': 'Test',
      'tagline': '',
      'laloux': 'red',
      'personaPrompt': '',
      'lexicon': lexicon,
      'outputMapper': 'questLine',
      'toneModifiers': <String, dynamic>{},
    });

void main() {
  group('kanbanColumnLabel', () {
    test('returns canonical label when style is null', () {
      expect(kanbanColumnLabel(TaskColumn.backlog, null), TaskColumn.backlog.label);
      expect(
          kanbanColumnLabel(TaskColumn.inProgress, null), TaskColumn.inProgress.label);
      expect(kanbanColumnLabel(TaskColumn.testing, null), TaskColumn.testing.label);
      expect(kanbanColumnLabel(TaskColumn.done, null), TaskColumn.done.label);
    });

    test('returns canonical label when style has empty lexicon', () {
      final style = _styleWithLexicon(const {});
      for (final col in TaskColumn.values) {
        expect(kanbanColumnLabel(col, style), col.label);
      }
    });

    test('returns lexicon override when present', () {
      final style = _styleWithLexicon(const {
        'backlog': 'questboard',
        'in_progress': 'in motion',
        'testing': 'trial',
        'done': 'forged',
      });
      expect(kanbanColumnLabel(TaskColumn.backlog, style), 'questboard');
      expect(kanbanColumnLabel(TaskColumn.inProgress, style), 'in motion');
      expect(kanbanColumnLabel(TaskColumn.testing, style), 'trial');
      expect(kanbanColumnLabel(TaskColumn.done, style), 'forged');
    });

    test('falls through to canonical for keys missing from a partial lexicon',
        () {
      // Only `done` is overridden; the rest must fall back.
      final style = _styleWithLexicon(const {'done': 'shipped'});
      expect(kanbanColumnLabel(TaskColumn.backlog, style), TaskColumn.backlog.label);
      expect(
          kanbanColumnLabel(TaskColumn.inProgress, style), TaskColumn.inProgress.label);
      expect(kanbanColumnLabel(TaskColumn.testing, style), TaskColumn.testing.label);
      expect(kanbanColumnLabel(TaskColumn.done, style), 'shipped');
    });

    test('treats empty-string overrides as missing', () {
      // An asset author who writes "" must not blank out the UI.
      final style = _styleWithLexicon(const {'backlog': ''});
      expect(kanbanColumnLabel(TaskColumn.backlog, style), TaskColumn.backlog.label);
    });

    test('uses the canonical column.key for lookups', () {
      // Defensive: lexicon keys must match TaskColumn.key, not enum names.
      // (`inProgress` enum vs `in_progress` lexicon key.)
      final wrong = _styleWithLexicon(const {'inProgress': 'WRONG'});
      expect(kanbanColumnLabel(TaskColumn.inProgress, wrong),
          TaskColumn.inProgress.label,
          reason: 'enum-name key must NOT match');

      final right = _styleWithLexicon(const {'in_progress': 'active'});
      expect(kanbanColumnLabel(TaskColumn.inProgress, right), 'active');
    });
  });
}
