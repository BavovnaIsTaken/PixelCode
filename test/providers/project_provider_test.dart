/// Regression coverage for the "game created in the wrong project" bug.
///
/// Symptom: the server restarted and its global working directory reset to
/// the config default, while the client restored its previously selected
/// project from SharedPreferences and kept showing it in the UI. Messages
/// then ran agents in the server's actual cwd — files landed in a different
/// repository than the one selected in the project dropdown.
///
/// Client-side fixes pinned here:
///   1. `ProjectNotifier` stamps `AgentWsService.projectPath` with the
///      restored selection so every `send_message` carries it.
///   2. The server is the source of truth: on any `init` whose
///      `workingDirectory` disagrees with the local selection, the notifier
///      follows the server (state + persistence) WITHOUT echoing
///      `set_project` back (two devices must not fight over the global).
///   3. A `project_mismatch` rejection surfaces in the chat transcript as a
///      user-visible warning instead of a silently dropped message.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/providers/agent_provider.dart';
import 'package:pixelcode/providers/project_provider.dart';
import 'package:pixelcode/providers/settings_provider.dart';
import 'package:pixelcode/services/agent_ws_service.dart';
import 'package:pixelcode/services/project_persistence_service.dart';

class _FakeWs extends AgentWsService {
  final _msgCtrl = StreamController<ServerMessage>.broadcast();
  final List<String> setProjectCalls = [];

  /// Mirrors the real listener: buffer the InitMessage on the service and
  /// forward it to subscribers.
  void inject(ServerMessage msg) {
    if (msg is InitMessage) lastInit = msg;
    _msgCtrl.add(msg);
  }

  @override
  Stream<ServerMessage> get messages => _msgCtrl.stream;

  @override
  Stream<String> get connectionLog => const Stream.empty();

  @override
  void setProject(String path) {
    projectPath = path;
    setProjectCalls.add(path);
  }

  @override
  Future<void> dispose() async {
    await _msgCtrl.close();
    return super.dispose();
  }
}

InitMessage _init(String workingDirectory) => InitMessage(
      sessionId: 'sess-1',
      agents: const [],
      workingDirectory: workingDirectory,
    );

Future<({ProviderContainer container, _FakeWs ws, SharedPreferences prefs})>
    _makeHarness({String? savedProjectPath}) async {
  SharedPreferences.setMockInitialValues({
    'current_project_path': ?savedProjectPath,
  });
  final prefs = await SharedPreferences.getInstance();
  final ws = _FakeWs();
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    wsServiceProvider.overrideWithValue(ws),
  ]);
  addTearDown(() async {
    container.dispose();
    await ws.dispose();
  });
  return (container: container, ws: ws, prefs: prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProjectNotifier — projectPath stamping', () {
    test('restored selection is stamped onto the ws service', () async {
      final h = await _makeHarness(savedProjectPath: '/projects/selected');

      final project = h.container.read(projectProvider);

      expect(project?.path, '/projects/selected');
      expect(h.ws.projectPath, '/projects/selected');
    });
  });

  group('ProjectNotifier — follows the server', () {
    test('init with a different workingDirectory overrides the selection',
        () async {
      final h = await _makeHarness(savedProjectPath: '/projects/selected');
      expect(h.container.read(projectProvider)?.path, '/projects/selected');

      h.ws.inject(_init('/projects/server-actual'));
      await Future<void>.delayed(Duration.zero);

      expect(h.container.read(projectProvider)?.path, '/projects/server-actual');
      expect(h.ws.projectPath, '/projects/server-actual');
      // Persisted, so the next launch restores the server's project.
      expect(
        ProjectPersistenceService.loadCurrentProjectPath(h.prefs),
        '/projects/server-actual',
      );
    });

    test('following the server does NOT echo set_project back', () async {
      final h = await _makeHarness(savedProjectPath: '/projects/selected');
      h.container.read(projectProvider);

      h.ws.inject(_init('/projects/server-actual'));
      await Future<void>.delayed(Duration.zero);

      expect(h.ws.setProjectCalls, isEmpty,
          reason: 'auto-asserting the local selection would make two devices '
              'with different saved projects fight over the global');
    });

    test(
      'buffered init that arrived BEFORE build still wins over the '
      'saved selection (cold-start race)',
      () async {
        final h = await _makeHarness(savedProjectPath: '/projects/selected');
        // Init flows through the service before any provider consumer exists.
        h.ws.inject(_init('/projects/server-actual'));

        // First read builds the notifier; reconciliation is scheduled.
        expect(h.container.read(projectProvider)?.path, '/projects/selected');
        await Future<void>.delayed(Duration.zero);

        expect(
          h.container.read(projectProvider)?.path,
          '/projects/server-actual',
        );
        expect(h.ws.projectPath, '/projects/server-actual');
      },
    );

    test('init matching the selection is a no-op', () async {
      final h = await _makeHarness(savedProjectPath: '/projects/selected');
      final before = h.container.read(projectProvider);

      h.ws.inject(_init('/projects/selected'));
      await Future<void>.delayed(Duration.zero);

      expect(identical(h.container.read(projectProvider), before), isTrue);
      expect(
        ProjectPersistenceService.loadCurrentProjectPath(h.prefs),
        '/projects/selected',
      );
    });

    test('init without workingDirectory is ignored', () async {
      final h = await _makeHarness(savedProjectPath: '/projects/selected');
      h.container.read(projectProvider);

      h.ws.inject(InitMessage(sessionId: 'sess-1', agents: const []));
      await Future<void>.delayed(Duration.zero);

      expect(h.container.read(projectProvider)?.path, '/projects/selected');
    });
  });

  group('ChatNotifier — project_mismatch handling', () {
    test('rejection surfaces as a warning message in the transcript',
        () async {
      final h = await _makeHarness(savedProjectPath: '/projects/selected');
      // Build the chat notifier so it subscribes to the message stream.
      expect(h.container.read(chatProvider), isEmpty);

      h.ws.inject(ProjectMismatchMessage(
        requested: '/projects/selected',
        active: '/projects/server-actual',
      ));
      await Future<void>.delayed(Duration.zero);

      final messages = h.container.read(chatProvider);
      expect(messages, hasLength(1));
      expect(messages.single.text, contains('/projects/server-actual'));
      expect(messages.single.text, contains('/projects/selected'));
      expect(messages.single.text, contains('не виконано'));
    });
  });
}
