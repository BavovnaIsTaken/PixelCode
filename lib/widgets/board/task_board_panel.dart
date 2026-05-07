/// Kanban-style task board with drag-and-drop sticky notes.
/// Mobile: single column at a time with swipeable PageView + tab rail.
/// Desktop: side-by-side columns in a Row.
library;

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/task_board.dart';
import '../../models/work_log_entry.dart';
import '../../providers/active_facilitator_style_provider.dart';
import '../../providers/agent_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/task_board_provider.dart';
import '../../providers/task_progress_provider.dart';
import '../../utils/kanban_labels.dart';
import 'task_board_helpers.dart';

// ─── Sticky note colors ─────────────────────────────────────────────────────

const _stickyColors = <StickyColor, (Color bg, Color border, Color text)>{
  StickyColor.yellow: (Color(0xFFFFF9C4), Color(0xFFFFEB3B), Color(0xFF5D4037)),
  StickyColor.pink: (Color(0xFFF8BBD0), Color(0xFFE91E63), Color(0xFF880E4F)),
  StickyColor.blue: (Color(0xFFBBDEFB), Color(0xFF2196F3), Color(0xFF0D47A1)),
  StickyColor.green: (Color(0xFFC8E6C9), Color(0xFF4CAF50), Color(0xFF1B5E20)),
  StickyColor.orange: (Color(0xFFFFE0B2), Color(0xFFFF9800), Color(0xFFE65100)),
  StickyColor.purple: (Color(0xFFE1BEE7), Color(0xFF9C27B0), Color(0xFF4A148C)),
};

const _priorityIndicators = <TaskPriority, (Color color, String icon)>{
  TaskPriority.low: (Color(0xFF78909C), '↓'),
  TaskPriority.normal: (Color(0xFF90A4AE), '•'),
  TaskPriority.high: (Color(0xFFFF9800), '↑'),
  TaskPriority.urgent: (Color(0xFFFF3B3B), '⚡'),
};

const _columnColors = <TaskColumn, Color>{
  TaskColumn.backlog: Color(0xFF424242),
  TaskColumn.inProgress: Color(0xFF1565C0),
  TaskColumn.testing: Color(0xFFE65100),
  TaskColumn.done: Color(0xFF2E7D32),
};

const _columnEmptyHints = <TaskColumn, String>{
  TaskColumn.backlog: 'Натисніть «+» щоб створити задачу',
  TaskColumn.inProgress: 'Перемістіть задачу сюди, щоб почати роботу',
  TaskColumn.testing: 'Задачі на перевірці з\'являться тут',
  TaskColumn.done: 'Завершені задачі будуть тут',
};

// ─── Main Board Panel ───────────────────────────────────────────────────────

class TaskBoardPanel extends ConsumerWidget {
  const TaskBoardPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activates the simulation timer for auto-advancing tasks.
    ref.watch(taskProgressProvider);
    final board = ref.watch(taskBoardProvider);
    final isNarrow = MediaQuery.sizeOf(context).width < 768;
    final colors = context.appColors;

    return Container(
      color: colors.background,
      child: Column(
        children: [
          _BoardHeader(taskCount: board.tasks.length),
          if (isNarrow)
            Expanded(child: _MobileBoard(board: board))
          else
            Expanded(child: _DesktopBoard(board: board)),
        ],
      ),
    );
  }
}

// ─── Desktop Board (original Row layout) ────────────────────────────────────

class _DesktopBoard extends ConsumerWidget {
  final BoardState board;
  const _DesktopBoard({required this.board});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final column in TaskColumn.values) ...[
            if (column != TaskColumn.values.first) const SizedBox(width: 10),
            Expanded(
              child: _DesktopColumn(
                column: column,
                tasks: board.tasksInColumn(column),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Mobile Board (PageView + Tab Rail) ─────────────────────────────────────

class _MobileBoard extends ConsumerStatefulWidget {
  final BoardState board;
  const _MobileBoard({required this.board});

  @override
  ConsumerState<_MobileBoard> createState() => _MobileBoardState();
}

class _MobileBoardState extends ConsumerState<_MobileBoard> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.board;

    // Check if entire board is empty
    if (board.tasks.isEmpty) {
      return Column(
        children: [
          _ColumnTabRail(
            currentIndex: _currentIndex,
            taskCounts: {
              for (final c in TaskColumn.values) c: board.tasksInColumn(c).length,
            },
            onTabTapped: _onTabTapped,
          ),
          const Expanded(child: _GlobalEmptyState()),
        ],
      );
    }

    return Column(
      children: [
        _ColumnTabRail(
          currentIndex: _currentIndex,
          taskCounts: {
            for (final c in TaskColumn.values) c: board.tasksInColumn(c).length,
          },
          onTabTapped: _onTabTapped,
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: TaskColumn.values.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final column = TaskColumn.values[index];
              final tasks = board.tasksInColumn(column);
              return _MobileColumnPage(column: column, tasks: tasks);
            },
          ),
        ),
      ],
    );
  }
}

