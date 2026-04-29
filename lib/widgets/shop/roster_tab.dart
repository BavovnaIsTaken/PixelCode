part of 'shop_panel.dart';

/// Curated Roster v1 — hiring UI for named characters.
///
/// Part of D.1 (Curated Roster v1) from STRATEGY.md Phase 1.5.
/// This is a reusable component shared with Marketplace v1 stats-card.
class RosterTab extends ConsumerStatefulWidget {
  const RosterTab({super.key});

  @override
  ConsumerState<RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends ConsumerState<RosterTab> {
  /// Currently selected role filter (null = show all roster characters).
  String? _filterRole;

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameEconomyProvider);
    final notifier = ref.read(gameEconomyProvider.notifier);

    final hired = game.agents.values.toList();

    // Roles present in the curated roster, in catalog order, deduplicated.
    final rosterRoles = <String>[];
    for (final c in rosterCatalog) {
      if (!rosterRoles.contains(c.roleType)) rosterRoles.add(c.roleType);
    }

    final filtered = _filterRole == null
        ? rosterCatalog
        : rosterCatalog.where((c) => c.roleType == _filterRole).toList();

    // Count of how many of each character are already on the team.
    final hiredByCharacter = <String, int>{};
    for (final a in hired) {
      final cid = a.characterId;
      if (cid != null) {
        hiredByCharacter[cid] = (hiredByCharacter[cid] ?? 0) + 1;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _SectionHeader(
          icon: Icons.groups_outlined,
          title: 'Команда',
          trailing: '${game.hiredCount}/${game.officeLevel.maxAgents} місць',
        ),
        const SizedBox(height: 8),
        _TeamSection(
          agents: hired,
          onFire: (id) {
            final wasSelected = ref.read(selectedAgentProvider) == id;
            notifier.fireAgent(id);
            if (wasSelected) {
              final managers = ref.read(gameEconomyProvider).instancesOfRole('manager');
              ref.read(selectedAgentProvider.notifier).state =
                  managers.isNotEmpty ? managers.first.instanceId : 'manager#1';
            }
          },
        ),
        const SizedBox(height: 18),
        _SectionHeader(
          icon: Icons.storefront_outlined,
          title: 'Доступні персонажі',
        ),
        const SizedBox(height: 8),
        _RoleFilterBar(
          roles: rosterRoles,
          selected: _filterRole,
          onSelect: (r) => setState(() => _filterRole = r),
        ),
        const SizedBox(height: 12),
        for (final character in filtered)
          _RosterCharacterCard(
            character: character,
            ownedCount: hiredByCharacter[character.id] ?? 0,
            canHire: notifier.canHireCharacter(character.id),
            canHireMore: game.canHireMore,
            onHire: () => notifier.hireCharacter(character.id),
          ),
        const SizedBox(height: 8),
        _SpawnCustomAgentCard(
          canSpawn: game.canHireMore,
          onTap: () async {
            final data = await showModalBottomSheet<CustomAgentSpawnData>(
              context: context,
              isScrollControlled: true,
              backgroundColor: const Color(0xFF0E1117),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              builder: (_) => DraggableScrollableSheet(
                initialChildSize: 0.85,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                expand: false,
                builder: (_, sc) => SingleChildScrollView(
                  controller: sc,
                  child: CustomAgentSpawnForm(),
                ),
              ),
            );
            if (data != null) notifier.spawnCustomAgent(data);
          },
        ),
        const SizedBox(height: 8),
        _ImportAgentCard(
          canSpawn: game.canHireMore,
          onImport: (spawnData) => notifier.spawnCustomAgent(spawnData),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─── Team section (currently hired agents) ─────────────────────────────────

class _TeamSection extends StatelessWidget {
  final List<AgentGameData> agents;
  final ValueChanged<String> onFire;

  const _TeamSection({required this.agents, required this.onFire});

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Text(
          'Команда поки порожня — найми когось зі списку нижче.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      );
    }

    // Manager first; rest by instanceId for stable order.
    final sorted = [...agents]..sort((a, b) {
        if (a.roleType == 'manager' && b.roleType != 'manager') return -1;
        if (b.roleType == 'manager' && a.roleType != 'manager') return 1;
        return a.instanceId.compareTo(b.instanceId);
      });

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            _TeamRow(
              instance: sorted[i],
              onFire: () => onFire(sorted[i].instanceId),
            ),
            if (i < sorted.length - 1)
              Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.05),
              ),
          ],
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  final AgentGameData instance;
  final VoidCallback onFire;

  const _TeamRow({required this.instance, required this.onFire});

  void _showMemories(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: PersonalizationPanel(
            agentId: instance.instanceId,
            agentName: instance.nickname,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = roleCatalogFor(instance.roleType);
    final isManager = instance.roleType == 'manager';

    return GestureDetector(
      onTap: () => showAgentDetailDrawer(context, instance),
      child: Padding(
      key: Key('team-row-${instance.instanceId}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Text(
            role?.passive.icon ?? '👤',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        instance.nickname,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _VendorPill(provider: instance.provider),
                    if (instance.specializations.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _SpecializationBadge(
                          specializations: instance.specializations),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${role?.role ?? instance.roleType} · Lv ${instance.level} · ${instance.hardware.label}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showMemories(context),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Tooltip(
                message: 'Пам\'ять агента',
                child: Icon(
                  Icons.psychology_outlined,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          if (isManager)
            Container(
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
          else
            _ActionButton(
              label: 'Звільнити',
              color: _red,
              onTap: onFire,
            ),
        ],
      ),
    ),
    );
  }
}

// ─── Spawn custom agent card ──────────────────────────────────────────────

class _SpawnCustomAgentCard extends StatelessWidget {
  final bool canSpawn;
  final VoidCallback onTap;

  const _SpawnCustomAgentCard({required this.canSpawn, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = canSpawn ? _accent : Colors.white.withValues(alpha: 0.15);
    return GestureDetector(
      onTap: canSpawn ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: canSpawn
              ? _accent.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Власний агент',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canSpawn
                        ? 'Налаштуй роль, prompt і навички вручну'
                        : 'Немає вільних місць у команді',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (canSpawn)
              Icon(Icons.chevron_right,
                  size: 16, color: color.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

// ─── Import agent card ────────────────────────────────────────────────────

class _ImportAgentCard extends StatelessWidget {
  final bool canSpawn;
  final ValueChanged<CustomAgentSpawnData> onImport;

  const _ImportAgentCard({required this.canSpawn, required this.onImport});

  Future<void> _showImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1F),
          title: const Text(
            'Import Agent',
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Встав вміст .agent.json файлу:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('import-agent-json-field'),
                  controller: controller,
                  maxLines: 8,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: '{\n  "pixelcodeAgent": "1",\n  ...\n}',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 11,
                    ),
                    errorText: errorText,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12)),
                    ),
                  ),
                  onChanged: (_) {
                    if (errorText != null) setState(() => errorText = null);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Скасувати',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              ),
            ),
            FilledButton(
              key: const Key('import-agent-confirm-btn'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                const service = AgentExportService();
                try {
                  final blueprint = service.importFromString(controller.text);
                  final spawnData = service.toSpawnData(blueprint);
                  Navigator.of(ctx).pop();
                  onImport(spawnData);
                } on FormatException catch (e) {
                  setState(() => errorText = e.message);
                } catch (e) {
                  setState(() => errorText = 'Помилка: $e');
                }
              },
              child: const Text('Імпортувати'),
            ),
          ],
        ),
      ),
    );
    // controller is a local variable — no dispose needed; GC handles it.
  }

