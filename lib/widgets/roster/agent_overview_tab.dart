/// Overview tab for the Agent Detail Drawer — level, XP, skills, hardware,
/// and backend swap (D.1 Advanced Settings).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/agent_level.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/models/roster_catalog.dart';
import 'package:pixelcode/providers/deepseek_auth_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/kimi_auth_provider.dart';
import 'package:pixelcode/services/agent_export_service.dart';

class AgentOverviewTab extends ConsumerWidget {
  final String instanceId;

  /// Override the file-export function (used in tests to avoid file I/O).
  final Future<String> Function(AgentBlueprint)? exportFn;

  const AgentOverviewTab({required this.instanceId, super.key, this.exportFn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agent = ref.watch(
      gameEconomyProvider.select((s) => s.agents[instanceId]),
    );
    if (agent == null) return const SizedBox.shrink();

    final xpNeeded = xpToNextLevel(agent.level);
    final xpProgress =
        xpNeeded > 0 ? (agent.xp / xpNeeded).clamp(0.0, 1.0) : 1.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (agent.workplaceStatus == WorkplaceStatus.unassigned)
          const _NeedsDeskBanner(),
        if (agent.workplaceStatus == WorkplaceStatus.unassigned)
          const SizedBox(height: 12),
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
        const SizedBox(height: 12),

        // Backend swap — D.1 Advanced Settings
        _BackendSwapCard(agent: agent),
        const SizedBox(height: 12),

        // Export — D Agent JSON export
        _ExportCard(agent: agent, exportFn: exportFn),
      ],
    );
  }
}

// ─── Backend swap card ────────────────────────────────────────────────────────

class _BackendSwapCard extends ConsumerWidget {
  final AgentGameData agent;
  const _BackendSwapCard({required this.agent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameEconomyProvider.notifier);
    final deepseekLinked =
        ref.watch(deepseekAuthProvider).valueOrNull?.linked ?? false;
    final kimiLinked =
        ref.watch(kimiAuthProvider).valueOrNull?.linked ?? false;

    // The roster character's recommended provider (if any).
    final rosChar = agent.characterId != null
        ? rosterCharacterById(agent.characterId!)
        : null;
    final recommended = rosChar?.defaultProvider;

    return _InfoCard(
      children: [
        Row(
          children: [
            Icon(
              Icons.swap_horiz,
              size: 14,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              'Backend',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              'Зміна не впливає на identity',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 9,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in AgentProviderType.values)
              _ProviderButton(
                provider: p,
                isSelected: agent.provider == p,
                isRecommended: p == recommended,
                hasAuth: _hasAuth(p, deepseekLinked, kimiLinked),
                onTap: () =>
                    notifier.setAgentProvider(agent.instanceId, p),
              ),
          ],
        ),
      ],
    );
  }

  bool _hasAuth(
    AgentProviderType p,
    bool deepseekLinked,
    bool kimiLinked,
  ) =>
      switch (p) {
        AgentProviderType.cloud => true,
        AgentProviderType.local => true,
        AgentProviderType.ollama => true,
        AgentProviderType.deepseek => deepseekLinked,
        AgentProviderType.kimi => kimiLinked,
      };
}

class _ProviderButton extends StatelessWidget {
  final AgentProviderType provider;
  final bool isSelected;
  final bool isRecommended;
  final bool hasAuth;
  final VoidCallback onTap;

  const _ProviderButton({
    required this.provider,
    required this.isSelected,
    required this.isRecommended,
    required this.hasAuth,
    required this.onTap,
  });

  static (String label, Color color) _meta(AgentProviderType p) => switch (p) {
        AgentProviderType.cloud => ('Claude', const Color(0xFFD97706)),
        AgentProviderType.local => ('Gemini', const Color(0xFF4285F4)),
        AgentProviderType.deepseek => ('DeepSeek', const Color(0xFF4D6BFE)),
        AgentProviderType.kimi => ('Kimi', const Color(0xFFFF6A3D)),
        AgentProviderType.ollama => ('Ollama', const Color(0xFF22C55E)),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _meta(provider);
    final effectiveColor = isSelected ? color : Colors.white.withValues(alpha: 0.3);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (isRecommended) ...[
              const SizedBox(width: 3),
              Text(
                '★',
                style: TextStyle(
                  color: color.withValues(alpha: isSelected ? 0.9 : 0.5),
                  fontSize: 8,
                ),
              ),
            ],
            if (!hasAuth) ...[
              const SizedBox(width: 3),
              Text(
                '⚠',
                style: TextStyle(
                  color: Colors.orange.withValues(alpha: 0.7),
                  fontSize: 8,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Export card ─────────────────────────────────────────────────────────────

class _ExportCard extends StatefulWidget {
  final AgentGameData agent;
  final Future<String> Function(AgentBlueprint)? exportFn;
  const _ExportCard({required this.agent, this.exportFn});

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final blueprint = AgentBlueprint.fromAgent(widget.agent);
      final fn = widget.exportFn ?? const AgentExportService().exportToFile;
      final path = await fn(blueprint);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Збережено: $path'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка експорту: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      children: [
        Row(
          children: [
            Icon(
              Icons.ios_share,
              size: 14,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 6),
            Text(
              'Export',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Зберегти агента як .agent.json файл. Можна передати іншому гравцю або імпортувати пізніше.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('agent-export-btn'),
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : const Icon(Icons.download, size: 14),
            label: Text(_exporting ? 'Зберігаємо…' : 'Export Agent'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.7),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

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

class _NeedsDeskBanner extends StatelessWidget {
  const _NeedsDeskBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF00C0D1).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00C0D1).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Text('🖥️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Потрібен стіл',
                  style: TextStyle(
                    color: Color(0xFF00C0D1),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Агент без робочого місця. Coding/testing/debugging мають підвищений ризик не завершитись. Збудуй Workstation через Build Mode.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
