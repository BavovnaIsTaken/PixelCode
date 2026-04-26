import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/deploy_state.dart';
import 'package:pixelcode/models/agent_message.dart' show AndroidDevice;

void main() {
  // ─── DeployPhase / isBusy ─────────────────────────────────────────────

  group('DeployState.isBusy', () {
    test('idle is not busy', () {
      const state = DeployState(phase: DeployPhase.idle);
      expect(state.isBusy, isFalse);
    });

    test('checking is busy', () {
      const state = DeployState(phase: DeployPhase.checking);
      expect(state.isBusy, isTrue);
    });

    test('building is busy', () {
      const state = DeployState(phase: DeployPhase.building);
      expect(state.isBusy, isTrue);
    });

    test('ready is not busy', () {
      const state = DeployState(phase: DeployPhase.ready);
      expect(state.isBusy, isFalse);
    });

    test('error is not busy', () {
      const state = DeployState(phase: DeployPhase.error);
      expect(state.isBusy, isFalse);
    });
  });

  // ─── Default values ───────────────────────────────────────────────────

  group('DeployState defaults', () {
    test('phase defaults to idle', () {
      const state = DeployState();
      expect(state.phase, DeployPhase.idle);
    });

    test('installUrl defaults to null', () {
      const state = DeployState();
      expect(state.installUrl, isNull);
    });

    test('lastError defaults to null', () {
      const state = DeployState();
      expect(state.lastError, isNull);
    });

    test('logs defaults to empty list', () {
      const state = DeployState();
      expect(state.logs, isEmpty);
    });

    test('devices defaults to empty list', () {
      const state = DeployState();
      expect(state.devices, isEmpty);
    });

    test('selectedSerial defaults to null', () {
      const state = DeployState();
      expect(state.selectedSerial, isNull);
    });
  });

  // ─── copyWith ─────────────────────────────────────────────────────────

  group('DeployState.copyWith', () {
    const base = DeployState(
      phase: DeployPhase.idle,
      installUrl: 'https://install.example.com',
      lastError: null,
      logs: ['step 1'],
      selectedSerial: 'SERIAL123',
    );

    test('preserves unchanged fields', () {
      final copy = base.copyWith(phase: DeployPhase.building);
      expect(copy.installUrl, base.installUrl);
      expect(copy.logs, base.logs);
      expect(copy.selectedSerial, base.selectedSerial);
    });

    test('changes only phase', () {
      final copy = base.copyWith(phase: DeployPhase.error);
      expect(copy.phase, DeployPhase.error);
    });

    test('changes installUrl', () {
      final copy = base.copyWith(installUrl: 'https://new.example.com');
      expect(copy.installUrl, 'https://new.example.com');
    });

    test('changes lastError', () {
      final copy = base.copyWith(lastError: 'Build failed');
      expect(copy.lastError, 'Build failed');
    });

    test('appends to logs', () {
      final copy = base.copyWith(logs: [...base.logs, 'step 2']);
      expect(copy.logs.length, 2);
      expect(copy.logs.last, 'step 2');
    });

    test('clearSelectedSerial=true sets selectedSerial to null', () {
      final copy = base.copyWith(clearSelectedSerial: true);
      expect(copy.selectedSerial, isNull);
    });

    test('clearSelectedSerial=false preserves selectedSerial', () {
      final copy = base.copyWith(
        phase: DeployPhase.building,
        clearSelectedSerial: false,
      );
      expect(copy.selectedSerial, base.selectedSerial);
    });

    test('new selectedSerial is applied when clearSelectedSerial=false', () {
      final copy = base.copyWith(selectedSerial: 'NEWSERIAL');
      expect(copy.selectedSerial, 'NEWSERIAL');
    });

    test('clearSelectedSerial=true takes precedence over selectedSerial', () {
      // If clearSelectedSerial is true, selectedSerial arg is ignored
      final copy = base.copyWith(
        selectedSerial: 'IGNORED',
        clearSelectedSerial: true,
      );
      expect(copy.selectedSerial, isNull);
    });
  });

  // ─── AndroidDevice.isReady ────────────────────────────────────────────

  group('AndroidDevice.isReady', () {
    test('true when state is "device"', () {
      const device = AndroidDevice(
        serial: 'ABC123',
        model: 'Pixel_6',
        state: 'device',
      );
      expect(device.isReady, isTrue);
    });

    test('false when state is "unauthorized"', () {
      const device = AndroidDevice(
        serial: 'ABC123',
        model: 'Pixel_6',
        state: 'unauthorized',
      );
      expect(device.isReady, isFalse);
    });

    test('false when state is "offline"', () {
      const device = AndroidDevice(
        serial: 'ABC123',
        model: 'Pixel_6',
        state: 'offline',
      );
      expect(device.isReady, isFalse);
    });

    test('false for unknown state', () {
      const device = AndroidDevice(
        serial: 'ABC123',
        model: 'Pixel_6',
        state: 'unknown',
      );
      expect(device.isReady, isFalse);
    });

    test('fromJson parses all fields', () {
      final json = {
        'serial': 'SERIAL42',
        'model': 'Galaxy_S22',
        'state': 'device',
      };
      final device = AndroidDevice.fromJson(json);

      expect(device.serial, 'SERIAL42');
      expect(device.model, 'Galaxy_S22');
      expect(device.state, 'device');
      expect(device.isReady, isTrue);
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};
      final device = AndroidDevice.fromJson(json);

      expect(device.serial, '');
      expect(device.model, '');
      expect(device.state, 'unknown');
      expect(device.isReady, isFalse);
    });
  });
}
