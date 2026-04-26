import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/screens/facilitator/facilitator_picker_screen.dart';

FacilitatorStyle _style({
  required String id,
  required String name,
  required Laloux laloux,
  required OutputFormat output,
  int intakeQuestions = 2,
  List<CeremonySpec> ceremonies = const [],
}) {
  return FacilitatorStyle(
    id: id,
    displayName: name,
    tagline: 'tag for $name',
    laloux: laloux,
    personaPrompt: 'p',
    lexicon: const {},
    ceremonySchedule: ceremonies,
    intakeTemplate: List.generate(
      intakeQuestions,
      (i) => IntakeQuestion(id: 'q$i', prompt: 'Question $i'),
    ),
    outputMapper: output,
    toneModifiers: const ToneModifiers(
      aggression: 0.5,
      formality: 0.5,
      verbosity: 0.5,
    ),
  );
}

Future<FacilitatorStyle?> _pushPicker(
  WidgetTester tester, {
  required List<FacilitatorStyle> styles,
}) async {
  FacilitatorStyle? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<FacilitatorStyle>(
                  MaterialPageRoute(
                    builder: (_) =>
                        FacilitatorPickerScreen(styles: styles),
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
  return picked;
}

void main() {
  testWidgets('renders one card per style with displayName + tagline', (
    tester,
  ) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'gm',
          name: 'Game Master',
          laloux: Laloux.green,
          output: OutputFormat.questLine,
        ),
        _style(
          id: 'marina',
          name: 'Marina',
          laloux: Laloux.amber,
          output: OutputFormat.milestoneTree,
        ),
        _style(
          id: 'drill',
          name: 'Drill',
          laloux: Laloux.red,
          output: OutputFormat.missionBriefing,
        ),
      ],
    );

    expect(find.text('Game Master'), findsOneWidget);
    expect(find.text('Marina'), findsOneWidget);
    expect(find.text('Drill'), findsOneWidget);
    expect(find.text('tag for Game Master'), findsOneWidget);
    expect(find.text('tag for Marina'), findsOneWidget);
    expect(find.text('tag for Drill'), findsOneWidget);
  });

  testWidgets('shows Laloux badge label per style', (tester) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'gm',
          name: 'Game Master',
          laloux: Laloux.green,
          output: OutputFormat.questLine,
        ),
        _style(
          id: 'marina',
          name: 'Marina',
          laloux: Laloux.amber,
          output: OutputFormat.milestoneTree,
        ),
      ],
    );
    expect(find.text(Laloux.green.label), findsOneWidget);
    expect(find.text(Laloux.amber.label), findsOneWidget);
  });

  testWidgets('shows output mapper label localized to style', (tester) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'gm',
          name: 'Game Master',
          laloux: Laloux.green,
          output: OutputFormat.questLine,
        ),
        _style(
          id: 'marina',
          name: 'Marina',
          laloux: Laloux.amber,
          output: OutputFormat.milestoneTree,
        ),
        _style(
          id: 'drill',
          name: 'Drill',
          laloux: Laloux.red,
          output: OutputFormat.missionBriefing,
        ),
      ],
    );
    expect(find.text('Quest line'), findsOneWidget);
    expect(find.text('Milestone tree'), findsOneWidget);
    expect(find.text('Mission briefing'), findsOneWidget);
  });

  testWidgets('intake question count is shown per style', (tester) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'gm',
          name: 'Game Master',
          laloux: Laloux.green,
          output: OutputFormat.questLine,
          intakeQuestions: 3,
        ),
      ],
    );
    expect(find.text('3 questions'), findsOneWidget);
  });

  testWidgets('ceremony summary: clock + event-driven counts shown', (
    tester,
  ) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'drill',
          name: 'Drill',
          laloux: Laloux.red,
          output: OutputFormat.missionBriefing,
          ceremonies: const [
            CeremonySpec(kind: CeremonyKind.standup, cadence: CeremonyCadence.daily),
            CeremonySpec(
              kind: CeremonyKind.briefing,
              cadence: CeremonyCadence.onEvent,
              triggerEvent: 'mission_assigned',
            ),
          ],
        ),
      ],
    );
    expect(find.text('1 scheduled · 1 event-driven'), findsOneWidget);
  });

  testWidgets('ceremony summary: only event-driven', (tester) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'gm',
          name: 'Game Master',
          laloux: Laloux.green,
          output: OutputFormat.questLine,
          ceremonies: const [
            CeremonySpec(
              kind: CeremonyKind.briefing,
              cadence: CeremonyCadence.onEvent,
              triggerEvent: 'act_start',
            ),
          ],
        ),
      ],
    );
    expect(find.text('1 event-driven'), findsOneWidget);
  });

  testWidgets('ceremony summary: no ceremonies fallback', (tester) async {
    await _pushPicker(
      tester,
      styles: [
        _style(
          id: 'x',
          name: 'X',
          laloux: Laloux.teal,
          output: OutputFormat.koanEntry,
          ceremonies: const [],
        ),
      ],
    );
    expect(find.text('No ceremonies'), findsOneWidget);
  });

  testWidgets('tap on Choose pops the picker with the chosen style', (
    tester,
  ) async {
    final styles = [
      _style(
        id: 'gm',
        name: 'Game Master',
        laloux: Laloux.green,
        output: OutputFormat.questLine,
      ),
      _style(
        id: 'drill',
        name: 'Drill',
        laloux: Laloux.red,
        output: OutputFormat.missionBriefing,
      ),
    ];

    FacilitatorStyle? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked =
                      await Navigator.of(context).push<FacilitatorStyle>(
                    MaterialPageRoute(
                      builder: (_) =>
                          FacilitatorPickerScreen(styles: styles),
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

    // Tap on the Drill card body itself.
    await tester.tap(find.byKey(const Key('facilitator-card-drill')));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.id, 'drill');
  });

  testWidgets('tap on per-card "Choose" button also pops with the style', (
    tester,
  ) async {
    final styles = [
      _style(
        id: 'gm',
        name: 'Game Master',
        laloux: Laloux.green,
        output: OutputFormat.questLine,
      ),
    ];

    FacilitatorStyle? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked =
                      await Navigator.of(context).push<FacilitatorStyle>(
                    MaterialPageRoute(
                      builder: (_) =>
                          FacilitatorPickerScreen(styles: styles),
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

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.id, 'gm');
  });

  testWidgets('empty styles list renders without crashing (just subtitle)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FacilitatorPickerScreen(styles: []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FacilitatorPickerScreen), findsOneWidget);
    expect(find.text('Choose your facilitator'), findsOneWidget);
  });
}
