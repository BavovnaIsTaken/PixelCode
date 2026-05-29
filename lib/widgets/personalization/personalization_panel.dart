/// Agent memory panel — shows learned traits, allows deletion and consent control.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/agent_traits_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

// ─── Color palette (dark-theme pixel-office style) ──────────────────────────

const _bg = Color(0xFF0E1117);
const _surface = Color(0xFF161B22);
const _border = Color(0xFF1E2A36);
const _accent = Color(0xFF58A6FF);
const _green = Color(0xFF3FB950);
const _red = Color(0xFFFF7B72);
const _gold = Color(0xFFD29922);
const _textHigh = Color(0xFFE6EDF3);
const _textMid = Color(0xFF8B949E);
const _textLow = Color(0xFF484F58);

// ─── Panel ──────────────────────────────────────────────────────────────────

class PersonalizationPanel extends ConsumerWidget {
  final String agentId;
  final String agentName;

  const PersonalizationPanel({
    required this.agentId,
    required this.agentName,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strengths =
        ref.watch(agentTraitsByTypeProvider((agentId, TraitType.strength)));
    final weaknesses =
        ref.watch(agentTraitsByTypeProvider((agentId, TraitType.weakness)));
    final consent =
        ref.watch(settingsProvider.select((s) => s.learningConsentEnabled));
    final notifier = ref.read(traitsProvider.notifier);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final totalCount = strengths.length + weaknesses.length;

    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            agentName: agentName,
            totalCount: totalCount,
            learningEnabled: consent,
            onToggleLearning: settingsNotifier.setLearningConsentEnabled,
          ),
          const Divider(height: 1, color: _border),
          const _SystemHealthBanner(),
          const Divider(height: 1, color: _border),
          Expanded(
            child: totalCount == 0
                ? _EmptyState(learningEnabled: consent)
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (strengths.isNotEmpty) ...[
                        _SectionTitle(
                          label: 'Сильні сторони',
                          count: strengths.length,
                          color: _green,
                          icon: Icons.bolt_outlined,
                        ),
                        const SizedBox(height: 6),
                        for (final t in strengths)
                          _TraitCard(
                            trait: t,
                            onDelete: () => notifier.removeLesson(t.id),
                          ),
                        const SizedBox(height: 14),
                      ],
                      if (weaknesses.isNotEmpty) ...[
                        _SectionTitle(
                          label: 'Слабкі сторони',
                          count: weaknesses.length,
                          color: _red,
                          icon: Icons.warning_amber_outlined,
                        ),
                        const SizedBox(height: 6),
                        for (final t in weaknesses)
                          _TraitCard(
                            trait: t,
                            onDelete: () => notifier.removeLesson(t.id),
                          ),
                      ],
                      _TopicAffinitiesSection(agentId: agentId),
                      if (totalCount > 0) ...[
                        const SizedBox(height: 20),
                        _ClearAllButton(
                          onClear: () => _clearAll(ref, agentId),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _clearAll(WidgetRef ref, String agentId) {
    final all = ref.read(agentTraitsProvider(agentId));
    final notifier = ref.read(traitsProvider.notifier);
    for (final t in all) {
      notifier.removeLesson(t.id);
    }
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final String agentName;
  final int totalCount;
  final bool learningEnabled;
  final ValueChanged<bool> onToggleLearning;

  const _Header({
    required this.agentName,
    required this.totalCount,
    required this.learningEnabled,
    required this.onToggleLearning,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 16, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  agentName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (totalCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$totalCount урок${_lessonSuffix(totalCount)}',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 12, color: _textLow),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Авто-навчання',
                  style: TextStyle(color: _textMid, fontSize: 11),
                ),
              ),
              Transform.scale(
                scale: 0.75,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: learningEnabled,
                  onChanged: onToggleLearning,
                  activeThumbColor: _accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _lessonSuffix(int n) {
    if (n % 10 == 1 && n % 100 != 11) return '';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'и';
    }
    return 'ів';
  }
}

// ─── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _SectionTitle({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          '$label ($count)',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Trait card ───────────────────────────────────────────────────────────────

class _TraitCard extends StatelessWidget {
  final AgentTrait trait;
  final VoidCallback onDelete;

  const _TraitCard({required this.trait, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final (emphColor, emphLabel) = switch (trait.emphasis) {
      TraitEmphasis.critical => (_red, 'критично'),
      TraitEmphasis.important => (_gold, 'важливо'),
      TraitEmphasis.note => (_textLow, 'нотатка'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: emphColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CategoryBadge(category: trait.category),
                    const SizedBox(width: 6),
                    _FrequencyPip(
                      frequency: trait.frequency,
                      emphColor: emphColor,
                      emphLabel: emphLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  trait.lesson,
                  style: const TextStyle(color: _textHigh, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  trait.tag,
                  style: const TextStyle(color: _textLow, fontSize: 9),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline, size: 14, color: _textLow),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  static const _labels = <String, String>{
    'code_quality': 'якість',
    'architecture': 'архіт.',
    'testing': 'тести',
    'security': 'безпека',
    'communication': 'комун.',
    'delegation': 'делег.',
    'problem_solving': 'задачі',
    'tools_usage': 'інстр.',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[category] ?? category;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: _accent, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _FrequencyPip extends StatelessWidget {
  final int frequency;
  final Color emphColor;
  final String emphLabel;

  const _FrequencyPip({
    required this.frequency,
    required this.emphColor,
    required this.emphLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.refresh, size: 9, color: emphColor),
        const SizedBox(width: 2),
        Text(
          '×$frequency · $emphLabel',
          style: TextStyle(
              color: emphColor, fontSize: 9, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool learningEnabled;
  const _EmptyState({required this.learningEnabled});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology_outlined, size: 36, color: _textLow),
            const SizedBox(height: 12),
            Text(
              learningEnabled ? 'Уроків ще немає' : 'Авто-навчання вимкнено',
              style: const TextStyle(
                  color: _textMid, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              learningEnabled
                  ? 'Агент накопичить уроки після перших задач.'
                  : 'Увімкни авто-навчання, щоб агент запам\'ятовував патерни.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textLow, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Topic affinities section ──────────────────────────────────────────────────

class _TopicAffinitiesSection extends ConsumerWidget {
  final String agentId;

  const _TopicAffinitiesSection({required this.agentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final affinities = ref.watch(agentTopicAffinitiesProvider(agentId));
    if (affinities.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        _SectionTitle(
          label: 'Теми',
          count: affinities.length,
          color: _accent,
          icon: Icons.auto_graph_outlined,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final entry in affinities) _TopicChip(entry: entry)],
        ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  final TopicAffinityEntry entry;

  const _TopicChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = _accentColorForAffinity(
      strengthCount: entry.strengthCount,
      weaknessCount: entry.weaknessCount,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.category.displayName,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          if (entry.strengthCount > 0) ...[
            Icon(Icons.bolt, size: 9, color: _green),
            const SizedBox(width: 2),
            Text(
              entry.strengthCount.toString(),
              style: const TextStyle(
                color: _green,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (entry.weaknessCount > 0) ...[
            const SizedBox(width: 4),
            Icon(Icons.warning, size: 9, color: _red),
            const SizedBox(width: 2),
            Text(
              entry.weaknessCount.toString(),
              style: const TextStyle(
                color: _red,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _accentColorForAffinity({
    required int strengthCount,
    required int weaknessCount,
  }) {
    if (strengthCount > weaknessCount) return _green;
    if (weaknessCount > strengthCount) return _red;
    return _gold;
  }
}

// ─── Clear all button ─────────────────────────────────────────────────────────

class _ClearAllButton extends StatelessWidget {
  final VoidCallback onClear;
  const _ClearAllButton({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClear,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _red.withValues(alpha: 0.2)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 13, color: _red),
            SizedBox(width: 6),
            Text(
              'Очистити всю пам\'ять агента',
              style: TextStyle(
                  color: _red, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── System health banner — confabulation-gate KPIs ─────────────────────────

/// Header banner rendering the personalization-system health snapshot at a
/// glance. Compact by default (single line with a traffic light + verdict);
/// tap to expand into per-signal KPIs and recent constraint violations.
///
/// Surfaces the same data as `server/scripts/reflection-health.ts`. Source of
/// truth for the thresholds is [ReflectionKpiMessage.overallHealthy] etc — do
/// not duplicate threshold values here. Mirrors CLAUDE.md §5.
class _SystemHealthBanner extends ConsumerStatefulWidget {
  const _SystemHealthBanner();

  @override
  ConsumerState<_SystemHealthBanner> createState() => _SystemHealthBannerState();
}

class _SystemHealthBannerState extends ConsumerState<_SystemHealthBanner> {
  bool _expanded = false;
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    // Lazy-fetch on first build of this panel so closed bottom-sheets do not
    // burn cycles for no reason.
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(reflectionKpiProvider.notifier).refresh(sinceDays: 30);
        }
      });
    }

    final kpi = ref.watch(reflectionKpiProvider);

    if (kpi == null) {
      // Static placeholder while the WS round-trip lands. Avoid spinners here:
      // a constantly-animating CircularProgressIndicator prevents
      // pumpAndSettle in widget tests from ever settling.
      return _bannerShell(
        leading: const Icon(Icons.hourglass_empty, size: 13, color: _textMid),
        title: 'Перевіряю стан пам\'яті команди…',
        subtitle: null,
      );
    }

    if (!kpi.hasData) {
      return _bannerShell(
        leading: const Icon(Icons.cloud_off_outlined, size: 14, color: _textMid),
        title: 'Пам\'ять команди ще "холодна"',
        subtitle: 'Дані з\'являться після перших ~10 чат-сесій',
      );
    }

    final healthy = kpi.overallHealthy ?? false;
    final dotColor = healthy ? _green : _red;
    final verdict = healthy
        ? 'Усе ок — gate працює, confabulations не пропускає'
        : 'Знайдено сигнал тривоги — натисни для деталей';

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: _bannerShell(
            leading: _Dot(color: dotColor),
            title: 'Пам\'ять команди: ${healthy ? "🟢 здорова" : "🔴 потребує уваги"}',
            subtitle: verdict,
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: _textMid,
            ),
          ),
        ),
        if (_expanded) _ExpandedHealth(kpi: kpi),
      ],
    );
  }

  Widget _bannerShell({
    required Widget leading,
    required String title,
    required String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textHigh,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _textMid, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1),
        ],
      ),
    );
  }
}

class _ExpandedHealth extends StatelessWidget {
  final ReflectionKpiMessage kpi;
  const _ExpandedHealth({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final window = kpi.windowDays != null ? 'за останні ${kpi.windowDays} днів' : 'за весь час';
    return Container(
      width: double.infinity,
      color: _surface,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Метрики $window',
            style: const TextStyle(color: _textLow, fontSize: 9),
          ),
          const SizedBox(height: 8),
          _Kpi(
            label: 'Promotion rate',
            value: _pct(kpi.promotionRate),
            healthy: kpi.promotionRateOk,
            hint: kpi.promotionRateOk
                ? 'У здоровому діапазоні 10–70%'
                : kpi.promotionRate < 0.1
                    ? 'Занизько — gate може бути занадто жорстким'
                    : 'Зависоко — gate може бути занадто м\'яким',
          ),
          _Kpi(
            label: 'Bypass rate',
            value: _pct(kpi.bypassRate),
            healthy: kpi.bypassRateOk,
            hint: kpi.bypassRateOk
                ? 'Gate робить корисну роботу'
                : 'Більшість promotions йдуть в обхід gate (через existing trait)',
          ),
          _Kpi(
            label: 'Violation rate',
            value: _pct(kpi.violationRate),
            healthy: kpi.violationRateOk,
            hint: kpi.violationRateOk
                ? 'LLM поважає hard-constraint'
                : 'LLM генерує "tool unavailable"-style claims попри ground-truth',
          ),
          const SizedBox(height: 6),
          Text(
            'Активність: ${kpi.submitted} candidates submitted • '
            '${kpi.promotedViaThreshold + kpi.promotedViaBypass} promoted • '
            '${kpi.tooSoon} too-soon (burst-defense)',
            style: const TextStyle(color: _textLow, fontSize: 9),
          ),
          if (kpi.recentViolations.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Останні порушення:',
              style: TextStyle(
                color: _red,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final v in kpi.recentViolations.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '• [${v.agentId}] ${v.tag} — ${v.phrases.join(", ")}',
                  style: const TextStyle(
                    color: _textMid,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final bool healthy;
  final String hint;

  const _Kpi({
    required this.label,
    required this.value,
    required this.healthy,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final color = healthy ? _green : _red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Dot(color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: _textHigh,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              hint,
              style: const TextStyle(color: _textMid, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }
}
