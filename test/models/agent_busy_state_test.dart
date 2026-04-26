import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';

void main() {
  group('AgentBusyState', () {
    group('enum values', () {
      test('has exactly two values: idle and busy', () {
        expect(AgentBusyState.values, hasLength(2));
        expect(AgentBusyState.values, contains(AgentBusyState.idle));
        expect(AgentBusyState.values, contains(AgentBusyState.busy));
      });
    });

    group('AgentState.busyState derivation', () {
      AgentState stateWith(AgentStatus status) => AgentState(
            info: const AgentInfo(
              id: 'coder#1',
              name: 'Майстер',
              role: 'Розробник',
              model: 'sonnet',
              roleType: 'coder',
            ),
            status: status,
          );

      test('idle status → AgentBusyState.idle', () {
        expect(stateWith(AgentStatus.idle).busyState, AgentBusyState.idle);
      });

      test('thinking status → AgentBusyState.busy', () {
        expect(stateWith(AgentStatus.thinking).busyState, AgentBusyState.busy);
      });

      test('typing status → AgentBusyState.busy', () {
        expect(stateWith(AgentStatus.typing).busyState, AgentBusyState.busy);
      });

      test('reading status → AgentBusyState.busy', () {
        expect(stateWith(AgentStatus.reading).busyState, AgentBusyState.busy);
      });

      test('running status → AgentBusyState.busy', () {
        expect(stateWith(AgentStatus.running).busyState, AgentBusyState.busy);
      });

      test('waiting status → AgentBusyState.busy', () {
        expect(stateWith(AgentStatus.waiting).busyState, AgentBusyState.busy);
      });
    });

    group('AgentState.isBusy', () {
      AgentState stateWith(AgentStatus status) => AgentState(
            info: const AgentInfo(
              id: 'reviewer#1',
              name: 'Детектив',
              role: 'Рецензент',
              model: 'sonnet',
              roleType: 'reviewer',
            ),
            status: status,
          );

      test('idle → isBusy is false', () {
        expect(stateWith(AgentStatus.idle).isBusy, isFalse);
      });

      test('running → isBusy is true', () {
        expect(stateWith(AgentStatus.running).isBusy, isTrue);
      });

      test('thinking → isBusy is true', () {
        expect(stateWith(AgentStatus.thinking).isBusy, isTrue);
      });
    });

    group('isActive and isBusy are equivalent', () {
      for (final status in AgentStatus.values) {
        test('$status: isActive == isBusy', () {
          final s = AgentState(
            info: const AgentInfo(
              id: 'tester#1',
              name: 'Крашер',
              role: 'Контроль якості',
              model: 'haiku',
              roleType: 'tester',
            ),
            status: status,
          );
          expect(s.isBusy, equals(s.isActive),
              reason: 'isBusy and isActive must agree for status $status');
        });
      }
    });

    group('copyWith preserves busyState', () {
      test('copyWith status change updates busyState', () {
        final idle = AgentState(
          info: const AgentInfo(
            id: 'coder#1',
            name: 'Майстер',
            role: 'Розробник',
            model: 'sonnet',
            roleType: 'coder',
          ),
          status: AgentStatus.idle,
        );
        final busy = idle.copyWith(status: AgentStatus.running);
        expect(idle.busyState, AgentBusyState.idle);
        expect(busy.busyState, AgentBusyState.busy);
      });

      test('copyWith to idle clears busy', () {
        final busy = AgentState(
          info: const AgentInfo(
            id: 'coder#1',
            name: 'Майстер',
            role: 'Розробник',
            model: 'sonnet',
            roleType: 'coder',
          ),
          status: AgentStatus.thinking,
        );
        final idle = busy.copyWith(status: AgentStatus.idle);
        expect(idle.isBusy, isFalse);
      });
    });
  });
}
