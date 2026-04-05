/// Right panel: pixel-art office scene showing agent characters at desks.
///
/// Inspired by pixel-agents (https://github.com/pablodelucca/pixel-agents).
/// Characters animate based on their current status — typing, reading, idle.
/// Monitors glow when the agent sitting at them is active.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';
import 'pixel_office_painter.dart';

class AgentCanvas extends ConsumerStatefulWidget {
  const AgentCanvas({super.key});

  @override
  ConsumerState<AgentCanvas> createState() => _AgentCanvasState();
}

class _AgentCanvasState extends ConsumerState<AgentCanvas> {
  int _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Animation tick every 300ms — slow pixel-art cadence.
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentsProvider);

    return Container(
      color: const Color(0xFF0E0E11),
      child: Column(
        children: [
          _buildHeader(agents),
          Expanded(
            child: agents.isEmpty ? _buildWaiting() : _buildOffice(agents),
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

  Widget _buildOffice(Map<String, AgentState> agents) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Pixel-art office scene
            Positioned.fill(
              child: CustomPaint(
                painter: PixelOfficePainter(
                  agents: agents,
                  tick: _tick,
                ),
              ),
            ),
            // Floating name labels over each agent station
            ..._buildNameOverlays(agents, constraints),
          ],
        );
      },
    );
  }

  List<Widget> _buildNameOverlays(
    Map<String, AgentState> agents,
    BoxConstraints constraints,
  ) {
    final scaleX = constraints.maxWidth / kVirtualWidth;
    final scaleY = constraints.maxHeight / kVirtualHeight;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    final offsetX = (constraints.maxWidth - kVirtualWidth * scale) / 2;
    final offsetY = (constraints.maxHeight - kVirtualHeight * scale) / 2;

    final widgets = <Widget>[];

    for (final station in [
      _StationInfo('tech-lead', 'Tech Lead', 102, 42, const Color(0xFF00C0D1)),
      _StationInfo('manager', 'Manager', 30, 86, const Color(0xFFF59E0B)),
      _StationInfo('coder', 'Coder', 102, 86, const Color(0xFF10B981)),
      _StationInfo('reviewer', 'Reviewer', 174, 86, const Color(0xFF8B5CF6)),
      _StationInfo('tester', 'Tester', 30, 130, const Color(0xFFEC4899)),
      _StationInfo('security', 'Security', 102, 130, const Color(0xFFEF4444)),
      _StationInfo('ui-ux-designer', 'UI/UX', 174, 130, const Color(0xFF3B82F6)),
    ]) {
      final agentState = agents[station.agentId];
      final isActive = agentState != null &&
          agentState.status != AgentStatus.idle;

      // Position the label below the desk station
      final screenX = offsetX + station.cx * scale;
      final screenY = offsetY + (station.cy + 4) * scale;

      widgets.add(
        Positioned(
          left: screenX - 40,
          top: screenY,
          child: SizedBox(
            width: 80,
            child: Column(
              children: [
                // Agent name
                Text(
                  station.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive
                        ? station.color
                        : Colors.white.withValues(alpha: 0.35),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                // Status text
                if (isActive)
                  Text(
                    _statusLabel(agentState.status),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: station.color.withValues(alpha: 0.6),
                      fontSize: 8,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                // Current task
                if (agentState?.currentTask != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      agentState!.currentTask!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 7,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  String _statusLabel(AgentStatus status) => switch (status) {
        AgentStatus.thinking => 'Thinking...',
        AgentStatus.typing => 'Writing...',
        AgentStatus.reading => 'Reading...',
        AgentStatus.running => 'Running...',
        AgentStatus.waiting => 'Waiting',
        AgentStatus.idle => '',
      };
}

class _StationInfo {
  final String agentId;
  final String name;
  final double cx; // character center X in virtual px
  final double cy; // character bottom Y in virtual px
  final Color color;

  const _StationInfo(this.agentId, this.name, this.cx, this.cy, this.color);
}
