/// Right panel: pixel-art office scene with animated agent characters.
///
/// Characters move around the office via BFS pathfinding, sit at desks
/// when active, and wander when idle — like a game.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../models/game_economy.dart';
import '../../providers/agent_provider.dart';
import '../../providers/game_economy_provider.dart';
import 'character_sprites.dart';
import 'office_game_state.dart';
import 'pixel_office_painter.dart';
import 'pixel_sprites.dart';

// ─── Main canvas widget ─────────────────────────────────────────────────────

class AgentCanvas extends ConsumerStatefulWidget {
  const AgentCanvas({super.key});

  @override
  ConsumerState<AgentCanvas> createState() => _AgentCanvasState();
}

class _AgentCanvasState extends ConsumerState<AgentCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final OfficeGameState _gameState;
  final SpriteManager _sprites = SpriteManager();
  Duration _lastElapsed = Duration.zero;
  int _tick = 0; // for monitor flicker & bubble animation
  double _tickAccum = 0;

  @override
  void initState() {
    super.initState();
    _gameState = OfficeGameState();
    _ticker = createTicker(_onTick)..start();
    _sprites.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onTick(Duration elapsed) {
    final dt =
        (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    final clampedDt = dt.clamp(0.0, 0.1);

    _gameState.update(clampedDt);

    // Slow tick for monitor animation & bubbles (~3.3 Hz)
    _tickAccum += clampedDt;
    if (_tickAccum >= 0.3) {
      _tickAccum -= 0.3;
      _tick++;
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  bool _logExpanded = false;
  String? _hoveredAgentId;

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentsProvider);
    final metrics = ref.watch(metricsProvider);
    final activityLog = ref.watch(activityLogProvider);
    final commEvents = ref.watch(commGraphProvider);
    final gameEconomy = ref.watch(gameEconomyProvider);

    // Sync agent states and hired status into game engine
    _gameState.syncAgents(agents);
    final hardwareMap = {
      for (final e in gameEconomy.agents.entries)
        e.key: e.value.hardware,
    };
    _gameState.syncHiredAgents(gameEconomy.hiredAgentIds, hardwareMap);

    final activeAgents =
        agents.entries.where((e) => e.value.isActive).toList();

    return Container(
      color: const Color(0xFF0E0E11),
      child: Column(
        children: [
          _buildHeader(agents),
          if (activeAgents.isNotEmpty)
            _ActiveAgentsStrip(agents: activeAgents, tick: _tick),
          Expanded(
            child: agents.isEmpty
                ? _buildWaiting()
                : _buildOffice(agents, gameEconomy.officeLevel),
          ),
          if (metrics.isNotEmpty) _TeamMetricsBar(metrics: metrics),
          if (commEvents.isNotEmpty) _CommGraphPanel(events: commEvents),
          _ActivityLogPanel(
            events: activityLog,
            expanded: _logExpanded,
            onToggle: () => setState(() => _logExpanded = !_logExpanded),
            onClear: () => ref.read(activityLogProvider.notifier).clear(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Map<String, AgentState> agents) {
    final active =
        agents.values.where((a) => a.status != AgentStatus.idle).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_outlined,
              color: Colors.white.withValues(alpha: 0.5), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Team',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active > 0
                  ? const Color(0xFF00C0D1).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              active > 0 ? '$active active' : 'all idle',
              style: TextStyle(
                color: active > 0
                    ? const Color(0xFF00C0D1)
                    : Colors.white.withValues(alpha: 0.3),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaiting() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hourglass_empty_rounded,
            size: 40,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for server connection...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffice(Map<String, AgentState> agents, OfficeLevel officeLevel) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) => _onCanvasHover(event.localPosition, constraints),
          onExit: (_) {
            setState(() => _hoveredAgentId = null);
          },
          child: GestureDetector(
            onTapDown: (d) => _onCanvasTap(d.localPosition, constraints),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: PixelOfficePainter(
                      gameState: _gameState,
                      sprites: _sprites,
                      selectedAgentId: ref.watch(selectedAgentProvider),
                      hoveredAgentId: _hoveredAgentId,
                      tick: _tick,
                      officeLevel: officeLevel,
                    ),
                  ),
                ),
                ..._buildNameOverlays(agents, constraints),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Convert screen position to world position and hit-test characters.
  String? _hitTestCharacter(Offset screenPos, BoxConstraints constraints) {
    final scaleX = constraints.maxWidth / kCanvasWidth;
    final scaleY = constraints.maxHeight / kCanvasHeight;
    final scale = math.min(scaleX, scaleY);
    final offsetX = (constraints.maxWidth - kCanvasWidth * scale) / 2;
    final offsetY = (constraints.maxHeight - kCanvasHeight * scale) / 2;

    final worldX = (screenPos.dx - offsetX) / scale;
    final worldY = (screenPos.dy - offsetY) / scale;

    // Check characters sorted by Y descending (front-most first)
    final chars = _gameState.characters.values.toList()
      ..sort((a, b) => b.y.compareTo(a.y));

    for (final ch in chars) {
      final sittingOffset =
          ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
      final left = ch.x - 8;
      final right = ch.x + 8;
      final top = ch.y + sittingOffset - 28; // slightly less than full sprite
      final bottom = ch.y + sittingOffset;

      if (worldX >= left && worldX <= right &&
          worldY >= top && worldY <= bottom) {
        return ch.agentId;
      }
    }
    return null;
  }

  void _onCanvasHover(Offset pos, BoxConstraints constraints) {
    final hit = _hitTestCharacter(pos, constraints);
    if (hit != _hoveredAgentId) {
      setState(() => _hoveredAgentId = hit);
    }
  }

  void _scheduleOverlayHover(String agentId) {
    if (_hoveredAgentId != agentId) {
      setState(() => _hoveredAgentId = agentId);
    }
  }

  void _onCanvasTap(Offset pos, BoxConstraints constraints) {
    final hit = _hitTestCharacter(pos, constraints);
    if (hit != null) {
      ref.read(selectedAgentProvider.notifier).state = hit;
    }
  }

  List<Widget> _buildNameOverlays(
    Map<String, AgentState> agents,
    BoxConstraints constraints,
  ) {
    final scaleX = constraints.maxWidth / kCanvasWidth;
    final scaleY = constraints.maxHeight / kCanvasHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (constraints.maxWidth - kCanvasWidth * scale) / 2;
    final offsetY = (constraints.maxHeight - kCanvasHeight * scale) / 2;

    final widgets = <Widget>[];

    for (final station in kStations) {
      final ch = _gameState.characters[station.agentId];
      if (ch == null || !ch.isHired) continue;

      final agentState = agents[station.agentId];
      final isActive =
          agentState != null && agentState.status != AgentStatus.idle;
      final isSelected =
          ref.watch(selectedAgentProvider) == station.agentId;
      final isHovered = _hoveredAgentId == station.agentId;
      final color = agentAccentColor(station.agentId);

      // Label follows the character, anchored below
      final labelX = ch.x;
      final sittingOffset =
          ch.state == CharState.typing ? kSittingOffsetPx : 0.0;
      final labelY = ch.y + sittingOffset + 6;

      final screenX = offsetX + labelX * scale;
      final screenY = offsetY + labelY * scale;

      final (nick, role) = _agentNickAndRole(station.agentId);

      final highlighted = isSelected || isHovered;
      final borderColor = isSelected
          ? color
          : const Color(0xFFFFC107); // amber for hover

      widgets.add(
        Positioned(
          left: screenX - 40,
          top: screenY,
          child: GestureDetector(
            onTap: () => ref.read(selectedAgentProvider.notifier).state =
                station.agentId,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _scheduleOverlayHover(station.agentId),
              onHover: (_) => _scheduleOverlayHover(station.agentId),
              onExit: (_) {
                if (_hoveredAgentId == station.agentId) {
                  setState(() => _hoveredAgentId = null);
                }
              },
              child: Container(
                width: 80,
                padding:
                    const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                decoration: BoxDecoration(
                  color: highlighted
                      ? borderColor.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: highlighted
                        ? borderColor.withValues(alpha: 0.4)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    // Nickname
                    Text(
                      nick,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: highlighted
                            ? (isSelected ? color : const Color(0xFFFFC107))
                            : isActive
                                ? color
                                : Colors.white.withValues(alpha: 0.4),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    // Role (always visible)
                    Text(
                      role,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: highlighted
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.white.withValues(alpha: 0.2),
                        fontSize: 7,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    // Status when active
                    if (isActive)
                      Text(
                        _statusLabel(agentState.status),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: color.withValues(alpha: 0.6),
                          fontSize: 7,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  static (String nick, String role) _agentNickAndRole(String id) =>
      switch (id) {
        'manager' => ('Менеджер', 'координатор'),
        'tech-lead' => ('Тех Лід', 'технічний лідер'),
        'coder' => ('Кодер', 'розробник'),
        'reviewer' => ("Рев'юер", 'рецензент'),
        'tester' => ('Тестер', 'контроль якості'),
        'security' => ("Сек'юріті", 'безпека'),
        'ui-ux-designer' => ('Дизайнер', 'UI/UX'),
        _ => (id, ''),
      };

  String _statusLabel(AgentStatus status) => switch (status) {
        AgentStatus.thinking => 'думає...',
        AgentStatus.typing => 'пише...',
        AgentStatus.reading => 'читає...',
        AgentStatus.running => 'виконує...',
        AgentStatus.waiting => 'чекає',
        AgentStatus.idle => '',
      };
}

// ─── Active Agents Status Strip ─────────────────────────────────────────────

class _ActiveAgentsStrip extends StatelessWidget {
  final List<MapEntry<String, AgentState>> agents;
  final int tick;

  const _ActiveAgentsStrip({required this.agents, required this.tick});

  static const _statusIcons = <AgentStatus, IconData>{
    AgentStatus.thinking: Icons.psychology_rounded,
    AgentStatus.typing: Icons.edit_rounded,
    AgentStatus.reading: Icons.visibility_rounded,
    AgentStatus.running: Icons.terminal_rounded,
    AgentStatus.waiting: Icons.hourglass_top_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131316),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          for (final entry in agents)
            _buildAgentRow(entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _buildAgentRow(String agentId, AgentState agent) {
    final color = agentAccentColor(agentId);
    final icon = _statusIcons[agent.status] ?? Icons.circle;
    final elapsed = _formatElapsed(agent.activeSince);
    final description = agent.lastToolDescription ?? agent.currentTask;
    final pulseAlpha = 0.6 + 0.4 * ((tick % 3) / 2.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: pulseAlpha),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            agent.info.name,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            _statusLabel(agent.status),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (description != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '·',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              child: Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                ),
              ),
            ),
          ] else
            const Spacer(),
          if (elapsed != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                elapsed,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(AgentStatus status) => switch (status) {
        AgentStatus.thinking => 'думає',
        AgentStatus.typing => 'пише',
        AgentStatus.reading => 'читає',
        AgentStatus.running => 'виконує',
        AgentStatus.waiting => 'чекає',
        AgentStatus.idle => '',
      };

  String? _formatElapsed(DateTime? since) {
    if (since == null) return null;
    final seconds = DateTime.now().difference(since).inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
  }
}

// ─── Comm Graph Panel ───────────────────────────────────────────────────────

class _CommGraphPanel extends StatefulWidget {
  final List<CommEvent> events;
  const _CommGraphPanel({required this.events});

  @override
  State<_CommGraphPanel> createState() => _CommGraphPanelState();
}

class _CommGraphPanelState extends State<_CommGraphPanel> {
  int? _windowMinutes = 30;

  static const _windows = <int?, String>{
    5: '5m',
    30: '30m',
    60: '1h',
    180: '3h',
    600: '10h',
    1440: '24h',
    null: 'All',
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131316),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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
                'Comms',
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
                'No communications in this window',
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
            from == 'user' ? 'You' : from,
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
            to == 'user' ? 'You' : to,
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

// ─── Team Metrics Bar ───────────────────────────────────────────────────────

class _TeamMetricsBar extends StatelessWidget {
  final Map<String, AgentMetrics> metrics;

  const _TeamMetricsBar({required this.metrics});

  static const _agentLabels = <String, String>{
    'manager': 'MGR',
    'tech-lead': 'TL',
    'coder': 'DEV',
    'reviewer': 'REV',
    'tester': 'QA',
    'security': 'SEC',
    'ui-ux-designer': 'UI',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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
                'Team Metrics',
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
                  label: _agentLabels[entry.key] ?? entry.key,
                  color: agentAccentColor(entry.key),
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

// ─── Activity Log Panel ─────────────────────────────────────────────────────

class _ActivityLogPanel extends StatefulWidget {
  final List<ActivityEventMessage> events;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  const _ActivityLogPanel({
    required this.events,
    required this.expanded,
    required this.onToggle,
    required this.onClear,
  });

  @override
  State<_ActivityLogPanel> createState() => _ActivityLogPanelState();
}

class _ActivityLogPanelState extends State<_ActivityLogPanel> {
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_ActivityLogPanel old) {
    super.didUpdateWidget(old);
    if (widget.events.length > old.events.length && widget.expanded) {
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

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131316),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
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
                    'Activity Log',
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
                  const Spacer(),
                  if (count > 0)
                    GestureDetector(
                      onTap: widget.onClear,
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    widget.expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            SizedBox(
              height: 180,
              child: count == 0
                  ? Center(
                      child: Text(
                        'No activity yet',
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
                        final icon = _eventIcons[e.event] ??
                            Icons.circle_outlined;
                        final time =
                            '${e.timestamp.hour.toString().padLeft(2, '0')}:'
                            '${e.timestamp.minute.toString().padLeft(2, '0')}:'
                            '${e.timestamp.second.toString().padLeft(2, '0')}';

                        return Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 52,
                                child: Text(
                                  time,
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.2),
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
                                    color: Colors.white
                                        .withValues(alpha: 0.45),
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
            ),
        ],
      ),
    );
  }
}
