/// Logo-path DSL editor: syntax highlighting, autocomplete, save/reset/info.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/logo_path_dsl.dart';

// ─── Public widget ─────────────────────────────────────────────────────────────

class LogoPathEditor extends StatefulWidget {
  final String script;
  final ValueChanged<String> onSaved;

  const LogoPathEditor({
    super.key,
    required this.script,
    required this.onSaved,
  });

  @override
  State<LogoPathEditor> createState() => _LogoPathEditorState();
}

class _LogoPathEditorState extends State<LogoPathEditor> {
  late final _SyntaxController _ctrl;
  late final FocusNode _focus;
  final _layerLink = LayerLink();
  OverlayEntry? _autocompleteOverlay;

  String? _validationError;
  bool _dirty = false; // script differs from saved value

  // Autocomplete state
  List<DslSymbol> _suggestions = [];
  int _selectedSuggestion = 0;

  static const _accent = Color(0xFF00C0D1);

  @override
  void initState() {
    super.initState();
    _ctrl = _SyntaxController(widget.script);
    _focus = FocusNode();
    _ctrl.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant LogoPathEditor old) {
    super.didUpdateWidget(old);
    if (!_dirty && widget.script != old.script) {
      _ctrl.text = widget.script;
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _ctrl.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Listeners ───────────────────────────────────────────────────────────────

  void _onTextChanged() {
    setState(() {
      _dirty = _ctrl.text != widget.script;
      _validationError = null;
    });
    _updateAutocomplete();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _removeOverlay();
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────────

  String _wordAtCursor() {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    if (!sel.isValid || sel.baseOffset < 0) return '';
    final pos = sel.baseOffset.clamp(0, text.length);
    int start = pos;
    while (start > 0 && _isWordChar(text[start - 1])) { start--; }
    return text.substring(start, pos);
  }

  bool _isWordChar(String c) => RegExp(r'[a-zA-Z0-9_]').hasMatch(c);

  void _updateAutocomplete() {
    final word = _wordAtCursor();
    if (word.isEmpty) {
      _removeOverlay();
      return;
    }
    final lower = word.toLowerCase();
    final matches = kDslSymbols
        .where((s) => s.name.toLowerCase().startsWith(lower) && s.name != word)
        .toList();

    if (matches.isEmpty) {
      _removeOverlay();
      return;
    }

    setState(() {
      _suggestions = matches;
      _selectedSuggestion = 0;
    });

    if (_autocompleteOverlay == null) {
      _showOverlay();
    } else {
      _autocompleteOverlay!.markNeedsBuild();
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    _autocompleteOverlay = OverlayEntry(builder: (_) => _buildOverlay());
    overlay.insert(_autocompleteOverlay!);
  }

  void _removeOverlay() {
    _autocompleteOverlay?.remove();
    _autocompleteOverlay = null;
  }

  void _acceptSuggestion(DslSymbol sym) {
    final text = _ctrl.text;
    final sel = _ctrl.selection;
    if (!sel.isValid) return;

    final pos = sel.baseOffset.clamp(0, text.length);
    int start = pos;
    while (start > 0 && _isWordChar(text[start - 1])) { start--; }

    // For functions insert "name(" and place cursor inside parens
    final insert = sym.kind == DslSymbolKind.fn ? '${sym.name}(' : sym.name;
    final newText = text.replaceRange(start, pos, insert);
    final cursorPos = start + insert.length;

    _ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPos),
    );
    _removeOverlay();
    _focus.requestFocus();
  }

  // ── Save / Reset ────────────────────────────────────────────────────────────

  void _save() {
    final error = validateLogoPathScript(_ctrl.text);
    if (error != null) {
      setState(() => _validationError = error);
      return;
    }
    widget.onSaved(_ctrl.text);
    setState(() {
      _dirty = false;
      _validationError = null;
    });
  }

  void _reset() {
    _ctrl.text = kDefaultLogoPathScript;
    widget.onSaved(kDefaultLogoPathScript);
    setState(() {
      _dirty = false;
      _validationError = null;
    });
  }

  // ── Keyboard handling for autocomplete navigation ───────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_suggestions.isEmpty || _autocompleteOverlay == null) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedSuggestion =
            (_selectedSuggestion + 1) % _suggestions.length;
      });
      _autocompleteOverlay!.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedSuggestion =
            (_selectedSuggestion - 1 + _suggestions.length) %
                _suggestions.length;
      });
      _autocompleteOverlay!.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedSuggestion < _suggestions.length) {
        _acceptSuggestion(_suggestions[_selectedSuggestion]);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(),
        const SizedBox(height: 8),
        CompositedTransformTarget(
          link: _layerLink,
          child: _buildEditor(),
        ),
        if (_validationError != null) ...[
          const SizedBox(height: 8),
          _buildError(_validationError!),
        ],
        const SizedBox(height: 12),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        Text(
          'Алгоритм позиції',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        _InfoButton(),
      ],
    );
  }

  Widget _buildEditor() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focus.hasFocus
              ? _accent.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Line numbers
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _LineNumbers(controller: _ctrl),
          ),
          // Code editor
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 10, 10, 10),
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: null,
                minLines: 8,
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 12.5,
                  height: 1.55,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 14, color: Colors.red.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red.withValues(alpha: 0.9),
                fontSize: 11.5,
                fontFamily: 'Courier New',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        // Reset
        OutlinedButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded, size: 14),
          label: const Text('Скинути', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.45),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        const Spacer(),
        // Save
        FilledButton.icon(
          onPressed: _dirty ? _save : null,
          icon: const Icon(Icons.check_rounded, size: 14),
          label: const Text('Зберегти', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: _accent.withValues(alpha: 0.15),
            disabledForegroundColor: _accent.withValues(alpha: 0.35),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );
  }

  // ── Autocomplete overlay ──────────────────────────────────────────────────

  Widget _buildOverlay() {
    // snapshot current state so the overlay builder is pure
    final suggestions = List<DslSymbol>.from(_suggestions);
    final selected = _selectedSuggestion.clamp(0, math.max(0, suggestions.length - 1)).toInt();
    if (suggestions.isEmpty) return const SizedBox.shrink();

    const itemH = 36.0;
    const docWidth = 220.0;
    final listH = (suggestions.length * itemH).clamp(0.0, 200.0).toDouble();
    final sym = suggestions[selected];

    return Positioned(
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(40, 0), // align to code area
        child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Suggestion list
                Container(
                  width: 200,
                  height: listH,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1F27),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 12)
                    ],
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: suggestions.length,
                    itemExtent: itemH,
                    itemBuilder: (_, i) => _SuggestionItem(
                      sym: suggestions[i],
                      isSelected: i == selected,
                      onTap: () => _acceptSuggestion(suggestions[i]),
                      onHover: (hovered) {
                        if (hovered) {
                          setState(() => _selectedSuggestion = i);
                          _autocompleteOverlay?.markNeedsBuild();
                        }
                      },
                    ),
                  ),
                ),
                // Doc panel for selected symbol
                Container(
                  width: docWidth,
                  constraints: const BoxConstraints(minHeight: 80),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17181E),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    border: Border(
                      top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      right: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: _DocPanel(sym: sym),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Line numbers ─────────────────────────────────────────────────────────────

class _LineNumbers extends StatefulWidget {
  final TextEditingController controller;
  const _LineNumbers({required this.controller});

  @override
  State<_LineNumbers> createState() => _LineNumbersState();
}

class _LineNumbersState extends State<_LineNumbers> {
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    _update();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final count = '\n'.allMatches(widget.controller.text).length + 1;
    if (count != _lineCount) setState(() => _lineCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      padding: const EdgeInsets.fromLTRB(0, 10, 6, 10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          _lineCount,
          (i) => SizedBox(
            height: 12.5 * 1.55, // fontSize * lineHeight
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 11,
                height: 1.55,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Syntax-highlighting text controller ────────────────────────────────────

class _SyntaxController extends TextEditingController {
  _SyntaxController(String initialText) : super(text: initialText);

  static const _keywords = {'val', 'return'};
  static const _builtinVars = {
    'start', 'end', 'screenWidth', 'screenHeight', 't', 'PI', 'E'
  };
  static final _builtinFns = kDslSymbols
      .where((s) => s.kind == DslSymbolKind.fn)
      .map((s) => s.name)
      .toSet();

  static const _cKeyword = Color(0xFF569CD6);  // blue — val/return
  static const _cVar = Color(0xFF4EC9B0);      // teal — builtin vars
  static const _cFn = Color(0xFFDCDCAA);       // yellow — functions
  static const _cNumber = Color(0xFFB5CEA8);   // green — numbers
  static const _cComment = Color(0xFF6A9955);  // green-gray — comments
  static const _cProp = Color(0xFF9CDCFE);     // light blue — .x .y
  static const _cOperator = Color(0xFFD4D4D4); // light — operators
  static const _cDefault = Color(0xFFCCCCCC);  // default text

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <TextSpan>[];
    final src = text;
    int i = 0;

    void push(String txt, Color color) {
      if (txt.isEmpty) return;
      spans.add(TextSpan(
        text: txt,
        style: TextStyle(
          fontFamily: 'Courier New',
          fontSize: 12.5,
          height: 1.55,
          color: color,
        ),
      ));
    }

    bool isDigit(String c) {
      final code = c.codeUnitAt(0);
      return code >= 48 && code <= 57;
    }

    bool isAlpha(String c) => RegExp(r'[a-zA-Z_]').hasMatch(c);

    while (i < src.length) {
      final ch = src[i];

      // Line comment
      if (ch == '/' && i + 1 < src.length && src[i + 1] == '/') {
        final start = i;
        while (i < src.length && src[i] != '\n') { i++; }
        push(src.substring(start, i), _cComment);
        continue;
      }

      // Number
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
        push(src.substring(start, i), _cNumber);
        continue;
      }

      // Identifier / keyword
      if (isAlpha(ch)) {
        final start = i;
        while (i < src.length && (isAlpha(src[i]) || isDigit(src[i]))) { i++; }
        final word = src.substring(start, i);

        // Check what follows for property access coloring
        final isPropAccess =
            start > 0 && src[start - 1] == '.';

        Color color;
        if (isPropAccess) {
          color = _cProp;
        } else if (_keywords.contains(word)) {
          color = _cKeyword;
        } else if (_builtinVars.contains(word)) {
          color = _cVar;
        } else if (_builtinFns.contains(word)) {
          // Only color as function if next non-space is '('
          int j = i;
          while (j < src.length && src[j] == ' ') { j++; }
          color = (j < src.length && src[j] == '(') ? _cFn : _cDefault;
        } else {
          color = _cDefault;
        }
        push(word, color);
        continue;
      }

      // Operators & punctuation
      const operators = {'+', '-', '*', '/', '%', '=', '(', ')', ',', '.'};
      if (operators.contains(ch)) {
        push(ch, _cOperator);
        i++;
        continue;
      }

      // Whitespace / newlines
      push(ch, _cDefault);
      i++;
    }

    return TextSpan(children: spans);
  }
}

// ─── Suggestion item ─────────────────────────────────────────────────────────

class _SuggestionItem extends StatelessWidget {
  final DslSymbol sym;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _SuggestionItem({
    required this.sym,
    required this.isSelected,
    required this.onTap,
    required this.onHover,
  });

  static const _kindColor = {
    DslSymbolKind.fn: Color(0xFFDCDCAA),
    DslSymbolKind.variable: Color(0xFF4EC9B0),
    DslSymbolKind.constant: Color(0xFF9CDCFE),
  };

  static const _kindLabel = {
    DslSymbolKind.fn: 'fn',
    DslSymbolKind.variable: 'var',
    DslSymbolKind.constant: 'const',
  };

  @override
  Widget build(BuildContext context) {
    final color = _kindColor[sym.kind]!;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: isSelected
              ? const Color(0xFF00C0D1).withValues(alpha: 0.15)
              : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 34,
                alignment: Alignment.centerLeft,
                child: Text(
                  _kindLabel[sym.kind]!,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 9,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  sym.signature,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Doc panel (shown in autocomplete) ───────────────────────────────────────

class _DocPanel extends StatelessWidget {
  final DslSymbol sym;
  const _DocPanel({required this.sym});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Signature
        Text(
          sym.signature,
          style: const TextStyle(
            fontFamily: 'Courier New',
            fontSize: 11.5,
            color: Color(0xFFDCDCAA),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '→ ${sym.returns}',
          style: TextStyle(
            fontFamily: 'Courier New',
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sym.description,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.65),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            sym.example,
            style: const TextStyle(
              fontFamily: 'Courier New',
              fontSize: 10.5,
              color: Color(0xFF6A9955),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Info button + reference sheet ───────────────────────────────────────────

class _InfoButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Довідник DSL',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _showReference(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  void _showReference(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _ReferenceDialog(),
    );
  }
}

// ─── Reference dialog ────────────────────────────────────────────────────────

class _ReferenceDialog extends StatelessWidget {
  const _ReferenceDialog();

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<DslSymbol>>{
      'Змінні': kDslSymbols
          .where((s) => s.kind == DslSymbolKind.variable)
          .toList(),
      'Константи': kDslSymbols
          .where((s) => s.kind == DslSymbolKind.constant)
          .toList(),
      'Тригонометрія': kDslSymbols
          .where((s) => s.kind == DslSymbolKind.fn)
          .where((s) =>
              {'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2'}
                  .contains(s.name))
          .toList(),
      'Математика': kDslSymbols
          .where((s) => s.kind == DslSymbolKind.fn)
          .where((s) =>
              {'abs', 'sqrt', 'pow', 'min', 'max', 'floor', 'ceil', 'round'}
                  .contains(s.name))
          .toList(),
      'Інтерполяція': kDslSymbols
          .where((s) => s.kind == DslSymbolKind.fn)
          .where((s) =>
              {'lerp', 'clamp', 'ease'}.contains(s.name))
          .toList(),
      'Вивід': kDslSymbols
          .where((s) => s.name == 'Point')
          .toList(),
    };

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 540,
          constraints: const BoxConstraints(maxHeight: 580),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 24)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded,
                        size: 16, color: Color(0xFF00C0D1)),
                    const SizedBox(width: 8),
                    const Text(
                      'Довідник DSL',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.4)),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
              Divider(
                  color: Colors.white.withValues(alpha: 0.06), height: 16),
              // Syntax hint
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '// Оголошення змінної\nval name = expression\n\n'
                    '// Повернення позиції (обов\'язково)\nreturn Point(x, y)',
                    style: TextStyle(
                      fontFamily: 'Courier New',
                      fontSize: 11.5,
                      color: Color(0xFF6A9955),
                      height: 1.6,
                    ),
                  ),
                ),
              ),
              // Scrollable reference list
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: groups.entries
                        .map((entry) => _RefGroup(
                            title: entry.key, symbols: entry.value))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefGroup extends StatelessWidget {
  final String title;
  final List<DslSymbol> symbols;
  const _RefGroup({required this.title, required this.symbols});

  @override
  Widget build(BuildContext context) {
    if (symbols.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.3),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        ...symbols.map((s) => _RefRow(sym: s)),
      ],
    );
  }
}

class _RefRow extends StatelessWidget {
  final DslSymbol sym;
  const _RefRow({required this.sym});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Signature chip
          Container(
            width: 180,
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sym.signature,
              style: const TextStyle(
                fontFamily: 'Courier New',
                fontSize: 11,
                color: Color(0xFFDCDCAA),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Description + example
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sym.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sym.example,
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 10,
                    color: Color(0xFF6A9955),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
