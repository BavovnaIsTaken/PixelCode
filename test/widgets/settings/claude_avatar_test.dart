/// Widget tests for [ClaudeAvatar] — covers sizing, glitch lifecycle, and
/// activation toggling. Pure widget, no Riverpod overrides needed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/settings/claude_avatar.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

void main() {
  group('ClaudeAvatar', () {
    testWidgets('renders at default size of 48', (tester) async {
      await _pump(tester, const ClaudeAvatar());
      // The outer SizedBox is the size we pass; CustomPaint sits inside.
      final box = tester.widgetList<SizedBox>(find.byType(SizedBox))
          .firstWhere((s) => s.width == 48 && s.height == 48);
      expect(box.width, 48);
      expect(box.height, 48);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders at custom size', (tester) async {
      await _pump(tester, const ClaudeAvatar(size: 96, isActive: true));
      final box = tester.widgetList<SizedBox>(find.byType(SizedBox))
          .firstWhere((s) => s.width == 96 && s.height == 96);
      expect(box.width, 96);
      expect(box.height, 96);
    });

    testWidgets('inactive avatar has no transform offset', (tester) async {
      await _pump(tester, const ClaudeAvatar());
      // Pump several frames; idle avatar should never displace.
      await tester.pump(const Duration(seconds: 1));
      final transform = tester.widget<Transform>(find.byType(Transform).first);
      // matrix entries [12]=tx, [13]=ty for an Offset translate.
      expect(transform.transform.storage[12], 0.0);
      expect(transform.transform.storage[13], 0.0);
    });

    testWidgets('toggling isActive cancels old timer (no leaks on dispose)',
        (tester) async {
      await _pump(tester, const ClaudeAvatar(isActive: true));
      await tester.pump(const Duration(milliseconds: 100));

      // Switch off — the State.didUpdateWidget path must cancel its timer.
      await _pump(tester, const ClaudeAvatar(isActive: false));
      await tester.pump(const Duration(milliseconds: 200));

      // After deactivation the avatar settles back to the origin.
      final transform = tester.widget<Transform>(find.byType(Transform).first);
      expect(transform.transform.storage[12], 0.0);
      expect(transform.transform.storage[13], 0.0);
    });

    testWidgets('disposes cleanly when removed from the tree', (tester) async {
      await _pump(tester, const ClaudeAvatar(isActive: true));
      await tester.pump(const Duration(milliseconds: 50));
      // Remove the widget — if the periodic timer was not cancelled, the test
      // framework would flag the pending timer.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('zero size renders without throwing', (tester) async {
      await _pump(tester, const ClaudeAvatar(size: 0));
      // Edge: a zero-sized avatar must still build.
      expect(find.byType(ClaudeAvatar), findsOneWidget);
    });
  });
}
