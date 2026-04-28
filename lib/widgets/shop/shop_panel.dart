/// Shop panel — hiring, skills, office upgrades, and donations.
///
/// Accessed via the "Ринок" toggle in the title bar.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_level.dart';
import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../models/roster_catalog.dart';
import '../../providers/agent_provider.dart' show selectedAgentProvider;
import '../../providers/game_economy_provider.dart';
import '../../providers/deepseek_auth_provider.dart';
import '../../providers/gemini_auth_provider.dart';
import '../../providers/kimi_auth_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import '../../services/agent_export_service.dart';
import '../personalization/custom_agent_spawn_form.dart';
import '../personalization/personalization_panel.dart';
import '../roster/agent_detail_drawer.dart';
import 'spinning_coin.dart';

part 'roster_tab.dart';

// ─── Fallback colours (used when context isn't available) ─────────────────
// Widgets that have BuildContext should prefer `context.appColors` instead.

const _cardBg = Color(0xFF1A1A1F);
const _accent = Color(0xFF00C0D1);
const _gold = Color(0xFFFFD700);
const _red = Color(0xFFEF4444);
const _green = Color(0xFF22C55E);

// ─── Main shop panel ───────────────────────────────────────────────────────

class ShopPanel extends ConsumerStatefulWidget {
  const ShopPanel({super.key});

  @override
  ConsumerState<ShopPanel> createState() => _ShopPanelState();
}

class _ShopPanelState extends ConsumerState<ShopPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);

    // Jump to the requested tab when navigated here via deep-link.
    ref.listen(shopDeepLinkProvider, (_, tab) {
      if (tab != null && mounted) {
        _tabCtrl.animateTo(tab);
        ref.read(shopDeepLinkProvider.notifier).state = null;
      }
    });

    final c = context.appColors;

    return RepaintBoundary(
      child: Container(
        color: c.background,
        child: Column(
          children: [
            // Balance header
            _BalanceHeader(grymni: game.grymni, totalEarned: game.totalEarned),
            // Tab bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom:
                      BorderSide(color: c.divider),
                ),
              ),
              child: TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: c.accent,
                unselectedLabelColor: c.textLow,
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                indicatorColor: c.accent,
                indicatorWeight: 2,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Наймання'),
                  Tab(text: 'Навички'),
                  Tab(text: 'Офіс'),
                  Tab(text: 'Косметика'),
                  Tab(text: 'Донат'),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const BouncingScrollPhysics(),
                children: const [
                  RepaintBoundary(child: RosterTab()),
                  RepaintBoundary(child: _SkillsTab()),
                  RepaintBoundary(child: _OfficeTab()),
                  RepaintBoundary(child: _CosmeticsTab()),
                  RepaintBoundary(child: _DonationTab()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Balance header ────────────────────────────────────────────────────────

class _BalanceHeader extends StatelessWidget {
  final int grymni;
  final int totalEarned;

  const _BalanceHeader({required this.grymni, required this.totalEarned});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _gold.withValues(alpha: 0.08),
            _gold.withValues(alpha: 0.02),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: _gold.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          // Currency icon — spinning 3D coin
          const SpinningCoin(size: 32, layers: 5),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatNumber(grymni),
                style: const TextStyle(
                  color: _gold,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                _grymniLabel(grymni),
                style: TextStyle(
                  color: _gold.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Зароблено: ${_formatNumber(totalEarned)}₲',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String icon;
  final String label;

  const _MiniStat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 9)),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 8,
          ),
        ),
      ],
    );
  }
}

// ─── Skills tab ────────────────────────────────────────────────────────────

class _SkillsTab extends ConsumerStatefulWidget {
  const _SkillsTab();

  @override
  ConsumerState<_SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends ConsumerState<_SkillsTab> {
  String? _selectedAgentId;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);
    // Every entry in game.agents is a hired instance (presence = hired).
    final hiredAgents = game.agents.entries.toList();

    // Auto-select first if none selected
    if (_selectedAgentId == null && hiredAgents.isNotEmpty) {
      _selectedAgentId = hiredAgents.first.key;
    }

