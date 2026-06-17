/// Unit tests for every pure builder in `lib/services/agent_ws_messages.dart`.
///
/// These guard the wire shape — a typo in the `'type'` discriminator or an
/// accidental field rename would break the server contract silently.
///
/// Conventions covered:
/// - Optional params are OMITTED when null (`?` spread semantics).
/// - `setGameState` is the deliberate exception: nullable keys are kept
///   present with null values (the server reads them as "not changed").
/// - Numeric clamps live in builders (e.g. `startDungeon` 1..3).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/facilitator_output.dart';
import 'package:pixelcode/models/facilitator_style.dart';
import 'package:pixelcode/services/agent_ws_messages.dart';

void main() {
  group('chat', () {
    test('buildSendMessage — minimal payload', () {
      expect(buildSendMessage('hi'), {
        'type': 'send_message',
        'content': 'hi',
        'agentId': 'manager',
      });
    });

    test('buildSendMessage — custom agent + images', () {
      expect(buildSendMessage('hi', agentId: 'coder', images: ['a', 'b']), {
        'type': 'send_message',
        'content': 'hi',
        'agentId': 'coder',
        'images': ['a', 'b'],
      });
    });

    test('buildSendMessage — empty images list is omitted', () {
      final m = buildSendMessage('hi', images: const []);
      expect(m.containsKey('images'), isFalse);
    });

    test('buildSendMessage — null images is omitted', () {
      final m = buildSendMessage('hi', images: null);
      expect(m.containsKey('images'), isFalse);
    });

    test('buildSendMessage — localId and projectPath are included when set', () {
      expect(
        buildSendMessage('hi', localId: 'abc123', projectPath: '/projects/demo'),
        {
          'type': 'send_message',
          'content': 'hi',
          'agentId': 'manager',
          'localId': 'abc123',
          'projectPath': '/projects/demo',
        },
      );
    });

    test('buildSendMessage — null localId and projectPath are omitted', () {
      final m = buildSendMessage('hi');
      expect(m.containsKey('localId'), isFalse);
      expect(m.containsKey('projectPath'), isFalse);
    });

    test('singletons (newChat / clearSessions / interrupt / getStatus)', () {
      expect(buildNewChat(), {'type': 'new_chat'});
      expect(buildClearSessions(), {'type': 'clear_sessions'});
      expect(buildInterrupt(), {'type': 'interrupt'});
      expect(buildGetStatus(), {'type': 'get_status'});
    });
  });

  group('task board', () {
    test('buildBoardGetState', () {
      expect(buildBoardGetState(), {'type': 'board_get_state'});
    });

    test('buildBoardCreateTask — title-only minimal', () {
      final m = buildBoardCreateTask(title: 'X');
      expect(m, {'type': 'board_create_task', 'title': 'X'});
      // All optional keys absent
      for (final k in [
        'description',
        'color',
        'priority',
        'difficulty',
        'allowedRoles',
        'taskType',
      ]) {
        expect(m.containsKey(k), isFalse, reason: 'expected $k absent');
      }
    });

    test('buildBoardCreateTask — full payload preserves every field', () {
      final m = buildBoardCreateTask(
        title: 'Refactor router',
        description: 'split into modules',
        color: '#abcdef',
        priority: 'high',
        difficulty: 4,
        allowedRoles: const ['coder', 'reviewer'],
        taskType: 'refactor',
      );
      expect(m, {
        'type': 'board_create_task',
        'title': 'Refactor router',
        'description': 'split into modules',
        'color': '#abcdef',
        'priority': 'high',
        'difficulty': 4,
        'allowedRoles': ['coder', 'reviewer'],
        'taskType': 'refactor',
      });
    });

    test('buildBoardMoveTask', () {
      expect(buildBoardMoveTask(taskId: 't1', column: 'doing'), {
        'type': 'board_move_task',
        'taskId': 't1',
        'column': 'doing',
      });
    });

    test('buildBoardUpdateTask passes through the updates map verbatim', () {
      final updates = {'title': 'new', 'difficulty': 2};
      expect(buildBoardUpdateTask(taskId: 't1', updates: updates), {
        'type': 'board_update_task',
        'taskId': 't1',
        'updates': updates,
      });
    });

    test('buildBoardDeleteTask', () {
      expect(buildBoardDeleteTask(taskId: 't9'), {
        'type': 'board_delete_task',
        'taskId': 't9',
      });
    });

    test('buildBoardAssignAgent — assign=true and assign=false both carried', () {
      expect(
        buildBoardAssignAgent(taskId: 't1', agentId: 'coder#1', assign: true),
        {
          'type': 'board_assign_agent',
          'taskId': 't1',
          'agentId': 'coder#1',
          'assign': true,
        },
      );
      expect(
        buildBoardAssignAgent(taskId: 't1', agentId: 'coder#1', assign: false)
            ['assign'],
        false,
      );
    });

    test('buildBoardAddAttachment', () {
      expect(
        buildBoardAddAttachment(
          taskId: 't1',
          name: 'spec.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 1024,
          dataBase64: 'AAA=',
        ),
        {
          'type': 'board_add_attachment',
          'taskId': 't1',
          'name': 'spec.pdf',
          'mimeType': 'application/pdf',
          'sizeBytes': 1024,
          'dataBase64': 'AAA=',
        },
      );
    });

    test('buildBoardRemoveAttachment', () {
      expect(buildBoardRemoveAttachment(taskId: 't1', attachmentId: 'a1'), {
        'type': 'board_remove_attachment',
        'taskId': 't1',
        'attachmentId': 'a1',
      });
    });
  });

  group('project management', () {
    test('buildSetProject', () {
      expect(buildSetProject('/work/repo'),
          {'type': 'set_project', 'path': '/work/repo'});
    });

    test('buildSetProjectContext', () {
      expect(buildSetProjectContext('memories blob'),
          {'type': 'set_project_context', 'memories': 'memories blob'});
    });

    test('buildGenerateSummary', () {
      expect(buildGenerateSummary(), {'type': 'generate_summary'});
    });
  });

  group('game economy', () {
    test('buildSetGameState — null fields are kept as null (server contract)',
        () {
      final m = buildSetGameState(instances: {});
      // Crucially: nullable keys MUST be present, value MUST be null.
      expect(m['type'], 'set_game_state');
      expect(m['instances'], <String, Map<String, dynamic>>{});
      for (final k in [
        'fullState',
        'stateUpdatedAt',
        'deepseekApiKey',
        'kimiApiKey',
      ]) {
        expect(m.containsKey(k), isTrue, reason: '$k must be present');
        expect(m[k], isNull);
      }
    });

    test('buildSetGameState — full payload', () {
      final m = buildSetGameState(
        instances: {
          'coder#1': {'roleType': 'coder', 'tier': 0},
        },
        fullState: '{}',
        stateUpdatedAt: 12345,
        deepseekApiKey: 'sk-ds',
        kimiApiKey: 'sk-km',
      );
      expect(m['instances']['coder#1']['roleType'], 'coder');
      expect(m['fullState'], '{}');
      expect(m['stateUpdatedAt'], 12345);
      expect(m['deepseekApiKey'], 'sk-ds');
      expect(m['kimiApiKey'], 'sk-km');
    });
  });

  group('session presence', () {
    test('claim + release', () {
      expect(buildClaimSession(), {'type': 'session_claim'});
      expect(buildReleaseSession(), {'type': 'session_release'});
    });
  });

  group('agent traits & lessons', () {
    test('buildGetTraits', () {
      expect(buildGetTraits(), {'type': 'get_traits'});
    });

    test('buildRecordLesson — every field threaded through', () {
      expect(
        buildRecordLesson(
          agentId: 'coder#1',
          lessonType: 'success',
          category: 'arch',
          tag: 'router',
          lesson: 'split before adding the 4th param',
        ),
        {
          'type': 'record_lesson',
          'agentId': 'coder#1',
          'lessonType': 'success',
          'category': 'arch',
          'tag': 'router',
          'lesson': 'split before adding the 4th param',
        },
      );
    });

    test('buildRemoveLesson', () {
      expect(buildRemoveLesson('lsn-42'),
          {'type': 'remove_lesson', 'lessonId': 'lsn-42'});
    });
  });

  group('dungeon — difficulty clamp', () {
    test('positive: in-range values pass through', () {
      for (final d in [1, 2, 3]) {
        expect(
          buildStartDungeon(agentId: 'a', skillType: 0, difficulty: d)
              ['difficulty'],
          d,
        );
      }
    });

    test('negative: below 1 clamps to 1', () {
      expect(
        buildStartDungeon(agentId: 'a', skillType: 0, difficulty: 0)
            ['difficulty'],
        1,
      );
      expect(
        buildStartDungeon(agentId: 'a', skillType: 0, difficulty: -99)
            ['difficulty'],
        1,
      );
    });

    test('negative: above 3 clamps to 3', () {
      expect(
        buildStartDungeon(agentId: 'a', skillType: 0, difficulty: 4)
            ['difficulty'],
        3,
      );
      expect(
        buildStartDungeon(agentId: 'a', skillType: 0, difficulty: 999)
            ['difficulty'],
        3,
      );
    });

    test('full message shape', () {
      expect(
        buildStartDungeon(agentId: 'coder#1', skillType: 2, difficulty: 2),
        {
          'type': 'start_dungeon',
          'agentId': 'coder#1',
          'skillType': 2,
          'difficulty': 2,
        },
      );
    });
  });

  group('facilitator system', () {
    final style = FacilitatorStyle(
      id: 'game_master',
      displayName: 'Game Master',
      tagline: 'Quest-driven',
      laloux: Laloux.green,
      personaPrompt: 'lead like a DM',
      lexicon: const {'task': 'mission'},
      outputMapper: OutputFormat.questLine,
      toneModifiers: const ToneModifiers(
        aggression: 0.2,
        formality: 0.4,
        verbosity: 0.6,
      ),
    );

    test('buildFacilitatorStart — style is JSON-encoded into the payload', () {
      final m = buildFacilitatorStart(
        style: style,
        projectDescription: 'tower defence game',
        answers: const {'tone': 'fun'},
      );
      expect(m['type'], 'facilitator_start');
      expect(m['projectDescription'], 'tower defence game');
      expect(m['answers'], {'tone': 'fun'});
      // Style is serialised — sanity-check the inner shape rather than
      // duplicating the entire fromJson contract.
      final s = m['style'] as Map<String, dynamic>;
      expect(s['id'], 'game_master');
      expect(s['laloux'], 'green');
      expect(s['toneModifiers'], isA<Map>());
    });

    test('buildGetFacilitatorOutput', () {
      expect(buildGetFacilitatorOutput(), {'type': 'get_facilitator_output'});
    });

    test('buildPushFacilitatorOutput', () {
      expect(
        buildPushFacilitatorOutput(
          outputFormat: 'quest_line',
          outputJson: '{"quests":[]}',
        ),
        {
          'type': 'push_facilitator_output',
          'outputFormat': 'quest_line',
          'outputJson': '{"quests":[]}',
        },
      );
    });
  });

  group('position + input sync', () {
    test('buildSyncPositions passes the map verbatim', () {
      final p = {
        'coder#1': {'x': 1.0, 'y': 2.0},
      };
      expect(buildSyncPositions(p),
          {'type': 'sync_positions', 'positions': p});
    });

    test('buildInputText', () {
      expect(buildInputText('hello'),
          {'type': 'input_text', 'text': 'hello'});
    });

    test('buildInputImages — empty list still sent (caller decides intent)',
        () {
      expect(buildInputImages(const []),
          {'type': 'input_images', 'images': []});
    });

    test('buildInputImages — populated list', () {
      expect(buildInputImages(const ['a', 'b']),
          {'type': 'input_images', 'images': ['a', 'b']});
    });
  });

  group('iOS deploy', () {
    test('all three are static type-only messages', () {
      expect(buildIosDeployCheck(), {'type': 'ios_deploy_check'});
      expect(buildIosDeployStart(), {'type': 'ios_deploy_start'});
      expect(buildIosDeployCancel(), {'type': 'ios_deploy_cancel'});
    });
  });

  group('Android deploy', () {
    test('static checks', () {
      expect(buildAndroidDeployCheck(), {'type': 'android_deploy_check'});
      expect(buildAndroidDeployListDevices(),
          {'type': 'android_deploy_list_devices'});
      expect(buildAndroidDeployCancel(), {'type': 'android_deploy_cancel'});
    });

    test('buildAndroidDeployStart — no serial omits the key', () {
      final m = buildAndroidDeployStart();
      expect(m, {'type': 'android_deploy_start'});
      expect(m.containsKey('deviceSerial'), isFalse);
    });

    test('buildAndroidDeployStart — with serial includes it', () {
      expect(buildAndroidDeployStart(deviceSerial: 'emulator-5554'), {
        'type': 'android_deploy_start',
        'deviceSerial': 'emulator-5554',
      });
    });
  });

  group('screenshot', () {
    test('without serial — key omitted', () {
      final m = buildCaptureScreenshot(platform: 'ios');
      expect(m, {'type': 'screenshot_capture', 'platform': 'ios'});
      expect(m.containsKey('deviceSerial'), isFalse);
    });

    test('with serial — key present', () {
      expect(
        buildCaptureScreenshot(platform: 'android', deviceSerial: 'ABC123'),
        {
          'type': 'screenshot_capture',
          'platform': 'android',
          'deviceSerial': 'ABC123',
        },
      );
    });
  });

  group('misc singletons', () {
    test('tailscale + health + permissions + traits all carry stable types',
        () {
      expect(buildTailscaleConnect(), {'type': 'tailscale_connect'});
      expect(buildHealthCheckRequest(), {'type': 'health_check_request'});
      expect(buildHealthFixRequest('net-1'),
          {'type': 'health_fix_request', 'id': 'net-1'});
      expect(buildSetBypassPermissions(true),
          {'type': 'set_bypass_permissions', 'enabled': true});
      expect(buildSetBypassPermissions(false)['enabled'], false);
    });
  });

  group('client info', () {
    test('every field present in the handshake', () {
      expect(
        buildClientInfo(
          clientId: 'abcd1234',
          deviceName: 'Studio-Mac',
          platform: 'macos',
        ),
        {
          'type': 'client_info',
          'clientId': 'abcd1234',
          'deviceName': 'Studio-Mac',
          'platform': 'macos',
        },
      );
    });
  });
}
