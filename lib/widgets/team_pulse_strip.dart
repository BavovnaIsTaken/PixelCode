/// TeamPulseStrip — compact horizontal band showing the most recent N
/// task completions. Subscribes to [techLeadPulseProvider] which streams
/// the server's broadcast on every new completion.
///
/// Design: zero-height when empty (so first-time users see no clutter);
/// when entries exist, renders the latest as a single muted line. This
/// is the minimum surfacing of growth — fancier layouts can come later
/// once the data flow is proven.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tech_lead_pulse_provider.dart';
import '../models/app_theme.dart';

class TeamPulseStrip extends ConsumerWidget {
  const TeamPulseStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(techLeadPulseProvider);
    if (entries.isEmpty) return const SizedBox.shrink();

    final tc = context.appColors;
    // Show the freshest first; the underlying list is newest-last.
    final latest = entries.reversed.take(3).toList();
    final headline = latest.first;

    final textStyle = TextStyle(
      color: tc.textHigh.withValues(alpha: 0.78),
      fontSize: 11,
      height: 1.2,
    );
    final mutedStyle = textStyle.copyWith(
      color: tc.textHigh.withValues(alpha: 0.45),
    );

    return Tooltip(
      message: latest
          .map((e) {
            final lessonSuffix = e.topLesson == null
                ? ''
                : '\n   learned (${e.topLesson!.type}): ${e.topLesson!.lesson}';
            return '${e.role}: ${e.title}  ·  ${_relativeTime(e.ts)}$lessonSuffix';
          })
          .join('\n'),
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: tc.surface.withValues(alpha: 0.5),
          border: Border(
            bottom: BorderSide(
              color: tc.border.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 13,
              color: tc.textHigh.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: headline.role, style: textStyle),
                    TextSpan(text: ' finished ', style: mutedStyle),
                    TextSpan(
                      text: '"${headline.title}"',
                      style: textStyle,
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (entries.length > 1)
              Text(
                '+${entries.length - 1}',
                style: mutedStyle.copyWith(fontSize: 10),
              ),
            const SizedBox(width: 8),
            Text(
              _relativeTime(headline.ts),
              style: mutedStyle.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeTime(DateTime ts) {
    final now = DateTime.now().toUtc();
    final diff = now.difference(ts.toUtc());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
