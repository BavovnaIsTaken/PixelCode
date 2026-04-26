/// Facilitator Picker — first screen a user sees when starting a new
/// project. Renders the available styles (loaded from
/// `FacilitatorStyleLoader`) and returns the chosen one via Navigator.
///
/// Design: docs/FACILITATOR_SYSTEM.md §8 (MVP cut: style picker as a
/// modal on project start).
library;

import 'package:flutter/material.dart';

import '../../models/facilitator_output.dart';
import '../../models/facilitator_style.dart';

/// A pickable style with its visual badge color. Caller supplies the
/// style; the screen only renders.
class FacilitatorPickerScreen extends StatelessWidget {
  const FacilitatorPickerScreen({
    super.key,
    required this.styles,
    this.title = 'Choose your facilitator',
    this.subtitle =
        'Pick a style that matches how you want to lead this project. '
        'You can switch later.',
  });

  final List<FacilitatorStyle> styles;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              for (final style in styles) ...[
                _StyleCard(
                  style: style,
                  onPick: () => Navigator.of(context).pop(style),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Style card ─────────────────────────────────────────────────────────────

class _StyleCard extends StatelessWidget {
  const _StyleCard({required this.style, required this.onPick});

  final FacilitatorStyle style;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentForLaloux(style.laloux);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key('facilitator-card-${style.id}'),
        onTap: onPick,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      style.displayName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _LalouxBadge(laloux: style.laloux, accent: accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                style.tagline,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.format_list_bulleted_rounded,
                    label: _outputLabel(style.outputMapper),
                  ),
                  _InfoChip(
                    icon: Icons.event_note_outlined,
                    label: _ceremonyLabel(style),
                  ),
                  _InfoChip(
                    icon: Icons.question_answer_outlined,
                    label: '${style.intakeTemplate.length} questions',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Choose'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bits ───────────────────────────────────────────────────────────────────

class _LalouxBadge extends StatelessWidget {
  const _LalouxBadge({required this.laloux, required this.accent});
  final Laloux laloux;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        laloux.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mappers ────────────────────────────────────────────────────────────────

Color _accentForLaloux(Laloux l) => switch (l) {
      Laloux.red => const Color(0xFFD64545),
      Laloux.amber => const Color(0xFFD4A53A),
      Laloux.orange => const Color(0xFFE08B3F),
      Laloux.green => const Color(0xFF4A8E5A),
      Laloux.teal => const Color(0xFF3D8A8A),
    };

String _outputLabel(OutputFormat f) => switch (f) {
      OutputFormat.questLine => 'Quest line',
      OutputFormat.missionBriefing => 'Mission briefing',
      OutputFormat.milestoneTree => 'Milestone tree',
      OutputFormat.sprintBacklog => 'Sprint backlog',
      OutputFormat.koanEntry => 'Reflection journal',
    };

String _ceremonyLabel(FacilitatorStyle style) {
  if (style.ceremonySchedule.isEmpty) return 'No ceremonies';
  final clock = style.ceremonySchedule.where((c) => c.cadence != CeremonyCadence.onEvent).length;
  final eventDriven = style.ceremonySchedule.length - clock;
  if (clock > 0 && eventDriven > 0) {
    return '$clock scheduled · $eventDriven event-driven';
  }
  if (clock > 0) return '$clock scheduled';
  return '$eventDriven event-driven';
}
