/// Minimal Kotlin-like DSL for the logo shutdown-animation path.
///
/// Inputs available in the script:
///   start        — Point with .x and .y (starting position in px)
///   end          — Point with .x and .y (destination in px)
///   screenWidth  — screen width in logical pixels
///   screenHeight — screen height in logical pixels
///   t            — progress from 0.0 to 1.0
///   PI, E        — math constants
///
/// The script must end with:
///   return Point(x, y)
///
/// Example:
///   val dx = end.x - start.x
///   val dy = end.y - start.y
///   val wave = sin(t * PI * 6) * 40
///   return Point(start.x + dx * t + wave, start.y + dy * t)
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset;

// ─── Public API ───────────────────────────────────────────────────────────────

const String kDefaultLogoPathScript = '''// Position of the logo at time t (0.0 → 1.0)
// start, end — starting and destination points (.x, .y)
// screenWidth, screenHeight — screen size in pixels
// PI, E — math constants

val dx = end.x - start.x
val dy = end.y - start.y
val wave = sin(t * PI * 6) * 40
val x = start.x + dx * t + wave
val y = start.y + dy * t
return Point(x, y)''';

/// Evaluates the script for a given [t] in [0..1].
/// Returns the logo position, or null on runtime error.
Offset? evalLogoPath({
  required String script,
  required Offset start,
  required Offset end,
  required double screenWidth,
  required double screenHeight,
  required double t,
}) {
  try {
    final tokens = _lex(script);
    final result = _Interpreter(tokens).run({
      'start': _Point(start.dx, start.dy),
      'end': _Point(end.dx, end.dy),
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      't': t,
      'PI': math.pi,
      'E': math.e,
    });
    return result;
  } catch (_) {
    return null;
  }
}

/// Validates the script by running it with sample values.
/// Returns a human-readable error string, or null if the script is valid.
String? validateLogoPathScript(String script) {
  try {
    final tokens = _lex(script);
    final result = _Interpreter(tokens).run({
      'start': _Point(16.0, 12.0),
      'end': _Point(500.0, 800.0),
      'screenWidth': 390.0,
      'screenHeight': 844.0,
      't': 0.5,
      'PI': math.pi,
      'E': math.e,
    });
    if (result == null) return 'return Point(x, y) не знайдено';
    return null;
  } on _DslError catch (e) {
    return e.message;
  } catch (e) {
    return e.toString();
  }
}

// ─── Internal point type ──────────────────────────────────────────────────────

class _Point {
  final double x, y;
  const _Point(this.x, this.y);
}

// ─── Error ────────────────────────────────────────────────────────────────────

class _DslError implements Exception {
  final String message;
  const _DslError(this.message);
  @override
  String toString() => message;
}

// ─── Token types ──────────────────────────────────────────────────────────────

enum _TT {
  num,
  ident,
  plus,
  minus,
  star,
  slash,
  percent,
  lparen,
  rparen,
  comma,
  dot,
  eq,
  nl,
  eof,
  kVal,
  kReturn,
}

class _Token {
  final _TT type;
  final String text;
  final int pos; // byte offset in source (for error messages)
  const _Token(this.type, this.text, this.pos);
}

// ─── Lexer ────────────────────────────────────────────────────────────────────

List<_Token> _lex(String src) {
  final out = <_Token>[];
  int i = 0;

  bool isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  bool isAlpha(String c) => RegExp(r'[a-zA-Z_]').hasMatch(c);

  while (i < src.length) {
    final ch = src[i];

    // Spaces / tabs / carriage returns
    if (ch == ' ' || ch == '\t' || ch == '\r') {
      i++;
      continue;
    }

    // Line comments
    if (ch == '/' && i + 1 < src.length && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') { i++; }
      continue;
    }

    // Newline
    if (ch == '\n') {
      out.add(_Token(_TT.nl, '\n', i));
      i++;
      continue;
    }

    // Number literal  (integer or float, no exponent needed)
    if (isDigit(ch) ||
        (ch == '.' && i + 1 < src.length && isDigit(src[i + 1]))) {
      final start = i;
      bool hasDot = false;
      while (i < src.length) {
        if (src[i] == '.' && !hasDot) {
          hasDot = true;
          i++;
        } else if (isDigit(src[i])) {
          i++;
        } else {
          break;
        }
      }
      out.add(_Token(_TT.num, src.substring(start, i), start));
      continue;
    }

    // Identifier / keyword
    if (isAlpha(ch)) {
      final start = i;
      while (i < src.length && (isAlpha(src[i]) || isDigit(src[i]))) { i++; }
      final text = src.substring(start, i);
      final type = switch (text) {
        'val' => _TT.kVal,
        'return' => _TT.kReturn,
        _ => _TT.ident,
      };
      out.add(_Token(type, text, start));
      continue;
    }

    // Single-char tokens
    final type = switch (ch) {
      '+' => _TT.plus,
      '-' => _TT.minus,
      '*' => _TT.star,
      '/' => _TT.slash,
      '%' => _TT.percent,
      '(' => _TT.lparen,
      ')' => _TT.rparen,
      ',' => _TT.comma,
      '.' => _TT.dot,
      '=' => _TT.eq,
      _ => throw _DslError('Невідомий символ: "$ch" (позиція $i)'),
    };
    out.add(_Token(type, ch, i));
    i++;
  }

  out.add(_Token(_TT.eof, '', src.length));
  return out;
}