    final selectedAgent = _selectedAgentId != null
        ? game.agents[_selectedAgentId]
        : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Agent selector
        _SectionHeader(icon: Icons.person_outline, title: 'Обери агента'),
        const SizedBox(height: 8),
        RepaintBoundary(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in hiredAgents)
                _AgentChip(
                  agentId: entry.key,
                  isSelected: _selectedAgentId == entry.key,
                  onTap: () => setState(() => _selectedAgentId = entry.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (selectedAgent != null) ...[
          // Hardware upgrade
          _SectionHeader(
            icon: Icons.computer_outlined,
            title: 'Залізо',
            trailing: selectedAgent.hardware.label,
          ),
          const SizedBox(height: 8),
          _HardwareUpgradeCard(
            current: selectedAgent.hardware,
            canUpgrade: notifier.canUpgradeHardware(_selectedAgentId!),
            onUpgrade: () => notifier.upgradeHardware(_selectedAgentId!),
          ),
          const SizedBox(height: 16),

          // AI provider
          _SectionHeader(
            icon: Icons.hub_outlined,
            title: 'Провайдер AI',
            trailing: switch (selectedAgent.provider) {
              AgentProviderType.local => 'Gemini',
              AgentProviderType.deepseek => 'DeepSeek',
              AgentProviderType.kimi => 'Kimi',
              _ => 'Claude',
            },
          ),
          if (defaultTargetPlatform == TargetPlatform.macOS) ...[
            const SizedBox(height: 8),
            _ProviderCard(
              instanceId: _selectedAgentId!,
              current: selectedAgent.provider,
            ),
          ],
          const SizedBox(height: 16),

          // Skills
          _SectionHeader(icon: Icons.trending_up, title: 'Навички'),
          const SizedBox(height: 8),
          for (final skill in SkillType.values)
            _SkillUpgradeCard(
              skill: skill,
              level: selectedAgent.skills[skill] ?? 1,
              skillCap: skillCap(selectedAgent.level),
              capped: notifier.isSkillCapped(_selectedAgentId!, skill),
              canUpgrade: notifier.canUpgradeSkill(_selectedAgentId!, skill),
              onUpgrade: () => notifier.upgradeSkill(_selectedAgentId!, skill),
            ),
        ],
      ],
    );
  }
}

class _AgentChip extends ConsumerWidget {
  final String agentId;
  final bool isSelected;
  final VoidCallback onTap;

