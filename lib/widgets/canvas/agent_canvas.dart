import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';

/// Right panel: visual canvas showing 7 agent characters
class AgentCanvas extends ConsumerWidget {
  const AgentCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsProvider);

    return Container(
      color: const Color(0xFF0E0E11),
      child: Column(
        children: [
          // Header
          Container(
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
                _ActiveCount(agents: agents),
              ],
            ),
          ),
          // Canvas area
          Expanded(
            child: agents.isEmpty
                ? _buildWaiting()
                : _buildOffice(agents),
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
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: agents.values
                .map((agent) => _AgentCard(agent: agent))
                .toList(),
          ),
        );
      },
    );
  }
}

class _ActiveCount extends StatelessWidget {
  final Map<String, AgentState> agents;

  const _ActiveCount({required this.agents});

  @override
  Widget build(BuildContext context) {
    final active =
        agents.values.where((a) => a.status != AgentStatus.idle).length;

    return Container(
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
    );
  }
}

// ─── Individual Agent Card ──────────────────────────────────────────────────

class _AgentCard extends StatelessWidget {
  final AgentState agent;

  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    final isActive = agent.status != AgentStatus.idle;
    final color = _agentColor(agent.info.id);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.08)
            : const Color(0xFF1A1A1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? color.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 16)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar
          _AgentAvatar(
            agentId: agent.info.id,
            color: color,
            status: agent.status,
          ),
          const SizedBox(height: 10),
          // Name
          Text(
            agent.info.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Status
          _StatusBadge(status: agent.status, color: color),
          // Current task
          if (agent.currentTask != null) ...[
            const SizedBox(height: 6),
            Text(
              agent.currentTask!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Color _agentColor(String id) => switch (id) {
        'tech-lead' => const Color(0xFF00C0D1),
        'manager' => const Color(0xFFF59E0B),
        'coder' => const Color(0xFF10B981),
        'reviewer' => const Color(0xFF8B5CF6),
        'tester' => const Color(0xFFEC4899),
        'security' => const Color(0xFFEF4444),
        'ui-ux-designer' => const Color(0xFF3B82F6),
        _ => const Color(0xFF6B7280),
      };
}

class _AgentAvatar extends StatefulWidget {
  final String agentId;
  final Color color;
  final AgentStatus status;

  const _AgentAvatar({
    required this.agentId,
    required this.color,
    required this.status,
  });

  @override
  State<_AgentAvatar> createState() => _AgentAvatarState();
}

class _AgentAvatarState extends State<_AgentAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_AgentAvatar old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _updateAnimation();
  }

  void _updateAnimation() {
    if (widget.status != AgentStatus.idle) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = 1.0 + (_pulseController.value * 0.06);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.color,
                  widget.color.withValues(alpha: 0.6),
                ],
              ),
              boxShadow: widget.status != AgentStatus.idle
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              _agentIcon(widget.agentId),
              size: 22,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  IconData _agentIcon(String id) => switch (id) {
        'tech-lead' => Icons.psychology,
        'manager' => Icons.assignment,
        'coder' => Icons.code,
        'reviewer' => Icons.rate_review,
        'tester' => Icons.bug_report,
        'security' => Icons.shield,
        'ui-ux-designer' => Icons.palette,
        _ => Icons.person,
      };
}

class _StatusBadge extends StatelessWidget {
  final AgentStatus status;
  final Color color;

  const _StatusBadge({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      AgentStatus.idle => 'Idle',
      AgentStatus.thinking => 'Thinking...',
      AgentStatus.typing => 'Writing...',
      AgentStatus.reading => 'Reading...',
      AgentStatus.running => 'Running...',
      AgentStatus.waiting => 'Waiting',
    };

    final isActive = status != AgentStatus.idle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? color : Colors.white.withValues(alpha: 0.3),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
