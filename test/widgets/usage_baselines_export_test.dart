import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/settings/usage_baselines_export.dart';

UsageBaselineNumericStats _stats({
  double min = 0,
  double max = 0,
  double mean = 0,
  double median = 0,
  double p95 = 0,
  double p99 = 0,
}) =>
    UsageBaselineNumericStats(
      min: min,
      max: max,
      mean: mean,
      median: median,
      p95: p95,
      p99: p99,
    );

UsageBaselineBucket _bucket({
  required String role,
  required String taskType,
  required int count,
  required bool confident,
  UsageBaselineNumericStats? cost,
  UsageBaselineNumericStats? dur,
  UsageBaselineNumericStats? tools,
  UsageBaselineNumericStats? turns,
}) =>
    UsageBaselineBucket(
      role: role,
      taskType: taskType,
      count: count,
      confident: confident,
      costUsd: cost ?? _stats(),
      durationMs: dur ?? _stats(),
      numToolCalls: tools ?? _stats(),
      numTurns: turns ?? _stats(),
      inputTokens: _stats(),
      outputTokens: _stats(),
    );

void main() {
  group('formatBaselinesMarkdown', () {
    test('empty report renders header + OK health + (порожньо) buckets', () {
      final md = formatBaselinesMarkdown(
        UsageBaselinesMessage(
          generatedAt: DateTime.utc(2026, 5, 30, 12, 0, 0),
          totalEntries: 0,
          buckets: const [],
          health: const [],
        ),
      );

      expect(md, contains('# Usage baselines — 2026-05-30T12:00:00.000Z'));
      expect(md, contains('Всього записів: 0 · бакетів: 0'));
      expect(md, contains('## Health'));
      expect(md, contains('OK (без сигналів)'));
      expect(md, contains('## Buckets'));
      expect(md, contains('(порожньо)'));
    });

    test('confident bucket renders ✓ marker and rounded metrics', () {
      final md = formatBaselinesMarkdown(
        UsageBaselinesMessage(
          generatedAt: DateTime.utc(2026, 5, 30),
          totalEntries: 30,
          buckets: [
            _bucket(
              role: 'manager',
              taskType: 'chat',
              count: 30,
              confident: true,
              cost: _stats(median: 0.0318, p95: 0.1799, max: 0.1858),
              dur: _stats(median: 2955, p95: 18612, max: 70088),
              tools: _stats(median: 0, p95: 2, max: 10),
              turns: _stats(median: 1, p95: 3, max: 11),
            ),
          ],
          health: const [],
        ),
      );

      expect(md, contains('### manager | chat — n=30 (✓ confident)'));
      expect(md, contains('cost: med \$0.0318'));
      expect(md, contains('p95 \$0.1799'));
      expect(md, contains('max \$0.1858'));
      expect(md, contains('dur:  med 2955ms'));
      expect(md, contains('tools: med 0'));
      expect(md, contains('turns: med 1'));
    });

    test('not-confident bucket renders ⏳ accumulating marker', () {
      final md = formatBaselinesMarkdown(
        UsageBaselinesMessage(
          generatedAt: DateTime.utc(2026, 5, 30),
          totalEntries: 8,
          buckets: [
            _bucket(
              role: 'character-artist',
              taskType: 'dispatch',
              count: 8,
              confident: false,
            ),
          ],
          health: const [],
        ),
      );

      expect(md,
          contains('### character-artist | dispatch — n=8 (⏳ accumulating)'));
    });

    test('warn signal renders ⚠️, info renders ℹ️', () {
      final md = formatBaselinesMarkdown(
        UsageBaselinesMessage(
          generatedAt: DateTime.utc(2026, 5, 30),
          totalEntries: 5,
          buckets: const [],
          health: const [
            UsageBaselineHealthSignal(
              code: 'unknown_role_leak',
              severity: 'warn',
              message: 'role="unknown" leaked into 3 entries',
            ),
            UsageBaselineHealthSignal(
              code: 'single_dominant_bucket',
              severity: 'info',
              message: 'one bucket owns >90% of traffic',
            ),
          ],
        ),
      );

      expect(md, contains('⚠️ `unknown_role_leak` — '
          'role="unknown" leaked into 3 entries'));
      expect(md, contains('ℹ️ `single_dominant_bucket` — '
          'one bucket owns >90% of traffic'));
      expect(md, isNot(contains('OK (без сигналів)')));
    });
  });
}