  @override
  Widget build(BuildContext context) {
    final color =
        canSpawn ? Colors.white.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.15);
    return GestureDetector(
      onTap: canSpawn ? () => _showImportDialog(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: canSpawn ? 0.1 : 0.05),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.upload_file_outlined, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Імпорт агента',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canSpawn
                        ? 'Вставити .agent.json від іншого гравця'
                        : 'Немає вільних місць у команді',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 10,
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

// ─── Filter bar ────────────────────────────────────────────────────────────

class _RoleFilterBar extends StatelessWidget {
  final List<String> roles;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _RoleFilterBar({
    required this.roles,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'Усі',
            isSelected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final role in roles) ...[
            const SizedBox(width: 6),
            _FilterChip(
              label: roleCatalogFor(role)?.role ?? role,
              isSelected: selected == role,
              onTap: () => onSelect(role),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: Key('role-filter-$label'),
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
          label,
          style: TextStyle(
            color: isSelected ? _accent : Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Roster character card ─────────────────────────────────────────────────

class _RosterCharacterCard extends StatelessWidget {
  final RosterCharacter character;
  final int ownedCount;
  final bool canHire;
  final bool canHireMore;
  final VoidCallback onHire;

  const _RosterCharacterCard({
    required this.character,
    required this.ownedCount,
    required this.canHire,
    required this.canHireMore,
    required this.onHire,
  });

  @override
  Widget build(BuildContext context) {
    final role = roleCatalogFor(character.roleType);
    final owned = ownedCount > 0;

    return Container(
      key: Key('roster-card-${character.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: owned
              ? _green.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Portrait placeholder — signature stat icon on tinted square.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _accent.withValues(alpha: 0.2)),
                ),
                child: Center(
                  child: Text(
                    character.signatureStat.icon,
                    style: const TextStyle(fontSize: 22),
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
                        Flexible(
                          child: Text(
                            character.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _VendorPill(provider: character.defaultProvider),
                        if (owned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ownedCount > 1
                                  ? '×$ownedCount'
                                  : 'найнятий',
                              style: const TextStyle(
                                color: _green,
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
                      role?.role ?? character.roleType,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _ActionButton(
                label: character.price > 0
                    ? '${_formatNumber(character.price)}₲'
                    : 'Безкоштовно',
                color: canHire ? _accent : Colors.white.withValues(alpha: 0.15),
                onTap: canHire ? onHire : null,
                subtitle: !canHireMore ? 'Немає місць' : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            character.tagline,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          _StatBars(weights: character.statWeights),
          const SizedBox(height: 6),
          Text(
            '💪 ${character.strength}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 9,
            ),
          ),
          Text(
            '⚠️  ${character.weakness}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.28),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBars extends StatelessWidget {
  final Map<SkillType, int> weights;
  const _StatBars({required this.weights});

  static Color _barColor(int v) {
    if (v >= 6) return _gold;
    if (v >= 4) return _accent;
    if (v >= 2) return _accent.withValues(alpha: 0.5);
    return Colors.white.withValues(alpha: 0.25);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final stat in SkillType.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              children: [
                Text(stat.icon, style: const TextStyle(fontSize: 9)),
                const SizedBox(width: 5),
                SizedBox(
                  width: 70,
                  child: Text(
                    stat.label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 9,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value:
                          ((weights[stat] ?? 0) / rosterStatMax).clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      valueColor:
                          AlwaysStoppedAnimation(_barColor(weights[stat] ?? 0)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 14,
                  child: Text(
                    '${weights[stat] ?? 0}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Vendor pill ───────────────────────────────────────────────────────────

class _SpecializationBadge extends StatelessWidget {
  final Set<String> specializations;
  const _SpecializationBadge({required this.specializations});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF59E0B);
    final tooltip = 'Спеціалізація: ${specializations.join(", ")}';
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 8, color: color),
            const SizedBox(width: 2),
            Text(
              '${specializations.length}',
              style: const TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorPill extends StatelessWidget {
  final AgentProviderType provider;
  const _VendorPill({required this.provider});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (provider) {
      AgentProviderType.cloud => ('Claude', const Color(0xFFD97706)),
      AgentProviderType.local => ('Gemini', const Color(0xFF4285F4)),
      AgentProviderType.deepseek => ('DeepSeek', const Color(0xFF4D6BFE)),
      AgentProviderType.kimi => ('Kimi', const Color(0xFFFF6A3D)),
      AgentProviderType.ollama => ('Local', Color(0xFF22C55E)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
