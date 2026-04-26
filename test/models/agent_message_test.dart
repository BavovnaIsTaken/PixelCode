import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/models/facilitator_output.dart' show OutputFormat;

void main() {
  // ─── parseAgentStatus ─────────────────────────────────────────────────────

  group('parseAgentStatus', () {
    test('thinking', () => expect(parseAgentStatus('thinking'), AgentStatus.thinking));
    test('typing', () => expect(parseAgentStatus('typing'), AgentStatus.typing));
    test('reading', () => expect(parseAgentStatus('reading'), AgentStatus.reading));
    test('running', () => expect(parseAgentStatus('running'), AgentStatus.running));
    test('waiting', () => expect(parseAgentStatus('waiting'), AgentStatus.waiting));
    test('unknown string falls back to idle', () => expect(parseAgentStatus('bogus'), AgentStatus.idle));
    test('empty string falls back to idle', () => expect(parseAgentStatus(''), AgentStatus.idle));
  });

  // ─── AgentInfo.fromJson ───────────────────────────────────────────────────

  group('AgentInfo.fromJson', () {
    test('parses all fields', () {
      final json = {
        'id': 'coder#1',
        'name': 'Alice',
        'role': 'Senior Developer',
        'model': 'claude-sonnet-4-6',
        'roleType': 'coder',
        'provider': 0,
      };
      final info = AgentInfo.fromJson(json);
      expect(info.id, 'coder#1');
      expect(info.name, 'Alice');
      expect(info.role, 'Senior Developer');
      expect(info.model, 'claude-sonnet-4-6');
      expect(info.roleType, 'coder');
      expect(info.provider, AgentProviderType.cloud);
    });

    test('derives roleType from id prefix when not provided', () {
      final json = {
        'id': 'designer#2',
        'name': 'Bob',
        'role': 'Designer',
        'model': 'claude-sonnet-4-6',
        'provider': 0,
      };
      final info = AgentInfo.fromJson(json);
      expect(info.roleType, 'designer');
    });

    test('derives roleType as full id when no # present', () {
      final json = {
        'id': 'manager',
        'name': 'Manager',
        'role': 'Manager',
        'model': 'claude-sonnet-4-6',
        'provider': 0,
      };
      final info = AgentInfo.fromJson(json);
      expect(info.roleType, 'manager');
    });

    test('explicit roleType takes precedence over id prefix', () {
      final json = {
        'id': 'coder#5',
        'name': 'Carol',
        'role': 'Coder',
        'model': 'claude-sonnet-4-6',
        'roleType': 'senior_coder',
        'provider': 0,
      };
      final info = AgentInfo.fromJson(json);
      expect(info.roleType, 'senior_coder');
    });

    test('provider defaults to cloud (0) when missing', () {
      final json = {
        'id': 'coder#1',
        'name': 'Dev',
        'role': 'Coder',
        'model': 'claude-sonnet-4-6',
        'roleType': 'coder',
      };
      final info = AgentInfo.fromJson(json);
      expect(info.provider, AgentProviderType.cloud);
    });

    test('provider=1 maps to local', () {
      final json = {
        'id': 'coder#1',
        'name': 'Dev',
        'role': 'Coder',
        'model': 'gemini-nano',
        'roleType': 'coder',
        'provider': 1,
      };
      final info = AgentInfo.fromJson(json);
      expect(info.provider, AgentProviderType.local);
    });
  });

  // ─── HealthItemId ─────────────────────────────────────────────────────────

  group('HealthItemId.fromWire', () {
    test('tailscaleInstalled', () => expect(
      HealthItemId.fromWire('tailscaleInstalled'), HealthItemId.tailscaleInstalled));
    test('tailscaleRunning', () => expect(
      HealthItemId.fromWire('tailscaleRunning'), HealthItemId.tailscaleRunning));
    test('funnelActive', () => expect(
      HealthItemId.fromWire('funnelActive'), HealthItemId.funnelActive));
    test('serverListening', () => expect(
      HealthItemId.fromWire('serverListening'), HealthItemId.serverListening));
    test('clientConnected', () => expect(
      HealthItemId.fromWire('clientConnected'), HealthItemId.clientConnected));
    test('iosSigning', () => expect(
      HealthItemId.fromWire('iosSigning'), HealthItemId.iosSigning));
    test('xcodeTools', () => expect(
      HealthItemId.fromWire('xcodeTools'), HealthItemId.xcodeTools));
    test('androidSdk', () => expect(
      HealthItemId.fromWire('androidSdk'), HealthItemId.androidSdk));
    test('mdnsActive', () => expect(
      HealthItemId.fromWire('mdnsActive'), HealthItemId.mdnsActive));
    test('unknown returns null', () => expect(
      HealthItemId.fromWire('bogus'), isNull));
    test('empty string returns null', () => expect(
      HealthItemId.fromWire(''), isNull));
  });

  group('HealthItemId.wire round-trip', () {
    test('all values survive wire round-trip', () {
      for (final id in HealthItemId.values) {
        expect(HealthItemId.fromWire(id.wire), id);
      }
    });
  });

  // ─── HealthItem.fromJson ──────────────────────────────────────────────────

  group('HealthItem.fromJson', () {
    test('parses ok status', () {
      final item = HealthItem.fromJson({
        'id': 'tailscaleRunning',
        'status': 'ok',
      });
      expect(item, isNotNull);
      expect(item!.status, HealthStatus.ok);
    });

    test('parses checking status', () {
      final item = HealthItem.fromJson({
        'id': 'serverListening',
        'status': 'checking',
      });
      expect(item!.status, HealthStatus.checking);
    });

    test('unknown status maps to fail', () {
      final item = HealthItem.fromJson({
        'id': 'tailscaleInstalled',
        'status': 'unknown',
      });
      expect(item!.status, HealthStatus.fail);
    });

    test('missing status defaults to fail', () {
      final item = HealthItem.fromJson({'id': 'tailscaleInstalled'});
      expect(item!.status, HealthStatus.fail);
    });

    test('fixable defaults to false when missing', () {
      final item = HealthItem.fromJson({
        'id': 'androidSdk',
        'status': 'fail',
      });
      expect(item!.fixable, isFalse);
    });

    test('fixable=true is parsed', () {
      final item = HealthItem.fromJson({
        'id': 'androidSdk',
        'status': 'fail',
        'fixable': true,
        'instruction': 'Install Android SDK',
      });
      expect(item!.fixable, isTrue);
      expect(item.instruction, 'Install Android SDK');
    });

    test('unknown id returns null', () {
      final item = HealthItem.fromJson({'id': 'nonExistentItem', 'status': 'ok'});
      expect(item, isNull);
    });

    test('missing id returns null', () {
      final item = HealthItem.fromJson({'status': 'ok'});
      expect(item, isNull);
    });

    test('detail is preserved', () {
      final item = HealthItem.fromJson({
        'id': 'funnelActive',
        'status': 'ok',
        'detail': 'Tunnel running on port 443',
      });
      expect(item!.detail, 'Tunnel running on port 443');
    });
  });

  group('HealthItem.copyWith', () {
    test('changes status', () {
      const item = HealthItem(id: HealthItemId.serverListening, status: HealthStatus.checking);
      final updated = item.copyWith(status: HealthStatus.ok);
      expect(updated.status, HealthStatus.ok);
      expect(updated.id, HealthItemId.serverListening);
    });
  });

  // ─── ChatMessage ──────────────────────────────────────────────────────────

  group('ChatMessage.toJson / fromJson', () {
    test('round-trip preserves all fields', () {
      final msg = ChatMessage(
        role: ChatRole.user,
        text: 'Hello world',
        agentId: 'coder#1',
        timestamp: DateTime.parse('2026-03-01T12:00:00.000Z'),
        threadId: 'thread-42',
        category: MessageCategory.awaitingReply,
      );

      final json = msg.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.role, ChatRole.user);
      expect(restored.text, 'Hello world');
      expect(restored.agentId, 'coder#1');
      expect(restored.threadId, 'thread-42');
      expect(restored.category, MessageCategory.awaitingReply);
    });

    test('toJson omits threadId when null', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Hi',
        agentId: 'manager',
        timestamp: DateTime.now(),
      );
      final json = msg.toJson();
      expect(json.containsKey('threadId'), isFalse);
    });

    test('toJson omits category when null', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Hi',
        agentId: 'manager',
        timestamp: DateTime.now(),
      );
      final json = msg.toJson();
      expect(json.containsKey('category'), isFalse);
    });

    test('toJson omits images when empty', () {
      final msg = ChatMessage(
        role: ChatRole.user,
        text: 'No images',
        agentId: 'manager',
        timestamp: DateTime.now(),
      );
      final json = msg.toJson();
      expect(json.containsKey('images'), isFalse);
    });

    test('fromJson parses assistant role', () {
      final json = {
        'role': 'assistant',
        'text': 'Sure',
        'agentId': 'coder#1',
        'timestamp': '2026-01-01T00:00:00.000Z',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.role, ChatRole.assistant);
    });

    test('fromJson defaults agentId to manager when missing', () {
      final json = {
        'role': 'assistant',
        'text': 'Hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.agentId, 'manager');
    });

    test('fromJson parses status category', () {
      final json = {
        'role': 'assistant',
        'text': 'status update',
        'agentId': 'manager',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'category': 'status',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.category, MessageCategory.status);
    });

    test('fromJson parses taskLinked category', () {
      final json = {
        'role': 'assistant',
        'text': 'Task added',
        'agentId': 'manager',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'category': 'taskLinked',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.category, MessageCategory.taskLinked);
    });

    test('fromJson returns null category for unknown value', () {
      final json = {
        'role': 'assistant',
        'text': 'Hi',
        'agentId': 'manager',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'category': 'unknownCategory',
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.category, isNull);
    });
  });

  group('ChatMessage.copyWith', () {
    test('changes text', () {
      final msg = ChatMessage(
        role: ChatRole.user,
        text: 'original',
        agentId: 'manager',
      );
      final copy = msg.copyWith(text: 'updated');
      expect(copy.text, 'updated');
      expect(copy.role, ChatRole.user);
      expect(copy.agentId, 'manager');
    });

    test('preserves unchanged fields', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'Hi',
        agentId: 'coder#1',
        isStreaming: true,
      );
      final copy = msg.copyWith(text: 'Hello');
      expect(copy.isStreaming, isTrue);
      expect(copy.agentId, 'coder#1');
    });

    test('sets isStreaming to false', () {
      final msg = ChatMessage(
        role: ChatRole.assistant,
        text: 'partial...',
        agentId: 'manager',
        isStreaming: true,
      );
      final done = msg.copyWith(isStreaming: false, text: 'partial... done');
      expect(done.isStreaming, isFalse);
      expect(done.text, 'partial... done');
    });
  });

  // ─── ServerMessage.fromJson routing ──────────────────────────────────────

  group('ServerMessage.fromJson', () {
    ServerMessage parse(Map<String, dynamic> json) =>
        ServerMessage.fromJson(jsonEncode(json));

    test('init routes to InitMessage', () {
      final msg = parse({
        'type': 'init',
        'sessionId': 'sess-1',
        'agents': [],
      });
      expect(msg, isA<InitMessage>());
      expect((msg as InitMessage).sessionId, 'sess-1');
    });

    test('assistant_text routes to AssistantTextMessage', () {
      final msg = parse({
        'type': 'assistant_text',
        'text': 'Hello',
        'isPartial': false,
        'agentId': 'manager',
      });
      expect(msg, isA<AssistantTextMessage>());
      final cast = msg as AssistantTextMessage;
      expect(cast.text, 'Hello');
      expect(cast.isPartial, isFalse);
    });

    test('assistant_message_done routes to AssistantDoneMessage', () {
      final msg = parse({
        'type': 'assistant_message_done',
        'messageId': 'msg-42',
        'text': 'Final',
        'agentId': 'coder#1',
      });
      expect(msg, isA<AssistantDoneMessage>());
      expect((msg as AssistantDoneMessage).messageId, 'msg-42');
    });

    test('error routes to ErrorMessage', () {
      final msg = parse({'type': 'error', 'message': 'Something failed'});
      expect(msg, isA<ErrorMessage>());
      expect((msg as ErrorMessage).message, 'Something failed');
    });

    test('unknown type routes to ErrorMessage with Unknown prefix', () {
      final msg = parse({'type': 'not_a_real_type'});
      expect(msg, isA<ErrorMessage>());
      expect((msg as ErrorMessage).message, contains('Unknown message type'));
    });

    test('result routes to ResultMessage', () {
      final msg = parse({
        'type': 'result',
        'text': 'Done',
        'costUsd': 0.05,
        'durationMs': 1200,
      });
      expect(msg, isA<ResultMessage>());
      final cast = msg as ResultMessage;
      expect(cast.costUsd, 0.05);
      expect(cast.durationMs, 1200);
    });

    test('agent_status routes to AgentStatusMessage', () {
      final msg = parse({
        'type': 'agent_status',
        'agentId': 'coder#1',
        'status': 'thinking',
        'tools': [],
      });
      expect(msg, isA<AgentStatusMessage>());
      final cast = msg as AgentStatusMessage;
      expect(cast.status, AgentStatus.thinking);
    });

    test('dungeon_complete routes to DungeonCompleteMessage', () {
      final msg = parse({
        'type': 'dungeon_complete',
        'agentId': 'coder#1',
        'skillType': 2,
        'xpEarned': 150,
        'score': 8,
        'feedback': 'Great work',
        'passed': true,
      });
      expect(msg, isA<DungeonCompleteMessage>());
      final cast = msg as DungeonCompleteMessage;
      expect(cast.xpEarned, 150);
      expect(cast.passed, isTrue);
    });

    test('dungeon_error routes to DungeonErrorMessage', () {
      final msg = parse({
        'type': 'dungeon_error',
        'agentId': 'coder#1',
        'error': 'Timeout',
      });
      expect(msg, isA<DungeonErrorMessage>());
      expect((msg as DungeonErrorMessage).error, 'Timeout');
    });

    test('health_check_result routes to HealthCheckResultMessage', () {
      final msg = parse({
        'type': 'health_check_result',
        'items': [
          {'id': 'tailscaleRunning', 'status': 'ok'},
        ],
      });
      expect(msg, isA<HealthCheckResultMessage>());
      final cast = msg as HealthCheckResultMessage;
      expect(cast.items.length, 1);
      expect(cast.items[0].id, HealthItemId.tailscaleRunning);
    });

    test('health_check_result skips unknown item ids', () {
      final msg = parse({
        'type': 'health_check_result',
        'items': [
          {'id': 'nonExistent', 'status': 'ok'},
          {'id': 'tailscaleRunning', 'status': 'ok'},
        ],
      });
      final cast = msg as HealthCheckResultMessage;
      expect(cast.items.length, 1);
    });

    test('server_info routes to ServerInfoMessage', () {
      final msg = parse({
        'type': 'server_info',
        'hostname': 'myhost',
        'localIps': ['192.168.1.1'],
        'port': 9720,
      });
      expect(msg, isA<ServerInfoMessage>());
      final cast = msg as ServerInfoMessage;
      expect(cast.hostname, 'myhost');
      expect(cast.localIps, ['192.168.1.1']);
    });

    test('positions_sync routes to PositionsSyncMessage', () {
      final msg = parse({
        'type': 'positions_sync',
        'positions': {
          'coder#1': {'col': 3, 'row': 5, 'state': 'walk', 'dir': 'right'},
        },
      });
      expect(msg, isA<PositionsSyncMessage>());
      final cast = msg as PositionsSyncMessage;
      expect(cast.positions['coder#1']?.col, 3);
      expect(cast.positions['coder#1']?.dir, 'right');
    });

    test('queue_status routes to QueueStatusMessage', () {
      final msg = parse({
        'type': 'queue_status',
        'pending': 3,
        'running': [],
      });
      expect(msg, isA<QueueStatusMessage>());
      expect((msg as QueueStatusMessage).pending, 3);
    });
  });

  // ─── RemoteCharPosition.fromJson ─────────────────────────────────────────

  group('RemoteCharPosition.fromJson', () {
    test('parses all fields', () {
      final pos = RemoteCharPosition.fromJson({
        'col': 4,
        'row': 7,
        'state': 'walk',
        'dir': 'left',
        'onSkateboard': true,
      });
      expect(pos.col, 4);
      expect(pos.row, 7);
      expect(pos.state, 'walk');
      expect(pos.dir, 'left');
      expect(pos.onSkateboard, isTrue);
    });

    test('defaults all fields when empty', () {
      final pos = RemoteCharPosition.fromJson({});
      expect(pos.col, 0);
      expect(pos.row, 0);
      expect(pos.state, 'idle');
      expect(pos.dir, 'down');
      expect(pos.onSkateboard, isFalse);
    });
  });

  // ─── OutputFormat (from facilitator_output.dart) ─────────────────────────

  group('OutputFormat.fromKey', () {
    test('mission_briefing', () => expect(
      OutputFormat.fromKey('mission_briefing'), OutputFormat.missionBriefing));
    test('milestone_tree', () => expect(
      OutputFormat.fromKey('milestone_tree'), OutputFormat.milestoneTree));
    test('sprint_backlog', () => expect(
      OutputFormat.fromKey('sprint_backlog'), OutputFormat.sprintBacklog));
    test('koan_entry', () => expect(
      OutputFormat.fromKey('koan_entry'), OutputFormat.koanEntry));
    test('unknown falls back to questLine', () => expect(
      OutputFormat.fromKey('bogus'), OutputFormat.questLine));
    test('quest_line explicit', () => expect(
      OutputFormat.fromKey('quest_line'), OutputFormat.questLine));

    test('all keys survive round-trip', () {
      for (final format in OutputFormat.values) {
        expect(OutputFormat.fromKey(format.key), format);
      }
    });
  });
}
