/// Shop panel — hiring, skills, office upgrades, and donations.
///
/// Accessed via the "Крамниця" toggle in the title bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_economy.dart';
import '../../providers/game_economy_provider.dart';
import 'spinning_coin.dart';

// ─── Colors ────────────────────────────────────────────────────────────────

const _bg = Color(0xFF0E0E11);
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
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);

    return Container(
      color: _bg,
      child: Column(
        children: [
          // Balance header
          _BalanceHeader(grymni: game.grymni, totalEarned: game.totalEarned),
          // Tab bar
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: false,
              labelColor: _accent,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.3),
              labelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
              indicatorColor: _accent,
              indicatorWeight: 2,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Наймання'),
                Tab(text: 'Навички'),
                Tab(text: 'Офіс'),
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
                _HiringTab(),
                _SkillsTab(),
                _OfficeTab(),
                _DonationTab(),
              ],
            ),
          ),
        ],
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

// ─── Hiring tab ────────────────────────────────────────────────────────────

class _HiringTab extends ConsumerWidget {
  const _HiringTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Capacity indicator
        _SectionHeader(
          icon: Icons.groups_outlined,
          title: 'Команда',
          trailing:
              '${game.hiredCount}/${game.officeLevel.maxAgents} місць',
        ),
        const SizedBox(height: 8),
        for (final entry in agentCatalog)
          _AgentHireCard(
            entry: entry,
            agentData: game.agents[entry.agentId],
            canHire: notifier.canHire(entry.agentId),
            canHireMore: game.canHireMore,
            onHire: () => notifier.hireAgent(entry.agentId),
            onFire: () => notifier.fireAgent(entry.agentId),
          ),
      ],
    );
  }
}

class _AgentHireCard extends StatelessWidget {
  final AgentCatalogEntry entry;
  final AgentGameData? agentData;
  final bool canHire;
  final bool canHireMore;
  final VoidCallback onHire;
  final VoidCallback onFire;

  const _AgentHireCard({
    required this.entry,
    required this.agentData,
    required this.canHire,
    required this.canHireMore,
    required this.onHire,
    required this.onFire,
  });

  @override
  Widget build(BuildContext context) {
    final isHired = agentData?.isHired ?? false;
    final isStarter = entry.startsHired;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHired
              ? _green.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHired ? _green : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(width: 10),
          // Agent info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(
                        color: isHired
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.role,
                        style: TextStyle(
                          color: _accent.withValues(alpha: 0.7),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  entry.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 9,
                  ),
                ),
                if (isHired && agentData != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _MiniStat(
                          icon: agentData!.hardware.shortLabel,
                          label: agentData!.hardware.label,
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          icon: '⭐',
                          label: 'Рівень ${agentData!.skillLevel}',
                        ),
                        const SizedBox(width: 8),
                        _MiniStat(
                          icon: '💰',
                          label: '${entry.salary}₲/задача',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action button
          if (isHired)
            isStarter
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Основа',
                      style: TextStyle(
                        color: _green,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : _ActionButton(
                    label: 'Звільнити',
                    color: _red,
                    onTap: onFire,
                  )
          else
            _ActionButton(
              label: entry.hireCost > 0
                  ? 'Найняти · ${_formatNumber(entry.hireCost)}₲'
                  : 'Найняти',
              color: canHire ? _accent : Colors.white.withValues(alpha: 0.15),
              onTap: canHire ? onHire : null,
              subtitle: !canHireMore ? 'Немає місць' : null,
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
    final hiredAgents = game.agents.entries
        .where((e) => e.value.isHired)
        .toList();

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
        Wrap(
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

          // Skills
          _SectionHeader(icon: Icons.trending_up, title: 'Навички'),
          const SizedBox(height: 8),
          for (final skill in SkillType.values)
            _SkillUpgradeCard(
              skill: skill,
              level: selectedAgent.skills[skill] ?? 1,
              canUpgrade:
                  notifier.canUpgradeSkill(_selectedAgentId!, skill),
              onUpgrade: () =>
                  notifier.upgradeSkill(_selectedAgentId!, skill),
            ),
        ],
      ],
    );
  }
}

class _AgentChip extends StatelessWidget {
  final String agentId;
  final bool isSelected;
  final VoidCallback onTap;

  const _AgentChip({
    required this.agentId,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final catalog = catalogFor(agentId);
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
        child: Text(
          catalog?.name ?? agentId,
          style: TextStyle(
            color: isSelected ? _accent : Colors.white.withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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

class _SkillUpgradeCard extends StatelessWidget {
  final SkillType skill;
  final int level;
  final bool canUpgrade;
  final VoidCallback onUpgrade;

  const _SkillUpgradeCard({
    required this.skill,
    required this.level,
    required this.canUpgrade,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final cost = skill.upgradeCost(level);
    final isMaxed = level >= 10;

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
                Text(
                  skill.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                // Level bar
                Row(
                  children: [
                    for (int i = 0; i < 10; i++)
                      Container(
                        width: 12,
                        height: 4,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: i < level
                              ? _accent
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      '$level/10',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isMaxed)
            Text(
              'MAX',
              style: TextStyle(
                color: _gold.withValues(alpha: 0.6),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            _ActionButton(
              label: '${_formatNumber(cost)}₲',
              color:
                  canUpgrade ? _accent : Colors.white.withValues(alpha: 0.15),
              onTap: canUpgrade ? onUpgrade : null,
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

  const _OfficeLevelCard({
    required this.level,
    required this.isCurrent,
    required this.isUnlocked,
    required this.isNext,
    required this.canUpgrade,
    required this.onUpgrade,
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
                  ],
                ),
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
          else if (isUnlocked && !isCurrent)
            Icon(Icons.check_circle,
                size: 18, color: _green.withValues(alpha: 0.5)),
        ],
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
        _SectionHeader(icon: Icons.diamond_outlined, title: 'Крамниця гримень'),
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Оплата успішна! +${_formatNumber(pkg.grymni)}₲',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: _green,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
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
