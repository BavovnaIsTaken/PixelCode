import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/services/agent_export_service.dart';
import 'package:pixelcode/widgets/roster/agent_overview_tab.dart';

import '../../helpers/fake_ws_service.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<ProviderContainer> _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    wsServiceProvider.overrideWith((_) => FakeAgentWsService()),
  ]);
}

Future<void> _pumpOverviewTab(
  WidgetTester tester,
  ProviderContainer container,
  String instanceId, {
  Future<String> Function(AgentBlueprint)? exportFn,
}) =>
    tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: AgentOverviewTab(instanceId: instanceId, exportFn: exportFn),
        ),
      ),
    ));

Future<void> _scrollToExportBtn(WidgetTester tester) async {
  // Two-step: bring button into render tree, then scroll until fully in viewport.
  await tester.scrollUntilVisible(
    find.byKey(const Key('agent-export-btn')),
    300.0,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(const Key('agent-export-btn')));
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('_ExportCard', () {
    testWidgets('renders export button with correct key and label',
        (tester) async {
      final container = await _makeContainer();
      final coder = container
          .read(gameEconomyProvider)
          .agents
          .values
          .firstWhere((a) => a.roleType == 'coder');

      await _pumpOverviewTab(tester, container, coder.instanceId);
      await tester.pump();

      await _scrollToExportBtn(tester);
      expect(find.byKey(const Key('agent-export-btn')), findsOneWidget);
      expect(find.text('Export Agent'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('successful export shows snackbar with file path',
        (tester) async {
      final container = await _makeContainer();
      final coder = container
          .read(gameEconomyProvider)
          .agents
          .values
          .firstWhere((a) => a.roleType == 'coder');

      await _pumpOverviewTab(
        tester,
        container,
        coder.instanceId,
        exportFn: (_) async => '/docs/PixelCode/agent.agent.json',
      );
      await tester.pump();

      await _scrollToExportBtn(tester);
      await tester.tap(find.byKey(const Key('agent-export-btn')));
      await tester.pump();

      expect(
        find.textContaining('/docs/PixelCode/agent.agent.json'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('failed export shows error snackbar', (tester) async {
      final container = await _makeContainer();
      final coder = container
          .read(gameEconomyProvider)
          .agents
          .values
          .firstWhere((a) => a.roleType == 'coder');

      await _pumpOverviewTab(
        tester,
        container,
        coder.instanceId,
        exportFn: (_) async => throw Exception('disk full'),
      );
      await tester.pump();

      await _scrollToExportBtn(tester);
      await tester.tap(find.byKey(const Key('agent-export-btn')));
      await tester.pump();

      expect(find.textContaining('Помилка експорту'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });
}
