/// Tests for the reconciled agent-status providers (C.2.6).
///
/// These exist because two server streams used to disagree:
///   - `agentsProvider` (push, sticky) said "manager#1 reading"
///   - `activeAgentsProvider` (snapshot, authoritative) said "no one"
///
/// The reconciler forces idle whenever the active set says the agent isn't
/// running, regardless of the last push. Pin the table below so future
/// refactors of either upstream provider can't silently re-introduce the
/// desync.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/active_agents_provider.dart';
import 'package:pixelcode/providers/agent_operational_status_provider.dart';
import 'package:pixelcode/providers/agent_provider.dart';

const _managerInfo = AgentInfo(
  id: 'manager#1',
  name: 'Капітан',
  role: 'Manager',
  model: 'auto',
  roleType: 'manager',
);

const _techInfo = AgentInfo(
  id: 'tech-lead#1',
  name: 'Архітектор',
  role: 'Tech lead',
  model: 'auto',
  roleType: 'tech-lead',
);

class _StubActiveAgentsNotifier extends ActiveAgentsNotifier {
  _StubActiveAgentsNotifier(this._seed);
  final List<ActiveAgentEntry> _seed;

  @override
  List<ActiveAgentEntry> build() => List.unmodifiable(_seed);
}

class _StubAgentsNotifier extends AgentsNotifier {
  _StubAgentsNotifier(this._seed);
  final Map<String, AgentState> _seed;

  @override
  Map<String, AgentState> build() => Map.unmodifiable(_seed);
}

ProviderContainer _makeContainer({
  required Map<String, AgentState> pushed,
  required List<ActiveAgentEntry> active,
}) {
  final c = ProviderContainer(overrides: [
    agentsProvider.overrideWith(() => _StubAgentsNotifier(pushed)),
    activeAgentsProvider.overrideWith(() => _StubActiveAgentsNotifier(active)),
  ]);
  addTearDown(c.dispose);
  return c;
}

ActiveAgentEntry _chat(String agentId) => ActiveAgentEntry(
      kind: ActiveAgentKind.chat,
      id: 'q_$agentId',
      agentId: agentId,
      task: 'work',
      elapsedMs: 1000,
    );

void main() {
  group('agentOperationalStatusProvider', () {
    test('forces idle when active set is empty even if push says reading',
        () {
      // The original bug: chat header showed "Reading" while Settings said
      // "no one is working" because the agent_status push was sticky and
      // the SDK run had terminated without a final idle event.
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(
            info: _managerInfo,
            status: AgentStatus.reading,
          ),
        },
        active: const [],
      );
      expect(
        c.read(agentOperationalStatusProvider('manager#1')),
        AgentStatus.idle,
      );
    });

    test('passes the granular push status when agent is in active set', () {
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(
            info: _managerInfo,
            status: AgentStatus.typing,
          ),
        },
        active: [_chat('manager#1')],
      );
      expect(
        c.read(agentOperationalStatusProvider('manager#1')),
        AgentStatus.typing,
      );
    });

    test('queried agent NOT in active set returns idle even if peer is busy',
        () {
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(
            info: _managerInfo,
            status: AgentStatus.reading,
          ),
          'tech-lead#1': const AgentState(
            info: _techInfo,
            status: AgentStatus.running,
          ),
        },
        active: [_chat('tech-lead#1')],
      );
      expect(
        c.read(agentOperationalStatusProvider('manager#1')),
        AgentStatus.idle,
      );
      expect(
        c.read(agentOperationalStatusProvider('tech-lead#1')),
        AgentStatus.running,
      );
    });

    test('unknown agentId returns idle (no false-positive busy)', () {
      final c = _makeContainer(pushed: const {}, active: const []);
      expect(
        c.read(agentOperationalStatusProvider('ghost#9')),
        AgentStatus.idle,
      );
    });

    test('push=idle stays idle regardless of active membership', () {
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(info: _managerInfo),
        },
        active: [_chat('manager#1')],
      );
      expect(
        c.read(agentOperationalStatusProvider('manager#1')),
        AgentStatus.idle,
      );
    });
  });

  group('agentOperationalStatusesProvider', () {
    test('emits a reconciled status per known agent', () {
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(
            info: _managerInfo,
            status: AgentStatus.reading,
          ),
          'tech-lead#1': const AgentState(
            info: _techInfo,
            status: AgentStatus.thinking,
          ),
        },
        active: [_chat('tech-lead#1')],
      );
      final map = c.read(agentOperationalStatusesProvider);
      expect(map['manager#1'], AgentStatus.idle);
      expect(map['tech-lead#1'], AgentStatus.thinking);
    });
  });

  group('reconciledAgentsProvider', () {
    test('preserves AgentInfo when forcing idle', () {
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(
            info: _managerInfo,
            status: AgentStatus.reading,
            activeTools: [
              ToolActivity(
                toolUseId: 't1',
                toolName: 'Read',
                status: 'Reading char_0.png',
              ),
            ],
          ),
        },
        active: const [],
      );
      final reconciled = c.read(reconciledAgentsProvider);
      final state = reconciled['manager#1']!;
      expect(state.info, _managerInfo, reason: 'info preserved');
      expect(state.status, AgentStatus.idle, reason: 'status forced idle');
      expect(state.activeTools, isEmpty, reason: 'stale tools cleared');
    });

    test('leaves active agents untouched (passes through .status + tools)',
        () {
      const tools = [
        ToolActivity(
          toolUseId: 't1',
          toolName: 'Read',
          status: 'Reading lib/foo.dart',
        ),
      ];
      final c = _makeContainer(
        pushed: {
          'manager#1': const AgentState(
            info: _managerInfo,
            status: AgentStatus.reading,
            activeTools: tools,
          ),
        },
        active: [_chat('manager#1')],
      );
      final state = c.read(reconciledAgentsProvider)['manager#1']!;
      expect(state.status, AgentStatus.reading);
      expect(state.activeTools, tools);
    });

    test('idle-already-idle stays idle without allocating a new state', () {
      const seed = AgentState(info: _managerInfo);
      final c = _makeContainer(
        pushed: const {'manager#1': seed},
        active: const [],
      );
      expect(identical(c.read(reconciledAgentsProvider)['manager#1'], seed),
          isTrue);
    });
  });
}