// ─── Interpreter (recursive-descent parser + evaluator in one pass) ───────────

class _Interpreter {
  final List<_Token> _toks;
  int _pos = 0;

  _Interpreter(this._toks);

  _Token get _cur => _toks[_pos];

  _Token _consume([_TT? expected]) {
    final t = _cur;
    if (expected != null && t.type != expected) {
      throw _DslError(
          'Очікувалось ${expected.name}, але зустрілось "${t.text}"');
    }
    _pos++;
    return t;
  }

  void _skipNl() {
    while (_cur.type == _TT.nl) { _pos++; }
  }

  // ── Entry point ────────────────────────────────────────────────────────────

  Offset? run(Map<String, dynamic> ctx) {
    final env = Map<String, dynamic>.from(ctx);
    _skipNl();

    while (_cur.type != _TT.eof) {
      _skipNl();
      if (_cur.type == _TT.eof) break;

      if (_cur.type == _TT.kReturn) {
        _consume(_TT.kReturn);
        final val = _expr(env);
        if (val is _Point) return Offset(val.x, val.y);
        throw _DslError('return очікує Point(x, y)');
      }

      if (_cur.type == _TT.kVal) {
        _valDecl(env);
      } else {
        throw _DslError('Очікувалось val або return');
      }
    }
    throw _DslError('Відсутній return Point(x, y)');
  }

  // ── val declaration ────────────────────────────────────────────────────────

  void _valDecl(Map<String, dynamic> env) {
    _consume(_TT.kVal);
    final name = _consume(_TT.ident);
    _consume(_TT.eq);
    env[name.text] = _expr(env);
    _skipNl();
  }

  // ── Expressions ───────────────────────────────────────────────────────────

  dynamic _expr(Map<String, dynamic> env) => _addSub(env);

  dynamic _addSub(Map<String, dynamic> env) {
    var left = _mulDiv(env);
    while (_cur.type == _TT.plus || _cur.type == _TT.minus) {
      final op = _consume();
      final right = _mulDiv(env);
      final l = _num(left, op);
      final r = _num(right, op);
      left = op.type == _TT.plus ? l + r : l - r;
    }
    return left;
  }

  dynamic _mulDiv(Map<String, dynamic> env) {
    var left = _unary(env);
    while (_cur.type == _TT.star ||
        _cur.type == _TT.slash ||
        _cur.type == _TT.percent) {
      final op = _consume();
      final right = _unary(env);
      final l = _num(left, op);
      final r = _num(right, op);
      left = switch (op.type) {
        _TT.star => l * r,
        _TT.slash => r == 0 ? double.nan : l / r,
        _TT.percent => l % r,
        _ => throw _DslError('unreachable'),
      };
    }
    return left;
  }

  dynamic _unary(Map<String, dynamic> env) {
    if (_cur.type == _TT.minus) {
      final op = _consume();
      return -_num(_unary(env), op);
    }
    if (_cur.type == _TT.plus) {
      _consume();
      return _unary(env);
    }
    return _primary(env);
  }

