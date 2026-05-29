/// Three live info panels — Team Metrics, Comm Graph, Activity Log — that used
/// to stack under the office canvas. Hosted by [ActivityOverlaySheet] now;
/// extracted here so the sheet and tests can use them independently of
/// AgentCanvas internals.
library;

import 'package:flutter/material.dart';

import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../services/agent_id_format.dart';
import '../canvas/pixel_sprites.dart' show agentAccentColor;

// ─── Team Metrics Bar ───────────────────────────────────────────────────────

class TeamMetricsBar extends StatelessWidget {
  final Map<String, AgentMetrics> metrics;

  const TeamMetricsBar({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 14, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(
                'Метрики команди',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final entry in metrics.entries)
                _MetricChip(
                  label: shortAgentLabel(entry.key),
                  color: agentAccentColor(agentRoleOf(entry.key)),
                  assigned: entry.value.tasksAssigned,
                  completed: entry.value.tasksCompleted,
                  rework: entry.value.reworkCount,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;
  final int assigned;
  final int completed;
  final int rework;

  const _MetricChip({
    required this.label,
    required this.color,
    required this.assigned,
    required this.completed,
    required this.rework,
  });

  @override
  Widget build(BuildContext context) {
    final hasRework = rework > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasRework
              ? const Color(0xFFEF4444).withValues(alpha: 0.3)
              : color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$completed/$assigned',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
          if (hasRework) ...[
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${rework}rw',
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Comm Graph Panel ───────────────────────────────────────────────────────

class CommGraphPanel extends StatefulWidget {
  final List<CommEvent> events;
  const CommGraphPanel({super.key, required this.events});

  @override
  State<CommGraphPanel> createState() => _CommGraphPanelState();
}

class _CommGraphPanelState extends State<CommGraphPanel> {
  int? _windowMinutes = 30;

  static const _windows = <int?, String>{
    5: '5m',
    30: '30m',
    60: '1h',
    180: '3h',
    600: '10h',
    1440: '24h',
    null: 'Все',
  };

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff =
        _windowMinutes != null ? now - _windowMinutes! * 60 * 1000 : 0;
    final filtered =
        widget.events.where((e) => e.timestamp >= cutoff).toList();

    final edges = <(String, String), int>{};
    for (final e in filtered) {
      final key = (e.from, e.to);
      edges[key] = (edges[key] ?? 0) + 1;
    }

    final sorted = edges.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined,
                  size: 14, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(
                'Комунікації',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              for (final entry in _windows.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _windowMinutes = entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _windowMinutes == entry.key
                            ? const Color(0xFF00C0D1)
                                .withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _windowMinutes == entry.key
                              ? const Color(0xFF00C0D1)
                                  .withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: _windowMinutes == entry.key
                              ? const Color(0xFF00C0D1)
                              : Colors.white.withValues(alpha: 0.25),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Немає комунікацій у цьому вікні',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.15),
                  fontSize: 9,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final edge in sorted.take(12))
                    _CommEdge(
                      from: edge.key.$1,
                      to: edge.key.$2,
                      count: edge.value,
                      fromColor: agentAccentColor(edge.key.$1),
                      toColor: agentAccentColor(edge.key.$2),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommEdge extends StatelessWidget {
  final String from;
  final String to;
  final int count;
  final Color fromColor;
  final Color toColor;

  const _CommEdge({
    required this.from,
    required this.to,
    required this.count,
    required this.fromColor,
    required this.toColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            from == 'user' ? 'Ви' : from,
            style: TextStyle(
              color: fromColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 9,
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          Text(
            to == 'user' ? 'Ви' : to,
            style: TextStyle(
              color: toColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF00C0D1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Color(0xFF00C0D1),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Activity Log Panel ─────────────────────────────────────────────────────

class ActivityLogPanel extends StatefulWidget {
  final List<ActivityEventMessage> events;
  final VoidCallback onClear;

  /// Whether to render the collapsible header. The overlay sheet keeps the
  /// header (so the player can still hit Clear) but skips the redundant
  /// expand/collapse chevron, since the sheet itself controls visibility.
  final bool showHeader;

  /// Body fills the available height; the sheet's [DraggableScrollableSheet]
  /// owns the outer constraint, so we don't impose a 180px inner SizedBox
  /// anymore.
  final bool fillHeight;

  const ActivityLogPanel({
    super.key,
    required this.events,
    required this.onClear,
    this.showHeader = true,
    this.fillHeight = true,
  });

  @override
  State<ActivityLogPanel> createState() => _ActivityLogPanelState();
}

class _ActivityLogPanelState extends State<ActivityLogPanel> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(ActivityLogPanel old) {
    super.didUpdateWidget(old);
    if (widget.events.length > old.events.length) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  static const _eventIcons = <String, IconData>{
    'started': Icons.play_arrow_rounded,
    'tool_use': Icons.build_rounded,
    'completed': Icons.check_circle_outline_rounded,
    'delegated': Icons.call_split_rounded,
    'error': Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final count = widget.events.length;
    final c = context.appColors;

    final body = Stack(
      children: [
        count == 0
            ? Center(
                child: Text(
                  'Поки що немає активності',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.15),
                    fontSize: 11,
                  ),
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                itemCount: count,
                itemBuilder: (context, i) {
                  final e = widget.events[i];
                  final color = agentAccentColor(e.agentId);
                  final icon =
                      _eventIcons[e.event] ?? Icons.circle_outlined;
                  final time =
                      '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                      '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                      '${e.timestamp.second.toString().padLeft(2, '0')}';

                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            time,
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.2),
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Icon(icon, size: 11, color: color),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 62,
                          child: Text(
                            e.agentId,
                            style: TextStyle(
                              color: color,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            e.detail,
                            style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.45),
                              fontSize: 9,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        if (count > 0)
          Positioned(
            right: 8,
            bottom: 8,
            child: GestureDetector(
              onTap: widget.onClear,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E24),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceDim,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        children: [
          if (widget.showHeader)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Журнал активності',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C0D1)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Color(0xFF00C0D1),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.fillHeight) Expanded(child: body) else SizedBox(height: 180, child: body),
        ],
      ),
    );
  }
}
