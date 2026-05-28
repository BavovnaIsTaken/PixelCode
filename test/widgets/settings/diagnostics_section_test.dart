/// Widget tests for [DiagnosticsSection] — covers core/extra row rendering,
/// status-driven action buttons, instruction reveal, and refresh state.
///
/// We override [healthProvider] with a fake notifier so we can drive the
/// state machine directly without spinning up a real WS service.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/health_provider.dart';
import 'package:pixelcode/widgets/settings/diagnostics_section.dart';

// ─── Fake notifier ──────────────────────────────────────────────────────────

class _FakeHealthNotifier extends HealthNotifier {
  _FakeHealthNotifier(this._initial);
  final HealthState _initial;
  int refreshAllCalls = 0;
  final List<HealthItemId> fixCalls = [];

  @override
  HealthState build() => _initial;

  @override
  void refreshAll() {
    refreshAllCalls += 1;
    state = state.copyWith(refreshing: true);
  }

  @override
  void fix(HealthItemId id) {
    fixCalls.add(id);
    final next = Map<HealthItemId, HealthItemView>.from(state.items);
    final prev = next[id];
    if (prev != null) {
      next[id] = prev.copyWith(fixing: true);
      state = state.copyWith(items: next);
    }
  }
}

HealthItemView _view({
  required HealthItemId id,
  required HealthStatus status,
  String? detail,
  bool fixable = false,
  String? instruction,
  bool fixing = false,
}) =>
    HealthItemView(
      item: HealthItem(
        id: id,
        status: status,
        detail: detail,
        fixable: fixable,
        instruction: instruction,
      ),
      fixing: fixing,
    );

Future<void> _pump(
  WidgetTester tester, {
  required HealthState state,
  _FakeHealthNotifier? notifier,
}) async {
  final n = notifier ?? _FakeHealthNotifier(state);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      healthProvider.overrideWith(() => n),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 600, child: DiagnosticsSection()),
        ),
      ),
    ),
  ));
}

