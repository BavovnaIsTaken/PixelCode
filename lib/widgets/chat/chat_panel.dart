import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/agent_message.dart';
import '../../providers/agent_provider.dart';

/// Parses numbered choice options from agent text.
/// Returns a list of choice labels if 2+ consecutive items starting from 1 are found.
List<String>? _extractChoices(String text) {
  final pattern = RegExp(r'(?:^|\n)\s*(\d+)[.)]\s+(.+)', multiLine: true);
  final matches = pattern.allMatches(text).toList();
  if (matches.length < 2) return null;
  final numbers = matches.map((m) => int.tryParse(m.group(1)!) ?? 0).toList();
  if (numbers.first != 1) return null;
  for (int i = 1; i < numbers.length; i++) {
    if (numbers[i] != numbers[i - 1] + 1) return null;
  }
  return matches.map((m) => m.group(2)!.trim()).toList();
}

String _agentNickname(String id) => switch (id) {
      'manager' => 'Капітан',
      'tech-lead' => 'Архітект',
      'coder' => 'Майстер',
      'reviewer' => 'Детектив',
      'tester' => 'Крашер',
      'security' => 'Страж',
      'ui-ux-designer' => 'Піксельник',
      _ => id,
    };

class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final FocusNode _focusNode;
  bool _autoScroll = true;

  String _lastAgentId = '';
  final List<Uint8List> _attachedImages = [];
  bool _applyingRemoteUpdate = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          _send();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _controller.addListener(_onInputChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _onInputChanged() {
    if (_applyingRemoteUpdate) return;
    ref.read(wsServiceProvider).sendInputText(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_onInputChanged);
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 40;
    if (_autoScroll && !atBottom) {
      setState(() => _autoScroll = false);
    } else if (!_autoScroll && atBottom) {
      setState(() => _autoScroll = true);
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedImages.isEmpty) return;
    ref
        .read(chatProvider.notifier)
        .sendMessage(text, images: List.of(_attachedImages));
    _controller.clear();
    setState(() => _attachedImages.clear());
    ref.read(wsServiceProvider).sendInputText('');
    ref.read(remoteInputTextProvider.notifier).clear();
    _focusNode.requestFocus();
    setState(() => _autoScroll = true);
    _scrollToBottom();
  }

  Future<void> _pickImages() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
      uniformTypeIdentifiers: ['public.image'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;
    final bytes = await Future.wait(files.map((f) => f.readAsBytes()));
    setState(() => _attachedImages.addAll(bytes));
  }

  Future<void> _pasteImage() async {
    // Pasteboard image paste is desktop-only (pasteboard package removed — iOS crash)
  }

  void _removeImage(int index) {
    setState(() => _attachedImages.removeAt(index));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentAgent = ref.watch(selectedAgentProvider);
    final messages = ref.watch(chatProvider);

    if (_lastAgentId != currentAgent) {
      _lastAgentId = currentAgent;
      _autoScroll = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    ref.listen(chatProvider, (prev, next) {
      if (_autoScroll) _scrollToBottom();
    });

    ref.listen(remoteInputTextProvider, (prev, next) {
      if (next == _controller.text) return;
      _applyingRemoteUpdate = true;
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _applyingRemoteUpdate = false;
    });

    return Container(
      color: const Color(0xFF0E0E11),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.chat_outlined, color: Color(0xFF00C0D1), size: 18),
                const SizedBox(width: 8),
                Text(
                  _agentNickname(ref.watch(selectedAgentProvider)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _BypassToggle(),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState()
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) =>
                            _ChatBubble(message: messages[index]),
                      ),
                      if (!_autoScroll)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _autoScroll = true);
                              _scrollToBottom();
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1F27),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF00C0D1),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          // Input
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final workDir = ref.watch(workingDirectoryProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'Почніть розмову',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 14,
            ),
          ),
          if (workDir != null) ...[
            const SizedBox(height: 12),
            Tooltip(
              message: workDir,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      workDir.split('/').last,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Attached image previews
          if (_attachedImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachedImages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _attachedImages[index],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attach image from file
                Tooltip(
                  message: 'Додати зображення',
                  child: IconButton(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.attach_file_rounded),
                    color: Colors.white.withValues(alpha: 0.4),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
                // Paste image from clipboard
                Tooltip(
                  message: 'Вставити зображення з буфера',
                  child: IconButton(
                    onPressed: _pasteImage,
                    icon: const Icon(Icons.content_paste_rounded),
                    color: Colors.white.withValues(alpha: 0.4),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: MediaQuery.of(context).size.width >= 600,
                    maxLines: 4,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText:
                          'Повідомлення ${_agentNickname(ref.watch(selectedAgentProvider))}...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0E0E11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF00C0D1),
                          width: 1,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                  color: const Color(0xFF00C0D1),
                  iconSize: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends ConsumerWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == ChatRole.user;
    final choices =
        (!isUser && !message.isStreaming) ? _extractChoices(message.text) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF00D4E7), Color(0xFF00A5B4)],
                ),
              ),
              child: const Icon(Icons.psychology, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF00C0D1).withValues(alpha: 0.15)
                        : const Color(0xFF1E1F27),
                    borderRadius: BorderRadius.circular(12).copyWith(
                      bottomRight: isUser ? const Radius.circular(4) : null,
                      bottomLeft: !isUser ? const Radius.circular(4) : null,
                    ),
                    border: Border.all(
                      color: isUser
                          ? const Color(0xFF00C0D1).withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.imageBase64s.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: message.imageBase64s.map((b64) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(b64),
                                  width: 180,
                                  height: 130,
                                  fit: BoxFit.cover,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      if (message.text.isNotEmpty)
                        SelectableText(
                          message.text,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      if (message.isStreaming)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _TypingDots(),
                        ),
                    ],
                  ),
                ),
                // Choice buttons below the bubble
                if (choices != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: choices.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final label = entry.value;
                      return _ChoiceButton(
                        label: '$idx. $label',
                        onTap: () => ref
                            .read(chatProvider.notifier)
                            .sendMessage('$idx'),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 36),
        ],
      ),
    );
  }
}