// ─── Column Tab Rail ────────────────────────────────────────────────────────

class _ColumnTabRail extends StatelessWidget {
  final int currentIndex;
  final Map<TaskColumn, int> taskCounts;
  final ValueChanged<int> onTabTapped;

  const _ColumnTabRail({
    required this.currentIndex,
    required this.taskCounts,
    required this.onTabTapped,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(
          bottom: BorderSide(color: colors.divider),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < TaskColumn.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _TabItem(
                column: TaskColumn.values[i],
                count: taskCounts[TaskColumn.values[i]] ?? 0,
                isActive: i == currentIndex,
                onTap: () => onTabTapped(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabItem extends ConsumerWidget {
  final TaskColumn column;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _TabItem({
    required this.column,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final columnColor = _columnColors[column]!;
    final style = ref.watch(activeFacilitatorStyleProvider).valueOrNull;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? columnColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Square pixel dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: isActive
                    ? columnColor
                    : columnColor.withValues(alpha: 0.4),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: columnColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 5),
            // Label
            Flexible(
              child: Text(
                kanbanColumnLabel(column, style),
                style: TextStyle(
                  color: isActive
                      ? colors.textHigh
                      : colors.textLow,
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // Count badge (only if > 0)
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? columnColor.withValues(alpha: 0.25)
                      : colors.surfaceDim,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isActive
                        ? columnColor
                        : colors.textLow,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Global Empty State ─────────────────────────────────────────────────────

class _GlobalEmptyState extends StatelessWidget {
  const _GlobalEmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pixel-art kanban icon
            _PixelBoardIcon(),
            const SizedBox(height: 20),
            Text(
              'Дошка порожня',
              style: TextStyle(
                color: colors.textMedium,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Створіть першу задачу,\nщоб почати працювати',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textLow,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _LargeAddTaskButton(),
          ],
        ),
      ),
    );
  }
}

class _PixelBoardIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accent = context.appColors.accent;
    return SizedBox(
      width: 52,
      height: 52,
      child: CustomPaint(
        painter: _PixelBoardPainter(accent),
      ),
    );
  }
}

class _PixelBoardPainter extends CustomPainter {
  final Color accent;
  _PixelBoardPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw a 10x10 pixel grid forming a kanban board icon
    // Board outline
    paint.color = accent.withValues(alpha: 0.15);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 6, size.width - 4, size.height - 8),
        const Radius.circular(3),
      ),
      paint,
    );

    // Board border
    paint.color = accent.withValues(alpha: 0.3);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, 6, size.width - 4, size.height - 8),
        const Radius.circular(3),
      ),
      paint,
    );
    paint.style = PaintingStyle.fill;

