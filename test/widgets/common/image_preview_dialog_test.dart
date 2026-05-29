import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/common/image_preview_dialog.dart';

// 1×1 transparent PNG — minimum valid PNG that decodes in widget tests.
final _onePxPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

Widget _harness(Widget Function(BuildContext) launchBuilder) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(builder: launchBuilder),
    ),
  );
}

void main() {
  testWidgets('renders an Image and a close button', (tester) async {
    await tester.pumpWidget(_harness((ctx) {
      return ElevatedButton(
        onPressed: () => showImagePreviewDialog(ctx, _onePxPng),
        child: const Text('open'),
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('renders name badge when provided', (tester) async {
    await tester.pumpWidget(_harness((ctx) {
      return ElevatedButton(
        onPressed: () =>
            showImagePreviewDialog(ctx, _onePxPng, name: 'photo.png'),
        child: const Text('open'),
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('photo.png'), findsOneWidget);
  });

  testWidgets('close button dismisses the dialog', (tester) async {
    await tester.pumpWidget(_harness((ctx) {
      return ElevatedButton(
        onPressed: () => showImagePreviewDialog(ctx, _onePxPng),
        child: const Text('open'),
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('tap on dim background dismisses the dialog', (tester) async {
    await tester.pumpWidget(_harness((ctx) {
      return ElevatedButton(
        onPressed: () => showImagePreviewDialog(ctx, _onePxPng),
        child: const Text('open'),
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Top-left corner is on the background GestureDetector, not the image.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
  });
}
