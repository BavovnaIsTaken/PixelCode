import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke: MaterialApp builds', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('PixelCode')),
    ));
    expect(find.text('PixelCode'), findsOneWidget);
  });
}