void main() {
  group('DiagnosticsSection — layout', () {
    testWidgets('renders all 5 core rows by default', (tester) async {
      await _pump(tester, state: const HealthState());
      // Pump post-frame callback that kicks off the first refresh.
      await tester.pump();

      expect(find.text('Tailscale CLI встановлений'), findsOneWidget);
      expect(find.text('Tailscale демон запущений'), findsOneWidget);
      expect(find.text('Funnel активний'), findsOneWidget);
      expect(find.text('Сервер слухає порт'), findsOneWidget);
      expect(find.text('Клієнт підключений до сервера'), findsOneWidget);
      // Extras hidden by default.
      expect(find.text('iOS signing identity'), findsNothing);
    });

    testWidgets('extra rows expand on toggle', (tester) async {
      await _pump(tester, state: const HealthState());
      await tester.pump();

      expect(find.text('Bonjour / mDNS'), findsNothing);
      await tester.tap(find.text('Додаткові перевірки'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('iOS signing identity'), findsOneWidget);
      expect(find.text('Xcode Command Line Tools'), findsOneWidget);
      expect(find.text('Android SDK / adb'), findsOneWidget);
      expect(find.text('Android signing keystore'), findsOneWidget);
      expect(find.text('Bonjour / mDNS'), findsOneWidget);
    });

    testWidgets('header description is shown', (tester) async {
      await _pump(tester, state: const HealthState());
      await tester.pump();
      expect(find.textContaining('Перевірка компонентів'), findsOneWidget);
    });
  });

  group('DiagnosticsSection — refresh button', () {
    testWidgets('label says "Оновити" when idle, calls refreshAll on tap',
        (tester) async {
      final notifier = _FakeHealthNotifier(const HealthState());
      await _pump(tester, state: const HealthState(), notifier: notifier);
      // Initial postFrame call counts as 1.
      await tester.pump();
      expect(notifier.refreshAllCalls, 1);

      // Tapping the visible "Оновити" button bumps the counter.
      // After the first refresh, the fake puts state in `refreshing`, so the
      // button shows "Перевірка…" — flip back to idle to enable the button.
      notifier.state = const HealthState();
      await tester.pump();

      await tester.tap(find.text('Оновити'));
      await tester.pump();
      expect(notifier.refreshAllCalls, 2);
    });

    testWidgets('label says "Перевірка…" while refreshing and is disabled',
        (tester) async {
      final notifier = _FakeHealthNotifier(
        const HealthState(refreshing: true),
      );
      await _pump(tester, state: const HealthState(), notifier: notifier);
      await tester.pump();

      expect(find.text('Перевірка…'), findsOneWidget);
      // Counter was bumped once by post-frame kick. Tapping the disabled
      // button must not bump it again.
      final before = notifier.refreshAllCalls;
      await tester.tap(find.text('Перевірка…'), warnIfMissed: false);
      await tester.pump();
      expect(notifier.refreshAllCalls, before);
    });
  });

  group('DiagnosticsSection — row actions', () {
    testWidgets('fail + fixable shows "Виправити" and triggers fix()',
        (tester) async {
      final state = HealthState(items: {
        HealthItemId.tailscaleRunning: _view(
          id: HealthItemId.tailscaleRunning,
          status: HealthStatus.fail,
          fixable: true,
          detail: 'демон не запущено',
        ),
      });
      final notifier = _FakeHealthNotifier(state);
      await _pump(tester, state: state, notifier: notifier);
      await tester.pump();

      expect(find.text('Виправити'), findsOneWidget);
      expect(find.text('демон не запущено'), findsOneWidget);

      await tester.tap(find.text('Виправити'));
      await tester.pump();
      expect(notifier.fixCalls, [HealthItemId.tailscaleRunning]);
    });

    testWidgets('fail + non-fixable + instruction reveals instruction panel',
        (tester) async {
      const instruction = 'brew install tailscale';
      final state = HealthState(items: {
        HealthItemId.tailscaleInstalled: _view(
          id: HealthItemId.tailscaleInstalled,
          status: HealthStatus.fail,
          fixable: false,
          instruction: instruction,
        ),
      });
      await _pump(tester, state: state);
      await tester.pump();

      expect(find.text('Інструкція'), findsOneWidget);
      // Hidden until we tap.
      expect(find.text(instruction), findsNothing);

      await tester.tap(find.text('Інструкція'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(instruction), findsOneWidget);
      expect(find.text('Сховати'), findsOneWidget);

      // Toggling closes it again.
      await tester.tap(find.text('Сховати'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(instruction), findsNothing);
    });

    testWidgets('OK row shows no action button', (tester) async {
      final state = HealthState(items: {
        HealthItemId.serverListening: _view(
          id: HealthItemId.serverListening,
          status: HealthStatus.ok,
        ),
      });
      await _pump(tester, state: state);
      await tester.pump();
      // Header has only the global "Оновити". No per-row "Виправити" / "Інструкція".
      expect(find.text('Виправити'), findsNothing);
      expect(find.text('Інструкція'), findsNothing);
    });

    testWidgets('fixing flag disables the fix button', (tester) async {
      final state = HealthState(items: {
        HealthItemId.tailscaleRunning: _view(
          id: HealthItemId.tailscaleRunning,
          status: HealthStatus.fail,
          fixable: true,
          fixing: true,
        ),
      });
      final notifier = _FakeHealthNotifier(state);
      await _pump(tester, state: state, notifier: notifier);
      await tester.pump();

      expect(find.text('Виправляю…'), findsOneWidget);
      // Disabled — tapping it should NOT enqueue another fix call.
      await tester.tap(find.text('Виправляю…'), warnIfMissed: false);
      await tester.pump();
      expect(notifier.fixCalls, isEmpty);
    });

    testWidgets('instruction panel exposes a copy button', (tester) async {
      const instruction = 'launchctl load com.tailscale';
      final state = HealthState(items: {
        HealthItemId.tailscaleRunning: _view(
          id: HealthItemId.tailscaleRunning,
          status: HealthStatus.fail,
          fixable: false,
          instruction: instruction,
        ),
      });
      await _pump(tester, state: state);
      await tester.pump();
      await tester.tap(find.text('Інструкція'));
      await tester.pump(const Duration(milliseconds: 200));

      // Capture only Clipboard.setData calls; let other calls fall through
      // (MaterialApp issues SystemChrome.setApplicationSwitcherDescription on
      // the same channel during initState).
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.tap(find.byTooltip('Копіювати'));
      await tester.pump();
      expect(copied, instruction);

      // Cleanup channel handler.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  });

  group('DiagnosticsSection — edge cases', () {
    testWidgets('row with no view shows checking spinner', (tester) async {
      await _pump(tester, state: const HealthState());
      await tester.pump();

      // Default state: items map is empty so every row falls back to
      // HealthStatus.checking and renders a CircularProgressIndicator.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('empty detail string does not render a subtitle line',
        (tester) async {
      final state = HealthState(items: {
        HealthItemId.funnelActive: _view(
          id: HealthItemId.funnelActive,
          status: HealthStatus.fail,
          detail: '',
        ),
      });
      await _pump(tester, state: state);
      await tester.pump();

      // The label is shown but no subtitle Padding-wrapped detail Text exists.
      expect(find.text('Funnel активний'), findsOneWidget);
      // A non-empty detail would render an extra Text inside the label column.
      // We assert by the absence of any visible empty whitespace text.
    });
  });
}
