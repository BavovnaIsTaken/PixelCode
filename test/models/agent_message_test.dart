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
    test('androidSigning', () => expect(
      HealthItemId.fromWire('androidSigning'), HealthItemId.androidSigning));
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
      expect(msg.workingDirectory, isNull);
    });

    test('init parses workingDirectory when present', () {
      final msg = parse({
        'type': 'init',
        'sessionId': 'sess-1',
        'agents': [],
        'workingDirectory': '/Users/dev/Projects/MyApp',
      }) as InitMessage;
      expect(msg.workingDirectory, '/Users/dev/Projects/MyApp');
    });

    test('init keeps workingDirectory null when field is missing', () {
      final msg = parse({
        'type': 'init',
        'sessionId': 'sess-1',
        'agents': [],
      }) as InitMessage;
      expect(msg.workingDirectory, isNull);
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

  // ─── ServerMessage.fromJson — remaining routes ────────────────────────────

  group('ServerMessage.fromJson — remaining routes', () {
    ServerMessage parse(Map<String, dynamic> json) =>
        ServerMessage.fromJson(jsonEncode(json));

    test('subagent_start routes to SubagentStartMessage', () {
      final msg = parse({
        'type': 'subagent_start',
        'parentAgentId': 'manager#1',
        'agentId': 'coder#1',
        'agentType': 'coder',
        'task': 'Write tests',
      });
      expect(msg, isA<SubagentStartMessage>());
      final cast = msg as SubagentStartMessage;
      expect(cast.agentType, 'coder');
      expect(cast.task, 'Write tests');
    });

    test('subagent_stop routes to SubagentStopMessage', () {
      final msg = parse({'type': 'subagent_stop', 'agentId': 'coder#1'});
      expect(msg, isA<SubagentStopMessage>());
      expect((msg as SubagentStopMessage).agentId, 'coder#1');
    });

    test('tool_use routes to ToolUseMessage', () {
      final msg = parse({
        'type': 'tool_use',
        'agentId': 'coder#1',
        'toolUseId': 'tu-42',
        'toolName': 'Bash',
        'status': 'running',
        'threadId': 'th-1',
      });
      expect(msg, isA<ToolUseMessage>());
      final cast = msg as ToolUseMessage;
      expect(cast.toolName, 'Bash');
      expect(cast.threadId, 'th-1');
    });

    test('subagent_thread_event routes to SubagentThreadEventMessage', () {
      final msg = parse({
        'type': 'subagent_thread_event',
        'agentId': 'manager#1',
        'toolUseId': 'tu-42_m',
        'toolName': 'Bash',
        'status': 'grep -r palette',
        'threadId': 'dispatch-1',
      });
      expect(msg, isA<SubagentThreadEventMessage>());
      final cast = msg as SubagentThreadEventMessage;
      expect(cast.agentId, 'manager#1');
      expect(cast.toolName, 'Bash');
      expect(cast.status, 'grep -r palette');
      expect(cast.threadId, 'dispatch-1');
    });

    test('tool_done routes to ToolDoneMessage', () {
      final msg = parse({
        'type': 'tool_done',
        'agentId': 'coder#1',
        'toolUseId': 'tu-42',
      });
      expect(msg, isA<ToolDoneMessage>());
      expect((msg as ToolDoneMessage).toolUseId, 'tu-42');
    });

    test('team_metrics routes to TeamMetricsMessage', () {
      final msg = parse({
        'type': 'team_metrics',
        'metrics': {
          'coder#1': {
            'tasksAssigned': 3,
            'tasksCompleted': 2,
            'reworkCount': 1,
          },
        },
      });
      expect(msg, isA<TeamMetricsMessage>());
      final cast = msg as TeamMetricsMessage;
      expect(cast.metrics['coder#1']!.tasksAssigned, 3);
      expect(cast.metrics['coder#1']!.tasksCompleted, 2);
      expect(cast.metrics['coder#1']!.reworkCount, 1);
    });

    test('activity_event routes to ActivityEventMessage', () {
      final msg = parse({
        'type': 'activity_event',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'agentId': 'coder#1',
        'event': 'tool_use',
        'detail': 'Reading file',
      });
      expect(msg, isA<ActivityEventMessage>());
      final cast = msg as ActivityEventMessage;
      expect(cast.event, 'tool_use');
      expect(cast.detail, 'Reading file');
    });

    test('comm_graph routes to CommGraphMessage', () {
      final msg = parse({
        'type': 'comm_graph',
        'events': [
          {'timestamp': 1000, 'from': 'manager#1', 'to': 'coder#1'},
        ],
      });
      expect(msg, isA<CommGraphMessage>());
      final cast = msg as CommGraphMessage;
      expect(cast.events.length, 1);
      expect(cast.events.first.from, 'manager#1');
    });

    test('debug_log routes to DebugLogMessage', () {
      final msg = parse({
        'type': 'debug_log',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'level': 'info',
        'category': 'ws',
        'message': 'Connected',
      });
      expect(msg, isA<DebugLogMessage>());
      final cast = msg as DebugLogMessage;
      expect(cast.level, 'info');
      expect(cast.category, 'ws');
    });

    test('board_state routes to BoardStateMessage (empty tasks)', () {
      final msg = parse({'type': 'board_state', 'tasks': []});
      expect(msg, isA<BoardStateMessage>());
      expect((msg as BoardStateMessage).boardState.tasks, isEmpty);
    });

    test('summary_result routes to SummaryResultMessage', () {
      final msg = parse({'type': 'summary_result', 'summary': 'All done.'});
      expect(msg, isA<SummaryResultMessage>());
      expect((msg as SummaryResultMessage).summary, 'All done.');
    });

    test('agent_traits routes to AgentTraitsMessage', () {
      final msg = parse({
        'type': 'agent_traits',
        'traits': [
          {
            'id': 'trait-1',
            'agentId': 'coder#1',
            'type': 'strength',
            'category': 'code',
            'tag': 'clean_code',
            'lesson': 'Writes clean code',
            'frequency': 3,
            'firstSeen': '2026-01-01T00:00:00.000Z',
            'lastSeen': '2026-01-02T00:00:00.000Z',
          },
        ],
      });
      expect(msg, isA<AgentTraitsMessage>());
      final cast = msg as AgentTraitsMessage;
      expect(cast.traits.length, 1);
      expect(cast.traits.first.tag, 'clean_code');
    });

    test('input_text routes to InputTextMessage', () {
      final msg = parse({'type': 'input_text', 'text': 'Hello from remote'});
      expect(msg, isA<InputTextMessage>());
      expect((msg as InputTextMessage).text, 'Hello from remote');
    });

    group('reflection_kpi', () {
      test('routes to ReflectionKpiMessage', () {
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': 30,
          'hasData': true,
          'submitted': 12,
          'promotedViaThreshold': 4,
          'promotedViaBypass': 2,
          'pending': 3,
          'duplicate': 1,
          'tooSoon': 2,
          'prunedStale': 0,
          'decayedPruned': 0,
          'constraintViolations': 1,
          'promotionRate': 0.5,
          'bypassRate': 0.33,
          'violationRate': 0.083,
          'recentViolations': [
            {
              'agentId': 'manager#1',
              'tag': 'agent-dispatch-unavailable',
              'phrases': ['was not available', 'fell back to task'],
              'lesson': 'Attempted dispatch but...',
              'ts': '2026-05-18T10:00:00.000Z',
            },
          ],
        });
        expect(msg, isA<ReflectionKpiMessage>());
        final cast = msg as ReflectionKpiMessage;
        expect(cast.windowDays, 30);
        expect(cast.submitted, 12);
        expect(cast.promotionRate, closeTo(0.5, 1e-9));
        expect(cast.recentViolations.length, 1);
        expect(cast.recentViolations.first.tag, 'agent-dispatch-unavailable');
        expect(cast.recentViolations.first.phrases, hasLength(2));
      });

      test('hasData=false snapshot is parseable + overallHealthy is null', () {
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': null,
          'hasData': false,
          'submitted': 0,
          'promotedViaThreshold': 0,
          'promotedViaBypass': 0,
          'pending': 0,
          'duplicate': 0,
          'tooSoon': 0,
          'prunedStale': 0,
          'decayedPruned': 0,
          'constraintViolations': 0,
          'promotionRate': 0,
          'bypassRate': 0,
          'violationRate': 0,
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.hasData, false);
        expect(msg.overallHealthy, isNull,
            reason: 'cold-project state must be reported as unknown, not green');
      });

      test('overallHealthy: true when all signals within thresholds', () {
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': 30, 'hasData': true,
          'submitted': 10, 'promotedViaThreshold': 4, 'promotedViaBypass': 0,
          'pending': 4, 'duplicate': 1, 'tooSoon': 1,
          'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
          'invalidTagCount': 0,
          'promotionRate': 0.4, 'bypassRate': 0.0, 'violationRate': 0.0,
          'invalidTagRate': 0.0, 'tagEntropy': 2.5, 'topTagShare': 0.3,
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.overallHealthy, isTrue);
        expect(msg.promotionRateOk, isTrue);
        expect(msg.bypassRateOk, isTrue);
        expect(msg.violationRateOk, isTrue);
        expect(msg.invalidTagRateOk, isTrue);
        expect(msg.tagEntropyOk, isTrue);
        expect(msg.topTagShareOk, isTrue);
      });

      test('overallHealthy: false when any signal red', () {
        // violationRate above 5% — the most critical signal.
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': 30, 'hasData': true,
          'submitted': 10, 'promotedViaThreshold': 4, 'promotedViaBypass': 0,
          'pending': 4, 'duplicate': 1, 'tooSoon': 1,
          'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 2,
          'promotionRate': 0.4, 'bypassRate': 0.0, 'violationRate': 0.2,
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.overallHealthy, isFalse);
        expect(msg.violationRateOk, isFalse);
        // The other two are still ok — make sure verdict is the AND of all.
        expect(msg.promotionRateOk, isTrue);
        expect(msg.bypassRateOk, isTrue);
      });

      test('promotionRate boundaries: 0.1 ok, 0.099 not ok, 0.7 ok, 0.71 not ok', () {
        ReflectionKpiMessage build(double rate) => parse({
              'type': 'reflection_kpi',
              'windowDays': null, 'hasData': true,
              'submitted': 100, 'promotedViaThreshold': 0, 'promotedViaBypass': 0,
              'pending': 0, 'duplicate': 0, 'tooSoon': 0,
              'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
              'promotionRate': rate, 'bypassRate': 0, 'violationRate': 0,
              'recentViolations': [],
            }) as ReflectionKpiMessage;
        expect(build(0.1).promotionRateOk, isTrue,
            reason: 'lower boundary 10% must be considered ok');
        expect(build(0.099).promotionRateOk, isFalse,
            reason: 'just below 10% must be flagged');
        expect(build(0.7).promotionRateOk, isTrue,
            reason: 'upper boundary 70% must be considered ok');
        expect(build(0.71).promotionRateOk, isFalse,
            reason: 'just above 70% must be flagged');
      });

      test('handles missing optional fields gracefully', () {
        // Worst-case: schema drift means some fields go missing. We must
        // never crash on a partial payload — fall back to zero.
        final msg = parse({
          'type': 'reflection_kpi',
          'hasData': true,
          // intentionally missing all numeric counters
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.submitted, 0);
        expect(msg.promotionRate, 0);
        expect(msg.windowDays, isNull);
        // C.2.6 fields also default to 0 when missing.
        expect(msg.invalidTagCount, 0);
        expect(msg.invalidTagRate, 0);
        expect(msg.tagEntropy, 0);
        expect(msg.topTagShare, 0);
      });

      // ─── C.2.6 — taxonomy drift signals ──────────────────────────────────

      test('parses C.2.6 fields from server payload', () {
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': 30, 'hasData': true,
          'submitted': 20, 'promotedViaThreshold': 5, 'promotedViaBypass': 0,
          'pending': 10, 'duplicate': 4, 'tooSoon': 1,
          'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
          'invalidTagCount': 3,
          'promotionRate': 0.25, 'bypassRate': 0.0, 'violationRate': 0.0,
          'invalidTagRate': 0.13,
          'tagEntropy': 2.4,
          'topTagShare': 0.35,
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.invalidTagCount, 3);
        expect(msg.invalidTagRate, closeTo(0.13, 1e-9));
        expect(msg.tagEntropy, closeTo(2.4, 1e-9));
        expect(msg.topTagShare, closeTo(0.35, 1e-9));
      });

      test('invalidTagRateOk: ≤ 8% green, > 8% red', () {
        ReflectionKpiMessage build(double rate) => parse({
              'type': 'reflection_kpi',
              'windowDays': null, 'hasData': true,
              'submitted': 100, 'promotedViaThreshold': 0, 'promotedViaBypass': 0,
              'pending': 0, 'duplicate': 0, 'tooSoon': 0,
              'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
              'invalidTagCount': 10,
              'promotionRate': 0.5, 'bypassRate': 0, 'violationRate': 0,
              'invalidTagRate': rate, 'tagEntropy': 3.0, 'topTagShare': 0.2,
              'recentViolations': [],
            }) as ReflectionKpiMessage;
        expect(build(0.08).invalidTagRateOk, isTrue);
        expect(build(0.081).invalidTagRateOk, isFalse);
        expect(build(0.0).invalidTagRateOk, isTrue);
      });

      test('tagEntropyOk: small samples (< 5) tolerated as ok', () {
        // Cold-start protection: a 2-candidate stream trivially has low
        // entropy. We must not flag it as drift before we have enough data.
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': 30, 'hasData': true,
          'submitted': 3, 'promotedViaThreshold': 1, 'promotedViaBypass': 0,
          'pending': 2, 'duplicate': 0, 'tooSoon': 0,
          'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
          'invalidTagCount': 0,
          'promotionRate': 0.33, 'bypassRate': 0, 'violationRate': 0,
          'invalidTagRate': 0, 'tagEntropy': 0.0, 'topTagShare': 1.0,
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.tagEntropyOk, isTrue,
            reason: 'must not flag drift before 5-sample minimum');
        expect(msg.topTagShareOk, isTrue,
            reason: 'cold-start top-share is meaningless until min sample reached');
      });

      test('tagEntropyOk: ≥ 1.5 bits green at threshold, < 1.5 red', () {
        ReflectionKpiMessage build(double h) => parse({
              'type': 'reflection_kpi',
              'windowDays': null, 'hasData': true,
              'submitted': 100, 'promotedViaThreshold': 30, 'promotedViaBypass': 0,
              'pending': 70, 'duplicate': 0, 'tooSoon': 0,
              'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
              'invalidTagCount': 0,
              'promotionRate': 0.3, 'bypassRate': 0, 'violationRate': 0,
              'invalidTagRate': 0, 'tagEntropy': h, 'topTagShare': 0.4,
              'recentViolations': [],
            }) as ReflectionKpiMessage;
        expect(build(1.5).tagEntropyOk, isTrue,
            reason: 'lower boundary 1.5 bits is the cutoff; ≥ is ok');
        expect(build(1.499).tagEntropyOk, isFalse,
            reason: 'just below cutoff must flag binning drift');
        expect(build(3.5).tagEntropyOk, isTrue);
      });

      test('topTagShareOk: ≤ 50% green, > 50% red', () {
        ReflectionKpiMessage build(double share) => parse({
              'type': 'reflection_kpi',
              'windowDays': null, 'hasData': true,
              'submitted': 100, 'promotedViaThreshold': 30, 'promotedViaBypass': 0,
              'pending': 70, 'duplicate': 0, 'tooSoon': 0,
              'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
              'invalidTagCount': 0,
              'promotionRate': 0.3, 'bypassRate': 0, 'violationRate': 0,
              'invalidTagRate': 0, 'tagEntropy': 2.0, 'topTagShare': share,
              'recentViolations': [],
            }) as ReflectionKpiMessage;
        expect(build(0.5).topTagShareOk, isTrue);
        expect(build(0.501).topTagShareOk, isFalse);
      });

      test('overallHealthy: AND of all 6 signals — entropy red flips overall', () {
        // The pre-C.2.6 overallHealthy was AND of 3 signals. Post-C.2.6
        // adds three more (invalidTagRate, tagEntropy, topTagShare).
        // Ensure entropy drift alone flips the verdict.
        final msg = parse({
          'type': 'reflection_kpi',
          'windowDays': 30, 'hasData': true,
          'submitted': 100, 'promotedViaThreshold': 30, 'promotedViaBypass': 0,
          'pending': 70, 'duplicate': 0, 'tooSoon': 0,
          'prunedStale': 0, 'decayedPruned': 0, 'constraintViolations': 0,
          'invalidTagCount': 0,
          'promotionRate': 0.3, 'bypassRate': 0, 'violationRate': 0,
          'invalidTagRate': 0, 'tagEntropy': 0.8, 'topTagShare': 0.4,
          'recentViolations': [],
        }) as ReflectionKpiMessage;
        expect(msg.promotionRateOk, isTrue);
        expect(msg.bypassRateOk, isTrue);
        expect(msg.violationRateOk, isTrue);
        expect(msg.invalidTagRateOk, isTrue);
        expect(msg.tagEntropyOk, isFalse);
        expect(msg.topTagShareOk, isTrue);
        expect(msg.overallHealthy, isFalse,
            reason: 'entropy drift alone must flip overall health');
      });
    });

    test('input_images routes to InputImagesMessage', () {
      final msg = parse({
        'type': 'input_images',
        'images': ['base64data1', 'base64data2'],
      });
      expect(msg, isA<InputImagesMessage>());
      expect((msg as InputImagesMessage).images, hasLength(2));
    });

    test('ios_deploy_status routes to IOSDeployStatusMessage', () {
      final msg = parse({
        'type': 'ios_deploy_status',
        'subtype': 'deps_result',
        'hasFlutter': true,
      });
      expect(msg, isA<IOSDeployStatusMessage>());
      final cast = msg as IOSDeployStatusMessage;
      expect(cast.subtype, 'deps_result');
      expect(cast.hasFlutter, isTrue);
    });

    test('android_deploy_status routes to AndroidDeployStatusMessage', () {
      final msg = parse({
        'type': 'android_deploy_status',
        'subtype': 'devices_list',
        'devices': [
          {'serial': 'emulator-5554', 'model': 'Pixel 6', 'state': 'device'},
        ],
      });
      expect(msg, isA<AndroidDeployStatusMessage>());
      final cast = msg as AndroidDeployStatusMessage;
      expect(cast.subtype, 'devices_list');
      expect(cast.devices!.length, 1);
      expect(cast.devices!.first.serial, 'emulator-5554');
    });

    test('screenshot_status routes to ScreenshotStatusMessage', () {
      final msg = parse({
        'type': 'screenshot_status',
        'subtype': 'ready',
        'platform': 'android',
        'url': 'http://localhost/shot.png',
      });
      expect(msg, isA<ScreenshotStatusMessage>());
      final cast = msg as ScreenshotStatusMessage;
      expect(cast.platform, 'android');
      expect(cast.url, 'http://localhost/shot.png');
    });

    test('tailscale_log routes to TailscaleLogMessage', () {
      final msg = parse({'type': 'tailscale_log', 'message': 'Starting tunnel'});
      expect(msg, isA<TailscaleLogMessage>());
      expect((msg as TailscaleLogMessage).message, 'Starting tunnel');
    });

    test('health_item_update routes to HealthItemUpdateMessage', () {
      final msg = parse({
        'type': 'health_item_update',
        'item': {'id': 'serverListening', 'status': 'ok'},
      });
      expect(msg, isA<HealthItemUpdateMessage>());
      final cast = msg as HealthItemUpdateMessage;
      expect(cast.item!.id, HealthItemId.serverListening);
      expect(cast.item!.status, HealthStatus.ok);
    });

    test('chat_history routes to ChatHistoryMessage', () {
      final msg = parse({
        'type': 'chat_history',
        'messages': [
          {
            'role': 'user',
            'text': 'Hello',
            'agentId': 'manager#1',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        ],
      });
      expect(msg, isA<ChatHistoryMessage>());
      final cast = msg as ChatHistoryMessage;
      expect(cast.messages.length, 1);
      expect(cast.messages.first.text, 'Hello');
    });

    test('game_state_sync routes to GameStateSyncMessage', () {
      final msg = parse({
        'type': 'game_state_sync',
        'fullState': '{"grymni":1000}',
        'stateUpdatedAt': 1700000000,
      });
      expect(msg, isA<GameStateSyncMessage>());
      final cast = msg as GameStateSyncMessage;
      expect(cast.fullState, '{"grymni":1000}');
      expect(cast.stateUpdatedAt, 1700000000);
    });

    test('task_dispatched routes to TaskDispatchedMessage', () {
      final msg = parse({
        'type': 'task_dispatched',
        'dispatchId': 'disp-1',
        'agentId': 'coder#1',
        'task': 'Fix the bug',
        'priority': 'high',
      });
      expect(msg, isA<TaskDispatchedMessage>());
      final cast = msg as TaskDispatchedMessage;
      expect(cast.task, 'Fix the bug');
      expect(cast.priority, 'high');
    });

    test('subagent_result routes to SubagentResultMessage', () {
      final msg = parse({
        'type': 'subagent_result',
        'dispatchId': 'disp-1',
        'agentId': 'coder#1',
        'result': 'Bug fixed.',
        'costUsd': 0.02,
        'durationMs': 5000,
      });
      expect(msg, isA<SubagentResultMessage>());
      final cast = msg as SubagentResultMessage;
      expect(cast.result, 'Bug fixed.');
      expect(cast.costUsd, 0.02);
    });

    test('task_too_hard routes to TaskTooHardMessage', () {
      final msg = parse({
        'type': 'task_too_hard',
        'agentId': 'coder#1',
        'required': 3.5,
        'current': 2.0,
      });
      expect(msg, isA<TaskTooHardMessage>());
      final cast = msg as TaskTooHardMessage;
      expect(cast.required, 3.5);
      expect(cast.current, 2.0);
    });

    test('dungeon_started routes to DungeonStartedMessage', () {
      final msg = parse({
        'type': 'dungeon_started',
        'agentId': 'coder#1',
        'skillType': 1,
        'difficulty': 3,
        'challenge': 'Implement BFS',
      });
      expect(msg, isA<DungeonStartedMessage>());
      final cast = msg as DungeonStartedMessage;
      expect(cast.difficulty, 3);
      expect(cast.challenge, 'Implement BFS');
    });

    test('facilitator_error routes to FacilitatorErrorMessage', () {
      final msg = parse({
        'type': 'facilitator_error',
        'error': 'LLM timeout',
      });
      expect(msg, isA<FacilitatorErrorMessage>());
      expect((msg as FacilitatorErrorMessage).error, 'LLM timeout');
    });

    test('facilitator_seeded routes to FacilitatorSeededMessage', () {
      final msg = parse({
        'type': 'facilitator_seeded',
        'styleId': 'quest_line',
        'outputFormat': 'quest_line',
        'outputJson': '{}',
        'finalScore': {
          'entityCount': 2,
          'interactionSurface': 1,
          'auth': 0,
          'integrations': 0,
          'realtime': 0,
        },
      });
      expect(msg, isA<FacilitatorSeededMessage>());
      final cast = msg as FacilitatorSeededMessage;
      expect(cast.styleId, 'quest_line');
      expect(cast.finalScore.entityCount, 2);
    });

    test('facilitator_output_sync routes to FacilitatorOutputSyncMessage', () {
      final msg = parse({
        'type': 'facilitator_output_sync',
        'styleId': 'sprint_backlog',
        'outputFormat': 'sprint_backlog',
        'outputJson': '{}',
        'finalScore': {
          'entityCount': 1,
          'interactionSurface': 0,
          'auth': 0,
          'integrations': 0,
          'realtime': 0,
        },
      });
      expect(msg, isA<FacilitatorOutputSyncMessage>());
      expect((msg as FacilitatorOutputSyncMessage).styleId, 'sprint_backlog');
    });

    test('facilitator_output_sync handles missing finalScore gracefully', () {
      final msg = parse({
        'type': 'facilitator_output_sync',
        'styleId': 'x',
        'outputFormat': 'quest_line',
        'outputJson': '{}',
        // finalScore intentionally omitted
      });
      expect(msg, isA<FacilitatorOutputSyncMessage>());
      final cast = msg as FacilitatorOutputSyncMessage;
      expect(cast.finalScore.total, 0); // ScopeScore.empty()
    });
  });

  // ─── AndroidDevice ────────────────────────────────────────────────────────

  group('AndroidDevice', () {
    test('isReady true when state==device', () {
      final d = AndroidDevice.fromJson(
          {'serial': 's1', 'model': 'Pixel', 'state': 'device'});
      expect(d.isReady, isTrue);
    });

    test('isReady false when state==unauthorized', () {
      final d = AndroidDevice.fromJson(
          {'serial': 's2', 'model': 'Pixel', 'state': 'unauthorized'});
      expect(d.isReady, isFalse);
    });

    test('defaults when fields missing', () {
      final d = AndroidDevice.fromJson({});
      expect(d.serial, isEmpty);
      expect(d.model, isEmpty);
      expect(d.state, 'unknown');
    });
  });

  // ─── RunningAgentInfo.fromJson ────────────────────────────────────────────

  group('RunningAgentInfo.fromJson', () {
    test('parses all fields', () {
      final r = RunningAgentInfo.fromJson({
        'dispatchId': 'disp-99',
        'agentId': 'tester#1',
        'task': 'Run tests',
        'elapsedMs': 1500,
      });
      expect(r.dispatchId, 'disp-99');
      expect(r.agentId, 'tester#1');
      expect(r.task, 'Run tests');
      expect(r.elapsedMs, 1500);
    });

    test('defaults when fields missing', () {
      final r = RunningAgentInfo.fromJson({});
      expect(r.dispatchId, isEmpty);
      expect(r.elapsedMs, 0);
    });
  });

  // ─── QueueStatusMessage with running agents ───────────────────────────────

  group('QueueStatusMessage.running', () {
    test('parses running agents list', () {
      final msg = ServerMessage.fromJson(jsonEncode({
        'type': 'queue_status',
        'pending': 2,
        'running': [
          {
            'dispatchId': 'disp-1',
            'agentId': 'coder#1',
            'task': 'Implement',
            'elapsedMs': 3000,
          },
        ],
      })) as QueueStatusMessage;
      expect(msg.pending, 2);
      expect(msg.running.length, 1);
      expect(msg.running.first.agentId, 'coder#1');
    });

    test('empty running list when not provided', () {
      final msg = ServerMessage.fromJson(
              jsonEncode({'type': 'queue_status', 'pending': 0}))
          as QueueStatusMessage;
      expect(msg.running, isEmpty);
    });
  });

  // ─── AgentMetrics defaults ────────────────────────────────────────────────

  group('AgentMetrics.fromJson', () {
    test('defaults to zero when fields missing', () {
      final m = AgentMetrics.fromJson({});
      expect(m.tasksAssigned, 0);
      expect(m.tasksCompleted, 0);
      expect(m.reworkCount, 0);
    });
  });

  // ─── ToolActivity.fromJson ─────────────────────────────────────────────────

  group('ToolActivity.fromJson', () {
    test('parses all fields', () {
      final ta = ToolActivity.fromJson({
        'toolUseId': 'tu-99',
        'toolName': 'Read',
        'status': 'done',
      });
      expect(ta.toolUseId, 'tu-99');
      expect(ta.toolName, 'Read');
      expect(ta.status, 'done');
    });

    test('agent_status with non-empty tools calls ToolActivity.fromJson', () {
      final msg = ServerMessage.fromJson(jsonEncode({
        'type': 'agent_status',
        'agentId': 'coder#1',
        'status': 'running',
        'tools': [
          {'toolUseId': 'tu-1', 'toolName': 'Bash', 'status': 'running'},
        ],
      })) as AgentStatusMessage;
      expect(msg.tools.length, 1);
      expect(msg.tools.first.toolName, 'Bash');
    });
  });

  // ─── Null-fallback branches in fromJson ───────────────────────────────────

  group('null-fallback branches', () {
    ServerMessage parse(Map<String, dynamic> json) =>
        ServerMessage.fromJson(jsonEncode(json));

    test('board_state without tasks key uses empty fallback', () {
      final msg = parse({'type': 'board_state'}) as BoardStateMessage;
      expect(msg.boardState.tasks, isEmpty);
    });

    test('agent_traits without traits key uses empty fallback', () {
      final msg = parse({'type': 'agent_traits'}) as AgentTraitsMessage;
      expect(msg.traits, isEmpty);
    });
  });

  // ─── HealthItem.copyWith — all fields ─────────────────────────────────────

  group('HealthItem.copyWith — all fields', () {
    test('changes detail', () {
      var item = HealthItem(id: HealthItemId.funnelActive, status: HealthStatus.ok);
      item = item.copyWith(detail: 'Tunnel on 443');
      expect(item.detail, 'Tunnel on 443');
    });

    test('changes fixable', () {
      var item = HealthItem(id: HealthItemId.androidSdk, status: HealthStatus.fail);
      item = item.copyWith(fixable: true);
      expect(item.fixable, isTrue);
    });

    test('changes instruction', () {
      var item = HealthItem(id: HealthItemId.xcodeTools, status: HealthStatus.fail);
      item = item.copyWith(instruction: 'Run xcode-select --install');
      expect(item.instruction, 'Run xcode-select --install');
    });

    test('preserves id through all changes', () {
      var item = HealthItem(id: HealthItemId.mdnsActive, status: HealthStatus.checking);
      item = item.copyWith(status: HealthStatus.ok, detail: 'ok', fixable: false);
      expect(item.id, HealthItemId.mdnsActive);
    });
  });

  // ─── C.2.5 — SubagentFailedMessage ────────────────────────────────────────
  //
  // The server emits this discriminated event alongside the generic `error`
  // toast so the client can clear stale tool-progress state and choose UX
  // per failure reason (timeout → retry-friendly, breaker → cost-budget
  // warning, error → generic). Drift in reason parsing would silently
  // collapse the discriminator back to generic `error`.

  group('SubagentFailedMessage', () {
    test('parses timeout reason', () {
      final raw = {
        'type': 'subagent_failed',
        'dispatchId': 'dispatch_42_1700000000',
        'agentId': 'character-artist#1',
        'reason': 'timeout',
        'message': 'Sub-agent character-artist#1 hard timeout (180s)',
      };
      final msg = ServerMessage.fromJson(jsonEncode(raw)) as SubagentFailedMessage;
      expect(msg.reason, SubagentFailureReason.timeout);
      expect(msg.dispatchId, 'dispatch_42_1700000000');
      expect(msg.agentId, 'character-artist#1');
      expect(msg.message, contains('hard timeout'));
    });

    test('parses breaker reason', () {
      final raw = {
        'type': 'subagent_failed',
        'dispatchId': 'd1',
        'agentId': 'coder#1',
        'reason': 'breaker',
        'message': 'circuit breaker tripped: \$5 cap',
      };
      final msg = ServerMessage.fromJson(jsonEncode(raw)) as SubagentFailedMessage;
      expect(msg.reason, SubagentFailureReason.breaker);
    });

    test('parses generic error reason', () {
      final raw = {
        'type': 'subagent_failed',
        'dispatchId': 'd1',
        'agentId': 'coder#1',
        'reason': 'error',
        'message': 'ECONNRESET',
      };
      final msg = ServerMessage.fromJson(jsonEncode(raw)) as SubagentFailedMessage;
      expect(msg.reason, SubagentFailureReason.error);
    });

    test('unknown reason string falls back to error (safe default)', () {
      // If server adds a new reason variant before the client knows about
      // it, the client must NOT crash — it should degrade to generic.
      final raw = {
        'type': 'subagent_failed',
        'dispatchId': 'd1',
        'agentId': 'coder#1',
        'reason': 'wat',
        'message': '',
      };
      final msg = ServerMessage.fromJson(jsonEncode(raw)) as SubagentFailedMessage;
      expect(msg.reason, SubagentFailureReason.error);
    });
  });
}
