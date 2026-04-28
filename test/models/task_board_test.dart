import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/task_board.dart';

void main() {
  // ─── TaskColumn ────────────────────────────────────────────────────────

  group('TaskColumn', () {
    test('fromKey parses all known keys', () {
      expect(TaskColumn.fromKey('backlog'), TaskColumn.backlog);
      expect(TaskColumn.fromKey('in_progress'), TaskColumn.inProgress);
      expect(TaskColumn.fromKey('testing'), TaskColumn.testing);
      expect(TaskColumn.fromKey('done'), TaskColumn.done);
    });

    test('fromKey defaults to backlog for unknown key', () {
      expect(TaskColumn.fromKey('unknown'), TaskColumn.backlog);
      expect(TaskColumn.fromKey(''), TaskColumn.backlog);
      expect(TaskColumn.fromKey('TODO'), TaskColumn.backlog);
    });

    test('key property round-trips through fromKey', () {
      for (final col in TaskColumn.values) {
        expect(TaskColumn.fromKey(col.key), col);
      }
    });

    test('label is non-empty for all values', () {
      for (final col in TaskColumn.values) {
        expect(col.label.isNotEmpty, isTrue);
      }
    });
  });

  // ─── TaskPriority ──────────────────────────────────────────────────────

  group('TaskPriority', () {
    test('fromKey parses all known keys', () {
      expect(TaskPriority.fromKey('low'), TaskPriority.low);
      expect(TaskPriority.fromKey('normal'), TaskPriority.normal);
      expect(TaskPriority.fromKey('high'), TaskPriority.high);
      expect(TaskPriority.fromKey('urgent'), TaskPriority.urgent);
    });

    test('fromKey defaults to normal for unknown key', () {
      expect(TaskPriority.fromKey('unknown'), TaskPriority.normal);
      expect(TaskPriority.fromKey(''), TaskPriority.normal);
      expect(TaskPriority.fromKey('CRITICAL'), TaskPriority.normal);
    });

    test('key property round-trips through fromKey', () {
      for (final priority in TaskPriority.values) {
        expect(TaskPriority.fromKey(priority.key), priority);
      }
    });

    test('label is non-empty for all values', () {
      for (final priority in TaskPriority.values) {
        expect(priority.label.isNotEmpty, isTrue);
      }
    });
  });

  // ─── StickyColor ──────────────────────────────────────────────────────

  group('StickyColor', () {
    test('fromKey parses all known keys', () {
      expect(StickyColor.fromKey('yellow'), StickyColor.yellow);
      expect(StickyColor.fromKey('pink'), StickyColor.pink);
      expect(StickyColor.fromKey('blue'), StickyColor.blue);
      expect(StickyColor.fromKey('green'), StickyColor.green);
      expect(StickyColor.fromKey('orange'), StickyColor.orange);
      expect(StickyColor.fromKey('purple'), StickyColor.purple);
    });

    test('fromKey defaults to yellow for unknown key', () {
      expect(StickyColor.fromKey('unknown'), StickyColor.yellow);
      expect(StickyColor.fromKey(''), StickyColor.yellow);
    });

    test('key property round-trips through fromKey', () {
      for (final color in StickyColor.values) {
        expect(StickyColor.fromKey(color.key), color);
      }
    });
  });

  // ─── requiredLevelFor ─────────────────────────────────────────────────

  group('requiredLevelFor', () {
    test('difficulty 1 (Trivial) requires level 1', () {
      expect(requiredLevelFor(1), 1);
    });

    test('difficulty 2 (Easy) requires level 2', () {
      expect(requiredLevelFor(2), 2);
    });

    test('difficulty 3 (Medium) requires level 4', () {
      expect(requiredLevelFor(3), 4);
    });

    test('difficulty 4 (Hard) requires level 7', () {
      expect(requiredLevelFor(4), 7);
    });

    test('difficulty 5 (Expert) requires level 11', () {
      expect(requiredLevelFor(5), 11);
    });

    test('requirements increase monotonically with difficulty', () {
      final levels = List.generate(5, (i) => requiredLevelFor(i + 1));
      for (int i = 0; i < levels.length - 1; i++) {
        expect(levels[i] < levels[i + 1], isTrue,
            reason: 'level for difficulty ${i + 1} should be less than difficulty ${i + 2}');
      }
    });

    test('out-of-range difficulties are clamped to [1,5]', () {
      expect(requiredLevelFor(0), requiredLevelFor(1));
      expect(requiredLevelFor(6), requiredLevelFor(5));
      expect(requiredLevelFor(-1), requiredLevelFor(1));
      expect(requiredLevelFor(100), requiredLevelFor(5));
    });
  });

  // ─── TaskDifficultyExt ────────────────────────────────────────────────

  group('TaskDifficultyExt', () {
    test('difficultyLabel maps correctly', () {
      expect(1.difficultyLabel, 'Trivial');
      expect(2.difficultyLabel, 'Easy');
      expect(3.difficultyLabel, 'Medium');
      expect(4.difficultyLabel, 'Hard');
      expect(5.difficultyLabel, 'Expert');
    });

    test('difficultyLabel fallback for out-of-range', () {
      expect(0.difficultyLabel, 'Easy');
      expect(99.difficultyLabel, 'Easy');
    });

    test('difficultyStars length matches difficulty level', () {
      expect(1.difficultyStars, '·');
      expect(2.difficultyStars, '··');
      expect(3.difficultyStars, '···');
      expect(4.difficultyStars, '····');
      expect(5.difficultyStars, '·····');
    });
  });

  // ─── TaskAttachment ───────────────────────────────────────────────────

  group('TaskAttachment', () {
    final sampleAttachment = TaskAttachment(
      id: 'attach-1',
      name: 'screenshot.png',
      mimeType: 'image/png',
      sizeBytes: 1024,
      dataBase64: 'base64data',
      uploadedAt: DateTime.parse('2026-01-01T00:00:00Z'),
    );

    test('isImage is true for image/png', () {
      expect(sampleAttachment.isImage, isTrue);
    });

    test('isImage is true for image/jpeg', () {
      final jpeg = TaskAttachment(
        id: 'a',
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 512,
        dataBase64: '',
        uploadedAt: DateTime.now(),
      );
      expect(jpeg.isImage, isTrue);
    });

    test('isImage is false for non-image mime type', () {
      final pdf = TaskAttachment(
        id: 'a',
        name: 'doc.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 2048,
        dataBase64: '',
        uploadedAt: DateTime.now(),
      );
      expect(pdf.isImage, isFalse);
    });

    test('fromJson / toJson round-trip', () {
      final json = sampleAttachment.toJson();
      final restored = TaskAttachment.fromJson(json);

      expect(restored.id, sampleAttachment.id);
      expect(restored.name, sampleAttachment.name);
      expect(restored.mimeType, sampleAttachment.mimeType);
      expect(restored.sizeBytes, sampleAttachment.sizeBytes);
      expect(restored.dataBase64, sampleAttachment.dataBase64);
      expect(restored.uploadedAt.toIso8601String(),
          sampleAttachment.uploadedAt.toIso8601String());
    });

    test('fromJson handles missing optional fields with defaults', () {
      final json = {
        'id': 'x',
        'name': 'file.bin',
        'uploadedAt': '2026-01-01T00:00:00.000Z',
        // mimeType, sizeBytes, dataBase64 are missing
      };
      final attachment = TaskAttachment.fromJson(json);

      expect(attachment.mimeType, 'application/octet-stream');
      expect(attachment.sizeBytes, 0);
      expect(attachment.dataBase64, '');
    });
  });

  // ─── TaskCard ────────────────────────────────────────────────────────

  group('TaskCard', () {
    final now = DateTime.parse('2026-01-01T12:00:00Z');

    TaskCard makeCard({
      String id = 'task-1',
      String title = 'Fix bug',
      TaskColumn column = TaskColumn.backlog,
      TaskPriority priority = TaskPriority.normal,
      StickyColor color = StickyColor.yellow,
      int difficulty = 2,
      List<String> allowedRoles = const ['coder'],
    }) {
      return TaskCard(
        id: id,
        title: title,
        column: column,
        priority: priority,
        color: color,
        difficulty: difficulty,
        allowedRoles: allowedRoles,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('defaults: column=backlog, priority=normal, color=yellow', () {
      final card = TaskCard(
        id: 'x',
        title: 'Test',
        createdAt: now,
        updatedAt: now,
      );
      expect(card.column, TaskColumn.backlog);
      expect(card.priority, TaskPriority.normal);
      expect(card.color, StickyColor.yellow);
      expect(card.difficulty, 2);
      expect(card.allowedRoles, ['coder']);
      expect(card.taskType, 'coding');
    });

    test('requiredLevel matches requiredLevelFor(difficulty)', () {
      for (int d = 1; d <= 5; d++) {
        final card = makeCard(difficulty: d);
        expect(card.requiredLevel, requiredLevelFor(d));
      }
    });

    test('copyWith preserves unchanged fields', () {
      final original = makeCard(
        title: 'Original',
        column: TaskColumn.backlog,
        difficulty: 2,
      );

      final updated = original.copyWith(title: 'Updated');

      expect(updated.id, original.id);
      expect(updated.title, 'Updated');
      expect(updated.column, original.column);
      expect(updated.difficulty, original.difficulty);
      expect(updated.allowedRoles, original.allowedRoles);
      expect(updated.createdAt, original.createdAt);
    });

    test('copyWith changes only targeted field', () {
      final card = makeCard(column: TaskColumn.backlog);
      final moved = card.copyWith(column: TaskColumn.inProgress);

      expect(moved.column, TaskColumn.inProgress);
      expect(moved.title, card.title);
      expect(moved.priority, card.priority);
    });

    test('fromJson / toJson round-trip preserves all fields', () {
      final original = TaskCard(
        id: 'task-42',
        title: 'Refactor API',
        description: 'Clean up the endpoints',
        column: TaskColumn.inProgress,
        priority: TaskPriority.high,
        color: StickyColor.blue,
        assignedAgents: ['coder#1', 'reviewer#1'],
        createdAt: DateTime.parse('2026-01-01T10:00:00Z'),
        updatedAt: DateTime.parse('2026-01-01T11:00:00Z'),
        difficulty: 3,
        allowedRoles: ['coder', 'tech-lead'],
        taskType: 'review',
        attachments: const [],
      );

      final json = original.toJson();
      final restored = TaskCard.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.description, original.description);
      expect(restored.column, original.column);
      expect(restored.priority, original.priority);
      expect(restored.color, original.color);
      expect(restored.assignedAgents, original.assignedAgents);
      expect(restored.difficulty, original.difficulty);
      expect(restored.allowedRoles, original.allowedRoles);
      expect(restored.taskType, original.taskType);
    });

    test('fromJson handles missing optional fields with defaults', () {
      final json = {
        'id': 'task-1',
        'title': 'Simple',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
      };
      final card = TaskCard.fromJson(json);

      expect(card.description, '');
      expect(card.column, TaskColumn.backlog);
      expect(card.priority, TaskPriority.normal);
      expect(card.color, StickyColor.yellow);
      expect(card.difficulty, 2);
      expect(card.allowedRoles, ['coder']);
      expect(card.taskType, 'coding');
      expect(card.attachments, isEmpty);
    });

    test('fromJson with attachments round-trips correctly', () {
      final card = TaskCard(
        id: 'task-1',
        title: 'With attachment',
        createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
        updatedAt: DateTime.parse('2026-01-01T00:00:00Z'),
        attachments: [
          TaskAttachment(
            id: 'att-1',
            name: 'design.png',
            mimeType: 'image/png',
            sizeBytes: 512,
            dataBase64: 'abc123',
            uploadedAt: DateTime.parse('2026-01-01T00:00:00Z'),
          ),
        ],
      );

      final restored = TaskCard.fromJson(card.toJson());
      expect(restored.attachments.length, 1);
      expect(restored.attachments[0].name, 'design.png');
    });
  });

  // ─── BoardState ──────────────────────────────────────────────────────

  group('BoardState', () {
    final now = DateTime.parse('2026-01-01T00:00:00Z');

    TaskCard card(String id, TaskColumn col) => TaskCard(
          id: id,
          title: 'Task $id',
          column: col,
          createdAt: now,
          updatedAt: now,
        );

    test('empty BoardState has no tasks', () {
      const board = BoardState();
      expect(board.tasks, isEmpty);
    });

    test('tasksInColumn filters correctly', () {
      final board = BoardState(tasks: [
        card('t1', TaskColumn.backlog),
        card('t2', TaskColumn.inProgress),
        card('t3', TaskColumn.backlog),
        card('t4', TaskColumn.done),
      ]);

      final backlog = board.tasksInColumn(TaskColumn.backlog);
      expect(backlog.length, 2);
      expect(backlog.map((t) => t.id), containsAll(['t1', 't3']));
    });

    test('tasksInColumn returns empty for column with no tasks', () {
      final board = BoardState(tasks: [
        card('t1', TaskColumn.backlog),
      ]);
      expect(board.tasksInColumn(TaskColumn.done), isEmpty);
    });

    test('encode / decode round-trip preserves tasks', () {
      final board = BoardState(tasks: [
        card('t1', TaskColumn.backlog),
        card('t2', TaskColumn.inProgress),
      ]);

      final encoded = board.encode();
      final decoded = BoardState.decode(encoded);

      expect(decoded.tasks.length, 2);
      expect(decoded.tasks[0].id, 't1');
      expect(decoded.tasks[1].id, 't2');
    });

    test('fromJson / toJson round-trip', () {
      final board = BoardState(tasks: [card('task-1', TaskColumn.testing)]);
      final restored = BoardState.fromJson(board.toJson());

      expect(restored.tasks.length, 1);
      expect(restored.tasks[0].column, TaskColumn.testing);
    });

    test('decode handles empty tasks list', () {
      final board = BoardState();
      final decoded = BoardState.decode(board.encode());
      expect(decoded.tasks, isEmpty);
    });

    test('fromJson with missing tasks key falls back to empty list', () {
      final board = BoardState.fromJson({});
      expect(board.tasks, isEmpty);
    });

    test('toJson with tasks serializes task list', () {
      final board = BoardState(tasks: [card('t1', TaskColumn.backlog)]);
      final json = board.toJson();
      expect((json['tasks'] as List).length, 1);
    });
  });
}
