import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelcode/providers/energy_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> makeContainer() async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
  }

  test('fresh build starts with zero usage', () async {
    final c = await makeContainer();
    addTearDown(c.dispose);
    final s = c.read(energyProvider);
    expect(s.tokensUsedToday, 0);
    expect(s.opusTasksUsedToday, 0);
    expect(s.sonnetTasksUsedToday, 0);
    expect(s.dailyTokenCap, 500000);
  });

  test('recordTaskTokens increments counters', () async {
    final c = await makeContainer();
    addTearDown(c.dispose);
    c.read(energyProvider.notifier).recordTaskTokens('opus', 12000);
    final s = c.read(energyProvider);
    expect(s.tokensUsedToday, 12000);
    expect(s.opusTasksUsedToday, 1);
    expect(s.sonnetTasksUsedToday, 0);
  });

  test('effectiveModel downgrades opus past cap', () async {
    final c = await makeContainer();
    addTearDown(c.dispose);
    final n = c.read(energyProvider.notifier);
    n.recordTaskTokens('opus', 10000);
    n.recordTaskTokens('opus', 10000);
    n.recordTaskTokens('opus', 10000);
    expect(n.effectiveModel(requested: 'opus'), 'sonnet');
  });

  test('effectiveModel downgrades everything to haiku past token cap', () async {
    final c = await makeContainer();
    addTearDown(c.dispose);
    final n = c.read(energyProvider.notifier);
    n.updateDailyCap(100000);
    n.recordTaskTokens('sonnet', 200000);
    expect(n.effectiveModel(requested: 'opus'), 'haiku');
    expect(n.effectiveModel(requested: 'sonnet'), 'haiku');
  });
}
