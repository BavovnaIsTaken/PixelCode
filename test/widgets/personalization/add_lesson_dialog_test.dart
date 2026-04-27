/// Tests for AddLessonDialog widget (via showAddLessonDialog).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_trait.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/widgets/personalization/add_lesson_dialog.dart';

void main() {
  group('AddLessonDialog', () {
    late _RecordingTraitsNotifier notifier;

    Widget buildTestApp() {
      notifier = _RecordingTraitsNotifier();
      return ProviderScope(
        overrides: [
          traitsProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showAddLessonDialog(context, 'coder#1'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(buildTestApp());
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows dialog title', (tester) async {
      await openDialog(tester);
      expect(find.text('Add Lesson'), findsOneWidget);
    });

    testWidgets('has strength/weakness segmented button', (tester) async {
      await openDialog(tester);
      expect(find.text('Strength'), findsOneWidget);
      expect(find.text('Weakness'), findsOneWidget);
      expect(find.byType(SegmentedButton<TraitType>), findsOneWidget);
    });

    testWidgets('has category dropdown with all 8 categories', (tester) async {
      await openDialog(tester);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      // Default shows 'code quality'
      expect(find.text('code quality'), findsOneWidget);
    });

    testWidgets('has tag text field with hint', (tester) async {
      await openDialog(tester);
      expect(find.text('Tag'), findsOneWidget);
      expect(find.text('e.g. clean-error-handling'), findsOneWidget);
    });

    testWidgets('has lesson text field with hint', (tester) async {
      await openDialog(tester);
      expect(find.text('Lesson'), findsOneWidget);
      expect(find.text('One sentence description'), findsOneWidget);
    });

    testWidgets('has Cancel and Add buttons', (tester) async {
      await openDialog(tester);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('Cancel dismisses the dialog', (tester) async {
      await openDialog(tester);
      expect(find.text('Add Lesson'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Lesson'), findsNothing);
    });

    testWidgets('validates empty tag field', (tester) async {
      await openDialog(tester);

      // Fill lesson but leave tag empty
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lesson'),
        'Some lesson',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      // Dialog should still be open
      expect(find.text('Add Lesson'), findsOneWidget);
    });

    testWidgets('validates empty lesson field', (tester) async {
      await openDialog(tester);

      // Fill tag but leave lesson empty
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tag'),
        'some-tag',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Add Lesson'), findsOneWidget);
    });

    testWidgets('validates both empty fields', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('submits lesson and dismisses dialog', (tester) async {
      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tag'),
        'clean-code',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lesson'),
        'Always uses descriptive names',
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Dialog dismissed
      expect(find.text('Add Lesson'), findsNothing);

      // Verify the notifier was called correctly
      expect(notifier.lastCall, isNotNull);
      expect(notifier.lastCall!['agentId'], 'coder#1');
      expect(notifier.lastCall!['type'], TraitType.strength);
      expect(notifier.lastCall!['category'], 'code_quality');
      expect(notifier.lastCall!['tag'], 'clean-code');
      expect(notifier.lastCall!['lesson'], 'Always uses descriptive names');
    });

    testWidgets('can switch to weakness type before submit', (tester) async {
      await openDialog(tester);

      // Tap Weakness segment
      await tester.tap(find.text('Weakness'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tag'),
        'verbose-code',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lesson'),
        'Tends to over-engineer solutions',
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(notifier.lastCall!['type'], TraitType.weakness);
    });

    testWidgets('trims whitespace from tag and lesson', (tester) async {
      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tag'),
        '  padded-tag  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lesson'),
        '  Padded lesson text  ',
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(notifier.lastCall!['tag'], 'padded-tag');
      expect(notifier.lastCall!['lesson'], 'Padded lesson text');
    });

    testWidgets('whitespace-only tag is rejected', (tester) async {
      await openDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tag'),
        '   ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lesson'),
        'Valid lesson',
      );

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Add Lesson'), findsOneWidget);
    });
  });
}

class _RecordingTraitsNotifier extends TraitsNotifier {
  Map<String, dynamic>? lastCall;

  @override
  List<AgentTrait> build() => [];

  @override
  void recordLesson({
    required String agentId,
    required TraitType type,
    required String category,
    required String tag,
    required String lesson,
  }) {
    lastCall = {
      'agentId': agentId,
      'type': type,
      'category': category,
      'tag': tag,
      'lesson': lesson,
    };
  }

  @override
  void removeLesson(String lessonId) {}
}