  dynamic _primary(Map<String, dynamic> env) {
    final t = _cur;

    // Grouped expression
    if (t.type == _TT.lparen) {
      _consume(_TT.lparen);
      final v = _expr(env);
      _consume(_TT.rparen);
      return v;
    }

    // Number literal
    if (t.type == _TT.num) {
      _consume();
      return double.parse(t.text);
    }

    // Identifier: variable, property access, or function call
    if (t.type == _TT.ident) {
      final name = _consume(_TT.ident);

      // Function call
      if (_cur.type == _TT.lparen) {
        _consume(_TT.lparen);
        final args = <dynamic>[];
        while (_cur.type != _TT.rparen && _cur.type != _TT.eof) {
          args.add(_expr(env));
          if (_cur.type == _TT.comma) _consume(_TT.comma);
        }
        _consume(_TT.rparen);
        return _callFn(name.text, args, name);
      }

      // Property access (e.g. start.x)
      if (_cur.type == _TT.dot) {
        _consume(_TT.dot);
        final prop = _consume(_TT.ident);
        final obj = _resolve(env, name);
        if (obj is _Point) {
          return switch (prop.text) {
            'x' => obj.x,
            'y' => obj.y,
            _ => throw _DslError(
                'Невідома властивість "${prop.text}" — доступні: .x, .y'),
          };
        }
        throw _DslError(
            '"${name.text}" не є Point — доступ до властивостей неможливий');
      }

      // Plain variable
      return _resolve(env, name);
    }

    throw _DslError('Неочікуваний токен "${t.text}"');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  dynamic _resolve(Map<String, dynamic> env, _Token name) {
    if (!env.containsKey(name.text)) {
      throw _DslError('Невідома змінна "${name.text}"');
    }
    return env[name.text];
  }

  double _num(dynamic v, _Token tok) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    throw _DslError('Очікується число, але отримано $v (${tok.text})');
  }

  void _req(String fn, List args, int count) {
    if (args.length != count) {
      throw _DslError(
          '$fn очікує $count аргумент(и), отримано ${args.length}');
    }
  }

  dynamic _callFn(String name, List<dynamic> args, _Token tok) {
    double n(int i) => _num(args[i], tok);
    void req(int c) => _req(name, args, c);

    switch (name) {
      // Trig
      case 'sin':    req(1); return math.sin(n(0));
      case 'cos':    req(1); return math.cos(n(0));
      case 'tan':    req(1); return math.tan(n(0));
      case 'asin':   req(1); return math.asin(n(0));
      case 'acos':   req(1); return math.acos(n(0));
      case 'atan':   req(1); return math.atan(n(0));
      case 'atan2':  req(2); return math.atan2(n(0), n(1));
      // Arithmetic
      case 'abs':    req(1); return n(0).abs();
      case 'sqrt':   req(1); return math.sqrt(n(0));
      case 'pow':    req(2); return math.pow(n(0), n(1)).toDouble();
      case 'min':    req(2); return math.min(n(0), n(1));
      case 'max':    req(2); return math.max(n(0), n(1));
      // Rounding
      case 'floor':  req(1); return n(0).floorToDouble();
      case 'ceil':   req(1); return n(0).ceilToDouble();
      case 'round':  req(1); return n(0).roundToDouble();
      // Interpolation
      case 'lerp':   req(3); return n(0) + (n(1) - n(0)) * n(2).clamp(0.0, 1.0);
      case 'clamp':  req(3); return n(0).clamp(n(1), n(2));
      // Easing
      case 'ease':   req(1); return _easeInOut(n(0));
      // Point constructor
      case 'Point':  req(2); return _Point(n(0), n(1));
      default:       throw _DslError('Невідома функція "$name"');
    }
  }

  double _easeInOut(double t) {
    final c = t.clamp(0.0, 1.0);
    return c < 0.5 ? 2 * c * c : 1 - math.pow(-2 * c + 2, 2) / 2;
  }
}

// ─── Autocomplete reference (used by the editor widget) ──────────────────────

class DslSymbol {
  final String name;
  final String signature; // e.g. "sin(x)"
  final String returns; // e.g. "Number"
  final String description;
  final String example;
  final DslSymbolKind kind;

  const DslSymbol({
    required this.name,
    required this.signature,
    required this.returns,
    required this.description,
    required this.example,
    required this.kind,
  });
}

enum DslSymbolKind { variable, constant, fn }