  const _AgentChip({
    required this.agentId,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance =
        ref.watch(gameEconomyProvider.select((g) => g.agents[agentId]));
    final label = instance?.nickname ??
        roleCatalogFor(roleTypeFromInstanceId(agentId))?.baseName ??
        agentId;

    final geminiLoggedIn =
        ref.watch(geminiAuthProvider).valueOrNull?.loggedIn ?? false;
    final deepseekLinked =
        ref.watch(deepseekAuthProvider).valueOrNull?.linked ?? false;
    final kimiLinked =
        ref.watch(kimiAuthProvider).valueOrNull?.linked ?? false;

    final tired = switch (instance?.provider) {
      AgentProviderType.local => !geminiLoggedIn,
      AgentProviderType.deepseek => !deepseekLinked,
      AgentProviderType.kimi => !kimiLinked,
      _ => false,
    };

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: tired ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? _accent.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? _accent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? _accent : Colors.white.withValues(alpha: 0.4),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              if (instance?.provider == AgentProviderType.local) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (instance?.provider == AgentProviderType.deepseek) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4D6BFE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: const Color(0xFF4D6BFE).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    tired ? 'zzz' : 'DS',
                    style: const TextStyle(
                      color: Color(0xFF4D6BFE),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (instance?.provider == AgentProviderType.kimi) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6A3D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: const Color(0xFFFF6A3D).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    tired ? 'zzz' : 'KM',
                    style: const TextStyle(
                      color: Color(0xFFFF6A3D),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (tired && instance?.provider == AgentProviderType.local) ...[
                const SizedBox(width: 5),
                Text(
                  'zzz',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HardwareUpgradeCard extends StatelessWidget {
  final HardwareTier current;
  final bool canUpgrade;
  final VoidCallback onUpgrade;

  const _HardwareUpgradeCard({
    required this.current,
    required this.canUpgrade,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final next = current.nextTier;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${current.shortLabel} ${current.label}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '×${current.speedModifier}',
                  style: TextStyle(
                    color: _accent.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(width: 4),
                Text(
                  '${next.label} (×${next.speedModifier})',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                _ActionButton(
                  label: '${_formatNumber(next.cost)}₲',
                  color:
                      canUpgrade ? _accent : Colors.white.withValues(alpha: 0.15),
                  onTap: canUpgrade ? onUpgrade : null,
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Максимальний рівень!',
                style: TextStyle(
                  color: _gold.withValues(alpha: 0.5),
                  fontSize: 9,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── AI provider card ──────────────────────────────────────────────────────

class _ProviderCard extends ConsumerWidget {
  final String instanceId;
  final AgentProviderType current;

  const _ProviderCard({required this.instanceId, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final geminiAuth = ref.watch(geminiAuthProvider);
    final geminiLoggedIn = geminiAuth.valueOrNull?.loggedIn ?? false;
    final deepseekAuth = ref.watch(deepseekAuthProvider);
    final deepseekLinked = deepseekAuth.valueOrNull?.linked ?? false;
    final kimiAuth = ref.watch(kimiAuthProvider);
    final kimiLinked = kimiAuth.valueOrNull?.linked ?? false;
    final notifier = ref.read(gameEconomyProvider.notifier);

    final String? hint = !geminiLoggedIn && current == AgentProviderType.local
        ? 'Увійдіть через Google у Налаштуваннях → Обліковий запис'
        : !deepseekLinked && current == AgentProviderType.deepseek
            ? 'Додайте API ключ DeepSeek у Налаштуваннях → Обліковий запис'
            : !kimiLinked && current == AgentProviderType.kimi
                ? 'Додайте API ключ Kimi у Налаштуваннях → Обліковий запис'
                : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProviderOption(
                label: 'Claude',
                sublabel: 'claude.ai',
                icon: Icons.cloud_outlined,
                active: current == AgentProviderType.cloud,
                onTap: () =>
                    notifier.setAgentProvider(instanceId, AgentProviderType.cloud),
              ),
              const SizedBox(width: 8),
              _ProviderOption(
                label: 'Gemini',
                sublabel: 'gemini',
                icon: Icons.auto_awesome_outlined,
                active: current == AgentProviderType.local,
                locked: !geminiLoggedIn,
                onTap: geminiLoggedIn
                    ? () => notifier.setAgentProvider(
                        instanceId, AgentProviderType.local)
                    : null,
              ),
              const SizedBox(width: 8),
              _ProviderOption(
                label: 'DeepSeek',
                sublabel: 'api.deepseek.com',
                icon: Icons.key_outlined,
                active: current == AgentProviderType.deepseek,
                locked: !deepseekLinked,
                onTap: deepseekLinked
                    ? () => notifier.setAgentProvider(
                        instanceId, AgentProviderType.deepseek)
                    : null,
              ),
              const SizedBox(width: 8),
              _ProviderOption(
                label: 'Kimi',
                sublabel: 'api.moonshot.ai',
                icon: Icons.key_outlined,
                active: current == AgentProviderType.kimi,
                locked: !kimiLinked,
                onTap: kimiLinked
                    ? () => notifier.setAgentProvider(
                        instanceId, AgentProviderType.kimi)
                    : null,
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(
              hint,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool active;
  final bool locked;
  final VoidCallback? onTap;

  const _ProviderOption({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.active,
    this.locked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = locked
        ? Colors.white.withValues(alpha: 0.15)
        : active
            ? _accent
            : Colors.white.withValues(alpha: 0.35);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: active && !locked
                ? _accent.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active && !locked
                  ? _accent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_outline : icon,
                size: 13,
                color: color,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      sublabel,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.55),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              if (active && !locked)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillUpgradeCard extends StatelessWidget {
  final SkillType skill;
  final int level;
  final int skillCap;
  final bool capped;
  final bool canUpgrade;
  final VoidCallback onUpgrade;

  const _SkillUpgradeCard({
    required this.skill,
    required this.level,
    required this.skillCap,
    required this.capped,
    required this.canUpgrade,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final cost = skill.upgradeCost(level);
    final progress = (level / skillCap).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Text(skill.icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        skill.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '$level / $skillCap',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation(
                      capped ? _gold : _accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: capped
                ? 'Досягнуто стелі. Підніми Lv агента, щоб відкрити далі.'
                : '',
            child: _ActionButton(
              label: capped ? 'Cap' : '${_formatNumber(cost)}₲',
              color: canUpgrade
                  ? _accent
                  : capped
                      ? _gold.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.15),
              onTap: canUpgrade ? onUpgrade : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Office tab ────────────────────────────────────────────────────────────

class _OfficeTab extends ConsumerWidget {
  const _OfficeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader(
          icon: Icons.apartment_outlined,
          title: 'Офіс',
          trailing: game.officeLevel.label,
        ),
        const SizedBox(height: 12),
        for (final level in OfficeLevel.values)
          _OfficeLevelCard(
            level: level,
            isCurrent: game.officeLevel == level,
            isUnlocked: level.index <= game.officeLevel.index,
            isNext: level == game.officeLevel.nextLevel,
            canUpgrade: level == game.officeLevel.nextLevel &&
                notifier.canUpgradeOffice(),
            onUpgrade: () => notifier.upgradeOffice(),
            currentExpansions:
                game.officeLevel == level ? game.officeExpansions : 0,
            nextExpansion:
                game.officeLevel == level ? game.nextExpansion : null,
            canBuyExpansion: game.officeLevel == level &&
                notifier.canBuyOfficeExpansion(),
            onBuyExpansion: () => notifier.buyOfficeExpansion(),
            playableTiles: game.officeLevel == level
                ? game.playableTiles
                : level.basePlayableTiles,
          ),
      ],
    );
  }
}

class _OfficeLevelCard extends StatelessWidget {
  final OfficeLevel level;
  final bool isCurrent;
  final bool isUnlocked;
  final bool isNext;
  final bool canUpgrade;
  final VoidCallback onUpgrade;

  /// Expansions bought at THIS level (zero for non-current tiers).
  final int currentExpansions;

  /// The next expansion step to be bought, or null if tier is maxed / not current.
  final OfficeExpansion? nextExpansion;

  final bool canBuyExpansion;
  final VoidCallback onBuyExpansion;

  /// Tiles available right now (effective for current; base for others).
  final int playableTiles;

  const _OfficeLevelCard({
    required this.level,
    required this.isCurrent,
    required this.isUnlocked,
    required this.isNext,
    required this.canUpgrade,
    required this.onUpgrade,
    this.currentExpansions = 0,
    this.nextExpansion,
    this.canBuyExpansion = false,
    required this.onBuyExpansion,
    required this.playableTiles,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isCurrent
        ? _accent.withValues(alpha: 0.3)
        : isNext
            ? _gold.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.06);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent
            ? _accent.withValues(alpha: 0.05)
            : _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Text(level.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      level.label,
                      style: TextStyle(
                        color: isUnlocked
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ЗАРАЗ',
                          style: TextStyle(
                            color: _accent,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  level.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _MiniStat(
                      icon: '👥',
                      label: 'до ${level.maxAgents} агентів',
                    ),
                    const SizedBox(width: 10),
                    _MiniStat(
                      icon: '⚡',
                      label: '×${level.speedModifier} швидкість',
                    ),
                    const SizedBox(width: 10),
                    _MiniStat(
                      icon: '📐',
                      label:
                          '$playableTiles / ${level.maxPlayableTiles} кліт.',
                    ),
                  ],
                ),
                if (isCurrent && level.expansions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _ExpansionProgress(
                    bought: currentExpansions,
                    total: level.expansions.length,
                  ),
                ],
              ],
            ),
          ),
          if (isNext)
            _ActionButton(
              label: '${_formatNumber(level.upgradeCost)}₲',
              color:
                  canUpgrade ? _gold : Colors.white.withValues(alpha: 0.15),
              onTap: canUpgrade ? onUpgrade : null,
            )
          else if (isCurrent && nextExpansion != null)
            _ActionButton(
              label: '+ ${_formatNumber(nextExpansion!.cost)}₲',
              color: canBuyExpansion
                  ? _green
                  : Colors.white.withValues(alpha: 0.15),
              onTap: canBuyExpansion ? onBuyExpansion : null,
            )
          else if (isUnlocked && !isCurrent)
            Icon(Icons.check_circle,
                size: 18, color: _green.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

/// Segmented progress bar — one filled pip per bought expansion step,
/// remaining pips dimmed. Purely visual; tap-to-buy happens via the card's
/// action button so the whole row stays a single target.
class _ExpansionProgress extends StatelessWidget {
  final int bought;
  final int total;

  const _ExpansionProgress({required this.bought, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Розширення',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        for (int i = 0; i < total; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: 10,
              height: 4,
              decoration: BoxDecoration(
                color: i < bought
                    ? _green.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 4),
        Text(
          '$bought / $total',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}


// ─── Cosmetics tab ─────────────────────────────────────────────────────────

class _CosmeticsTab extends ConsumerStatefulWidget {
  const _CosmeticsTab();

  @override
  ConsumerState<_CosmeticsTab> createState() => _CosmeticsTabState();
}

class _CosmeticsTabState extends ConsumerState<_CosmeticsTab> {
  CosmeticType _selectedType = CosmeticType.nicknameDecor;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);

    final filtered = cosmeticCatalog
        .where((c) => c.type == _selectedType)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Nickname preview with current decor
        if (game.nickname.isNotEmpty) ...[
          _SectionHeader(icon: Icons.badge_outlined, title: 'Твій профіль'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                // Avatar with frame indicator
                _AvatarFramePreview(
                  frameId: game.equippedFor(CosmeticType.avatarFrame),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title badge
                      if (game.equippedFor(CosmeticType.titleBadge) != null) ...[
                        Text(
                          cosmeticById(game.equippedFor(CosmeticType.titleBadge)!)?.preview ?? '',
                          style: TextStyle(
                            color: _gold.withValues(alpha: 0.8),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      // Decorated nickname
                      Text(
                        game.displayNickname,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Type selector
        _SectionHeader(icon: Icons.palette_outlined, title: 'Категорія'),
        const SizedBox(height: 8),
        RepaintBoundary(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in CosmeticType.values)
                _CosmeticTypeChip(
                  type: type,
                  isSelected: _selectedType == type,
                  onTap: () => setState(() => _selectedType = type),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Items
        _SectionHeader(
          icon: Icons.storefront_outlined,
          title: _selectedType.label,
        ),
        const SizedBox(height: 8),
        for (final item in filtered)
          _CosmeticItemCard(
            item: item,
            isOwned: game.ownedCosmetics.contains(item.id),
            isEquipped: game.equippedFor(item.type) == item.id,
            canBuy: notifier.canPurchaseCosmetic(item.id),
            onBuy: () {
              notifier.purchaseCosmetic(item.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '«${item.name}» придбано! -${_formatNumber(item.cost)}₲',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: _green,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            onEquip: () => notifier.equipCosmetic(item.id),
            onUnequip: () => notifier.unequipCosmetic(item.type),
          ),
      ],
    );
  }
}

class _CosmeticTypeChip extends StatelessWidget {
  final CosmeticType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _CosmeticTypeChip({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? _accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? _accent.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(type.icon, style: const TextStyle(fontSize: 10)),
            const SizedBox(width: 5),
            Text(
              type.label,
              style: TextStyle(
                color: isSelected ? _accent : Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CosmeticItemCard extends StatelessWidget {
  final CosmeticItem item;
  final bool isOwned;
  final bool isEquipped;
  final bool canBuy;
  final VoidCallback onBuy;
  final VoidCallback onEquip;
  final VoidCallback onUnequip;

  const _CosmeticItemCard({
    required this.item,
    required this.isOwned,
    required this.isEquipped,
    required this.canBuy,
    required this.onBuy,
    required this.onEquip,
    required this.onUnequip,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isEquipped
        ? _gold.withValues(alpha: 0.4)
        : isOwned
            ? _green.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.06);
    final bgColor = isEquipped
        ? _gold.withValues(alpha: 0.06)
        : _cardBg;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          // Preview
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                item.preview.length <= 4 ? item.preview : item.preview.substring(0, 1),
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: isOwned ? Colors.white : Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isEquipped) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ОДЯГНЕНО',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                // Preview text for nickname decorations
                if (item.type == CosmeticType.nicknameDecor ||
                    item.type == CosmeticType.titleBadge)
                  Text(
                    item.preview.replaceAll('{n}', 'NickName'),
                    style: TextStyle(
                      color: _gold.withValues(alpha: 0.5),
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action
          if (isOwned)
            _ActionButton(
              label: isEquipped ? 'Зняти' : 'Одягнути',
              color: isEquipped ? Colors.white.withValues(alpha: 0.3) : _green,
              onTap: isEquipped ? onUnequip : onEquip,
            )
          else
            _ActionButton(
              label: item.cost == 0
                  ? 'Безкоштовно'
                  : '${_formatNumber(item.cost)}₲',
              color: canBuy ? _accent : Colors.white.withValues(alpha: 0.15),
              onTap: canBuy ? onBuy : null,
            ),
        ],
      ),
    );
  }
}

class _AvatarFramePreview extends StatelessWidget {
  final String? frameId;
  const _AvatarFramePreview({this.frameId});

  static const _frameColors = <String, Color>{
    'frame_neon': Color(0xFF00C0D1),
    'frame_gold': Color(0xFFFFD700),
    'frame_fire': Color(0xFFFF6B35),
    'frame_glitch': Color(0xFF9B59B6),
    'frame_pixel': Color(0xFF22C55E),
    'frame_matrix': Color(0xFF00FF41),
  };

  @override
  Widget build(BuildContext context) {
    final frameColor = frameId != null
        ? (_frameColors[frameId!] ?? _accent)
        : Colors.white.withValues(alpha: 0.12);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: frameColor,
          width: frameId != null ? 2.5 : 1,
        ),
        boxShadow: frameId != null
            ? [BoxShadow(color: frameColor.withValues(alpha: 0.4), blurRadius: 8)]
            : null,
      ),
      child: Center(
        child: Text(
          '👤',
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );
  }
}

// ─── Donation tab ──────────────────────────────────────────────────────────

class _DonationTab extends ConsumerWidget {
  const _DonationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gameEconomyProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader(icon: Icons.diamond_outlined, title: 'Ринок гримень'),
        const SizedBox(height: 4),
        Text(
          'Підтримай розвиток студії!',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 12),
        for (final pkg in donationPackages)
          _DonationCard(
            package: pkg,
            onPurchase: () {
              notifier.purchaseDonation(pkg);
              _DonationToast.show(context, pkg.grymni);
            },
          ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Text(
            '* Це заглушка для тестування. Реальні платежі не здійснюються.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _DonationCard extends StatelessWidget {
  final DonationPackage package;
  final VoidCallback onPurchase;

  const _DonationCard({
    required this.package,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: package.isBestValue
              ? _gold.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          // Coin stack icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '₲',
                style: TextStyle(
                  color: _gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      package.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (package.isBestValue) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'НАЙКРАЩА ЦІНА',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatNumber(package.grymni)} ${_grymniLabel(package.grymni)}',
                  style: TextStyle(
                    color: _gold.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          _ActionButton(
            label: package.price,
            color: _gold,
            onTap: onPurchase,
          ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Text(
            trailing!,
            style: TextStyle(
              color: _accent.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? subtitle;

  const _ActionButton({
    required this.label,
    required this.color,
    this.onTap,
    this.subtitle,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final color = enabled ? widget.color : widget.color.withValues(alpha: 0.3);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered && enabled
                ? color.withValues(alpha: 0.25)
                : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: color.withValues(alpha: enabled ? 0.4 : 0.1),
            ),
          ),
          child: Column(
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: _red.withValues(alpha: 0.6),
                    fontSize: 7,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────

String _formatNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
  return n.toString();
}

/// Ukrainian plural forms for "гримня":
/// 1 гримня, 2-4 гримні, 5-20 гримнів, 21 гримня, 22 гримні …
String _grymniLabel(int n) {
  final abs = n.abs();
  final mod10 = abs % 10;
  final mod100 = abs % 100;
  if (mod10 == 1 && mod100 != 11) return 'гримня';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'гримні';
  return 'гримнів';
}

// ─── Aggregating donation toast ────────────────────────────────────────────

/// Prevents toast spam when the user taps a donation package many times.
/// While a donation toast is on screen, new purchases add to its running
/// total (with an animated digit change) and restart the auto-dismiss timer
/// instead of queueing another toast behind it.
class _DonationToast {
  static const _visibleFor = Duration(seconds: 2);

  static ValueNotifier<int>? _total;
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;
  static Timer? _dismissTimer;

  static void show(BuildContext context, int grymni) {
    final existing = _total;
    if (existing != null) {
      existing.value += grymni;
      _restartDismissTimer();
      return;
    }

    final notifier = ValueNotifier<int>(grymni);
    _total = notifier;

    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _DonationToastContent(total: notifier),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        // Long duration — we drive dismissal via _dismissTimer so new taps
        // can keep the same toast alive while they accumulate.
        duration: const Duration(days: 1),
      ),
    );
    _controller = controller;

    controller.closed.then((_) {
      if (identical(_controller, controller)) {
        _dismissTimer?.cancel();
        _dismissTimer = null;
        _total?.dispose();
        _total = null;
        _controller = null;
      }
    });

    _restartDismissTimer();
  }

  static void _restartDismissTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(_visibleFor, () => _controller?.close());
  }
}

class _DonationToastContent extends StatelessWidget {
  final ValueNotifier<int> total;

  const _DonationToastContent({required this.total});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: total,
      builder: (context, value, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
          builder: (context, animated, _) {
            return Text(
              'Оплата успішна! +${_formatNumber(animated.round())}₲',
              style: const TextStyle(color: Colors.white),
            );
          },
        );
      },
    );
  }
}
