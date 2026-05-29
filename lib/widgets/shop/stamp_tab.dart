part of 'shop_panel.dart';

/// Печатка — premium send-button cosmetic shop tab.
///
/// Send-button stamps are the highest-priced cosmetic in the catalogue
/// (6K–25K ₲). Treated as a signature/collection item rather than rank-and-file
/// cosmetic, hence its own tab with hero-strip + full-width interactive cards.
///
/// Confirm threshold: stamps costing 12K ₲ or more require an inline confirm
/// to prevent fat-finger 20K losses. Below that — direct purchase.
const int _kStampConfirmThreshold = 12000;

/// Feel-descriptions for each variant. Kept here (not in the catalogue) because
/// they are presentation-only and specific to this surface — adding a
/// `description` field to `CosmeticItem` for five rows is over-engineering.
String _stampFeelFor(SendButtonVariant v) => switch (v) {
      SendButtonVariant.classic => 'Тихий, рівний, безсуперечний.',
      SendButtonVariant.neonPulse => 'Дихає поряд із твоїм офісом.',
      SendButtonVariant.goldRocket => 'Важить як ухвалене рішення.',
      SendButtonVariant.pixelArcade => 'Клацає, як аркадна кнопка.',
      SendButtonVariant.liquidGlass => 'Скло, крізь яке проступає підпис.',
      SendButtonVariant.cloudDrift => 'Хмаринки, що нікуди не поспішають.',
    };

/// Premium-coded tab anchor in the ShopPanel TabBar.
///
/// Unlike its plain-text siblings, «Печатка» sits inside a gold-bordered chip
/// with a sparkle glyph and a breathing glow. Reads its own selected/idle
/// state straight from the [TabController] instead of relying on the parent
/// `labelColor` / `unselectedLabelColor`, so the chip stays gold whether
/// active or not — only the intensity changes.
class _StampTabChip extends StatefulWidget {
  const _StampTabChip({required this.controller});
  final TabController controller;

  @override
  State<_StampTabChip> createState() => _StampTabChipState();
}

class _StampTabChipState extends State<_StampTabChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    widget.controller.addListener(_onTab);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTab);
    _breath.dispose();
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.index == shopTabStamp;
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        // Soft sine 0..1..0 for the ambient glow.
        final breath = (math.sin(_breath.value * math.pi)).abs();
        final glowAlpha = (selected ? 0.32 : 0.16) + breath * 0.10;
        final borderAlpha = selected ? 0.85 : 0.55;
        final textAlpha = selected ? 1.0 : 0.85;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _gold.withValues(alpha: 0.16 + breath * 0.06),
                _gold.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _gold.withValues(alpha: borderAlpha),
              width: selected ? 1.2 : 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: _gold.withValues(alpha: glowAlpha),
                blurRadius: 10 + breath * 4,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 11,
                color: _gold.withValues(alpha: textAlpha),
              ),
              const SizedBox(width: 5),
              Text(
                'ПЕЧАТКА',
                style: TextStyle(
                  color: _gold.withValues(alpha: textAlpha),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StampTab extends ConsumerWidget {
  const _StampTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameEconomyProvider);
    final stamps = cosmeticCatalog
        .where((c) => c.type == CosmeticType.sendButtonStyle)
        .toList();
    final activeId = game.equippedFor(CosmeticType.sendButtonStyle);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _StampHeroStrip(activeId: activeId)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          sliver: SliverList.builder(
            itemCount: stamps.length,
            itemBuilder: (context, i) => _StampCard(item: stamps[i]),
          ),
        ),
      ],
    );
  }
}

// ─── Hero strip ──────────────────────────────────────────────────────────────

class _StampHeroStrip extends StatelessWidget {
  const _StampHeroStrip({required this.activeId});
  final String? activeId;