// ─── Choice Button ────────────────────────────────────────────────────────────

class _ChoiceButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _ChoiceButton({required this.label, required this.onTap});

  @override
  State<_ChoiceButton> createState() => _ChoiceButtonState();
}

class _ChoiceButtonState extends State<_ChoiceButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _pressed
              ? const Color(0xFF00C0D1).withValues(alpha: 0.2)
              : const Color(0xFF1E1F27),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _pressed
                ? const Color(0xFF00C0D1)
                : const Color(0xFF00C0D1).withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: _pressed
                ? const Color(0xFF00C0D1)
                : const Color(0xFF00C0D1).withValues(alpha: 0.8),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─── Bypass Permissions Toggle ───────────────────────────────────────────────

class _BypassToggle extends ConsumerWidget {
  const _BypassToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(bypassPermissionsProvider);
    return Tooltip(
      message: enabled ? 'Режим "Без обмежень" увімкнено' : 'Вмикнути режим "Без обмежень"',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Без обмежень',
            style: TextStyle(
              color: enabled
                  ? const Color(0xFF00C0D1)
                  : Colors.white.withValues(alpha: 0.35),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          _BoatSwitch(
            value: enabled,
            onChanged: (val) {
              ref.read(bypassPermissionsProvider.notifier).state = val;
              ref.read(wsServiceProvider).setBypassPermissions(val);
            },
          ),
        ],
      ),
    );
  }
}

// ─── Boat Switch ─────────────────────────────────────────────────────────────

class _BoatSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BoatSwitch({required this.value, required this.onChanged});

  @override
  State<_BoatSwitch> createState() => _BoatSwitchState();
}

class _BoatSwitchState extends State<_BoatSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: widget.value ? 1.0 : 0.0,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void didUpdateWidget(_BoatSwitch old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      widget.value ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = _anim.value;
          final onColor = const Color(0xFF00C0D1);
          const offBg = Color(0xFF1A1B24);
          final trackColor = Color.lerp(offBg, onColor.withValues(alpha: 0.2), t)!;
          final borderColor =
              Color.lerp(Colors.white.withValues(alpha: 0.15), onColor, t)!;

          return Container(
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: t > 0.3
                  ? [
                      BoxShadow(
                        color: onColor.withValues(alpha: 0.35 * t),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                // Tick marks on the track
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      4,
                      (_) => Container(
                        width: 1,
                        height: 10,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ),
                // Knob — slides from left to right
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  left: widget.value ? 22 : 2,
                  top: 2,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: t > 0.5
                            ? [const Color(0xFF00D4E7), const Color(0xFF0099A8)]
                            : [
                                const Color(0xFF4A4B5A),
                                const Color(0xFF2E2F3D),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                        if (t > 0.5)
                          BoxShadow(
                            color: const Color(0xFF00C0D1)
                                .withValues(alpha: 0.6 * t),
                            blurRadius: 4,
                          ),
                      ],
                    ),
                    // Ridges on the knob
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (_) => Container(
                          width: 10,
                          height: 1,
                          margin: const EdgeInsets.symmetric(vertical: 1),
                          color: Colors.white.withValues(alpha: t > 0.5 ? 0.5 : 0.2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final opacity =
                ((_controller.value + delay) % 1.0 < 0.5) ? 1.0 : 0.3;
            return Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00C0D1).withValues(alpha: opacity),
              ),
            );
          }),
        );
      },
    );
  }
}
