import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/chat/board_added_bubble.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('BoardAddedBubble', () {
    testWidgets('renders task title', (tester) async {
      await tester.pumpWidget(
        _wrap(const BoardAddedBubble(title: 'Реалізувати auth flow')),
      );
      expect(find.textContaining('Реалізувати auth flow'), findsOneWidget);
    });

    testWidgets('renders "Переглянути" button when onView is provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(BoardAddedBubble(
          title: 'Task',
          onView: () => tapped = true,
        )),
      );
      expect(find.text('Переглянути'), findsOneWidget);
      await tester.tap(find.text('Переглянути'));
      expect(tapped, isTrue);
    });

    testWidgets('hides "Переглянути" when onView is null', (tester) async {
      await tester.pumpWidget(
        _wrap(const BoardAddedBubble(title: 'Task')),
      );
      expect(find.text('Переглянути'), findsNothing);
    });

    testWidgets('truncates a very long title without overflow', (tester) async {
      const longTitle = 'Це дуже довга назва задачі яка не вміщується у один рядок на маленькому екрані';
      await tester.pumpWidget(
        _wrap(const SizedBox(width: 300, child: BoardAddedBubble(title: longTitle))),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
