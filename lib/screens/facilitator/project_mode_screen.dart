/// First screen of the facilitator onboarding flow — asks whether the
/// project is new (user fills intake) or existing (agent auto-scans).
///
/// Returns a [ProjectMode] via Navigator.pop; returning null means the
/// user dismissed without choosing (treated as cancel by the controller).
library;

import 'package:flutter/material.dart';

import '../../services/facilitator_onboarding.dart';

class ProjectModeScreen extends StatelessWidget {
  const ProjectModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Налаштування проєкту')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Це новий проєкт чи вже існуючий?',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              _ModeCard(
                key: const Key('mode-existing'),
                icon: Icons.folder_open_rounded,
                title: 'Існуючий проєкт',
                subtitle:
                    'Вже є код. Агент сам прочитає README, git-лог і структуру теки — без зайвих запитань.',
                onTap: () =>
                    Navigator.of(context).pop(ProjectMode.existing),
              ),
              const SizedBox(height: 16),
              _ModeCard(
                key: const Key('mode-fresh'),
                icon: Icons.add_circle_outline_rounded,
                title: 'Новий проєкт',
                subtitle:
                    'Починаю з нуля. Оберу стиль фасилітатора і відповім на кілька запитань.',
                onTap: () =>
                    Navigator.of(context).pop(ProjectMode.fresh),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
