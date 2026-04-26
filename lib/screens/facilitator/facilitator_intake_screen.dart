/// Facilitator Intake — second screen after the user picks a style.
/// Renders the chosen style's `intakeTemplate` as a form, collects
/// answers, and pops with `IntakeAnswers` (a `Map<String, String>`).
///
/// The screen is style-agnostic at the UI level — same layout for every
/// facilitator. The PROMPTS themselves carry the style flavor (each
/// preset's JSON authors them in voice). This way Drill's intake feels
/// brutal and Game Master's feels narrative without any per-style UI.
///
/// Design: docs/FACILITATOR_SYSTEM.md §8 (MVP cut: intake step).
library;

import 'package:flutter/material.dart';

import '../../models/facilitator_style.dart';

/// Returned from `Navigator.pop` on submit. Always includes the
/// project description; per-question answers keyed by `IntakeQuestion.id`.
class IntakeSubmission {
  final String projectDescription;
  final Map<String, String> answers;

  const IntakeSubmission({
    required this.projectDescription,
    required this.answers,
  });
}

class FacilitatorIntakeScreen extends StatefulWidget {
  const FacilitatorIntakeScreen({
    super.key,
    required this.style,
    this.title,
  });

  final FacilitatorStyle style;
  final String? title;

  @override
  State<FacilitatorIntakeScreen> createState() => _FacilitatorIntakeScreenState();
}

class _FacilitatorIntakeScreenState extends State<FacilitatorIntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final Map<String, TextEditingController> _textCtrls = {};
  final Map<String, String> _choiceAnswers = {};

  @override
  void initState() {
    super.initState();
    for (final q in widget.style.intakeTemplate) {
      if (q.inputKind == IntakeInputKind.text) {
        _textCtrls[q.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final answers = <String, String>{};
    for (final q in widget.style.intakeTemplate) {
      if (q.inputKind == IntakeInputKind.text) {
        final v = _textCtrls[q.id]?.text.trim() ?? '';
        if (v.isNotEmpty) answers[q.id] = v;
      } else {
        final v = _choiceAnswers[q.id];
        if (v != null && v.isNotEmpty) answers[q.id] = v;
      }
    }

    Navigator.of(context).pop(
      IntakeSubmission(
        projectDescription: _descriptionCtrl.text.trim(),
        answers: answers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? widget.style.displayName),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.style.tagline,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Project description — always asked, style-agnostic field.
                Text(
                  'Describe the project',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('intake-description'),
                  controller: _descriptionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'A few sentences about what you want to build…',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Describe the project to continue';
                    }
                    return null;
                  },
                ),

                // Per-style intake questions.
                for (final q in widget.style.intakeTemplate) ...[
                  const SizedBox(height: 24),
                  _IntakeQuestionField(
                    question: q,
                    textCtrl: _textCtrls[q.id],
                    choiceValue: _choiceAnswers[q.id],
                    onChoice: (v) =>
                        setState(() => _choiceAnswers[q.id] = v ?? ''),
                  ),
                ],

                const SizedBox(height: 32),
                FilledButton.icon(
                  key: const Key('intake-submit'),
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Start'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Single-question field ─────────────────────────────────────────────────

class _IntakeQuestionField extends StatelessWidget {
  const _IntakeQuestionField({
    required this.question,
    required this.textCtrl,
    required this.choiceValue,
    required this.onChoice,
  });

  final IntakeQuestion question;
  final TextEditingController? textCtrl;
  final String? choiceValue;
  final ValueChanged<String?> onChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: Key('intake-question-${question.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(question.prompt, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (question.inputKind == IntakeInputKind.text)
          TextFormField(
            key: Key('intake-text-${question.id}'),
            controller: textCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          )
        else
          Column(
            children: [
              for (final choice in question.choices)
                RadioListTile<String>(
                  key: Key('intake-choice-${question.id}-$choice'),
                  title: Text(choice),
                  value: choice,
                  groupValue: choiceValue,
                  onChanged: onChoice,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
      ],
    );
  }
}
