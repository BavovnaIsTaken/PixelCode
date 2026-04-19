/// Logo-path editor with two modes: block-based visual editor and a calm
/// text-script editor. Both represent the same program and round-trip
/// through parse/serialize on every edit.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_theme.dart';
import '../../services/logo_path_program.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Public widget
// ═══════════════════════════════════════════════════════════════════════════

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

enum _Mode { blocks, script }

class _LogoPathEditorState extends State<LogoPathEditor> {
  _Mode _mode = _Mode.blocks;

  // Source of truth for the blocks mode.
  List<LogoCommand> _commands = const [];

  // Script editor state (text controller + live parse error).
  late final TextEditingController _scriptCtrl;
  Timer? _scriptParseDebounce;
  String? _scriptError;

  // Last saved script — used to compute dirty state.
  late String _saved;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _saved = widget.script;
    _scriptCtrl = TextEditingController(text: widget.script);
    final parsed = parseLogoProgram(widget.script);
    _commands = parsed.error == null ? parsed.commands : const [];
    _scriptError = parsed.error;
    _scriptCtrl.addListener(_onScriptTextChanged);
  }

  @override
  void didUpdateWidget(covariant LogoPathEditor old) {
    super.didUpdateWidget(old);
    if (!_dirty && widget.script != old.script) {
      _saved = widget.script;
      _scriptCtrl.text = widget.script;
      final parsed = parseLogoProgram(widget.script);
      setState(() {
        _commands = parsed.error == null ? parsed.commands : _commands;
        _scriptError = parsed.error;
      });
    }
  }

  @override
  void dispose() {
    _scriptParseDebounce?.cancel();
    _scriptCtrl.removeListener(_onScriptTextChanged);
    _scriptCtrl.dispose();
    super.dispose();
  }

  // ── Sync plumbing ─────────────────────────────────────────────────────────

  void _onScriptTextChanged() {
    _scriptParseDebounce?.cancel();
    _scriptParseDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final parsed = parseLogoProgram(_scriptCtrl.text);
      setState(() {
        _scriptError = parsed.error;
        if (parsed.error == null) _commands = parsed.commands;
        _dirty = _scriptCtrl.text != _saved;
      });
    });
  }

  /// Called by block editor whenever commands change.
  void _setCommands(List<LogoCommand> next) {
    setState(() {
      _commands = next;
      final text = serializeLogoProgram(next);
      _scriptCtrl.removeListener(_onScriptTextChanged);
      _scriptCtrl.text = text;
      _scriptCtrl.addListener(_onScriptTextChanged);
      _scriptError = null;
      _dirty = text != _saved;
    });
  }

  // ── Save / reset ──────────────────────────────────────────────────────────

  void _save() {
    final text = _scriptCtrl.text;
    final error = validateLogoPathScript(text);
    if (error != null) {
      setState(() => _scriptError = error);
      return;
    }
    widget.onSaved(text);
    setState(() {
      _saved = text;
      _dirty = false;
    });
  }

  void _reset() {
    setState(() {
      _scriptCtrl.removeListener(_onScriptTextChanged);
      _scriptCtrl.text = kDefaultLogoPathScript;
      _scriptCtrl.addListener(_onScriptTextChanged);
      final parsed = parseLogoProgram(kDefaultLogoPathScript);
      _commands = parsed.commands;
      _scriptError = null;
      _saved = kDefaultLogoPathScript;
      _dirty = false;
    });
    widget.onSaved(kDefaultLogoPathScript);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 10),
        _buildModeSwitcher(),
        const SizedBox(height: 10),
        if (_mode == _Mode.blocks)
          _BlockEditor(
            commands: _commands,
            onChanged: _setCommands,
          )
        else
          _ScriptEditor(
            controller: _scriptCtrl,
            error: _scriptError,
          ),
        if (_scriptError != null && _mode == _Mode.blocks) ...[
          const SizedBox(height: 10),
          _ErrorBox(message: _scriptError!),
        ],
        const SizedBox(height: 12),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildHeader() {
    final c = context.appColors;
    return Row(
      children: [
        Icon(Icons.route_outlined, size: 16, color: c.accent),
        const SizedBox(width: 8),
        Text(
          'Шлях логотипа',
          style: TextStyle(
            color: c.textHigh,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(width: 10),
        if (_dirty)
          Text(
            'незбережено',
            style: TextStyle(
              color: c.accent,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    final c = context.appColors;
    Widget tab(String label, _Mode mode, IconData icon) {
      final selected = _mode == mode;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _mode = mode),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? c.accent.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? c.accent.withValues(alpha: 0.45)
                    : c.border.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 14,
                    color: selected ? c.accent : c.textMedium),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? c.textHigh : c.textMedium,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Блоки', _Mode.blocks, Icons.widgets_outlined),
        const SizedBox(width: 8),
        tab('Скрипт', _Mode.script, Icons.code),
      ],
    );
  }

  Widget _buildActionRow() {
    final c = context.appColors;
    return Row(
      children: [
        TextButton.icon(
          onPressed: _reset,
          icon: Icon(Icons.refresh, size: 15, color: c.textMedium),
          label: Text('Скинути',
              style: TextStyle(color: c.textMedium, fontSize: 12)),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _dirty ? _save : null,
          icon: const Icon(Icons.save_outlined, size: 15),
          label: const Text('Зберегти', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: c.accent.withValues(alpha: 0.18),
            disabledForegroundColor: c.textLow,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Script editor
// ═══════════════════════════════════════════════════════════════════════════

class _ScriptEditor extends StatelessWidget {
  final TextEditingController controller;
  final String? error;

  const _ScriptEditor({
    required this.controller,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final hasErr = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surfaceDim,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasErr
                  ? c.error.withValues(alpha: 0.6)
                  : c.border.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: TextField(
            controller: controller,
            maxLines: null,
            minLines: 8,
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 13,
              height: 1.5,
              color: c.textHigh,
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
            inputFormatters: const [],
          ),
        ),
        const SizedBox(height: 8),
        if (hasErr) _ErrorBox(message: error!) else _ScriptHint(),
      ],
    );
  }
}

class _ScriptHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    const tips = [
      'move right 100',
      'move down edge',
      'wait 0.5',
      'stamp trail   # або tile / dense / every 10',
      'repeat 3: … end',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: tips
          .map(
            (t) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: c.border.withValues(alpha: 0.4)),
              ),
              child: Text(
                t,
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 11,
                  color: c.textMedium,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: c.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 15, color: c.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: c.error,
                fontSize: 12,
                fontFamily: 'Courier New',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Block editor
// ═══════════════════════════════════════════════════════════════════════════

class _BlockEditor extends StatelessWidget {
  final List<LogoCommand> commands;
  final ValueChanged<List<LogoCommand>> onChanged;

  const _BlockEditor({required this.commands, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.all(10),
      child: _BlockList(
        commands: commands,
        path: const [],
        onChanged: onChanged,
      ),
    );
  }
}

/// Renders a list of commands. `path` is the index-path in the root tree,
/// used so nested edits can replace the right sub-list immutably.
class _BlockList extends StatelessWidget {
  final List<LogoCommand> commands;
  final List<int> path;
  final ValueChanged<List<LogoCommand>> onChanged;

  const _BlockList({
    required this.commands,
    required this.path,
    required this.onChanged,
  });

  List<LogoCommand> _replaceAt(int idx, LogoCommand? next) {
    final out = List<LogoCommand>.from(commands);
    if (next == null) {
      out.removeAt(idx);
    } else {
      out[idx] = next;
    }
    return out;
  }

  List<LogoCommand> _moveItem(int idx, int delta) {
    final out = List<LogoCommand>.from(commands);
    final j = idx + delta;
    if (j < 0 || j >= out.length) return commands;
    final item = out.removeAt(idx);
    out.insert(j, item);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final isRoot = path.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (commands.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              isRoot
                  ? 'Ще немає блоків. Додай перший знизу.'
                  : 'Порожньо всередині repeat.',
              style: TextStyle(
                color: c.textLow,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        for (var i = 0; i < commands.length; i++)
          _BlockRow(
            key: ValueKey([...path, i].join('.')),
            command: commands[i],
            canMoveUp: i > 0,
            canMoveDown: i < commands.length - 1,
            onChange: (c) => onChanged(_replaceAt(i, c)),
            onDelete: () => onChanged(_replaceAt(i, null)),
            onMoveUp: () => onChanged(_moveItem(i, -1)),
            onMoveDown: () => onChanged(_moveItem(i, 1)),
            onBodyChanged: (newBody) {
              final cmd = commands[i];
              if (cmd is RepeatCommand) {
                onChanged(_replaceAt(
                    i, RepeatCommand(count: cmd.count, body: newBody)));
              }
            },
          ),
        const SizedBox(height: 4),
        _AddBlockButton(
          onPick: (cmd) => onChanged([...commands, cmd]),
        ),
      ],
    );
  }
}

class _BlockRow extends StatelessWidget {
  final LogoCommand command;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<LogoCommand> onChange;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<List<LogoCommand>> onBodyChanged;

  const _BlockRow({
    super.key,
    required this.command,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onChange,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onBodyChanged,
  });

  Color _accentFor(BuildContext context) {
    final c = context.appColors;
    return switch (command) {
      MoveCommand() => c.accent,
      WaitCommand() => c.textMedium,
      StampCommand() => c.gold,
      RepeatCommand() => c.success,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final accent = _accentFor(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(
              color: c.border.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: accent),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                        child: Row(
                          children: [
                            Expanded(child: _buildBody(context)),
                            _IconAction(
                              icon: Icons.keyboard_arrow_up,
                              enabled: canMoveUp,
                              onTap: onMoveUp,
                              tooltip: 'Вгору',
                            ),
                            _IconAction(
                              icon: Icons.keyboard_arrow_down,
                              enabled: canMoveDown,
                              onTap: onMoveDown,
                              tooltip: 'Вниз',
                            ),
                            _IconAction(
                              icon: Icons.close,
                              enabled: true,
                              onTap: onDelete,
                              tooltip: 'Видалити',
                            ),
                          ],
                        ),
                      ),
                      if (command is RepeatCommand)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                          child: _BlockList(
                            commands: (command as RepeatCommand).body,
                            path: const [0],
                            onChanged: onBodyChanged,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (command) {
      case MoveCommand m:
        return _MoveBody(
          cmd: m,
          onChange: onChange,
        );
      case WaitCommand w:
        return _WaitBody(cmd: w, onChange: onChange);
      case StampCommand s:
        return _StampBody(cmd: s, onChange: onChange);
      case RepeatCommand r:
        return _RepeatHeader(cmd: r, onChange: onChange);
    }
  }
}

// ── Block bodies ────────────────────────────────────────────────────────────

class _MoveBody extends StatelessWidget {
  final MoveCommand cmd;
  final ValueChanged<LogoCommand> onChange;

  const _MoveBody({required this.cmd, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BlockLabel('Рухати'),
        _DirectionDropdown(
          value: cmd.dir,
          onChanged: (d) => onChange(cmd.copyWith(dir: d)),
        ),
        _SegmentedToggle(
          leftLabel: 'на',
          rightLabel: 'до краю',
          leftSelected: !cmd.untilEdge,
          onTap: (left) {
            if (left) {
              onChange(
                  cmd.copyWith(amount: cmd.amount ?? 100, untilEdge: false));
            } else {
              onChange(cmd.copyWith(untilEdge: true));
            }
          },
        ),
        if (!cmd.untilEdge)
          _NumberField(
            value: cmd.amount ?? 100,
            onChanged: (v) => onChange(cmd.copyWith(amount: v)),
            suffix: 'px',
            width: 72,
          ),
      ],
    );
  }
}

class _WaitBody extends StatelessWidget {
  final WaitCommand cmd;
  final ValueChanged<LogoCommand> onChange;

  const _WaitBody({required this.cmd, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BlockLabel('Пауза'),
        _NumberField(
          value: cmd.seconds,
          onChanged: (v) => onChange(WaitCommand(v)),
          suffix: 'с',
          width: 72,
          allowDecimal: true,
        ),
      ],
    );
  }
}

class _RepeatHeader extends StatelessWidget {
  final RepeatCommand cmd;
  final ValueChanged<LogoCommand> onChange;

  const _RepeatHeader({required this.cmd, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BlockLabel('Повторити'),
        _NumberField(
          value: cmd.count.toDouble(),
          onChanged: (v) => onChange(RepeatCommand(
            count: v.toInt().clamp(1, 999),
            body: cmd.body,
          )),
          suffix: 'раз',
          width: 78,
        ),
      ],
    );
  }
}

class _StampBody extends StatelessWidget {
  final StampCommand cmd;
  final ValueChanged<LogoCommand> onChange;

  const _StampBody({required this.cmd, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget preset(String label, StampPreset p) {
      final selected = cmd.preset == p;
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChange(StampCommand.preset(p)),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? c.gold.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? c.gold.withValues(alpha: 0.6)
                  : c.border.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: selected ? c.textHigh : c.textMedium,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    final isCustom = cmd.preset == StampPreset.custom;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _BlockLabel('Слід'),
        preset('Плитка', StampPreset.tile),
        preset('Слід', StampPreset.trail),
        preset('Щільний', StampPreset.dense),
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (!isCustom) {
              onChange(StampCommand.custom(cmd.spacing));
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isCustom ? c.gold.withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isCustom
                    ? c.gold.withValues(alpha: 0.6)
                    : c.border.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'Точно',
              style: TextStyle(
                fontSize: 11.5,
                color: isCustom ? c.textHigh : c.textMedium,
                fontWeight:
                    isCustom ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
        if (isCustom)
          _NumberField(
            value: cmd.spacing,
            onChanged: (v) => onChange(StampCommand.custom(v.clamp(1, 300))),
            suffix: 'px',
            width: 72,
          ),
      ],
    );
  }
}

// ── Atoms ──────────────────────────────────────────────────────────────────

class _BlockLabel extends StatelessWidget {
  final String text;
  const _BlockLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: context.appColors.textHigh,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _DirectionDropdown extends StatelessWidget {
  final MoveDir value;
  final ValueChanged<MoveDir> onChanged;
  const _DirectionDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MoveDir>(
          value: value,
          isDense: true,
          style: TextStyle(color: c.textHigh, fontSize: 12),
          dropdownColor: c.surface,
          items: const [
            DropdownMenuItem(value: MoveDir.right, child: Text('→ праворуч')),
            DropdownMenuItem(value: MoveDir.left, child: Text('← ліворуч')),
            DropdownMenuItem(value: MoveDir.up, child: Text('↑ вгору')),
            DropdownMenuItem(value: MoveDir.down, child: Text('↓ вниз')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final String leftLabel;
  final String rightLabel;
  final bool leftSelected;
  final ValueChanged<bool> onTap;

  const _SegmentedToggle({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    Widget seg(String label, bool isLeft) {
      final selected = isLeft == leftSelected;
      return InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onTap(isLeft),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                selected ? c.accent.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: selected ? c.textHigh : c.textMedium,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(leftLabel, true),
          seg(rightLabel, false),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String suffix;
  final double width;
  final bool allowDecimal;

  const _NumberField({
    required this.value,
    required this.onChanged,
    required this.suffix,
    required this.width,
    this.allowDecimal = false,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toString();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final parsed = double.tryParse(_ctrl.text.replaceAll(',', '.'));
    if (parsed != null) {
      widget.onChanged(parsed);
    } else {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        style: TextStyle(
          color: c.textHigh,
          fontSize: 12,
          fontFamily: 'Courier New',
        ),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(
            decimal: widget.allowDecimal),
        inputFormatters: widget.allowDecimal
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          suffixText: widget.suffix,
          suffixStyle:
              TextStyle(color: c.textLow, fontSize: 10),
          filled: true,
          fillColor: c.surfaceDim,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: c.border.withValues(alpha: 0.4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: c.border.withValues(alpha: 0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                BorderSide(color: c.accent, width: 1.2),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String tooltip;

  const _IconAction({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 16),
        color: c.textMedium,
        disabledColor: c.textLow.withValues(alpha: 0.4),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
        splashRadius: 16,
      ),
    );
  }
}

class _AddBlockButton extends StatelessWidget {
  final ValueChanged<LogoCommand> onPick;
  const _AddBlockButton({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return PopupMenuButton<String>(
      tooltip: 'Додати блок',
      position: PopupMenuPosition.under,
      color: c.surface,
      itemBuilder: (_) => [
        _menuItem('move', Icons.arrow_forward, 'Рух', c),
        _menuItem('wait', Icons.pause, 'Пауза', c),
        _menuItem('stamp', Icons.grain, 'Слід', c),
        _menuItem('repeat', Icons.refresh, 'Повторити', c),
      ],
      onSelected: (kind) {
        switch (kind) {
          case 'move':
            onPick(const MoveCommand(dir: MoveDir.right, amount: 100));
          case 'wait':
            onPick(const WaitCommand(0.5));
          case 'stamp':
            onPick(StampCommand.preset(StampPreset.trail));
          case 'repeat':
            onPick(const RepeatCommand(count: 2, body: []));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: c.accent.withValues(alpha: 0.4),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 16, color: c.accent),
            const SizedBox(width: 6),
            Text(
              'Додати блок',
              style: TextStyle(
                color: c.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, ThemeColors c) {
    return PopupMenuItem(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 15, color: c.textMedium),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: c.textHigh, fontSize: 12)),
        ],
      ),
    );
  }
}
