/// Tests for UsageBaselinesNotifier — pull-based contract:
///  - [refresh] flips `loading: true` and fires `get_usage_baselines` over WS
///  - an inbound `UsageBaselinesMessage` fills `report` + clears `loading`
///  - subsequent messages overwrite cleanly
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/usage_baselines_provider.dart';
import 'package:pixelcode/providers/ws_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

class _FakeWsService extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final _connCtrl = StreamController<bool>.broadcast();
  final List<String> ops = [];

  void inject(ServerMessage msg) => _msgCtrl.add(msg);

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<bool> get connectionStatus => _connCtrl.stream;

  @override
  bool get isConnected => true;

  @override
  void getUsageBaselines() {
    ops.add('getUsageBaselines');
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    await _connCtrl.close();
    return super.dispose();
  }
}

ProviderContainer _makeContainer(_FakeWsService fake) {
  final c = ProviderContainer(
    overrides: [wsServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(c.dispose);
  c.read(usageBaselinesProvider);
  return c;
}

UsageBaselinesMessage _report({int totalEntries = 0}) =>
    UsageBaselinesMessage(
      generatedAt: DateTime.utc(2026, 5, 18, 12, 0, 0),
      totalEntries: totalEntries,
      buckets: const [],
      health: const [],
    );

void main() {
  group('UsageBaselinesNotifier', () {
    test('initial state is empty', () {
      final c = _makeContainer(_FakeWsService());
      final s = c.read(usageBaselinesProvider);
      expect(s.report, isNull);
      expect(s.loading, isFalse);
      expect(s.lastRefreshAt, isNull);
    });

    test('refresh() flips loading and asks the server', () {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      c.read(usageBaselinesProvider.notifier).refresh();

      expect(c.read(usageBaselinesProvider).loading, isTrue);
      expect(fake.ops, equals(['getUsageBaselines']));
    });

    test('inbound report fills state + clears loading', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      c.read(usageBaselinesProvider.notifier).refresh();
      fake.inject(_report(totalEntries: 12));
      await Future.microtask(() {});

      final s = c.read(usageBaselinesProvider);
      expect(s.loading, isFalse);
      expect(s.report?.totalEntries, 12);
      expect(s.lastRefreshAt, isNotNull);
    });

    test('subsequent report overwrites previous', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(_report(totalEntries: 3));
      await Future.microtask(() {});
      expect(c.read(usageBaselinesProvider).report?.totalEntries, 3);

      fake.inject(_report(totalEntries: 99));
      await Future.microtask(() {});
      expect(c.read(usageBaselinesProvider).report?.totalEntries, 99);
    });

    test('non-matching messages do not flip state', () async {
      final fake = _FakeWsService();
      final c = _makeContainer(fake);

      fake.inject(ErrorMessage(message: 'ignore me'));
      await Future.microtask(() {});

      expect(c.read(usageBaselinesProvider).report, isNull);
    });
  });
}
