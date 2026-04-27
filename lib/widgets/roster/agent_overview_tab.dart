/// Overview tab for the Agent Detail Drawer — level, XP, skills, hardware.
library;

import 'package:flutter/material.dart';
import 'package:pixelcode/models/agent_level.dart';
import 'package:pixelcode/models/game_economy.dart';

class AgentOverviewTab extends StatelessWidget {
  final AgentGameData agent;

  const AgentOverviewTab({required this.agent, super.key});

  @override
  Widget build(BuildContext context) {
    final xpNeeded = xpToNextLevel(agent.level);
    final xpProgress = xpNeeded > 0
        ? (agent.xp / xpNeeded).clamp(0.0, 1.0)
        : 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Level + XP
        _InfoCard(
          children: [
            Row(
              children: [
                _LevelBadge(level: agent.level),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level ${agent.level}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: xpProgress,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFF00C0D1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${agent.xp} / $xpNeeded XP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Hardware
        _InfoCard(
          children: [
            Row(
              children: [
                Icon(
                  Icons.computer,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  agent.hardware.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${agent.hardware.speedModifier}x speed',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Skills
        _InfoCard(
          children: [
            Text(
              'Skills',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (agent.skills.isEmpty)
              Text(
                'No skills yet',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              )
            else
              for (final skill in SkillType.values)
                if (agent.skills.containsKey(skill))
                  _SkillRow(
                    skill: skill,
                    value: agent.skills[skill]!,
                    cap: skillCap(agent.level),
                  ),
          ],
        ),
        const SizedBox(height: 12),

        // Model tier
        _InfoCard(
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'Model tier: ${capabilityModelForSkills(
                    precision: agent.skills[SkillType.precision] ?? 0,
                    creativity: agent.skills[SkillType.creativity] ?? 0,
                    insight: agent.skills[SkillType.insight] ?? 0,
                    reliability: agent.skills[SkillType.reliability] ?? 0,
                    roleType: agent.roleType,
                  )}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final int level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF00C0D1).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF00C0D1).withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Text(
          '$level',
          style: const TextStyle(
            color: Color(0xFF00C0D1),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final SkillType skill;
  final int value;
  final int cap;

  const _SkillRow({
    required this.skill,
    required this.value,
    required this.cap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(skill.icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Text(
              skill.label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (value / cap).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation(
                  value >= cap * 0.8
                      ? const Color(0xFFFFD700)
                      : const Color(0xFF00C0D1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            child: Text(
              '$value/$cap',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
