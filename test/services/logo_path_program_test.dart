import 'package:flutter_test/flutter_test.dart';

import 'package:pixelcode/services/logo_path_program.dart';

void main() {
  // ─── parseLogoProgram — happy-path ──────────────────────────────────────

  group('parseLogoProgram happy-path', () {
    test('parses move right', () {
      final r = parseLogoProgram('move right 100');
      expect(r.error, isNull);
      expect(r.commands, hasLength(1));
      final cmd = r.commands.first as MoveCommand;
      expect(cmd.dir, MoveDir.right);
      expect(cmd.amount, 100.0);
    });

    test('parses move left', () {
      final r = parseLogoProgram('move left 50');
      expect(r.error, isNull);
      final cmd = r.commands.first as MoveCommand;
      expect(cmd.dir, MoveDir.left);
      expect(cmd.amount, 50.0);
    });

    test('parses move up', () {
      final r = parseLogoProgram('move up 30');
      final cmd = r.commands.first as MoveCommand;
      expect(cmd.dir, MoveDir.up);
      expect(cmd.amount, 30.0);
    });

    test('parses move down', () {
      final r = parseLogoProgram('move down 80');
      final cmd = r.commands.first as MoveCommand;
      expect(cmd.dir, MoveDir.down);
      expect(cmd.amount, 80.0);
    });

    test('parses move until edge', () {
      final r = parseLogoProgram('move right edge');
      expect(r.error, isNull);
      final cmd = r.commands.first as MoveCommand;
      expect(cmd.untilEdge, isTrue);
      expect(cmd.amount, isNull);
    });

    test('parses wait command', () {
      final r = parseLogoProgram('wait 2.5');
      expect(r.error, isNull);
      final cmd = r.commands.first as WaitCommand;
      expect(cmd.seconds, 2.5);
    });

    test('parses stamp tile', () {
      final r = parseLogoProgram('stamp tile');
      expect(r.error, isNull);
      final cmd = r.commands.first as StampCommand;
      expect(cmd.preset, StampPreset.tile);
      expect(cmd.spacing, 24.0);
    });

    test('parses stamp trail', () {
      final r = parseLogoProgram('stamp trail');
      final cmd = r.commands.first as StampCommand;
      expect(cmd.preset, StampPreset.trail);
      expect(cmd.spacing, 14.0);
    });

    test('parses stamp dense', () {
      final r = parseLogoProgram('stamp dense');
      final cmd = r.commands.first as StampCommand;
      expect(cmd.preset, StampPreset.dense);
      expect(cmd.spacing, 6.0);
    });

    test('parses stamp every N', () {
      final r = parseLogoProgram('stamp every 10');
      expect(r.error, isNull);
      final cmd = r.commands.first as StampCommand;
      expect(cmd.preset, StampPreset.custom);
      expect(cmd.spacing, 10.0);
    });

    test('parses repeat block', () {
      final r = parseLogoProgram('repeat 3:\n  move right 10\nend');
      expect(r.error, isNull);
      expect(r.commands, hasLength(1));
      final rep = r.commands.first as RepeatCommand;
      expect(rep.count, 3);
      expect(rep.body, hasLength(1));
    });

    test('parses nested repeat', () {
      final script = 'repeat 2:\n  repeat 3:\n    move down 5\n  end\nend';
      final r = parseLogoProgram(script);
      expect(r.error, isNull);
      final outer = r.commands.first as RepeatCommand;
      final inner = outer.body.first as RepeatCommand;
      expect(outer.count, 2);
      expect(inner.count, 3);
    });

    test('ignores comment lines', () {
      final r = parseLogoProgram('# comment\nmove right 10\n# another');
      expect(r.error, isNull);
      expect(r.commands, hasLength(1));
    });

    test('ignores inline comments', () {
      final r = parseLogoProgram('move right 10 # go right');
      expect(r.error, isNull);
      expect(r.commands, hasLength(1));
    });

    test('ignores empty lines', () {
      final r = parseLogoProgram('\n\nmove right 10\n\n');
      expect(r.error, isNull);
      expect(r.commands, hasLength(1));
    });

    test('parses kDefaultLogoPathScript without error', () {
      final r = parseLogoProgram(kDefaultLogoPathScript);
      expect(r.error, isNull);
      expect(r.commands, hasLength(2));
    });

    test('parses multiple commands in sequence', () {
      final script = 'move right 100\nwait 1\nmove down 50';
      final r = parseLogoProgram(script);
      expect(r.error, isNull);
      expect(r.commands, hasLength(3));
      expect(r.commands[0], isA<MoveCommand>());
      expect(r.commands[1], isA<WaitCommand>());
      expect(r.commands[2], isA<MoveCommand>());
    });
  });

  // ─── parseLogoProgram — error cases ─────────────────────────────────────

  group('parseLogoProgram errors', () {
    test('unknown command returns error', () {
      final r = parseLogoProgram('fly right 10');
      expect(r.error, isNotNull);
      expect(r.commands, isEmpty);
    });

    test('move with only one token returns error', () {
      final r = parseLogoProgram('move right');
      expect(r.error, isNotNull);
    });

    test('move with unknown direction returns error', () {
      final r = parseLogoProgram('move diagonal 10');
      expect(r.error, isNotNull);
    });

    test('move with negative amount returns error', () {
      final r = parseLogoProgram('move right -5');
      expect(r.error, isNotNull);
    });

    test('move with non-numeric amount returns error', () {
      final r = parseLogoProgram('move right fast');
      expect(r.error, isNotNull);
    });

    test('wait with no argument returns error', () {
      final r = parseLogoProgram('wait');
      expect(r.error, isNotNull);
    });

    test('wait with negative seconds returns error', () {
      final r = parseLogoProgram('wait -1');
      expect(r.error, isNotNull);
    });

    test('wait with non-numeric value returns error', () {
      final r = parseLogoProgram('wait forever');
      expect(r.error, isNotNull);
    });

    test('stamp with unknown preset returns error', () {
      final r = parseLogoProgram('stamp sparse');
      expect(r.error, isNotNull);
    });

    test('stamp every zero returns error', () {
      final r = parseLogoProgram('stamp every 0');
      expect(r.error, isNotNull);
    });

    test('stamp every negative returns error', () {
      final r = parseLogoProgram('stamp every -5');
      expect(r.error, isNotNull);
    });

    test('stamp with extra tokens (not every N) returns error', () {
      final r = parseLogoProgram('stamp tile dense');
      expect(r.error, isNotNull);
    });

    test('repeat without end returns error', () {
      final r = parseLogoProgram('repeat 2:\n  move right 10');
      expect(r.error, isNotNull);
    });

    test('repeat with n=0 returns error', () {
      final r = parseLogoProgram('repeat 0:\nend');
      expect(r.error, isNotNull);
    });

    test('repeat without colon returns error', () {
      final r = parseLogoProgram('repeat 2\n  move right 10\nend');
      expect(r.error, isNotNull);
    });
  });

  // ─── serializeLogoProgram — round-trips ─────────────────────────────────

  group('serializeLogoProgram round-trip', () {
    LogoCommand parseFirst(String src) => parseLogoProgram(src).commands.first;

    test('move right round-trips', () {
      final cmd = parseFirst('move right 100');
      final text = serializeLogoProgram([cmd]);
      final restored = parseLogoProgram(text).commands.first as MoveCommand;
      expect(restored.dir, MoveDir.right);
      expect(restored.amount, 100.0);
    });

    test('move until edge round-trips', () {
      final cmd = parseFirst('move left edge');
      final text = serializeLogoProgram([cmd]);
      final restored = parseLogoProgram(text).commands.first as MoveCommand;
      expect(restored.untilEdge, isTrue);
    });

    test('wait round-trips', () {
      final cmd = parseFirst('wait 1.5');
      final text = serializeLogoProgram([cmd]);
      final restored = parseLogoProgram(text).commands.first as WaitCommand;
      expect(restored.seconds, 1.5);
    });

    test('stamp preset round-trips', () {
      for (final preset in ['tile', 'trail', 'dense']) {
        final cmd = parseFirst('stamp $preset');
        final text = serializeLogoProgram([cmd]);
        expect(parseLogoProgram(text).error, isNull, reason: 'preset=$preset');
      }
    });

    test('stamp every N round-trips', () {
      final cmd = parseFirst('stamp every 8');
      final text = serializeLogoProgram([cmd]);
      final restored = parseLogoProgram(text).commands.first as StampCommand;
      expect(restored.preset, StampPreset.custom);
      expect(restored.spacing, 8.0);
    });

    test('repeat block round-trips', () {
      final src = 'repeat 4:\n  move right 100\nend';
      final cmd = parseFirst(src);
      final text = serializeLogoProgram([cmd]);
      final restored = parseLogoProgram(text).commands.first as RepeatCommand;
      expect(restored.count, 4);
      expect(restored.body, hasLength(1));
    });

    test('kDefaultLogoPathScript round-trips', () {
      final cmds = parseLogoProgram(kDefaultLogoPathScript).commands;
      final text = serializeLogoProgram(cmds);
      final r2 = parseLogoProgram(text);
      expect(r2.error, isNull);
      expect(r2.commands.length, cmds.length);
    });
  });

  // ─── validateLogoPathScript ──────────────────────────────────────────────

  group('validateLogoPathScript', () {
    test('returns null for valid script', () {
      expect(validateLogoPathScript('move right 50'), isNull);
    });

    test('returns null for kDefaultLogoPathScript', () {
      expect(validateLogoPathScript(kDefaultLogoPathScript), isNull);
    });

    test('returns error string for invalid script', () {
      expect(validateLogoPathScript('fly north'), isNotNull);
    });

    test('returns error for repeat without end', () {
      expect(validateLogoPathScript('repeat 2:\n  move right 10'), isNotNull);
    });
  });

  // ─── resolveLogoPathStamp ────────────────────────────────────────────────

  group('resolveLogoPathStamp', () {
    test('returns tile spacing (24.0) for stamp tile', () {
      expect(resolveLogoPathStamp('stamp tile'), 24.0);
    });

    test('returns trail spacing (14.0) for stamp trail', () {
      expect(resolveLogoPathStamp('stamp trail'), 14.0);
    });

    test('returns dense spacing (6.0) for stamp dense', () {
      expect(resolveLogoPathStamp('stamp dense'), 6.0);
    });

    test('returns custom spacing for stamp every N', () {
      expect(resolveLogoPathStamp('stamp every 9'), 9.0);
    });

    test('returns kDefaultTrailStep when no stamp present', () {
      expect(resolveLogoPathStamp('move right 100'), kDefaultTrailStep);
    });

    test('returns kDefaultTrailStep on parse error', () {
      expect(resolveLogoPathStamp('gibberish'), kDefaultTrailStep);
    });

    test('returns last stamp when multiple are present', () {
      final script = 'stamp tile\nmove right 10\nstamp dense';
      expect(resolveLogoPathStamp(script), 6.0);
    });

    test('last stamp inside repeat is found', () {
      final script = 'repeat 2:\n  stamp trail\nend';
      expect(resolveLogoPathStamp(script), 14.0);
    });

    test('wait command is ignored when finding stamp', () {
      expect(resolveLogoPathStamp('wait 1\nstamp tile'), 24.0);
    });
  });

  // ─── evalLogoPath ────────────────────────────────────────────────────────

  group('evalLogoPath', () {
    Offset? eval(String script, double t) => evalLogoPath(
          script: script,
          start: Offset.zero,
          end: const Offset(1000, 1000),
          screenWidth: 400,
          screenHeight: 800,
          t: t,
        );

    test('returns null on parse error', () {
      expect(eval('bad command', 0.5), isNull);
    });

    test('returns start at t=0 for single move', () {
      final pos = eval('move right 100', 0.0);
      expect(pos, isNotNull);
      expect(pos!.dx, closeTo(0.0, 0.01));
      expect(pos.dy, closeTo(0.0, 0.01));
    });

    test('returns end position at t=1 for single move', () {
      final pos = eval('move right 100', 1.0);
      expect(pos!.dx, closeTo(100.0, 0.01));
    });

    test('interpolates at t=0.5 for single move', () {
      final pos = eval('move right 100', 0.5);
      expect(pos!.dx, closeTo(50.0, 0.01));
    });

    test('clamps t > 1 to 1', () {
      final pos1 = eval('move right 100', 1.0);
      final pos2 = eval('move right 100', 2.0);
      expect(pos1!.dx, closeTo(pos2!.dx, 0.01));
    });

    test('clamps t < 0 to 0', () {
      final pos1 = eval('move right 100', 0.0);
      final pos2 = eval('move right 100', -1.0);
      expect(pos1!.dx, closeTo(pos2!.dx, 0.01));
    });

    test('wait creates pause without position change', () {
      final posA = eval('move right 100\nwait 100\nmove right 100', 0.5);
      expect(posA, isNotNull);
    });

    test('result is within reasonable screen bounds for default script', () {
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final pos = evalLogoPath(
          script: kDefaultLogoPathScript,
          start: const Offset(100, 100),
          end: const Offset(300, 300),
          screenWidth: 400,
          screenHeight: 800,
          t: t,
        );
        expect(pos, isNotNull, reason: 't=$t');
      }
    });

    test('move right edge fills remaining screen width', () {
      final pos = evalLogoPath(
        script: 'move right edge',
        start: const Offset(100, 200),
        end: Offset.zero,
        screenWidth: 400,
        screenHeight: 800,
        t: 1.0,
      );
      expect(pos, isNotNull);
      expect(pos!.dx, closeTo(400.0, 0.01));
    });

    test('move left edge reaches x=0', () {
      final pos = evalLogoPath(
        script: 'move left edge',
        start: const Offset(150, 200),
        end: Offset.zero,
        screenWidth: 400,
        screenHeight: 800,
        t: 1.0,
      );
      expect(pos, isNotNull);
      expect(pos!.dx, closeTo(0.0, 0.01));
    });

    test('move up edge reaches y=0', () {
      final pos = evalLogoPath(
        script: 'move up edge',
        start: const Offset(100, 300),
        end: Offset.zero,
        screenWidth: 400,
        screenHeight: 800,
        t: 1.0,
      );
      expect(pos, isNotNull);
      expect(pos!.dy, closeTo(0.0, 0.01));
    });

    test('move down edge fills remaining screen height', () {
      final pos = evalLogoPath(
        script: 'move down edge',
        start: const Offset(100, 200),
        end: Offset.zero,
        screenWidth: 400,
        screenHeight: 800,
        t: 1.0,
      );
      expect(pos, isNotNull);
      expect(pos!.dy, closeTo(800.0, 0.01));
    });
  });

  // ─── MoveCommand.copyWith ────────────────────────────────────────────────

  group('MoveCommand.copyWith', () {
    const base = MoveCommand(dir: MoveDir.right, amount: 100);

    test('changes direction', () {
      final c = base.copyWith(dir: MoveDir.left);
      expect(c.dir, MoveDir.left);
      expect(c.amount, 100.0);
    });

    test('changes amount', () {
      final c = base.copyWith(amount: 200);
      expect(c.amount, 200.0);
      expect(c.dir, MoveDir.right);
    });

    test('sets untilEdge=true clears amount', () {
      final c = base.copyWith(untilEdge: true);
      expect(c.untilEdge, isTrue);
      expect(c.amount, isNull);
    });

    test('setting untilEdge=false keeps existing amount', () {
      final c = base.copyWith(untilEdge: false);
      expect(c.untilEdge, isFalse);
      expect(c.amount, 100.0);
    });
  });
}
