import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/services/office_simulation_service.dart';
import 'package:pixelcode/widgets/canvas/office_game_state.dart';

void main() {
  group('OfficeSimulationService', () {
    test('constructs with a fresh OfficeGameState and frame counter at 0', () {
      final svc = OfficeSimulationService(autoStart: false);
      expect(svc.gameState, isA<OfficeGameState>());
      expect(svc.frame.value, 0);
      expect(svc.gameState.isFrozen, isFalse);
      expect(svc.gameState.isAutonomous, isFalse);
      svc.dispose();
    });

    test('accepts a pre-built OfficeGameState (for hot-restart-style state hydration)', () {
      final preexisting = OfficeGameState(level: OfficeLevel.smallOffice);
      final svc = OfficeSimulationService(
        gameState: preexisting,
        autoStart: false,
      );
      expect(identical(svc.gameState, preexisting), isTrue);
      svc.dispose();
    });

    test('debugStep advances the simulation and increments frame counter', () {
      final svc = OfficeSimulationService(autoStart: false);
      svc.debugStep(const Duration(milliseconds: 16));
      expect(svc.frame.value, 1);
      svc.debugStep(const Duration(milliseconds: 33));
      expect(svc.frame.value, 2);
      svc.dispose();
    });

    test('enterAutonomousWander flips state into autonomous mode', () {
      final svc = OfficeSimulationService(autoStart: false);
      svc.enterAutonomousWander();
      expect(svc.gameState.isAutonomous, isTrue);
      expect(svc.gameState.isFrozen, isFalse);
      svc.dispose();
    });

    test('wakeUp clears autonomous mode after enterAutonomousWander', () {
      final svc = OfficeSimulationService(autoStart: false);
      svc.enterAutonomousWander();
      svc.wakeUp();
      expect(svc.gameState.isAutonomous, isFalse);
      expect(svc.gameState.isFrozen, isFalse);
      svc.dispose();
    });

    test('debugStep keeps simulating while in autonomous mode (no freeze short-circuit)', () {
      final svc = OfficeSimulationService(autoStart: false);
      svc.enterAutonomousWander();
      svc.debugStep(const Duration(milliseconds: 16));
      svc.debugStep(const Duration(milliseconds: 32));
      expect(svc.frame.value, 2);
      // Still autonomous between ticks.
      expect(svc.gameState.isAutonomous, isTrue);
      svc.dispose();
    });

    test('rebuildLayout is forwarded to the underlying game state', () {
      final svc = OfficeSimulationService(autoStart: false);
      final beforeCols = svc.gameState.gridCols;
      svc.rebuildLayout(OfficeLevel.smallOffice, const [], const [], const []);
      // smallOffice has different inner cols than garage default.
      expect(svc.gameState.gridCols, isNot(beforeCols));
      svc.dispose();
    });

    test('dispose stops further debugStep calls (frame ValueNotifier is closed)', () {
      final svc = OfficeSimulationService(autoStart: false);
      svc.dispose();
      // Calling debugStep on a disposed service should not silently advance —
      // the frame ValueNotifier has been disposed and any further mutation
      // throws. This guards against use-after-dispose bugs in callers.
      expect(
        () => svc.debugStep(const Duration(milliseconds: 16)),
        throwsA(anything),
      );
    });
  });
}
