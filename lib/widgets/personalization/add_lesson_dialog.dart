/// Dialog for manually recording a lesson for an agent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';

const _categories = [
  'code_quality',
  'architecture',
  'testing',
  'security',
  'communication',
  'delegation',
  'problem_solving',
  'tools_usage',
];

void showAddLessonDialog(BuildContext context, String agentId) {
  showDialog<void>(
    context: context,
    builder: (_) => _AddLessonDialog(agentId: agentId),
  );
}

class _AddLessonDialog extends ConsumerStatefulWidget {
  final String agentId;
  const _AddLessonDialog({required this.agentId});

  @override
  ConsumerState<_AddLessonDialog> createState() => _AddLessonDialogState();
}

class _AddLessonDialogState extends ConsumerState<_AddLessonDialog> {
  TraitType _type = TraitType.strength;
  String _category = _categories.first;
  final _tagController = TextEditingController();
  final _lessonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _tagController.dispose();
    _lessonController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    ref.read(traitsProvider.notifier).recordLesson(
          agentId: widget.agentId,
          type: _type,
          category: _category,
          tag: _tagController.text.trim(),
          lesson: _lessonController.text.trim(),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Lesson'),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TraitType>(
                segments: const [
                  ButtonSegment(
                    value: TraitType.strength,
                    label: Text('Strength'),
                    icon: Icon(Icons.trending_up, size: 16),
                  ),
                  ButtonSegment(
                    value: TraitType.weakness,
                    label: Text('Weakness'),
                    icon: Icon(Icons.trending_down, size: 16),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  isDense: true,
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.replaceAll('_', ' ')),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagController,
                decoration: const InputDecoration(
                  labelText: 'Tag',
                  hintText: 'e.g. clean-error-handling',
                  isDense: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lessonController,
                decoration: const InputDecoration(
                  labelText: 'Lesson',
                  hintText: 'One sentence description',
                  isDense: true,
                ),
                maxLines: 2,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
