import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/providers/active_facilitator_style_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/widgets/chat/board_added_bubble.dart';

class _FakeStyleNotifier extends ActiveFacilitatorStyleNotifier {
  final FacilitatorStyle? seed;
  _FakeStyleNotifier(this.seed);
  @override
  Future<FacilitatorStyle?> build() async => seed;
}

Future<Widget> _wrap(Widget child, {FacilitatorStyle? style}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      activeFacilitatorStyleProvider.overrideWith(
        () => _FakeStyleNotifier(style),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

FacilitatorStyle _gameMaster() => FacilitatorStyle.fromJson({
      'id': 'game_master',
      'displayName': 'Game Master',
      'tagline': '',
      'laloux': 'green',
      'personaPrompt': '',
      'lexicon': {'backlog': 'questboard'},
      'outputMapper': 'questLine',
      'toneModifiers': <String, dynamic>{},
    });

void main() {
  group('BoardAddedBubble', () {
    testWidgets('renders task title', (tester) async {
      await tester.pumpWidget(
        await _wrap(const BoardAddedBubble(title: 'Реалізувати auth flow')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Реалізувати auth flow'), findsOneWidget);
    });

    testWidgets('renders "Переглянути" button when onView is provided',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        await _wrap(BoardAddedBubble(
          title: 'Task',
          onView: () => tapped = true,
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('Переглянути'), findsOneWidget);
      await tester.tap(find.text('Переглянути'));
      expect(tapped, isTrue);
    });

    testWidgets('hides "Переглянути" when onView is null', (tester) async {
      await tester.pumpWidget(
        await _wrap(const BoardAddedBubble(title: 'Task')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Переглянути'), findsNothing);
    });

    testWidgets('truncates a very long title without overflow', (tester) async {
      const longTitle =
          'Це дуже довга назва задачі яка не вміщується у один рядок на маленькому екрані';
      await tester.pumpWidget(
        await _wrap(const SizedBox(
            width: 300, child: BoardAddedBubble(title: longTitle))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to "беклог" when no facilitator style is active',
        (tester) async {
      await tester.pumpWidget(
        await _wrap(const BoardAddedBubble(title: 'X')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Додано в Нові'), findsOneWidget);
    });

    testWidgets('uses style.lexicon[backlog] when active style is set',
        (tester) async {
      await tester.pumpWidget(
        await _wrap(
          const BoardAddedBubble(title: 'X'),
          style: _gameMaster(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Додано в questboard'), findsOneWidget);
    });
  });
}