const kDslSymbols = <DslSymbol>[
  // ── Variables ──────────────────────────────────────────────────────────────
  DslSymbol(
    name: 'start',
    signature: 'start',
    returns: 'Point',
    kind: DslSymbolKind.variable,
    description: 'Стартова позиція логотипа (лівий верхній кут title bar).',
    example: 'start.x  // горизонтальна координата',
  ),
  DslSymbol(
    name: 'end',
    signature: 'end',
    returns: 'Point',
    kind: DslSymbolKind.variable,
    description: 'Цільова позиція логотипа (протилежний кут екрана).',
    example: 'end.y  // вертикальна координата',
  ),
  DslSymbol(
    name: 'screenWidth',
    signature: 'screenWidth',
    returns: 'Number',
    kind: DslSymbolKind.variable,
    description: 'Ширина екрана в логічних пікселях.',
    example: 'screenWidth / 2  // центр по горизонталі',
  ),
  DslSymbol(
    name: 'screenHeight',
    signature: 'screenHeight',
    returns: 'Number',
    kind: DslSymbolKind.variable,
    description: 'Висота екрана в логічних пікселях.',
    example: 'screenHeight * 0.5',
  ),
  DslSymbol(
    name: 't',
    signature: 't',
    returns: 'Number',
    kind: DslSymbolKind.variable,
    description: 'Прогрес анімації від 0.0 (початок) до 1.0 (кінець).',
    example: 'sin(t * PI * 4)  // 4 повних хвилі',
  ),
  // ── Constants ──────────────────────────────────────────────────────────────
  DslSymbol(
    name: 'PI',
    signature: 'PI',
    returns: 'Number',
    kind: DslSymbolKind.constant,
    description: 'Математична константа π ≈ 3.14159.',
    example: 'sin(t * PI * 2)',
  ),
  DslSymbol(
    name: 'E',
    signature: 'E',
    returns: 'Number',
    kind: DslSymbolKind.constant,
    description: 'Основа натурального логарифма e ≈ 2.71828.',
    example: 'pow(E, t)',
  ),
  // ── Trig functions ─────────────────────────────────────────────────────────
  DslSymbol(
    name: 'sin',
    signature: 'sin(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Синус кута x (в радіанах).',
    example: 'sin(t * PI * 6) * 80',
  ),
  DslSymbol(
    name: 'cos',
    signature: 'cos(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Косинус кута x (в радіанах).',
    example: 'cos(t * PI * 4) * 60',
  ),
  DslSymbol(
    name: 'tan',
    signature: 'tan(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Тангенс кута x (в радіанах).',
    example: 'tan(t * 0.5)',
  ),
  DslSymbol(
    name: 'atan2',
    signature: 'atan2(y, x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Арктангенс y/x, повертає кут у правильному квадранті.',
    example: 'atan2(dy, dx)',
  ),
  // ── Math functions ─────────────────────────────────────────────────────────
  DslSymbol(
    name: 'abs',
    signature: 'abs(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Абсолютне значення числа x.',
    example: 'abs(sin(t * PI))',
  ),
  DslSymbol(
    name: 'sqrt',
    signature: 'sqrt(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Квадратний корінь з x.',
    example: 'sqrt(t) * 100',
  ),
  DslSymbol(
    name: 'pow',
    signature: 'pow(x, exp)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'x у степені exp.',
    example: 'pow(t, 2)  // квадратична крива',
  ),
  DslSymbol(
    name: 'min',
    signature: 'min(a, b)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Мінімум з двох чисел.',
    example: 'min(x, screenWidth - 24)',
  ),
  DslSymbol(
    name: 'max',
    signature: 'max(a, b)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Максимум з двох чисел.',
    example: 'max(y, 0)',
  ),
  DslSymbol(
    name: 'floor',
    signature: 'floor(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Округлення вниз до цілого.',
    example: 'floor(t * 10) / 10  // ступінчастий рух',
  ),
  DslSymbol(
    name: 'ceil',
    signature: 'ceil(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Округлення вгору до цілого.',
    example: 'ceil(t * 5) * 20',
  ),
  DslSymbol(
    name: 'round',
    signature: 'round(x)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Округлення до найближчого цілого.',
    example: 'round(t * 10)',
  ),
  // ── Interpolation helpers ──────────────────────────────────────────────────
  DslSymbol(
    name: 'lerp',
    signature: 'lerp(a, b, t)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Лінійна інтерполяція між a і b за часом t (0–1).',
    example: 'lerp(start.x, end.x, t)',
  ),
  DslSymbol(
    name: 'clamp',
    signature: 'clamp(x, min, max)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'Обмежує x в діапазоні [min, max].',
    example: 'clamp(x, 0, screenWidth)',
  ),
  DslSymbol(
    name: 'ease',
    signature: 'ease(t)',
    returns: 'Number',
    kind: DslSymbolKind.fn,
    description: 'easeInOut — плавне прискорення та гальмування. t ∈ [0, 1].',
    example: 'lerp(start.x, end.x, ease(t))',
  ),
  // ── Output ────────────────────────────────────────────────────────────────
  DslSymbol(
    name: 'Point',
    signature: 'Point(x, y)',
    returns: 'Point',
    kind: DslSymbolKind.fn,
    description: 'Створює точку з координатами x, y. Обов\'язково у return.',
    example: 'return Point(x, y)',
  ),
];
