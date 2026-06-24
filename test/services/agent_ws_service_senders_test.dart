/// Integration coverage for the public sender methods on `AgentWsService`.
///
/// These tests close the coverage hole left by the one-line forwarders — the
/// builders are tested separately in `agent_ws_messages_test.dart`; this file
/// verifies the public sender methods actually route to `_send` (i.e. the
/// resulting frame really lands on the wire with the expected `type`).
///
/// Strategy: spin up a real loopback `HttpServer` + `WebSocketTransformer`,
/// connect a live `AgentWsService` to it, capture every frame the server
/// receives, drop the auto-handshake (`client_info` + `get_traits`) and then
/// assert the wire-type of each subsequent frame produced by calling the
/// matching public method on the service.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/services/agent_ws_service.dart';

/// Boots a loopback WebSocket server and returns its URL + a stream of
/// upgraded sockets, mirroring the harness in
/// `agent_ws_service_connect_test.dart`.
Future<({HttpServer server, String url, Stream<WebSocket> sockets})>
    _startServer() async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  final socketController = StreamController<WebSocket>.broadcast();
  server.listen((HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final ws = await WebSocketTransformer.upgrade(request);
      socketController.add(ws);
    } else {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  });
  return (
    server: server,
    url: 'ws://127.0.0.1:${server.port}/',
    sockets: socketController.stream,
  );
}

/// Per-group harness: live service connected to a loopback server, with a
/// `frames` list capturing every JSON-decoded payload the server received
/// AFTER the auto-handshake (client_info + get_traits) has been observed.
class _Harness {
  _Harness._(this.svc, this.frames, this._handshakeDone);

  final AgentWsService svc;
  final List<Map<String, dynamic>> frames;
  final Future<void> _handshakeDone;

  /// Wait until the next frame whose `type` equals [type] arrives. Returns
  /// the decoded payload. Times out at 3s.
  Future<Map<String, dynamic>> waitFor(String type) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final match = frames.where((f) => f['type'] == type).toList();
      if (match.isNotEmpty) return match.last;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw TimeoutException('No frame of type "$type" arrived',
        const Duration(seconds: 3));
  }

  /// Snapshot the wire-types of all frames captured so far, in order.
  List<String> get types =>
      frames.map((f) => f['type'] as String).toList(growable: false);

  Future<void> waitHandshake() => _handshakeDone;
}

Future<_Harness> _bootHarness() async {
  final s = await _startServer();
  addTearDown(() async => s.server.close(force: true));
  final svc = AgentWsService();
  addTearDown(svc.dispose);

  final frames = <Map<String, dynamic>>[];
  final handshakeCompleter = Completer<void>();
  var seen = 0;
  s.sockets.listen((ws) {
    ws.listen((data) {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      seen++;
      // Drop the first three auto-handshake frames:
      //   1. client_info  2. set_bypass_permissions  3. get_traits
      if (seen <= 3) {
        if (seen == 3 && !handshakeCompleter.isCompleted) {
          handshakeCompleter.complete();
        }
        return;
      }
      frames.add(map);
    });
  });

  await svc.connect(url: s.url).timeout(const Duration(seconds: 3));
  await handshakeCompleter.future.timeout(const Duration(seconds: 3));
  return _Harness._(svc, frames, handshakeCompleter.future);
}

