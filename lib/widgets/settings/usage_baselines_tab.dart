/// Daily-control surface for the `usage_log.jsonl` distribution. Shipped
/// alongside C.2 so a broken instrumentation pipeline (role="unknown" leak,
/// numToolCalls=0 across every dispatch, etc) surfaces from day-1 instead of
/// 30 days later when the player tries to *use* the baseline.
///
/// Strictly read-only: pulls a fresh snapshot from the server via
/// [UsageBaselinesNotifier.refresh] when the tab opens, then renders the
/// per-bucket stats and the analyzer's `health` list. No client-side stats —
/// every number you see was computed server-side by `analyze` in
/// `server/src/usage_baseline.ts`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/usage_baselines_provider.dart';

class UsageBaselinesTab extends ConsumerStatefulWidget {
  const UsageBaselinesTab({super.key});

  @override
  ConsumerState<UsageBaselinesTab> createState() => _UsageBaselinesTabState();
}

class _UsageBaselinesTabState extends ConsumerState<UsageBaselinesTab> {
  @override
  void initState() {
    super.initState();
    // Pull on open. Subsequent visits show the cached snapshot until the user
    // taps refresh — keeps the WS quiet for users who don't watch this tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(usageBaselinesProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(usageBaselinesProvider);
    final report = s.report;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(state: s),
        const SizedBox(height: 12),
        if (report == null && s.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (report == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Поки немає даних — натисни «Оновити».',
              style: TextStyle(color: Colors.white70),
            ),
          )
        else ...[
          if (report.health.isNotEmpty) ...[
            _HealthList(signals: report.health),
            const SizedBox(height: 16),
          ],
          _BucketsTable(buckets: report.buckets),
        ],
      ],
    );
  }
}

// ─── Header (counts + refresh + stale hint) ─────────────────────────────────

class _Header extends StatelessWidget {
  final UsageBaselinesState state;
  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final report = state.report;
    final refreshedAt = state.lastRefreshAt;
    final stale = refreshedAt != null &&
        DateTime.now().difference(refreshedAt) > const Duration(hours: 1);

    return Row(
      children: [
        const Icon(Icons.query_stats_outlined, size: 28, color: Colors.white70),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Емпіричні бейзлайни використання',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                report == null
                    ? 'Розподіл cost / duration / tool calls per role.'
                    : 'Всього записів: ${report.totalEntries} · '
                        'бакетів: ${report.buckets.length}'
                        '${stale ? "  · ❗ snapshot старіше за годину" : ""}',
                style: TextStyle(
                  fontSize: 12,
                  color: stale ? Colors.amber : Colors.white54,
                ),
              ),
            ],
          ),
        ),
        Consumer(builder: (context, ref, _) {
          return OutlinedButton.icon(
            onPressed: state.loading
                ? null
                : () => ref.read(usageBaselinesProvider.notifier).refresh(),
            icon: state.loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: const Text('Оновити'),
          );
        }),
      ],
    );
  }
}

// ─── Health signals ─────────────────────────────────────────────────────────

class _HealthList extends StatelessWidget {
  final List<UsageBaselineHealthSignal> signals;
  const _HealthList({required this.signals});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in signals) _HealthRow(signal: s),
      ],
    );
  }
}

class _HealthRow extends StatelessWidget {
  final UsageBaselineHealthSignal signal;
  const _HealthRow({required this.signal});

  @override
  Widget build(BuildContext context) {
    final isWarn = signal.severity == 'warn';
    final bg = isWarn ? const Color(0x33B07A1B) : const Color(0x222B4FB0);
    final fg = isWarn ? Colors.amberAccent : Colors.lightBlueAccent;
    final icon = isWarn ? Icons.warning_amber_rounded : Icons.info_outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signal.code,
                  style: TextStyle(
                    fontSize: 11,
                    color: fg,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  signal.message,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Buckets table ──────────────────────────────────────────────────────────

class _BucketsTable extends StatelessWidget {
  final List<UsageBaselineBucket> buckets;
  const _BucketsTable({required this.buckets});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Жодного bucket-у — `usage_log.jsonl` поки порожній.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in buckets) _BucketCard(bucket: b),
      ],
    );
  }
}

class _BucketCard extends StatelessWidget {
  final UsageBaselineBucket bucket;
  const _BucketCard({required this.bucket});

  String _fmtCost(double v) => '\$${v.toStringAsFixed(4)}';
  String _fmtMs(double v) => '${v.toStringAsFixed(0)}ms';
  String _fmtInt(double v) => v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: bucket.confident
              ? const Color(0x6688CC88)
              : const Color(0x44888888),
          width: bucket.confident ? 1.2 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                bucket.role,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  bucket.taskType,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'n=${bucket.count}',
                style: TextStyle(
                  fontSize: 12,
                  color: bucket.confident ? Colors.greenAccent : Colors.amber,
                  fontFamily: 'monospace',
                ),
              ),
              if (!bucket.confident) ...[
                const SizedBox(width: 4),
                const Tooltip(
                  message: 'Менше 10 записів — медіана нестабільна. '
                      'Не використовується для warning-ів.',
                  child: Icon(Icons.hourglass_bottom,
                      size: 14, color: Colors.amber),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _MetricRow(
            label: 'cost',
            median: _fmtCost(bucket.costUsd.median),
            p95: _fmtCost(bucket.costUsd.p95),
            max: _fmtCost(bucket.costUsd.max),
          ),
          _MetricRow(
            label: 'dur',
            median: _fmtMs(bucket.durationMs.median),
            p95: _fmtMs(bucket.durationMs.p95),
            max: _fmtMs(bucket.durationMs.max),
          ),
          _MetricRow(
            label: 'tools',
            median: _fmtInt(bucket.numToolCalls.median),
            p95: _fmtInt(bucket.numToolCalls.p95),
            max: _fmtInt(bucket.numToolCalls.max),
          ),
          _MetricRow(
            label: 'turns',
            median: _fmtInt(bucket.numTurns.median),
            p95: _fmtInt(bucket.numTurns.p95),
            max: _fmtInt(bucket.numTurns.max),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String median;
  final String p95;
  final String max;

  const _MetricRow({
    required this.label,
    required this.median,
    required this.p95,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      fontSize: 11,
      color: Colors.white54,
      fontFamily: 'monospace',
    );
    const valueStyle = TextStyle(
      fontSize: 12,
      color: Colors.white,
      fontFamily: 'monospace',
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label, style: labelStyle)),
          SizedBox(width: 110, child: Text('med $median', style: valueStyle)),
          SizedBox(width: 110, child: Text('p95 $p95', style: valueStyle)),
          Expanded(child: Text('max $max', style: valueStyle)),
        ],
      ),
    );
  }
}
