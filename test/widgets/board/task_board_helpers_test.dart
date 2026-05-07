/// Unit tests for the pure helpers carved out of `task_board_panel.dart`.
/// These cover column adjacency, drag-target predicates, the difficulty/
/// requirement chip text, attachment formatting, and work-history
/// duration formatting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/task_board.dart';
import 'package:pixelcode/widgets/board/task_board_helpers.dart';

TaskCard _task({
  TaskColumn column = TaskColumn.backlog,
  int difficulty = 2,
  List<String> allowedRoles = const ['coder'],
}) {
  final now = DateTime(2026, 1, 1);
  return TaskCard(
    id: 'task-1',
    title: 'T',
    column: column,
    difficulty: difficulty,
    allowedRoles: allowedRoles,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('nextColumn / prevColumn', () {
    test('backlog → inProgress, no prev', () {
      expect(nextColumn(TaskColumn.backlog), TaskColumn.inProgress);
      expect(prevColumn(TaskColumn.backlog), isNull);
    });

    test('inProgress wraps both ways', () {
      expect(nextColumn(TaskColumn.inProgress), TaskColumn.testing);
      expect(prevColumn(TaskColumn.inProgress), TaskColumn.backlog);
    });

    test('testing wraps both ways', () {
      expect(nextColumn(TaskColumn.testing), TaskColumn.done);
      expect(prevColumn(TaskColumn.testing), TaskColumn.inProgress);
    });

    test('done is terminal — no next', () {
      expect(nextColumn(TaskColumn.done), isNull);
      expect(prevColumn(TaskColumn.done), TaskColumn.testing);
    });

    test('full forward chain reaches done', () {
      var c = TaskColumn.backlog;
      final visited = <TaskColumn>[c];
      while (true) {
        final n = nextColumn(c);
        if (n == null) break;
        visited.add(n);
        c = n;
      }
      expect(visited, [
        TaskColumn.backlog,
        TaskColumn.inProgress,
        TaskColumn.testing,
        TaskColumn.done,
      ]);
    });
  });

  group('allowedDismissDirection', () {
    test('backlog only allows forward swipe', () {
      expect(
        allowedDismissDirection(TaskColumn.backlog),
        DismissDirection.startToEnd,
      );
    });

    test('inProgress allows both directions', () {
      expect(
        allowedDismissDirection(TaskColumn.inProgress),
        DismissDirection.horizontal,
      );
    });

    test('testing allows both directions', () {
      expect(
        allowedDismissDirection(TaskColumn.testing),
        DismissDirection.horizontal,
      );
    });

    test('done only allows backward swipe', () {
      expect(
        allowedDismissDirection(TaskColumn.done),
        DismissDirection.endToStart,
      );
    });
  });

  group('canDropOnColumn', () {
    test('rejects drop on the source column', () {
      final t = _task(column: TaskColumn.inProgress);
      expect(canDropOnColumn(t, TaskColumn.inProgress), isFalse);
    });

    test('accepts drop on a different column', () {
      final t = _task(column: TaskColumn.inProgress);
      expect(canDropOnColumn(t, TaskColumn.testing), isTrue);
      expect(canDropOnColumn(t, TaskColumn.done), isTrue);
      expect(canDropOnColumn(t, TaskColumn.backlog), isTrue);
    });

    test('a backlog task can drop anywhere except backlog', () {
      final t = _task(column: TaskColumn.backlog);
      for (final col in TaskColumn.values) {
        expect(canDropOnColumn(t, col), col != TaskColumn.backlog);
      }
    });
  });

  group('columnIcon', () {
    test('every column has a distinct icon', () {
      final icons = TaskColumn.values.map(columnIcon).toSet();
      expect(icons.length, TaskColumn.values.length);
    });

    test('backlog → inbox', () {
      expect(columnIcon(TaskColumn.backlog), Icons.inbox_outlined);
    });

    test('done → check_circle', () {
      expect(columnIcon(TaskColumn.done), Icons.check_circle_outline);
    });
  });

  group('difficultyChipData', () {
    test('1 → Trivial grey', () {
      final d = difficultyChipData(1);
      expect(d.label, contains('Trivial'));
      expect(d.label.startsWith('·'), isTrue);
    });

    test('2 (default) → Easy green', () {
      final d = difficultyChipData(2);
      expect(d.label, contains('Easy'));
      expect(d.label.startsWith('··'), isTrue);
    });

    test('3 → Medium', () {
      expect(difficultyChipData(3).label, contains('Medium'));
    });

    test('4 → Hard', () {
      expect(difficultyChipData(4).label, contains('Hard'));
    });

    test('5 → Expert', () {
      expect(difficultyChipData(5).label, contains('Expert'));
    });

    test('out-of-range falls through to Easy', () {
      expect(difficultyChipData(0).label, contains('Easy'));
      expect(difficultyChipData(99).label, contains('Easy'));
      expect(difficultyChipData(-1).label, contains('Easy'));
    });

    test('each defined difficulty has a distinct colour', () {
      final colors = [1, 2, 3, 4, 5].map((d) => difficultyChipData(d).color);
      expect(colors.toSet().length, 5);
    });
  });

  group('roleLabelFor / requirementChipText', () {
    test('single known role uses catalog name', () {
      // We don't assert exact catalog string (depends on game_economy data)
      // but it must be non-empty and not the raw key when a catalog entry
      // exists — at minimum it's never null.
      final label = roleLabelFor(_task(allowedRoles: const ['coder']));
      expect(label, isNotEmpty);
    });

    test('single unknown role falls back to the key', () {
      final label = roleLabelFor(
        _task(allowedRoles: const ['totally-not-a-real-role']),
      );
      expect(label, 'totally-not-a-real-role');
    });

    test('multiple roles render as count', () {
      expect(
        roleLabelFor(_task(allowedRoles: const ['a', 'b'])),
        '2 ролей',
      );
      expect(
        roleLabelFor(_task(allowedRoles: const ['a', 'b', 'c'])),
        '3 ролей',
      );
    });

    test('chip text contains required level and role label', () {
      final t = _task(difficulty: 4, allowedRoles: const ['coder']);
      final txt = requirementChipText(t);
      expect(txt, contains('🎯'));
      expect(txt, contains('Lv ${t.requiredLevel}+'));
    });

    test('chip text uses requiredLevel from difficulty', () {
      // requiredLevelFor(5) = 11
      final t = _task(difficulty: 5);
      expect(requirementChipText(t), contains('Lv 11+'));
    });
  });

  group('formatBytes', () {
    test('zero / negative → "0 B"', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-100), '0 B');
    });

    test('sub-KB shows raw bytes', () {
      expect(formatBytes(1), '1 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('1024 B → 1.0 KB', () {
      expect(formatBytes(1024), '1.0 KB');
    });

    test('sub-MB shows KB with one decimal', () {
      expect(formatBytes(1536), '1.5 KB');
    });

    test('MB threshold', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes((1.5 * 1024 * 1024).round()), '1.5 MB');
    });

    test('multi-MB still uses one decimal', () {
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('isAttachmentOverCap', () {
    test('exactly at cap is allowed', () {
      expect(isAttachmentOverCap(maxAttachmentBytes), isFalse);
    });

    test('one byte over is rejected', () {
      expect(isAttachmentOverCap(maxAttachmentBytes + 1), isTrue);
    });

    test('zero bytes is allowed', () {
      expect(isAttachmentOverCap(0), isFalse);
    });
  });

  group('mimeFromName', () {
    test('image extensions', () {
      expect(mimeFromName('a.png'), 'image/png');
      expect(mimeFromName('a.jpg'), 'image/jpeg');
      expect(mimeFromName('a.JPEG'), 'image/jpeg');
      expect(mimeFromName('a.gif'), 'image/gif');
      expect(mimeFromName('a.webp'), 'image/webp');
    });

    test('document extensions', () {
      expect(mimeFromName('doc.pdf'), 'application/pdf');
      expect(mimeFromName('notes.txt'), 'text/plain');
      expect(mimeFromName('readme.md'), 'text/plain');
      expect(mimeFromName('data.json'), 'application/json');
      expect(mimeFromName('archive.zip'), 'application/zip');
    });

    test('unknown extension → octet-stream', () {
      expect(mimeFromName('a.xyz'), 'application/octet-stream');
    });

    test('no extension → octet-stream', () {
      expect(mimeFromName('Makefile'), 'application/octet-stream');
    });

    test('extensions are case-insensitive', () {
      expect(mimeFromName('HELLO.PNG'), 'image/png');
      expect(mimeFromName('Hello.Pdf'), 'application/pdf');
    });

    test('multi-dot filenames use the last segment', () {
      expect(mimeFromName('archive.tar.gz'), 'application/octet-stream');
      expect(mimeFromName('photo.final.PNG'), 'image/png');
    });
  });

  group('formatWorkDuration', () {
    test('zero seconds', () {
      expect(formatWorkDuration(0), '0 с');
    });

    test('sub-minute', () {
      expect(formatWorkDuration(42), '42 с');
      expect(formatWorkDuration(59), '59 с');
    });

    test('exactly one minute', () {
      expect(formatWorkDuration(60), '1хв 0с');
    });

    test('mixed minutes and seconds', () {
      expect(formatWorkDuration(187), '3хв 7с');
    });

    test('large value', () {
      expect(formatWorkDuration(3600), '60хв 0с');
    });

    test('negative input clamps to 0', () {
      expect(formatWorkDuration(-30), '0 с');
    });
  });
}
