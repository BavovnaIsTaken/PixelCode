/// Imperative DSL for the logo shutdown-animation path.
///
/// Grammar (one statement per line, indentation optional):
///
/// ```
///   move DIR AMOUNT        — move by pixels in direction
///   move DIR edge          — move until the screen edge in that direction
///   wait SECONDS           — pause in place (relative duration)
///   stamp PRESET           — trail density (tile|trail|dense)
///   stamp every N          — trail density, explicit px spacing
///   repeat N:              — loop body N times (body ends with `end`)
///     …body…
///   end
/// ```
///
/// Directions: right | left | up | down
///
/// The pen starts at `start`; `end` is ignored — the user builds whatever
/// path they want. Total duration is normalised to t ∈ [0, 1] proportionally
/// to distance travelled (with `wait` contributing a synthetic duration).
library;

import 'package:flutter/painting.dart' show Offset;

// ═══════════════════════════════════════════════════════════════════════════
// Public API
// ═══════════════════════════════════════════════════════════════════════════

const String kDefaultLogoPathScript = '''stamp trail
repeat 4:
  move right 100
  move down 80
  move left 100
  move down 80
end''';

/// Default trail-step in pixels, used when the script contains no `stamp`.
const double kDefaultTrailStep = 14.0;

/// Returns the effective trail-step for [script], falling back to
/// [kDefaultTrailStep] when no `stamp` directive is present or the script
/// fails to parse.
double resolveLogoPathStamp(String script) {
  final parsed = parseLogoProgram(script);
  if (parsed.error != null) return kDefaultTrailStep;
  return _findLastStamp(parsed.commands) ?? kDefaultTrailStep;
}

double? _findLastStamp(List<LogoCommand> cmds) {
  double? last;
  void walk(List<LogoCommand> cs) {
    for (final c in cs) {
      switch (c) {
        case StampCommand(:final spacing):
          last = spacing;
        case RepeatCommand(:final body):
          walk(body);
        case MoveCommand():
        case WaitCommand():
      }
    }
  }

  walk(cmds);
  return last;
}

/// Evaluates the program at progress [t] ∈ [0, 1].
/// Returns the interpolated position, or null on error.
Offset? evalLogoPath({
  required String script,
  required Offset start,
  required Offset end, // unused in this DSL, kept for call-site compat
  required double screenWidth,
  required double screenHeight,
  required double t,
}) {
  final parsed = parseLogoProgram(script);
  if (parsed.error != null) return null;
  final segments = _compile(
    parsed.commands,
    start: start,
    screenW: screenWidth,
    screenH: screenHeight,
  );
  return _sampleAt(segments, start, t.clamp(0.0, 1.0));
}

/// Validates [script]. Returns null if OK, or a human-readable error.
String? validateLogoPathScript(String script) {
  final parsed = parseLogoProgram(script);
  return parsed.error;
}

// ═══════════════════════════════════════════════════════════════════════════
// Command model (also consumed by the block editor)
// ═══════════════════════════════════════════════════════════════════════════

enum MoveDir { right, left, up, down }

enum StampPreset { tile, trail, dense, custom }

sealed class LogoCommand {
  const LogoCommand();
}

/// `stamp <preset>` or `stamp every N` — trail density.
/// When [preset] is [StampPreset.custom], [spacing] is the user's number.
/// Otherwise [spacing] is derived from the preset at construction.
class StampCommand extends LogoCommand {
  final StampPreset preset;
  final double spacing;
  const StampCommand({required this.preset, required this.spacing});

  factory StampCommand.preset(StampPreset p) {
    assert(p != StampPreset.custom);
    return StampCommand(preset: p, spacing: _kPresetPx[p]!);
  }
  factory StampCommand.custom(double px) =>
      StampCommand(preset: StampPreset.custom, spacing: px);
}

const Map<StampPreset, double> _kPresetPx = {
  StampPreset.tile: 24.0,
  StampPreset.trail: 14.0,
  StampPreset.dense: 6.0,
};

/// `move <dir> <amount>` — amount is null iff moving until edge.
class MoveCommand extends LogoCommand {
  final MoveDir dir;
  final double? amount; // null = until edge
  const MoveCommand({required this.dir, required this.amount});
  bool get untilEdge => amount == null;
  MoveCommand copyWith({MoveDir? dir, double? amount, bool? untilEdge}) {
    return MoveCommand(
      dir: dir ?? this.dir,
      amount: (untilEdge ?? this.untilEdge) ? null : (amount ?? this.amount),
    );
  }
}

/// `wait <seconds>`
class WaitCommand extends LogoCommand {
  final double seconds;
  const WaitCommand(this.seconds);
}

/// `repeat <n>: … end`
class RepeatCommand extends LogoCommand {
  final int count;
  final List<LogoCommand> body;
  const RepeatCommand({required this.count, required this.body});
}

// ═══════════════════════════════════════════════════════════════════════════
// Parser
// ═══════════════════════════════════════════════════════════════════════════

class ParseResult {
  final List<LogoCommand> commands;
  final String? error;
  const ParseResult(this.commands, this.error);
}