void main() {
  group('chat senders', () {
    test('sendMessage / newChat / clearSessions / interrupt / getStatus '
        'each route to _send with the expected wire type', () async {
      final h = await _bootHarness();

      h.svc.sendMessage('hi');
      h.svc.newChat();
      h.svc.clearSessions();
      h.svc.interrupt();
      h.svc.getStatus();

      await h.waitFor('get_status');
      expect(
        h.types,
        ['send_message', 'new_chat', 'clear_sessions', 'interrupt',
         'get_status'],
      );
    });

    test('sendMessage stamps projectPath once a project is selected', () async {
      final h = await _bootHarness();

      h.svc.sendMessage('before selection');
      h.svc.projectPath = '/projects/demo';
      h.svc.sendMessage('after selection');
      h.svc.getStatus(); // fence — guarantees both frames have landed

      await h.waitFor('get_status');
      final sent = h.frames
          .where((f) => f['type'] == 'send_message')
          .toList(growable: false);
      expect(sent, hasLength(2));
      expect(sent[0].containsKey('projectPath'), isFalse,
          reason: 'no project known yet → field omitted (legacy behaviour)');
      expect(sent[1]['projectPath'], '/projects/demo');
    });

    test('setProject records the path for subsequent sendMessage frames',
        () async {
      final h = await _bootHarness();

      h.svc.setProject('/projects/worktree-a');
      h.svc.sendMessage('hello');
      h.svc.getStatus(); // fence

      await h.waitFor('get_status');
      final setFrame = h.frames.firstWhere((f) => f['type'] == 'set_project');
      expect(setFrame['path'], '/projects/worktree-a');
      final sendFrame =
          h.frames.firstWhere((f) => f['type'] == 'send_message');
      expect(sendFrame['projectPath'], '/projects/worktree-a');
    });
  });

  group('board senders', () {
    test('all eight board.* methods route to _send', () async {
      final h = await _bootHarness();

      h.svc.boardGetState();
      h.svc.boardCreateTask(title: 'T');
      h.svc.boardMoveTask(taskId: 't1', column: 'todo');
      h.svc.boardUpdateTask(taskId: 't1', updates: const {'title': 'x'});
      h.svc.boardDeleteTask(taskId: 't1');
      h.svc.boardAssignAgent(taskId: 't1', agentId: 'a', assign: true);
      h.svc.boardAddAttachment(
        taskId: 't1',
        name: 'a.png',
        mimeType: 'image/png',
        sizeBytes: 4,
        dataBase64: 'AAAA',
      );
      h.svc.boardRemoveAttachment(taskId: 't1', attachmentId: 'a1');

      await h.waitFor('board_remove_attachment');
      expect(h.types, [
        'board_get_state',
        'board_create_task',
        'board_move_task',
        'board_update_task',
        'board_delete_task',
        'board_assign_agent',
        'board_add_attachment',
        'board_remove_attachment',
      ]);
    });
  });

  group('project senders', () {
    test('setProject / setProjectContext / generateSummary route to _send',
        () async {
      final h = await _bootHarness();

      h.svc.setProject('/tmp/proj');
      h.svc.setProjectContext('memories');
      h.svc.generateSummary();

      await h.waitFor('generate_summary');
      expect(h.types,
          ['set_project', 'set_project_context', 'generate_summary']);
    });
  });

  group('game senders', () {
    test('setGameState routes to _send (and preserves null keys)', () async {
      final h = await _bootHarness();

      h.svc.setGameState(instances: const {});

      final frame = await h.waitFor('set_game_state');
      expect(frame['type'], 'set_game_state');
      // Builder contract: nullable keys are kept present with null values.
      expect(frame.containsKey('fullState'), isTrue);
      expect(frame['fullState'], isNull);
      expect(frame.containsKey('stateUpdatedAt'), isTrue);
      expect(frame['stateUpdatedAt'], isNull);
      expect(frame.containsKey('accountId'), isTrue);
      expect(frame['accountId'], isNull);
      expect(frame.containsKey('deepseekApiKey'), isTrue);
      expect(frame['deepseekApiKey'], isNull);
      expect(frame.containsKey('kimiApiKey'), isTrue);
      expect(frame['kimiApiKey'], isNull);
      expect(h.types, ['set_game_state']);
    });

    test('setGameState forwards a provided accountId', () async {
      final h = await _bootHarness();

      h.svc.setGameState(instances: const {}, accountId: 'local');

      final frame = await h.waitFor('set_game_state');
      expect(frame['accountId'], 'local');
    });
  });

  group('account senders', () {
    test('setAccount routes to _send with the account id', () async {
      final h = await _bootHarness();

      h.svc.setAccount('local');

      final frame = await h.waitFor('set_account');
      expect(frame['type'], 'set_account');
      expect(frame['accountId'], 'local');
      expect(h.types, ['set_account']);
    });
  });

  group('session senders', () {
    test('claimSession / releaseSession route to _send', () async {
      final h = await _bootHarness();

      h.svc.claimSession();
      h.svc.releaseSession();

      await h.waitFor('session_release');
      expect(h.types, ['session_claim', 'session_release']);
    });
  });

  group('traits senders', () {
    test('getTraits / recordLesson / removeLesson route to _send', () async {
      final h = await _bootHarness();

      h.svc.getTraits();
      h.svc.recordLesson(
        agentId: 'a',
        lessonType: 'success',
        category: 'general',
        tag: 't',
        lesson: 'L',
      );
      h.svc.removeLesson('lesson-1');

      await h.waitFor('remove_lesson');
      // The auto-handshake `get_traits` was dropped by the harness, so the
      // explicit getTraits() call surfaces here as the first frame.
      expect(h.types, ['get_traits', 'record_lesson', 'remove_lesson']);
    });
  });

  group('dungeon senders', () {
    test('startDungeon routes to _send', () async {
      final h = await _bootHarness();

      h.svc.startDungeon(agentId: 'a', skillType: 0, difficulty: 5);

      await h.waitFor('start_dungeon');
      expect(h.types, ['start_dungeon']);
    });
  });

  group('facilitator senders', () {
    final style = FacilitatorStyle(
      id: 'x',
      displayName: '',
      tagline: '',
      laloux: Laloux.red,
      personaPrompt: '',
      outputMapper: OutputFormat.questLine,
      toneModifiers: const ToneModifiers(
        aggression: 0.0,
        formality: 0.0,
        verbosity: 0.0,
      ),
    );

    test('sendFacilitatorStart / sendGetFacilitatorOutput / '
        'sendPushFacilitatorOutput route to _send', () async {
      final h = await _bootHarness();

      h.svc.sendFacilitatorStart(
        style: style,
        projectDescription: 'desc',
        answers: const {'k': 'v'},
      );
      h.svc.sendGetFacilitatorOutput();
      h.svc.sendPushFacilitatorOutput(
        outputFormat: 'quest_line',
        outputJson: '{}',
      );

      await h.waitFor('push_facilitator_output');
      expect(h.types, [
        'facilitator_start',
        'get_facilitator_output',
        'push_facilitator_output',
      ]);
    });
  });

  group('sync senders', () {
    test('syncPositions / sendInputText / sendInputImages route to _send',
        () async {
      final h = await _bootHarness();

      h.svc.syncPositions(const {
        'a': {'x': 1.0},
      });
      h.svc.sendInputText('typing…');
      h.svc.sendInputImages(const ['img1']);

      await h.waitFor('input_images');
      expect(h.types, ['sync_positions', 'input_text', 'input_images']);
    });
  });

  group('ios deploy senders', () {
    test('iosDeployCheck / iosDeployStart / iosDeployCancel route to _send',
        () async {
      final h = await _bootHarness();

      h.svc.iosDeployCheck();
      h.svc.iosDeployStart();
      h.svc.iosDeployCancel();

      await h.waitFor('ios_deploy_cancel');
      expect(h.types,
          ['ios_deploy_check', 'ios_deploy_start', 'ios_deploy_cancel']);
    });
  });

  group('android deploy senders', () {
    test('all five android deploy methods route to _send '
        '(covers both branches of androidDeployStart)', () async {
      final h = await _bootHarness();

      h.svc.androidDeployCheck();
      h.svc.androidDeployListDevices();
      h.svc.androidDeployStart(); // no deviceSerial
      h.svc.androidDeployStart(deviceSerial: 'pixel-7'); // with deviceSerial
      h.svc.androidDeployCancel();

      await h.waitFor('android_deploy_cancel');
      expect(h.types, [
        'android_deploy_check',
        'android_deploy_list_devices',
        'android_deploy_start',
        'android_deploy_start',
        'android_deploy_cancel',
      ]);
    });
  });

  group('screenshot senders', () {
    test('captureScreenshot routes to _send for both branches', () async {
      final h = await _bootHarness();

      h.svc.captureScreenshot(platform: 'ios'); // no deviceSerial
      h.svc.captureScreenshot(
        platform: 'android',
        deviceSerial: 'pixel-7',
      ); // with deviceSerial

      await h.waitFor('screenshot_capture');
      expect(h.types, ['screenshot_capture', 'screenshot_capture']);
    });
  });

  group('tailscale senders', () {
    test('tailscaleConnect routes to _send', () async {
      final h = await _bootHarness();

      h.svc.tailscaleConnect();

      await h.waitFor('tailscale_connect');
      expect(h.types, ['tailscale_connect']);
    });
  });

  group('health senders', () {
    test('healthCheckRequest / healthFixRequest route to _send', () async {
      final h = await _bootHarness();

      h.svc.healthCheckRequest();
      h.svc.healthFixRequest('dns');

      await h.waitFor('health_fix_request');
      expect(h.types, ['health_check_request', 'health_fix_request']);
    });
  });

  group('permissions senders', () {
    test('setBypassPermissions routes to _send', () async {
      final h = await _bootHarness();

      h.svc.setBypassPermissions(true);

      await h.waitFor('set_bypass_permissions');
      expect(h.types, ['set_bypass_permissions']);
    });
  });
}
