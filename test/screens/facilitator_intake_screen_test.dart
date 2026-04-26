import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/screens/facilitator/facilitator_intake_screen.dart';

FacilitatorStyle _styleWith(List<IntakeQuestion> questions) {
  return FacilitatorStyle(
    id: 'test',
    displayName: 'Test',
    tagline: 'tagline-text',
    laloux: Laloux.green,
    personaPrompt: 'p',
    lexicon: const {},
    ceremonySchedule: const [],
    intakeTemplate: questions,
    outputMapper: OutputFormat.questLine,
    toneModifiers: const ToneModifiers(
      aggression: 0.5,
      formality: 0.5,
      verbosity: 0.5,
    ),
  );
}

Future<IntakeSubmission?> _pushIntake(
  WidgetTester tester, {
  required FacilitatorStyle style,
}) async {
  IntakeSubmission? submission;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                submission =
                    await Navigator.of(context).push<IntakeSubmission>(
                  MaterialPageRoute(
                    builder: (_) => FacilitatorIntakeScreen(style: style),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return submission;
}

void main() {
  testWidgets('renders style displayName as title and tagline as subhead', (
    tester,
  ) async {
    await _pushIntake(
      tester,
      style: _styleWith(const []),
    );
    expect(find.text('Test'), findsOneWidget); // app bar title
    expect(find.text('tagline-text'), findsOneWidget);
  });

  testWidgets('renders project description field always', (tester) async {
    await _pushIntake(tester, style: _styleWith(const []));
    expect(find.byKey(const Key('intake-description')), findsOneWidget);
  });

  testWidgets('renders text + choice questions per template', (tester) async {
    await _pushIntake(
      tester,
      style: _styleWith(const [
        IntakeQuestion(
          id: 'q1',
          prompt: 'What is the goal?',
        ),
        IntakeQuestion(
          id: 'q2',
          prompt: 'Who uses this?',
          inputKind: IntakeInputKind.choice,
          choices: ['Solo', 'Squad', 'Public'],
        ),
      ]),
    );

    expect(find.text('What is the goal?'), findsOneWidget);
    expect(find.text('Who uses this?'), findsOneWidget);
    expect(find.byKey(const Key('intake-text-q1')), findsOneWidget);
    expect(find.byKey(const Key('intake-choice-q2-Solo')), findsOneWidget);
    expect(find.byKey(const Key('intake-choice-q2-Squad')), findsOneWidget);
    expect(find.byKey(const Key('intake-choice-q2-Public')), findsOneWidget);
  });

  testWidgets('submit blocked while project description empty', (tester) async {
    final received = await _pushIntakeAndSubmit(
      tester,
      style: _styleWith(const []),
      description: '',
    );
    expect(received, isNull, reason: 'should NOT pop without description');
    expect(
      find.text('Describe the project to continue'),
      findsOneWidget,
      reason: 'validator message shown',
    );
  });

  testWidgets('submit returns description + text + choice answers', (
    tester,
  ) async {
    final received = await _pushIntakeAndSubmit(
      tester,
      style: _styleWith(const [
        IntakeQuestion(id: 'q1', prompt: 'Goal?'),
        IntakeQuestion(
          id: 'q2',
          prompt: 'Audience?',
          inputKind: IntakeInputKind.choice,
          choices: ['Solo', 'Public'],
        ),
      ]),
      description: 'todo app',
      textAnswers: const {'q1': 'track tasks'},
      choicePicks: const {'q2': 'Solo'},
    );

    expect(received, isNotNull);
    expect(received!.projectDescription, 'todo app');
    expect(received.answers['q1'], 'track tasks');
    expect(received.answers['q2'], 'Solo');
  });

  testWidgets('blank text answers are NOT included in returned map', (
    tester,
  ) async {
    final received = await _pushIntakeAndSubmit(
      tester,
      style: _styleWith(const [
        IntakeQuestion(id: 'q1', prompt: 'Optional question'),
      ]),
      description: 'fine',
      textAnswers: const {'q1': '   '},
    );
    expect(received, isNotNull);
    expect(received!.answers.containsKey('q1'), false);
  });

  testWidgets('choice answers without selection are NOT included', (
    tester,
  ) async {
    final received = await _pushIntakeAndSubmit(
      tester,
      style: _styleWith(const [
        IntakeQuestion(
          id: 'q2',
          prompt: 'Pick',
          inputKind: IntakeInputKind.choice,
          choices: ['A', 'B'],
        ),
      ]),
      description: 'fine',
      // no choicePicks
    );
    expect(received, isNotNull);
    expect(received!.answers.containsKey('q2'), false);
  });

  testWidgets('description text is trimmed before being returned', (
    tester,
  ) async {
    final received = await _pushIntakeAndSubmit(
      tester,
      style: _styleWith(const []),
      description: '   spaced description   ',
    );
    expect(received!.projectDescription, 'spaced description');
  });
}

/// Helper: open intake, fill it, tap Start, return what got popped.
Future<IntakeSubmission?> _pushIntakeAndSubmit(
  WidgetTester tester, {
  required FacilitatorStyle style,
  required String description,
  Map<String, String> textAnswers = const {},
  Map<String, String> choicePicks = const {},
}) async {
  IntakeSubmission? received;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                received =
                    await Navigator.of(context).push<IntakeSubmission>(
                  MaterialPageRoute(
                    builder: (_) => FacilitatorIntakeScreen(style: style),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.enterText(
    find.byKey(const Key('intake-description')),
    description,
  );
  for (final entry in textAnswers.entries) {
    await tester.enterText(
      find.byKey(Key('intake-text-${entry.key}')),
      entry.value,
    );
  }
  for (final entry in choicePicks.entries) {
    final finder =
        find.byKey(Key('intake-choice-${entry.key}-${entry.value}'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pump();
  }

  final submitFinder = find.byKey(const Key('intake-submit'));
  await tester.ensureVisible(submitFinder);
  await tester.pumpAndSettle();
  await tester.tap(submitFinder);
  await tester.pumpAndSettle();

  return received;
}