  @override
  Widget build(BuildContext context) {
    final variant = sendButtonVariantForId(activeId);
    final activeItem = activeId == null ? null : cosmeticById(activeId!);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _gold.withValues(alpha: 0.10),
            _gold.withValues(alpha: 0.02),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: _gold.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 12, color: _gold.withValues(alpha: 0.85)),
                    const SizedBox(width: 6),
                    Text(
                      'ПЕЧАТКА',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (activeItem != null) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '· ${activeItem.name}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Твій жест, що звучить після кожного слова.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Live preview of equipped stamp. Cross-fade on change happens
          // automatically because the widget rebuilds with a different variant.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: SizedBox(
              key: ValueKey(variant),
              width: 44,
              height: 44,
              child: SendButton(
                onPressed: () {},
                variantOverride: variant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stamp card ──────────────────────────────────────────────────────────────

class _StampCard extends ConsumerStatefulWidget {
  const _StampCard({required this.item});
  final CosmeticItem item;

  @override
  ConsumerState<_StampCard> createState() => _StampCardState();
}

class _StampCardState extends ConsumerState<_StampCard> {
  bool _awaitingConfirm = false;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);
    final item = widget.item;
    final variant = sendButtonVariantForId(item.id);
    final owned = item.cost == 0 || game.ownedCosmetics.contains(item.id);
    // Classic is free — active when nothing is equipped.
    final equippedId = game.equippedFor(CosmeticType.sendButtonStyle);
    final isEquipped =
        equippedId == item.id || (equippedId == null && item.id == 'send_classic');
    final canAfford = game.grymni >= item.cost;
    final isPremium = item.cost >= _kStampConfirmThreshold;

    final borderColor = isEquipped
        ? _gold.withValues(alpha: 0.45)
        : owned
            ? _green.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06);
    final bgColor = isEquipped
        ? _gold.withValues(alpha: 0.06)
        : _cardBg;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isEquipped ? 1.3 : 1),
        boxShadow: isEquipped
            ? [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.12),
                  blurRadius: 14,
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Live, interactive preview. Tapping it equips (when owned).
          Opacity(
            opacity: owned ? 1.0 : 0.55,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AbsorbPointer(
                    absorbing: !owned,
                    child: SendButton(
                      variantOverride: variant,
                      size: 56,
                      onPressed: () {
                        if (!owned) return;
                        if (item.id == 'send_classic') {
                          notifier.unequipCosmetic(
                              CosmeticType.sendButtonStyle);
                        } else {
                          notifier.equipCosmetic(item.id);
                        }
                      },
                    ),
                  ),
                  if (!owned)
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: owned
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isPremium) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.auto_awesome,
                          size: 11, color: _gold.withValues(alpha: 0.8)),
                    ],
                    if (isEquipped) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'АКТИВНА',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _stampFeelFor(variant),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StampCardAction(
            item: item,
            owned: owned,
            isEquipped: isEquipped,
            canAfford: canAfford,
            awaitingConfirm: _awaitingConfirm,
            isPremium: isPremium,
            onTapEquip: () {
              if (item.id == 'send_classic') {
                notifier.unequipCosmetic(CosmeticType.sendButtonStyle);
              } else {
                notifier.equipCosmetic(item.id);
              }
            },
            onTapBuy: () {
              if (isPremium) {
                setState(() => _awaitingConfirm = true);
              } else {
                _purchase(notifier);
              }
            },
            onConfirm: () => _purchase(notifier),
            onCancelConfirm: () => setState(() => _awaitingConfirm = false),
          ),
        ],
      ),
    );
  }

  void _purchase(GameEconomyNotifier notifier) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      final origin = box.localToGlobal(
        Offset(box.size.width - 60, box.size.height / 2),
      );
      _CoinFlyOverlay.fire(context, origin: origin);
    }
    notifier.purchaseCosmetic(widget.item.id);
    // Auto-equip premium stamps so the buyer sees the result immediately —
    // hero-strip + chat both update with no extra tap.
    notifier.equipCosmetic(widget.item.id);
    if (mounted) setState(() => _awaitingConfirm = false);
  }
}

// ─── Card action button(s): buy / confirm / equip / unequip / locked ─────────

class _StampCardAction extends StatelessWidget {
  const _StampCardAction({
    required this.item,
    required this.owned,
    required this.isEquipped,
    required this.canAfford,
    required this.awaitingConfirm,
    required this.isPremium,
    required this.onTapEquip,
    required this.onTapBuy,
    required this.onConfirm,
    required this.onCancelConfirm,
  });

  final CosmeticItem item;
  final bool owned;
  final bool isEquipped;
  final bool canAfford;
  final bool awaitingConfirm;
  final bool isPremium;
  final VoidCallback onTapEquip;
  final VoidCallback onTapBuy;
  final VoidCallback onConfirm;
  final VoidCallback onCancelConfirm;

