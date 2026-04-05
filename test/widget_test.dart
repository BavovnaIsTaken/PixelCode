import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixel_code/main.dart';

void main() {
  testWidgets('App launches', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PixelCodeApp()));
    expect(find.text('PixelCode'), findsOneWidget);
  });
}
