import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agent_hub/main.dart';

void main() {
  testWidgets('App launches', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AgentHubApp()));
    expect(find.text('Agent Hub'), findsOneWidget);
  });
}
