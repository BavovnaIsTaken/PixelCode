import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';

const _info = AgentInfo(
  id: 'coder#1',
  name: 'Alice',
  role: 'Senior Developer',
  model: 'claude-sonnet',
  roleType: 'coder',
);

void main() {
  // ─── AgentState defaults ──────────────────────────────────────────────────

  group('AgentState defaults', () {
    test('status defaults to idle', () {
      expect(const AgentState(info: _info).status, AgentStatus.idle);
    });

    test('activeTools defaults to empty', () {
      expect(const AgentState(info: _info).activeTools, isEmpty);
    });

    test('currentTask defaults to null', () {
      expect(const AgentState(info: _info).currentTask, isNull);
    });

    test('activeSince defaults to null', () {
      expect(const AgentState(info: _info).activeSince, isNull);
    });
  });

  // ─── AgentState computed booleans ────────────────────────────────────────

  group('AgentState.isActive / isBusy / busyState', () {
    test('isActive false when idle', () {
      expect(const AgentState(info: _info).isActive, isFalse);
    });

    test('isActive true when thinking', () {
      expect(
        const AgentState(info: _info, status: AgentStatus.thinking).isActive,
        isTrue,
      );
    });

    test('isActive true when running', () {
      expect(
        const AgentState(info: _info, status: AgentStatus.running).isActive,
        isTrue,
      );
    });

    test('busyState is idle when status=idle', () {
      expect(const AgentState(info: _info).busyState, AgentBusyState.idle);
    });

    test('busyState is busy when status=typing', () {
      expect(
        const AgentState(info: _info, status: AgentStatus.typing).busyState,
        AgentBusyState.busy,
      );
    });

    test('isBusy false when idle', () {
      expect(const AgentState(info: _info).isBusy, isFalse);
    });

    test('isBusy true when not idle', () {
      expect(
        const AgentState(info: _info, status: AgentStatus.reading).isBusy,
        isTrue,
      );
    });
  });

  // ─── AgentState.copyWith ──────────────────────────────────────────────────

  group('AgentState.copyWith', () {
    const base = AgentState(
      info: _info,
      status: AgentStatus.thinking,
      currentTask: 'Fix bug',
    );

    test('changes status', () {
      expect(base.copyWith(status: AgentStatus.idle).status, AgentStatus.idle);
    });

    test('preserves info', () {
      expect(base.copyWith(status: AgentStatus.idle).info, _info);
    });

    test('preserves unchanged currentTask', () {
      expect(
        base.copyWith(status: AgentStatus.idle).currentTask,
        'Fix bug',
      );
    });

    test('null currentTask is treated as no-change (preserves existing)', () {
      // copyWith has no sentinel — null means "keep existing"
      expect(base.copyWith(currentTask: null).currentTask, 'Fix bug');
    });

    test('changes activeTools', () {
      final tools = [
        ToolActivity(toolUseId: 'tu-1', toolName: 'Bash', status: 'running'),
      ];
      expect(base.copyWith(activeTools: tools).activeTools, hasLength(1));
    });
  });
}
