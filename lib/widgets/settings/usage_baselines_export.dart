/// Renders a [UsageBaselinesMessage] as a chat-paste-friendly markdown block.
/// Exists so the daily-glance loop (look at the tab → drop numbers in chat or
/// `docs/BASELINES_AUDIT.md`) does not require screenshots or hand-retyping —
/// you tap «Експорт», markdown lands in the clipboard, paste once.
///
/// Pure function. No I/O. Trivially unit-testable.
library;

import '../../models/agent_message.dart';

String formatBaselinesMarkdown(UsageBaselinesMessage report) {
  final buf = StringBuffer();

  buf.writeln('# Usage baselines — ${report.generatedAt.toIso8601String()}');
  buf.writeln();
  buf.writeln(
    'Всього записів: ${report.totalEntries} · '
    'бакетів: ${report.buckets.length}',
  );
  buf.writeln();

  buf.writeln('## Health');
  if (report.health.isEmpty) {
    buf.writeln('- OK (без сигналів)');
  } else {
    for (final s in report.health) {
      final marker = s.severity == 'warn' ? '⚠️' : 'ℹ️';
      buf.writeln('- $marker `${s.code}` — ${s.message}');
    }
  }
  buf.writeln();

  buf.writeln('## Buckets');
  if (report.buckets.isEmpty) {
    buf.writeln('- (порожньо)');
  } else {
    for (final b in report.buckets) {
      final mark = b.confident ? '✓ confident' : '⏳ accumulating';
      buf.writeln();
      buf.writeln('### ${b.role} | ${b.taskType} — n=${b.count} ($mark)');
      buf.writeln(
        '- cost: med \$${_cost(b.costUsd.median)} / '
        'p95 \$${_cost(b.costUsd.p95)} / '
        'max \$${_cost(b.costUsd.max)}',
      );
      buf.writeln(
        '- dur:  med ${_ms(b.durationMs.median)} / '
        'p95 ${_ms(b.durationMs.p95)} / '
        'max ${_ms(b.durationMs.max)}',
      );
      buf.writeln(
        '- tools: med ${_int(b.numToolCalls.median)} / '
        'p95 ${_int(b.numToolCalls.p95)} / '
        'max ${_int(b.numToolCalls.max)}',
      );
      buf.writeln(
        '- turns: med ${_int(b.numTurns.median)} / '
        'p95 ${_int(b.numTurns.p95)} / '
        'max ${_int(b.numTurns.max)}',
      );
    }
  }

  return buf.toString();
}

String _cost(double v) => v.toStringAsFixed(4);
String _ms(double v) => '${v.toStringAsFixed(0)}ms';
String _int(double v) => v.toStringAsFixed(0);