ParseResult parseLogoProgram(String src) {
  try {
    final lines = _tokenizeLines(src);
    final parser = _Parser(lines);
    final cmds = parser.parseBlock(endKeyword: null);
    return ParseResult(cmds, null);
  } on _ParseError catch (e) {
    return ParseResult(const [], 'Рядок ${e.line}: ${e.message}');
  }
}

class _LineTokens {
  final int lineNo; // 1-based
  final List<String> tokens;
  const _LineTokens(this.lineNo, this.tokens);
}

List<_LineTokens> _tokenizeLines(String src) {
  final out = <_LineTokens>[];
  final lines = src.split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    final hash = line.indexOf('#');
    if (hash >= 0) line = line.substring(0, hash);
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // split keeping the ':' attached where present
    final raw = trimmed.split(RegExp(r'\s+'));
    final toks = <String>[];
    for (final t in raw) {
      if (t.endsWith(':') && t.length > 1) {
        toks.add(t.substring(0, t.length - 1));
        toks.add(':');
      } else {
        toks.add(t);
      }
    }
    out.add(_LineTokens(i + 1, toks));
  }
  return out;
}

class _ParseError implements Exception {
  final int line;
  final String message;
  const _ParseError(this.line, this.message);
}

class _Parser {
  final List<_LineTokens> _lines;
  int _idx = 0;
  _Parser(this._lines);

  bool get hasMore => _idx < _lines.length;
  int get line => hasMore ? _lines[_idx].lineNo : -1;

  List<LogoCommand> parseBlock({required String? endKeyword}) {
    final out = <LogoCommand>[];
    while (hasMore) {
      final lt = _lines[_idx];
      final first = lt.tokens.first;
      if (endKeyword != null && first == endKeyword) {
        _idx++;
        return out;
      }
      out.add(_parseStatement());
    }
    if (endKeyword != null) {
      throw _ParseError(line, 'Очікувався "$endKeyword"');
    }
    return out;
  }

  LogoCommand _parseStatement() {
    final lt = _lines[_idx];
    final toks = lt.tokens;
    final first = toks.first;

    switch (first) {
      case 'move':
        _idx++;
        return _parseMove(lt);
      case 'wait':
        _idx++;
        return _parseWait(lt);
      case 'repeat':
        _idx++;
        return _parseRepeat(lt);
      case 'stamp':
        _idx++;
        return _parseStamp(lt);
      default:
        throw _ParseError(lt.lineNo, 'Невідома команда "$first"');
    }
  }

  MoveCommand _parseMove(_LineTokens lt) {
    // move <dir> <amount|edge>
    if (lt.tokens.length != 3) {
      throw _ParseError(
          lt.lineNo, 'move очікує: move <напрямок> <число|edge>');
    }
    final dir = _parseDir(lt.tokens[1], lt.lineNo);
    final amountTok = lt.tokens[2];
    if (amountTok == 'edge') {
      return MoveCommand(dir: dir, amount: null);
    }
    final n = double.tryParse(amountTok);
    if (n == null) {
      throw _ParseError(
          lt.lineNo, 'Очікується число або "edge", отримано "$amountTok"');
    }
    if (n < 0) {
      throw _ParseError(
          lt.lineNo, 'Відстань не може бути від\'ємною (використайте інший напрямок)');
    }
    return MoveCommand(dir: dir, amount: n);
  }

  WaitCommand _parseWait(_LineTokens lt) {
    if (lt.tokens.length != 2) {
      throw _ParseError(lt.lineNo, 'wait очікує: wait <секунди>');
    }
    final s = double.tryParse(lt.tokens[1]);
    if (s == null || s < 0) {
      throw _ParseError(lt.lineNo, 'wait очікує невід\'ємне число');
    }
    return WaitCommand(s);
  }

  StampCommand _parseStamp(_LineTokens lt) {
    // stamp tile | stamp trail | stamp dense | stamp every N
    final toks = lt.tokens;
    if (toks.length == 2) {
      final preset = switch (toks[1]) {
        'tile' => StampPreset.tile,
        'trail' => StampPreset.trail,
        'dense' => StampPreset.dense,
        _ => null,
      };
      if (preset == null) {
        throw _ParseError(lt.lineNo,
            'stamp очікує: tile | trail | dense | every N');
      }
      return StampCommand.preset(preset);
    }
    if (toks.length == 3 && toks[1] == 'every') {
      final n = double.tryParse(toks[2]);
      if (n == null || n <= 0) {
        throw _ParseError(lt.lineNo, 'stamp every очікує додатнє число');
      }
      return StampCommand.custom(n);
    }
    throw _ParseError(
        lt.lineNo, 'stamp очікує: tile | trail | dense | every N');
  }