    // Clipboard clip on top
    paint.color = accent.withValues(alpha: 0.4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width / 2 - 8, 0, 16, 10),
        const Radius.circular(2),
      ),
      paint,
    );

    // Three column indicators
    final colWidth = (size.width - 20) / 3;
    final colors = [
      const Color(0xFF1565C0).withValues(alpha: 0.6),
      const Color(0xFFE65100).withValues(alpha: 0.6),
      const Color(0xFF2E7D32).withValues(alpha: 0.6),
    ];

    for (int i = 0; i < 3; i++) {
      final x = 8 + i * (colWidth + 2);

      // Column header dot
      paint.color = colors[i];
      canvas.drawCircle(
        Offset(x + colWidth / 2, 16),
        2,
        paint,
      );

      // "Cards" in column (small rectangles)
      paint.color = colors[i].withValues(alpha: 0.3);
      final cardCount = [2, 1, 1][i];
      for (int j = 0; j < cardCount; j++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 1, 22 + j * 10.0, colWidth - 2, 7),
            const Radius.circular(1),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LargeAddTaskButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.appColors.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showAddDialog(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: accent.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16, color: accent),
            const SizedBox(width: 6),
            Text(
              'Створити задачу',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mobile Column Page ─────────────────────────────────────────────────────

class _MobileColumnPage extends ConsumerWidget {
  final TaskColumn column;
  final List<TaskCard> tasks;

  const _MobileColumnPage({required this.column, required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) {
      return _ColumnEmptyState(column: column);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _MobileSwipeCard(task: task, column: column);
      },
    );
  }
}

// ─── Per-Column Empty State ─────────────────────────────────────────────────

class _ColumnEmptyState extends StatelessWidget {
  final TaskColumn column;
  const _ColumnEmptyState({required this.column});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final columnColor = _columnColors[column]!;
    final hint = _columnEmptyHints[column] ?? '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: columnColor.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: columnColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  columnIcon(column),
                  size: 20,
                  color: columnColor.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Немає задач',
                style: TextStyle(
                  color: colors.textLow,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textLow.withValues(alpha: 0.6),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ─── Mobile Swipe Card (Dismissible wrapper) ────────────────────────────────

class _MobileSwipeCard extends ConsumerWidget {
  final TaskCard task;
  final TaskColumn column;

  const _MobileSwipeCard({required this.task, required this.column});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = nextColumn(column);
    final prev = prevColumn(column);

    return Dismissible(
      key: ValueKey(task.id),
      direction: allowedDismissDirection(column),
      dismissThresholds: const {DismissDirection.horizontal: 0.3},
      confirmDismiss: (direction) async {
        final target = direction == DismissDirection.startToEnd ? next : prev;
        if (target != null) {
          HapticFeedback.lightImpact();
          ref.read(taskBoardProvider.notifier).moveTask(
                taskId: task.id,
                column: target,
              );
        }
        return false; // never actually dismiss
      },
      background: next != null
          ? _SwipeBackground(
              column: next,
              alignment: Alignment.centerLeft,
              icon: Icons.arrow_forward_rounded,
            )
          : const SizedBox.shrink(),
      secondaryBackground: prev != null
          ? _SwipeBackground(
              column: prev,
              alignment: Alignment.centerRight,
              icon: Icons.arrow_back_rounded,
            )
          : const SizedBox.shrink(),
      child: _MobileStickyNote(task: task),
    );
  }
}

class _SwipeBackground extends ConsumerWidget {
  final TaskColumn column;
  final Alignment alignment;
  final IconData icon;

  const _SwipeBackground({
    required this.column,
    required this.alignment,
    required this.icon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _columnColors[column]!;
    final style = ref.watch(activeFacilitatorStyleProvider).valueOrNull;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color.withValues(alpha: 0.8), size: 18),
          const SizedBox(width: 6),
          Text(
            kanbanColumnLabel(column, style),
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mobile Sticky Note Card ────────────────────────────────────────────────

class _MobileStickyNote extends ConsumerWidget {
  final TaskCard task;
  const _MobileStickyNote({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _stickyColors[task.color]!;
    final priority = _priorityIndicators[task.priority]!;
    final agents = ref.watch(agentsProvider);

    final workLog = ref.watch(workLogProvider)[task.id] ?? [];
    return GestureDetector(
      onTap: () => _showTaskDetailSheet(context, ref, task, agents, workLog),
      child: _buildCard(colors, priority, agents),
    );
  }

  Widget _buildCard(
    (Color bg, Color border, Color text) colors,
    (Color color, String icon) priority,
    Map<String, AgentState> agents,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.$2.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Folded corner decoration
            Positioned(
              top: 0,
              right: 0,
              child: CustomPaint(
                size: const Size(14, 14),
                painter: _FoldedCornerPainter(colors.$2.withValues(alpha: 0.3)),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Priority + title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.priority != TaskPriority.normal) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: priority.$1.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            priority.$2,
                            style: TextStyle(
                              color: priority.$1,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            color: colors.$3,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // Difficulty + requirements
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (task.difficulty != 2)
                        _DifficultyBadge(difficulty: task.difficulty, textColor: colors.$3),
                      _RequirementChip(task: task, textColor: colors.$3),
                    ],
                  ),
                  // Description
                  if (task.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      task.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.$3.withValues(alpha: 0.65),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  // Agents footer
                  if (task.assignedAgents.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: colors.$3.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final agentId in task.assignedAgents)
                              _AgentChip(
                                agentId: agentId,
                                agentState: agents[agentId],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldedCornerPainter extends CustomPainter {
  final Color color;
  _FoldedCornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Task Detail Bottom Sheet ───────────────────────────────────────────────

void _showTaskDetailSheet(
  BuildContext context,
  WidgetRef ref,
  TaskCard task,
  Map<String, AgentState> agents,
  List<WorkLogEntry> workLog,
) {
  final surface = context.appColors.surface;
  showModalBottomSheet(
    context: context,
    backgroundColor: surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _TaskDetailContent(
      taskId: task.id,
      agents: agents,
      workLog: workLog,
    ),
  );
}

class _TaskDetailContent extends ConsumerWidget {
  final String taskId;
  final Map<String, AgentState> agents;
  final List<WorkLogEntry> workLog;

  const _TaskDetailContent({
    required this.taskId,
    required this.agents,
    required this.workLog,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardState = ref.watch(taskBoardProvider);
    final task = boardState.tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () {
        // Task was deleted while sheet was open — close it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
        return TaskCard(
          id: taskId,
          title: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      },
    );
    final themeColors = context.appColors;
    final stickyColors = _stickyColors[task.color]!;
    final priority = _priorityIndicators[task.priority]!;
    final columnColor = _columnColors[task.column]!;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: themeColors.textLow,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Color dot + Priority + Title
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: stickyColors.$1,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: stickyColors.$2, width: 1.5),
                ),
              ),
              const SizedBox(width: 10),
              if (task.priority != TaskPriority.normal) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    priority.$2,
                    style: TextStyle(
                      color: priority.$1,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    color: themeColors.textHigh,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          // Description
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              task.description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Column / Status
          _DetailRow(
            label: 'Стовпець',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: columnColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: columnColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      color: columnColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    kanbanColumnLabel(
                      task.column,
                      ref.watch(activeFacilitatorStyleProvider).valueOrNull,
                    ),
                    style: TextStyle(
                      color: columnColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Priority
          _DetailRow(
            label: 'Пріоритет',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: priority.$1.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${priority.$2} ${task.priority.label}',
                style: TextStyle(
                  color: priority.$1,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Assigned agents
          if (task.assignedAgents.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Агенти',
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final agentId in task.assignedAgents)
                    _AgentChipLarge(
                      agentId: agentId,
                      agentState: agents[agentId],
                    ),
                ],
              ),
            ),
          ],
          // Work history
          if (workLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Історія',
              child: _WorkHistoryList(workLog: workLog, agents: agents),
            ),
          ],
          // Attachments
          const SizedBox(height: 12),
          _DetailRow(
            label: 'Файли',
            child: _AttachmentsSection(task: task),
          ),
          const SizedBox(height: 20),
          // Move task buttons
          _DetailRow(
            label: 'Перемістити',
            child: Row(
              children: [
                for (final col in TaskColumn.values) ...[
                  if (col != TaskColumn.values.first) const SizedBox(width: 6),
                  _MoveColumnButton(
                    column: col,
                    isCurrent: col == task.column,
                    onTap: col == task.column
                        ? null
                        : () {
                            ref.read(taskBoardProvider.notifier).moveTask(
                                  taskId: task.id,
                                  column: col,
                                );
                            Navigator.of(context).pop();
                          },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Delete button
          Center(
            child: TextButton.icon(
              onPressed: () {
                ref.read(taskBoardProvider.notifier).deleteTask(taskId: task.id);
                Navigator.of(context).pop();
              },
              icon: Icon(Icons.delete_outline,
                  size: 16, color: Colors.red.withValues(alpha: 0.6)),
              label: Text(
                'Видалити',
                style: TextStyle(
                  color: Colors.red.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attachments ────────────────────────────────────────────────────────────

class _AttachmentsSection extends ConsumerStatefulWidget {
  final TaskCard task;

  const _AttachmentsSection({required this.task});

  @override
  ConsumerState<_AttachmentsSection> createState() =>
      _AttachmentsSectionState();
}

class _AttachmentsSectionState extends ConsumerState<_AttachmentsSection> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    const typeGroup = XTypeGroup(label: 'Файли');
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        if (isAttachmentOverCap(bytes.length)) {
          _showError(
            '«${file.name}» завеликий (${formatBytes(bytes.length)}). '
            'Максимум ${formatBytes(maxAttachmentBytes)}.',
          );
          continue;
        }
        ref.read(taskBoardProvider.notifier).addAttachment(
              taskId: widget.task.id,
              name: file.name,
              mimeType: file.mimeType ?? mimeFromName(file.name),
              sizeBytes: bytes.length,
              dataBase64: base64Encode(bytes),
            );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _remove(TaskAttachment attachment) {
    ref.read(taskBoardProvider.notifier).removeAttachment(
          taskId: widget.task.id,
          attachmentId: attachment.id,
        );
  }

  void _preview(TaskAttachment attachment) {
    if (!attachment.isImage) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            child: Image.memory(base64Decode(attachment.dataBase64)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.task.attachments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attachments.isEmpty)
          Text(
            'Немає прикріплених файлів',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in attachments)
                _AttachmentTile(
                  attachment: a,
                  onTap: () => _preview(a),
                  onRemove: () => _remove(a),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _uploading ? null : _pickAndUpload,
            icon: _uploading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file, size: 16),
            label: Text(
              _uploading ? 'Завантаження…' : 'Прикріпити файл',
              style: const TextStyle(fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final TaskAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _AttachmentTile({
    required this.attachment,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 32,
                height: 32,
                child: attachment.isImage
                    ? Image.memory(
                        base64Decode(attachment.dataBase64),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(
                        color: Colors.white.withValues(alpha: 0.06),
                        child: Icon(
                          Icons.insert_drive_file_outlined,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    formatBytes(attachment.sizeBytes),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              Icons.close,
              size: 14,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
            splashRadius: 14,
            tooltip: 'Видалити',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _DetailRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _MoveColumnButton extends ConsumerWidget {
  final TaskColumn column;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _MoveColumnButton({
    required this.column,
    required this.isCurrent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _columnColors[column]!;
    final style = ref.watch(activeFacilitatorStyleProvider).valueOrNull;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isCurrent
                ? color.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isCurrent
                  ? color.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: isCurrent ? color : color.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                kanbanColumnLabel(column, style),
                style: TextStyle(
                  color: isCurrent
                      ? color
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: 9,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentChipLarge extends StatelessWidget {
  final String agentId;
  final AgentState? agentState;

  const _AgentChipLarge({required this.agentId, this.agentState});

  @override
  Widget build(BuildContext context) {
    final isActive = agentState?.isActive ?? false;
    final statusColor =
        isActive ? const Color(0xFF00C0D1) : const Color(0xFF78909C);
    final name = agentState?.info.name ?? agentId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Work History List ───────────────────────────────────────────────────────

class _WorkHistoryList extends StatelessWidget {
  final List<WorkLogEntry> workLog;
  final Map<String, AgentState> agents;

  const _WorkHistoryList({required this.workLog, required this.agents});

  @override
  Widget build(BuildContext context) {
    // Group by agentId, summing total duration.
    final totals = <String, int>{};
    final firstSeen = <String, DateTime>{};
    for (final e in workLog) {
      totals[e.agentId] = (totals[e.agentId] ?? 0) + e.durationSeconds;
      firstSeen.putIfAbsent(e.agentId, () => e.startedAt);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in totals.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00C0D1).withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    agents[entry.key]?.info.name ?? entry.key,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  formatWorkDuration(entry.value),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Board Header ───────────────────────────────────────────────────────────

class _BoardHeader extends ConsumerWidget {
  final int taskCount;
  const _BoardHeader({required this.taskCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.dashboard_outlined,
              size: 16, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 8),
          Text(
            'Дошка задач',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$taskCount',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
          _AddTaskButton(
            onAdd: (title, description, color, priority) {
              // Difficulty/allowedRoles/taskType use TaskCard defaults
              // (Easy, ['coder'], 'coding') until the _AddTaskButton sheet
              // grows UI for them. Gating still applies — just trivially
              // passes for any coder of Lv ≥ 2.
              final ok = ref.read(taskBoardProvider.notifier).createTask(
                title: title,
                description: description.isEmpty ? null : description,
                color: color,
                priority: priority,
              );
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сервер не підключено — задачу не створено'),
                    backgroundColor: Color(0xFF5A1A1E),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ─── Add Task Button + Dialog ───────────────────────────────────────────────

class _AddTaskButton extends StatelessWidget {
  final void Function(String title, String description, String color, String priority) onAdd;
  const _AddTaskButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Додати задачу',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showAddTaskDialog(context, onAdd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF00C0D1).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 14, color: const Color(0xFF00C0D1)),
              const SizedBox(width: 4),
              Text(
                'Нова задача',
                style: TextStyle(
                  color: const Color(0xFF00C0D1),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAddTaskDialog(
  BuildContext context,
  void Function(String, String, String, String) onAdd,
) {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  var selectedColor = StickyColor.yellow;
  var selectedPriority = TaskPriority.normal;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => Dialog(
        backgroundColor: const Color(0xFF1A1A1F),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(ctx).width < 600
                ? MediaQuery.sizeOf(ctx).width - 48
                : 400,
            maxHeight: MediaQuery.sizeOf(ctx).height -
                MediaQuery.viewInsetsOf(ctx).bottom -
                48,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text(
                'Новий стікер',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              TextField(
                controller: titleCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Назва задачі...',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF00C0D1)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) {
                  if (titleCtrl.text.trim().isNotEmpty) {
                    onAdd(titleCtrl.text.trim(), descCtrl.text.trim(),
                        selectedColor.key, selectedPriority.key);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
              const SizedBox(height: 12),
              // Description
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Опис (необов\'язково)...',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF00C0D1)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              // Color picker
              Text(
                'Колір',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final color in StickyColor.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = color),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _stickyColors[color]!.$1,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: selectedColor == color
                                  ? Colors.white
                                  : _stickyColors[color]!.$2,
                              width: selectedColor == color ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Priority picker
              Text(
                'Пріоритет',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in TaskPriority.values)
                    GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedPriority = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: selectedPriority == p
                                ? _priorityIndicators[p]!.$1
                                    .withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: selectedPriority == p
                                  ? _priorityIndicators[p]!.$1
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            '${_priorityIndicators[p]!.$2} ${p.label}',
                            style: TextStyle(
                              color: selectedPriority == p
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Скасувати',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (titleCtrl.text.trim().isNotEmpty) {
                        onAdd(titleCtrl.text.trim(), descCtrl.text.trim(),
                            selectedColor.key, selectedPriority.key);
                        Navigator.of(ctx).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C0D1),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                    ),
                    child: const Text(
                      'Створити',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            ),
          ),
        ),
      ),
    ),
  );
}

// Shared helper for the global empty state CTA
void _showAddDialog(BuildContext context, WidgetRef ref) {
  _showAddTaskDialog(context, (title, description, color, priority) {
    final ok = ref.read(taskBoardProvider.notifier).createTask(
      title: title,
      description: description.isEmpty ? null : description,
      color: color,
      priority: priority,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сервер не підключено — задачу не створено'),
          backgroundColor: Color(0xFF5A1A1E),
          duration: Duration(seconds: 3),
        ),
      );
    }
  });
}

// ─── Desktop Board Column (unchanged from original) ─────────────────────────

class _DesktopColumn extends ConsumerWidget {
  final TaskColumn column;
  final List<TaskCard> tasks;

  const _DesktopColumn({required this.column, required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnColor = _columnColors[column]!;

    return DragTarget<TaskCard>(
      onWillAcceptWithDetails: (details) =>
          canDropOnColumn(details.data, column),
      onAcceptWithDetails: (details) {
        ref
            .read(taskBoardProvider.notifier)
            .moveTask(taskId: details.data.id, column: column);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isHovering
                ? columnColor.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isHovering
                  ? columnColor.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Column header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: columnColor,
                        boxShadow: [
                          BoxShadow(
                            color: columnColor.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kanbanColumnLabel(
                          column,
                          ref
                              .watch(activeFacilitatorStyleProvider)
                              .valueOrNull,
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${tasks.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Task cards
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            isHovering ? 'Перетягни сюди' : 'Порожньо',
                            style: TextStyle(
                              color: isHovering
                                  ? columnColor.withValues(alpha: 0.7)
                                  : Colors.white.withValues(alpha: 0.15),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) =>
                            _DesktopStickyNote(task: tasks[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Desktop Sticky Note Card (with drag-and-drop) ──────────────────────────

class _DesktopStickyNote extends ConsumerWidget {
  final TaskCard task;
  const _DesktopStickyNote({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _stickyColors[task.color]!;
    final priority = _priorityIndicators[task.priority]!;
    final agents = ref.watch(agentsProvider);

    return Draggable<TaskCard>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 220,
          child: _buildCard(colors, priority, agents, isDragging: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCard(colors, priority, agents),
      ),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            _showContextMenu(context, ref, details.globalPosition, agents),
        child: _buildCard(colors, priority, agents),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
    Map<String, AgentState> agents,
  ) {
    final allAgentIds = agents.keys.toList();
    // Capture messenger before the async gap so we can safely surface the
    // rejection toast after the menu closes.
    final messenger = ScaffoldMessenger.of(context);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text(
            'Призначити агента',
            style: TextStyle(
              color: Color(0xFF78909C),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final agentId in allAgentIds)
          PopupMenuItem(
            value: 'agent:$agentId',
            height: 32,
            child: Row(
              children: [
                Icon(
                  task.assignedAgents.contains(agentId)
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 14,
                  color: task.assignedAgents.contains(agentId)
                      ? const Color(0xFF00C0D1)
                      : Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 8),
                Text(
                  agents[agentId]?.info.name ?? agentId,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 14, color: Colors.red.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                'Видалити',
                style: TextStyle(
                  color: Colors.red.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'delete') {
        ref.read(taskBoardProvider.notifier).deleteTask(taskId: task.id);
      } else if (value.startsWith('agent:')) {
        final agentId = value.substring(6);
        final isAssigned = task.assignedAgents.contains(agentId);
        // Gate assignment: reject if role mismatched or agent under-leveled.
        // Always allow un-assignment.
        if (!isAssigned) {
          final agent = ref.read(gameEconomyProvider).agents[agentId];
          if (agent != null) {
            final reason = assignmentRejectionReason(task, agent);
            if (reason != null) {
              messenger.showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 4),
                  content: Text(reason),
                ),
              );
              return;
            }
          }
        }
        ref.read(taskBoardProvider.notifier).assignAgent(
              taskId: task.id,
              agentId: agentId,
              assign: !isAssigned,
            );
      }
    });
  }

  Widget _buildCard(
    (Color bg, Color border, Color text) colors,
    (Color color, String icon) priority,
    Map<String, AgentState> agents, {
    bool isDragging = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.$2.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDragging ? 0.4 : 0.2),
              blurRadius: isDragging ? 12 : 4,
              offset: Offset(0, isDragging ? 6 : 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (task.priority != TaskPriority.normal) ...[
                    Text(
                      priority.$2,
                      style: TextStyle(
                        color: priority.$1,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        color: colors.$3,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              // Difficulty + requirements (desktop)
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (task.difficulty != 2)
                    _DifficultyBadge(difficulty: task.difficulty, textColor: colors.$3),
                  _RequirementChip(task: task, textColor: colors.$3),
                ],
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.$3.withValues(alpha: 0.7),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
              if (task.assignedAgents.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final agentId in task.assignedAgents)
                      _AgentChip(
                        agentId: agentId,
                        agentState: agents[agentId],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Difficulty Badge ────────────────────────────────────────────────────────

class _DifficultyBadge extends StatelessWidget {
  final int difficulty;
  final Color textColor;

  const _DifficultyBadge({required this.difficulty, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final data = difficultyChipData(difficulty);
    final label = data.label;
    final color = data.color;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Requirement chip (role + min level) ──────────────────────────────────

class _RequirementChip extends StatelessWidget {
  final TaskCard task;
  final Color textColor;

  const _RequirementChip({required this.task, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: textColor.withValues(alpha: 0.25)),
      ),
      child: Text(
        requirementChipText(task),
        style: TextStyle(
          color: textColor.withValues(alpha: 0.75),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── Agent Chip on Card ─────────────────────────────────────────────────────

class _AgentChip extends StatelessWidget {
  final String agentId;
  final AgentState? agentState;

  const _AgentChip({required this.agentId, this.agentState});

  @override
  Widget build(BuildContext context) {
    final isActive = agentState?.isActive ?? false;
    final statusColor = isActive ? const Color(0xFF00C0D1) : const Color(0xFF78909C);
    final name = agentState?.info.name ?? agentId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.6),
                        blurRadius: 3,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
