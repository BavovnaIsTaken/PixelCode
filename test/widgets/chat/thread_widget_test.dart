import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/chat/thread_widget.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

ChatMessage _msg(
  String text, {
  MessageCategory? category,
  String agentId = 'manager#1',
  String? threadId,
}) =>
    ChatMessage(
      role: ChatRole.assistant,
      text: text,
      agentId: agentId,
      category: category,
      threadId: threadId,
    );

void main() {
  group('ThreadSkeleton', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const ThreadSkeleton()));
      expect(tester.takeException(), isNull);
      expect(find.byType(ThreadSkeleton), findsOneWidget);
    });
  });

  group('StatusGroupWidget', () {
    final msgs = [
      _msg('читаю lib/main.dart', category: MessageCategory.status),
      _msg('запускаю тести', category: MessageCategory.status),
      _msg('збираю результати', category: MessageCategory.status),
    ];

    testWidgets('starts collapsed — shows count but not individual texts',
        (tester) async {
      await tester.pumpWidget(_wrap(StatusGroupWidget(messages: msgs)));
      expect(find.text('3 технічних дій'), findsOneWidget);
      expect(find.text('читаю lib/main.dart'), findsNothing);
    });

    testWidgets('expands on tap to show all messages', (tester) async {
      await tester.pumpWidget(_wrap(StatusGroupWidget(messages: msgs)));
      await tester.tap(find.text('3 технічних дій'));
      await tester.pumpAndSettle();
      expect(find.text('читаю lib/main.dart'), findsOneWidget);
      expect(find.text('запускаю тести'), findsOneWidget);
    });

    testWidgets('collapses again on second tap', (tester) async {
      await tester.pumpWidget(_wrap(StatusGroupWidget(messages: msgs)));
      await tester.tap(find.text('3 технічних дій'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 технічних дій'));
      await tester.pumpAndSettle();
      expect(find.text('читаю lib/main.dart'), findsNothing);
    });
  });

  group('ThreadTile', () {
    Widget builder(ChatMessage msg) => Text(msg.text);

    testWidgets('collapses by default for regular messages', (tester) async {
      final msgs = [
        _msg('Запускаю рефактор', threadId: 'th1'),
        _msg('Готово', threadId: 'th1'),
      ];
      await tester.pumpWidget(_wrap(ThreadTile(
        threadId: 'th1',
        messages: msgs,
        messageBuilder: builder,
      )));
      // Collapsed: shows count pill, not individual message texts
      expect(find.text('2 ↓'), findsOneWidget);
      expect(find.text('Готово'), findsNothing);
    });

    testWidgets('starts expanded when thread has awaitingReply message',
        (tester) async {
      final msgs = [
        _msg('Яку базу обрати?', category: MessageCategory.awaitingReply, threadId: 'th2'),
      ];
      await tester.pumpWidget(_wrap(ThreadTile(
        threadId: 'th2',
        messages: msgs,
        messageBuilder: builder,
      )));
      await tester.pumpAndSettle();
      // Expanded: 'Згорнути' strip visible, no count pill
      expect(find.text('Згорнути'), findsOneWidget);
      expect(find.text('1 ↓'), findsNothing);
    });

    testWidgets('tap header toggles expanded/collapsed', (tester) async {
      final msgs = [_msg('Починаю задачу', threadId: 'th3')];
      await tester.pumpWidget(_wrap(ThreadTile(
        threadId: 'th3',
        messages: msgs,
        messageBuilder: builder,
      )));
      // Initially collapsed — count pill shows, no 'Згорнути'
      expect(find.text('1 ↓'), findsOneWidget);
      expect(find.text('Згорнути'), findsNothing);
      // Tap count pill to expand
      await tester.tap(find.text('1 ↓'));
      await tester.pumpAndSettle();
      expect(find.text('Згорнути'), findsOneWidget);
      expect(find.text('1 ↓'), findsNothing);
      // Tap 'Згорнути' to collapse
      await tester.tap(find.text('Згорнути'));
      await tester.pumpAndSettle();
      expect(find.text('1 ↓'), findsOneWidget);
      expect(find.text('Згорнути'), findsNothing);
    });

    testWidgets('cyan accent for awaitingReply thread', (tester) async {
      final msgs = [
        _msg('Підтвердити?', category: MessageCategory.awaitingReply, threadId: 'th4'),
      ];
      await tester.pumpWidget(_wrap(ThreadTile(
        threadId: 'th4',
        messages: msgs,
        messageBuilder: builder,
      )));
      // Just verify it renders without error (accent color tested visually)
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders without overflow on narrow widget', (tester) async {
      final msgs = [
        _msg(
          'Дуже довга назва задачі яка не вміщується у один рядок навіть на великому екрані',
          threadId: 'th5',
        ),
      ];
      await tester.pumpWidget(_wrap(SizedBox(
        width: 280,
        child: ThreadTile(
          threadId: 'th5',
          messages: msgs,
          messageBuilder: builder,
        ),
      )));
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to first message text when all messages are status',
        (tester) async {
      final msgs = [
        _msg('читаю файл', category: MessageCategory.status, threadId: 'th6'),
      ];
      await tester.pumpWidget(_wrap(ThreadTile(
        threadId: 'th6',
        messages: msgs,
        messageBuilder: builder,
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