  RepeatCommand _parseRepeat(_LineTokens lt) {
    // repeat <n> :
    if (lt.tokens.length != 3 || lt.tokens[2] != ':') {
      throw _ParseError(
          lt.lineNo, 'repeat очікує: repeat <кількість>:');
    }
    final n = int.tryParse(lt.tokens[1]);
    if (n == null || n < 1) {
      throw _ParseError(lt.lineNo, 'repeat очікує ціле число ≥ 1');
    }
    final body = parseBlock(endKeyword: 'end');
    return RepeatCommand(count: n, body: body);
  }

  MoveDir _parseDir(String s, int lineNo) {
    return switch (s) {
      'right' => MoveDir.right,
      'left' => MoveDir.left,
      'up' => MoveDir.up,
      'down' => MoveDir.down,
      _ => throw _ParseError(lineNo,
          'Невідомий напрямок "$s" — має бути right/left/up/down'),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Serializer (commands → script text)
// ═══════════════════════════════════════════════════════════════════════════

String serializeLogoProgram(List<LogoCommand> commands) {
  final buf = StringBuffer();
  _writeBlock(buf, commands, 0);
  return buf.toString().trimRight();
}

void _writeBlock(StringBuffer buf, List<LogoCommand> cmds, int indent) {
  final pad = '  ' * indent;
  for (final c in cmds) {
    switch (c) {
      case MoveCommand(:final dir, :final amount):
        final d = _dirName(dir);
        final a = amount == null ? 'edge' : _fmt(amount);
        buf.writeln('${pad}move $d $a');
      case WaitCommand(:final seconds):
        buf.writeln('${pad}wait ${_fmt(seconds)}');
      case RepeatCommand(:final count, :final body):
        buf.writeln('${pad}repeat $count:');
        _writeBlock(buf, body, indent + 1);
        buf.writeln('${pad}end');
      case StampCommand(:final preset, :final spacing):
        if (preset == StampPreset.custom) {
          buf.writeln('${pad}stamp every ${_fmt(spacing)}');
        } else {
          buf.writeln('${pad}stamp ${_presetName(preset)}');
        }
    }
  }
}

String _presetName(StampPreset p) => switch (p) {
      StampPreset.tile => 'tile',
      StampPreset.trail => 'trail',
      StampPreset.dense => 'dense',
      StampPreset.custom =>
          throw StateError('_presetName: custom preset is handled before call site'),
    };

String _dirName(MoveDir d) => switch (d) {
      MoveDir.right => 'right',
      MoveDir.left => 'left',
      MoveDir.up => 'up',
      MoveDir.down => 'down',
    };

String _fmt(double v) {
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// Compiler (commands → path segments)
// ═══════════════════════════════════════════════════════════════════════════

class _Segment {
  final Offset from;
  final Offset to;
  final double weight; // relative duration (≥ 0)
  const _Segment(this.from, this.to, this.weight);
}

/// `wait <seconds>` is converted to a no-movement segment with this weight
/// per second. Chosen so a 1-second wait feels comparable to ~200 px of motion.
const double _kWaitWeightPerSecond = 200.0;

List<_Segment> _compile(
  List<LogoCommand> cmds, {
  required Offset start,
  required double screenW,
  required double screenH,
}) {
  final segs = <_Segment>[];
  var pos = start;

  void walk(List<LogoCommand> block) {
    for (final c in block) {
      switch (c) {
        case MoveCommand(:final dir, :final amount):
          final target = _applyMove(pos, dir, amount, screenW, screenH);
          final w = (target - pos).distance;
          if (w > 0) segs.add(_Segment(pos, target, w));
          pos = target;
        case WaitCommand(:final seconds):
          final w = seconds * _kWaitWeightPerSecond;
          if (w > 0) segs.add(_Segment(pos, pos, w));
        case RepeatCommand(:final count, :final body):
          for (var i = 0; i < count; i++) {
            walk(body);
          }
        case StampCommand():
          // render-only metadata; ignored by the path compiler
          break;
      }
    }
  }

  walk(cmds);
  return segs;
}

Offset _applyMove(
  Offset pos,
  MoveDir dir,
  double? amount,
  double screenW,
  double screenH,
) {
  switch (dir) {
    case MoveDir.right:
      final dx = amount ?? (screenW - pos.dx);
      return Offset(pos.dx + dx, pos.dy);
    case MoveDir.left:
      final dx = amount ?? pos.dx;
      return Offset(pos.dx - dx, pos.dy);
    case MoveDir.up:
      final dy = amount ?? pos.dy;
      return Offset(pos.dx, pos.dy - dy);
    case MoveDir.down:
      final dy = amount ?? (screenH - pos.dy);
      return Offset(pos.dx, pos.dy + dy);
  }
}

Offset _sampleAt(List<_Segment> segs, Offset start, double t) {
  if (segs.isEmpty) return start;
  final total = segs.fold<double>(0, (a, s) => a + s.weight);
  if (total <= 0) return start;
  var acc = 0.0;
  final target = t * total;
  for (final s in segs) {
    if (target <= acc + s.weight) {
      final local = s.weight == 0 ? 0.0 : (target - acc) / s.weight;
      return Offset.lerp(s.from, s.to, local.clamp(0.0, 1.0))!;
    }
    acc += s.weight;
  }
  return segs.last.to;
}
