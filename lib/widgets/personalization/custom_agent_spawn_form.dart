/// Custom Agent Spawn Form — allows users to create custom agents with system prompts,
/// role biases, and skill weights. Includes personality presets and stats preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game_economy.dart';

/// Data class for custom agent spawn submission.
class CustomAgentSpawnData {
  final String nickname;
  final String systemPrompt;
  final String selectedRole;
  final String personalityPreset;
  final Map<SkillType, int> skillWeights;

  const CustomAgentSpawnData({
    required this.nickname,
    required this.systemPrompt,
    required this.selectedRole,
    required this.personalityPreset,
    required this.skillWeights,
  });
}

/// Personality preset templates for quick agent creation.
const personalityPresets = {
  'balanced': ('Balanced', 'Jack of all trades, master of none'),
  'speedster': ('Speedster', 'Fast execution, optimize for time'),
  'perfectionist': ('Perfectionist', 'High precision, thorough work'),
  'creative': ('Creative', 'Novel solutions, experimental approach'),
  'reliable': ('Reliable', 'Steady, dependable, error-resistant'),
};

/// Provider for custom agent spawn form state.
final customAgentSpawnFormProvider =
    StateProvider.family<Map<SkillType, int>, String>((ref, formId) {
  return {
    SkillType.speed: 3,
    SkillType.precision: 3,
    SkillType.creativity: 3,
    SkillType.insight: 3,
    SkillType.reliability: 3,
  };
});

class CustomAgentSpawnForm extends ConsumerStatefulWidget {
  final VoidCallback? onSpawnCompleted;

  const CustomAgentSpawnForm({
    this.onSpawnCompleted,
    super.key,
  });

  @override
  ConsumerState<CustomAgentSpawnForm> createState() =>
      _CustomAgentSpawnFormState();
}

class _CustomAgentSpawnFormState extends ConsumerState<CustomAgentSpawnForm> {
  late final GlobalKey<FormState> _formKey;
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _promptCtrl;

  String _selectedRole = 'coder';
  String _selectedPreset = 'balanced';
  String _formId = 'spawn-form-1';

  @override
  void initState() {
    super.initState();
    _formKey = GlobalKey<FormState>();
    _nicknameCtrl = TextEditingController();
    _promptCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(String presetKey) {
    setState(() => _selectedPreset = presetKey);

    final skillWeights = <SkillType, int>{};
    for (final skill in SkillType.values) {
      skillWeights[skill] = 3;
    }

    switch (presetKey) {
      case 'speedster':
        skillWeights[SkillType.speed] = 5;
        skillWeights[SkillType.reliability] = 2;
      case 'perfectionist':
        skillWeights[SkillType.precision] = 5;
        skillWeights[SkillType.creativity] = 2;
      case 'creative':
        skillWeights[SkillType.creativity] = 5;
        skillWeights[SkillType.precision] = 2;
      case 'reliable':
        skillWeights[SkillType.reliability] = 5;
        skillWeights[SkillType.speed] = 2;
      default:
        break;
    }

    ref.read(customAgentSpawnFormProvider(_formId).notifier).state =
        skillWeights;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final skillWeights = ref.read(customAgentSpawnFormProvider(_formId));

    final spawnData = CustomAgentSpawnData(
      nickname: _nicknameCtrl.text.trim(),
      systemPrompt: _promptCtrl.text.trim(),
      selectedRole: _selectedRole,
      personalityPreset: _selectedPreset,
      skillWeights: skillWeights,
    );

    Navigator.of(context).pop(spawnData);
    widget.onSpawnCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skillWeights = ref.watch(customAgentSpawnFormProvider(_formId));
    final totalSkillPoints =
        skillWeights.values.fold<int>(0, (sum, val) => sum + val);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Custom Agent Spawn',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Agent nickname
            Text(
              'Agent Name',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('spawn-nickname'),
              controller: _nicknameCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g., Speedy Coder',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter an agent name';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Role bias
            Text(
              'Role Bias',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: const Key('spawn-role-dropdown'),
              isExpanded: true,
              value: _selectedRole,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRole = value);
                }
              },
              items: [
                'coder',
                'reviewer',
                'tester',
                'tech-lead',
                'manager',
              ]
                  .map((role) => DropdownMenuItem(
                        value: role,
                        child: Text(role),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),

            // System prompt
            Text(
              'System Prompt',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('spawn-prompt'),
              controller: _promptCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText:
                    'Custom instructions for the agent (optional)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v != null && v.length > 1000) {
                  return 'Prompt must be 1000 characters or less';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Personality presets
            Text(
              'Personality Preset',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: personalityPresets.entries.map((entry) {
                final (key, (label, _)) = (entry.key, entry.value);
                final isSelected = _selectedPreset == key;
                return FilterChip(
                  key: Key('preset-$key'),
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) _applyPreset(key);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Skill weights
            Text(
              'Skill Weights (Total: $totalSkillPoints)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            for (final skill in SkillType.values) ...[
              _SkillWeightSlider(
                skill: skill,
                weight: skillWeights[skill] ?? 3,
                onChanged: (value) {
                  ref
                      .read(customAgentSpawnFormProvider(_formId).notifier)
                      .state = {
                    ...skillWeights,
                    skill: value,
                  };
                },
              ),
              const SizedBox(height: 12),
            ],

            // Preview box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agent Preview',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Name: ${_nicknameCtrl.text.isEmpty ? "(empty)" : _nicknameCtrl.text}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'Role: $_selectedRole',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'Personality: ${personalityPresets[_selectedPreset]?.$1 ?? "unknown"}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'Total Skill Points: $totalSkillPoints',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Submit button
            FilledButton.icon(
              key: const Key('spawn-submit'),
              onPressed: _submit,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create Agent'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillWeightSlider extends StatelessWidget {
  final SkillType skill;
  final int weight;
  final ValueChanged<int> onChanged;

  const _SkillWeightSlider({
    required this.skill,
    required this.weight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${skill.icon} ${skill.label}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '$weight',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Slider(
          key: Key('skill-slider-${skill.name}'),
          value: weight.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (value) => onChanged(value.toInt()),
        ),
      ],
    );
  }
}
