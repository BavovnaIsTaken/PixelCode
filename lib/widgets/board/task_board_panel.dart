/// Kanban-style task board with drag-and-drop sticky notes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task_board.dart';
import '../../providers/agent_provider.dart';
import '../../providers/task_board_provider.dart';

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

// ─── Main Board Panel ───────────────────────────────────────────────────────

class TaskBoardPanel extends ConsumerWidget {
  const TaskBoardPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(taskBoardProvider);

    return Container(
      color: const Color(0xFF0E0E11),
      child: Column(
        children: [
          // Board header with "add task" button
          _BoardHeader(taskCount: board.tasks.length),
          // Columns
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final column in TaskColumn.values) ...[
                    if (column != TaskColumn.values.first) const SizedBox(width: 10),
                    Expanded(
                      child: _BoardColumn(
                        column: column,
                        tasks: board.tasksInColumn(column),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
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
        onTap: () => _showAddDialog(context),
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

  void _showAddDialog(BuildContext context) {
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
          child: Container(
            width: MediaQuery.sizeOf(ctx).width < 600
                ? MediaQuery.sizeOf(ctx).width - 48
                : 400,
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
                Row(
                  children: [
                    for (final p in TaskPriority.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
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
    );
  }
}

// ─── Board Column ───────────────────────────────────────────────────────────

class _BoardColumn extends ConsumerWidget {
  final TaskColumn column;
  final List<TaskCard> tasks;

  const _BoardColumn({required this.column, required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final columnColor = _columnColors[column]!;

    return DragTarget<TaskCard>(
      onWillAcceptWithDetails: (details) => details.data.column != column,
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
                    Text(
                      column.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
                            _StickyNoteCard(task: tasks[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Sticky Note Card ───────────────────────────────────────────────────────

class _StickyNoteCard extends ConsumerWidget {
  final TaskCard task;
  const _StickyNoteCard({required this.task});

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

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: const Color(0xFF1A1A1F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        // Assign/unassign agents
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
        // Delete
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
              // Priority + title row
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
              // Description
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
              // Assigned agents
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
