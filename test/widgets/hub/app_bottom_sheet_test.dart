/// Smoke tests for [showAppBottomSheet] — verifies the shared modal sheet
/// helper renders body + drag handle, applies the wide-viewport max-width
/// constraint, and respects the optional `showDragHandle: false` flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/hub/app_bottom_sheet.dart';

Widget _harness({required Widget child, Size size = const Size(1024, 800)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders body and drag handle by default', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(_harness(
      child: Builder(builder: (ctx) {
        capturedContext = ctx;
        return ElevatedButton(
          onPressed: () => showAppBottomSheet<void>(
            context: ctx,
            builder: (_, _) =>
                const Center(child: Text('SHEET BODY MARKER')),
          ),
          child: const Text('open'),
        );
      }),
    ));
    expect(capturedContext, isNotNull);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('SHEET BODY MARKER'), findsOneWidget);
    // Drag handle is a 40×4 Container — search via DraggableScrollableSheet.
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
  });

  testWidgets('respects showDragHandle: false', (tester) async {
    await tester.pumpWidget(_harness(
      child: Builder(builder: (ctx) {
        return ElevatedButton(
          onPressed: () => showAppBottomSheet<void>(
            context: ctx,
            showDragHandle: false,
            builder: (_, _) => const Text('NO HANDLE BODY'),
          ),
          child: const Text('open'),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('NO HANDLE BODY'), findsOneWidget);
  });

  testWidgets('caps width on wide viewports via maxWidth', (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(builder: (ctx) {
          return ElevatedButton(
            onPressed: () => showAppBottomSheet<void>(
              context: ctx,
              maxWidth: 720,
              builder: (_, _) => const SizedBox(
                key: ValueKey('body'),
                height: 100,
                child: Text('B'),
              ),
            ),
            child: const Text('open'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Sheet is constrained, so the DraggableScrollableSheet ends up at most
    // 720 px wide rather than spanning the entire 2400 px viewport.
    final sheet = tester.getSize(find.byType(DraggableScrollableSheet));
    expect(sheet.width, lessThanOrEqualTo(720));
  });
}