  @override
  Widget build(BuildContext context) {
    // Owned but not equipped → equip action.
    if (owned) {
      if (isEquipped) {
        return Text(
          'Активна',
          style: TextStyle(
            color: _gold.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        );
      }
      return _ActionButton(
        label: 'Одягнути',
        color: _green,
        onTap: onTapEquip,
      );
    }

    // Not owned: pending confirm (premium) → "Точно? ✓ ×"
    if (awaitingConfirm) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Точно?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          _ConfirmIconButton(
            icon: Icons.check_rounded,
            color: _gold,
            onTap: canAfford ? onConfirm : null,
          ),
          const SizedBox(width: 4),
          _ConfirmIconButton(
            icon: Icons.close_rounded,
            color: Colors.white.withValues(alpha: 0.5),
            onTap: onCancelConfirm,
          ),
        ],
      );
    }

    // Not owned, idle → price + buy.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_formatNumber(item.cost)} ₲',
          style: TextStyle(
            color: canAfford ? _gold : Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        _ActionButton(
          label: 'Купити',
          color: canAfford ? _gold : Colors.white.withValues(alpha: 0.18),
          onTap: canAfford ? onTapBuy : null,
        ),
      ],
    );
  }
}

class _ConfirmIconButton extends StatelessWidget {
  const _ConfirmIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.18 : 0.05),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: enabled ? 0.5 : 0.1)),
        ),
        child: Icon(icon,
            size: 14,
            color: color.withValues(alpha: enabled ? 1.0 : 0.3)),
      ),
    );
  }
}

// ─── Coin-fly overlay ────────────────────────────────────────────────────────

/// One-shot particle burst: 5 gold pixel-squares fly upward in a slight
/// parabolic arc with fade-out. Premium-purchase feedback — fires from the
/// buy button origin toward the top-right balance header (approximately).
class _CoinFlyOverlay {
  static void fire(BuildContext context, {required Offset origin}) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _CoinFlyLayer(
        origin: origin,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _CoinFlyLayer extends StatefulWidget {
  const _CoinFlyLayer({required this.origin, required this.onDone});
  final Offset origin;
  final VoidCallback onDone;

  @override
  State<_CoinFlyLayer> createState() => _CoinFlyLayerState();
}

class _CoinFlyLayerState extends State<_CoinFlyLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_CoinParticle> _particles;

  static const int _count = 5;
  static const double _spreadX = 40; // horizontal spread of launch dirs
  static const double _riseY = 90; // how far up they rise

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    final rand = math.Random();
    _particles = List.generate(_count, (i) {
      final t = (i / (_count - 1)) - 0.5; // -0.5..0.5
      final dx = t * _spreadX + (rand.nextDouble() - 0.5) * 10;
      final dy = -_riseY - rand.nextDouble() * 24;
      final size = 4.0 + rand.nextDouble() * 2.0;
      final delay = i * 0.04;
      return _CoinParticle(dx: dx, dy: dy, size: size, delay: delay);
    });
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            children: [
              for (final p in _particles)
                Positioned(
                  left: widget.origin.dx +
                      p.dx * _easeOut(_ctrl.value, p.delay),
                  top: widget.origin.dy +
                      _arcY(p.dy, _ctrl.value, p.delay),
                  child: Opacity(
                    opacity: _alphaFor(_ctrl.value, p.delay),
                    child: Container(
                      width: p.size,
                      height: p.size,
                      color: _gold,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _easeOut(double t, double delay) {
    final local = ((t - delay) / (1.0 - delay)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(local);
  }

  /// Parabolic Y: rise to target then keep going. Returns a y-offset from
  /// the origin (negative = upward in screen-space).
  double _arcY(double riseY, double t, double delay) {
    final local = ((t - delay) / (1.0 - delay)).clamp(0.0, 1.0);
    // Quadratic in/out: rises to ~apex at local≈0.6 then continues drifting up.
    final eased = 1.0 - math.pow(1.0 - local, 2).toDouble();
    return riseY * eased;
  }

  double _alphaFor(double t, double delay) {
    final local = ((t - delay) / (1.0 - delay)).clamp(0.0, 1.0);
    // Hold full alpha until 70%, then fade.
    if (local < 0.7) return 1.0;
    return (1.0 - (local - 0.7) / 0.3).clamp(0.0, 1.0);
  }
}

class _CoinParticle {
  _CoinParticle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.delay,
  });
  final double dx;
  final double dy;
  final double size;
  final double delay;
}
