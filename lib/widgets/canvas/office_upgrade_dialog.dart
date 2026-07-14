/// Upgrade-office dialog — the "Переїхати" flow surfaced by tapping the
/// back-wall door (or the foreman when an upgrade is pending).
///
/// Shows the current tier's expansion progress + the next tier's move-in
/// offer. The broader OfficeLevel encyclopedia still lives in Shop→Офіс.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_theme.dart';
import '../../models/game_economy.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import 'office_upgrade_helpers.dart';

const _accent = Color(0xFF00C0D1);
const _gold = Color(0xFFFFD700);
const _cardBg = Color(0xFF1A1A1F);

Future<void> showOfficeUpgradeDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => const _OfficeUpgradeDialog(),
  );
}

class _OfficeUpgradeDialog extends ConsumerWidget {
  const _OfficeUpgradeDialog();

  // Delegates to the pure helper so the formatter is unit-testable from
  // `test/widgets/canvas/office_upgrade_helpers_test.dart`.
  String _formatNumber(int n) => formatGrymniShort(n);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);
    final c = context.appColors;

    final current = game.officeLevel;
    final next = current.nextLevel;
    final canUpgrade = notifier.canUpgradeOffice();

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.home_work_outlined,
                      color: _accent, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Переїзд офісу',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.divider),
            // Body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current tier card — shows the fixed lot for this tier.
                  _CurrentTierCard(
                    level: current,
                    playableTiles: game.playableTiles,
                  ),
                  const SizedBox(height: 10),
                  // Next tier card — the "move in" offer
                  if (next != null)
                    _NextTierCard(
                      level: next,
                      canUpgrade: canUpgrade,
                      isWip: next.isWipComingSoon,
                      onUpgrade: () {
                        notifier.upgradeOffice();
                        Navigator.of(context).pop();
                      },
                      formatNumber: _formatNumber,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.emoji_events_outlined,
                            color: _gold.withValues(alpha: 0.8),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Ти на верхівці — куди вже переїжджати?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  // Footer link to Shop's Office tab (the encyclopedia)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      ref.read(shopDeepLinkProvider.notifier).state =
                          shopTabOffice;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.4)),
                          const SizedBox(width: 6),
                          Text(
                            'Усі рівні — у Ринку',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentTierCard extends StatelessWidget {
  final OfficeLevel level;
  final int playableTiles;

  const _CurrentTierCard({
    required this.level,
    required this.playableTiles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(level.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      level.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                ),
                const SizedBox(height: 2),
                Text(
                  'Лот ${level.gridCols - 2}×${level.gridRows - 2} • $playableTiles клітинок',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
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

class _NextTierCard extends StatelessWidget {
  final OfficeLevel level;
  final bool canUpgrade;
  final bool isWip;
  final VoidCallback onUpgrade;
  final String Function(int) formatNumber;

  const _NextTierCard({
    required this.level,
    required this.canUpgrade,
    required this.isWip,
    required this.onUpgrade,
    required this.formatNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWip
              ? Colors.white.withValues(alpha: 0.06)
              : _gold.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(level.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          level.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isWip
                                ? Colors.white.withValues(alpha: 0.08)
                                : _gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isWip ? 'СКОРО' : 'ДАЛІ',
                            style: TextStyle(
                              color: isWip
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : _gold,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      level.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatChip(icon: '👥', label: 'до ${level.maxAgents}'),
              const SizedBox(width: 8),
              _StatChip(icon: '⚡', label: '×${level.speedModifier}'),
              const SizedBox(width: 8),
              _StatChip(icon: '📐', label: '${level.playableTiles}'),
              const Spacer(),
              _ActionButton(
                label: isWip
                    ? 'СКОРО'
                    : 'Переїхати — ${formatNumber(level.upgradeCost)}₲',
                color: isWip
                    ? Colors.white.withValues(alpha: 0.15)
                    : (canUpgrade ? _gold : Colors.white.withValues(alpha: 0.15)),
                onTap: isWip ? null : (canUpgrade ? onUpgrade : null),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 10)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : _cardBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? color : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? color : Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
