import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/agent_message.dart';
import '../../models/app_theme.dart';
import '../../providers/agent_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/clipboard_service.dart';
import '../../services/facilitator_session_service.dart';
import 'board_added_bubble.dart';
import 'message_decorations.dart';
import 'send_button.dart';
import 'thread_widget.dart';

/// Parses numbered choice options from agent text.
/// Returns a list of choice labels only when the numbered list is at the very
/// end of the message (i.e. the agent is offering choices, not listing tasks
/// in the middle of a sentence).
List<String>? _extractChoices(String text) {
  final pattern = RegExp(r'(?:^|\n)\s*(\d+)[.)]\s+(.+)', multiLine: true);
  final matches = pattern.allMatches(text).toList();
  if (matches.length < 2) return null;
  final numbers = matches.map((m) => int.tryParse(m.group(1)!) ?? 0).toList();
  if (numbers.first != 1) return null;
  for (int i = 1; i < numbers.length; i++) {
    if (numbers[i] != numbers[i - 1] + 1) return null;
  }
  // Only treat as choices when the numbered list is at the end of the message.
  // If there is meaningful text after the last item it's an informational list.
  final lastMatch = matches.last;
  final afterList = text.substring(lastMatch.end).trim();
  if (afterList.isNotEmpty) return null;
  return matches.map((m) => m.group(2)!.trim()).toList();
}

/// Extract roleType prefix from an instanceId ("coder#1" → "coder").
String _roleTypeOf(String id) {
  final hash = id.indexOf('#');
  return hash > 0 ? id.substring(0, hash) : id;
}

/// Display nickname for an instance — looked up from [agentsProvider] when
/// possible (custom-set nicknames win), falling back to the role's default.
String _agentNickname(WidgetRef ref, String id) {
  final agents = ref.read(agentsProvider);
  final info = agents[id]?.info;
  if (info != null && info.name.isNotEmpty) return info.name;
  return switch (_roleTypeOf(id)) {
    'manager' => 'Капітан',
    'tech-lead' => 'Архітект',
    'coder' => 'Майстер',
    'reviewer' => 'Детектив',
    'tester' => 'Крашер',
    'security' => 'Страж',
    'ui-ux-designer' => 'Піксельник',
    'llm-specialist' => 'Промптер',
    _ => id,
  };
}

// ─── Chat item grouping ───────────────────────────────────────────────────────

sealed class _ChatItem {}

class _SingleMessage extends _ChatItem {
  final ChatMessage message;
  _SingleMessage(this.message);
}

class _StatusGroup extends _ChatItem {
  final List<ChatMessage> messages;
  _StatusGroup(this.messages);
}

class _ThreadGroup extends _ChatItem {
  final String id;
  final List<ChatMessage> messages;
  _ThreadGroup({required this.id, required this.messages});
}

/// Groups a flat message list into runs for rendering.
///
/// - Consecutive [MessageCategory.status] messages without a `threadId` (≥2)
///   become a [_StatusGroup].
/// - Messages sharing a `threadId` become a [_ThreadGroup].
/// - Everything else is a [_SingleMessage].
List<_ChatItem> _buildChatItems(List<ChatMessage> messages) {
  final items = <_ChatItem>[];
  int i = 0;
  while (i < messages.length) {
    final msg = messages[i];

    // Thread group: all consecutive messages sharing the same threadId
    if (msg.threadId != null) {
      final id = msg.threadId!;
      final group = <ChatMessage>[];
      while (i < messages.length && messages[i].threadId == id) {
        group.add(messages[i]);
        i++;
      }
      items.add(_ThreadGroup(id: id, messages: group));
      continue;
    }

    // Status run: consecutive status messages without a threadId
    if (msg.category == MessageCategory.status) {
      final run = <ChatMessage>[];
      while (i < messages.length &&
          messages[i].category == MessageCategory.status &&
          messages[i].threadId == null) {
        run.add(messages[i]);
        i++;
      }
      if (run.length >= 2) {
        items.add(_StatusGroup(run));
      } else {
        items.add(_SingleMessage(run.first));
      }
      continue;
    }

    items.add(_SingleMessage(msg));
    i++;
  }
  return items;
}

// ─────────────────────────────────────────────────────────────────────────────

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

  final List<Uint8List?> _attachedImages = []; // null = loading
  bool _applyingRemoteUpdate = false;
  bool _applyingRemoteImages = false;
  final _imagePicker = ImagePicker();
  Timer? _skeletonTimer;
  bool _showSkeleton = false;
  StreamSubscription<String>? _boardTaskSub;

  // Direct-messaging hint: dismissed once per chat opening. If the user ticks
  // the "don't show again" box, the hint is hidden permanently via settings.
  bool _directMsgHintDismissed = false;

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
        // Intercept Cmd+V (macOS) or Ctrl+V (all platforms) to support image paste.
        // We take over the shortcut entirely and handle text paste manually so that
        // clipboard images are never silently dropped.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyV &&
            (HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed)) {
          _handlePasteShortcut();
          return KeyEventResult.skipRemainingHandlers;
        }
        return KeyEventResult.ignored;
      },
    );
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onInputChanged);
    _scrollController.addListener(_onScroll);

    // Handle the initial syncing state — ref.listen only fires on *changes*,
    // so if the provider already starts as syncing we must kick off the timer
    // ourselves after the first frame (ref is not available synchronously).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(chatSyncStateProvider) == ChatSyncState.syncing) {
        _skeletonTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showSkeleton = true);
        });
      }
    });

    _boardTaskSub = facilitatorBoardTaskStream.listen(_onBoardTaskAdded);
  }

  void _onBoardTaskAdded(String title) {
    if (!mounted) return;
    ref.read(chatProvider.notifier).addLocalMessage(
      ChatMessage(
        role: ChatRole.assistant,
        agentId: ref.read(selectedAgentProvider),
        text: title,
        category: MessageCategory.taskLinked,
      ),
    );
  }

  void _onFocusChange() => setState(() {});

  bool _shouldShowDirectMsgHint() {
    if (_directMsgHintDismissed) return false;
    if (ref.watch(settingsProvider).hideDirectMessagingHint) return false;
    final selected = ref.watch(selectedAgentProvider);
    return _roleTypeOf(selected) != 'manager';
  }

  void _onInputChanged() {
    if (_applyingRemoteUpdate) return;
    ref.read(wsServiceProvider).sendInputText(_controller.text);
  }

  @override
  void dispose() {
    _boardTaskSub?.cancel();
    _skeletonTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
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
    // With reverse: true, pixels == 0 means bottom (newest messages).
    final atBottom = pos.pixels <= 40;
    if (_autoScroll && !atBottom) {
      setState(() => _autoScroll = false);
    } else if (!_autoScroll && atBottom) {
      setState(() => _autoScroll = true);
    }
  }

  void _send() {
    final text = _controller.text.trim();
    final loadedImages = _attachedImages.whereType<Uint8List>().toList();
    if (text.isEmpty && loadedImages.isEmpty) return;

    ref.read(chatProvider.notifier).sendMessage(
          text,
          images: loadedImages,
        );
    _controller.clear();
    setState(() => _attachedImages.clear());
    ref.read(wsServiceProvider).sendInputText('');
    ref.read(wsServiceProvider).sendInputImages([]);
    ref.read(remoteInputTextProvider.notifier).clear();
    ref.read(remoteInputImagesProvider.notifier).clear();
    _focusNode.requestFocus();
    setState(() => _autoScroll = true);
    _scrollToBottom();
  }

  Future<void> _pickImages() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1F),
        title: const Text(
          'Вибрати зображення',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF00C0D1)),
              title: const Text(
                'Камера',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00C0D1)),
              title: const Text(
                'Обрати фото',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Color(0xFF00C0D1)),
              title: const Text(
                'Обрати файл',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'camera') {
      await _pasteImage();
    } else if (choice == 'gallery') {
      await _pickImagesFromGallery();
    } else if (choice == 'file') {
      await _pickImagesFromFile();
    }
  }

  Future<void> _pickImagesFromFile() async {
    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'],
      uniformTypeIdentifiers: ['public.image'],
    );
    final files = await openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) return;
    // Add loading placeholders immediately
    final startIndex = _attachedImages.length;
    setState(() {
      for (var i = 0; i < files.length; i++) {
        _attachedImages.add(null);
      }
    });
    // Load each file and replace its placeholder
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      if (!mounted) return;
      setState(() => _attachedImages[startIndex + i] = bytes);
    }
    _syncImages();
  }

  Future<void> _pickImagesFromGallery() async {
    final pickedFiles = await _imagePicker.pickMultiImage();
    if (pickedFiles.isEmpty) return;
    final startIndex = _attachedImages.length;
    setState(() {
      for (var i = 0; i < pickedFiles.length; i++) {
        _attachedImages.add(null);
      }
    });
    for (var i = 0; i < pickedFiles.length; i++) {
      final bytes = await pickedFiles[i].readAsBytes();
      if (!mounted) return;
      setState(() => _attachedImages[startIndex + i] = bytes);
    }
    _syncImages();
  }

  Future<void> _pasteImage() async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.camera);
      if (image == null) return;
      final placeholderIndex = _attachedImages.length;
      setState(() => _attachedImages.add(null));
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _attachedImages[placeholderIndex] = bytes);
      _syncImages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка при вставленні: $e')),
      );
    }
  }

  /// Called when the user presses Cmd+V / Ctrl+V.
  /// Tries to paste an image from the clipboard first; if none is found,
  /// falls back to inserting plain text at the current cursor position.
  Future<void> _handlePasteShortcut() async {
    final imageBytes = await ClipboardService.getImageFromClipboard();
    if (imageBytes != null) {
      if (!mounted) return;
      setState(() => _attachedImages.add(imageBytes));
      _syncImages();
      return;
    }
    // Fall back to plain-text paste
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final sel = _controller.selection;
    final current = _controller.text;
    final start = sel.isValid ? sel.start : current.length;
    final end = sel.isValid ? sel.end : current.length;
    final newText = current.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }



  void _removeImage(int index) {
    setState(() => _attachedImages.removeAt(index));
    _syncImages();
  }

  /// Send current loaded images to other clients.
  void _syncImages() {
    if (_applyingRemoteImages) return;
    final base64s = _attachedImages
        .whereType<Uint8List>()
        .map((b) => base64Encode(b))
        .toList();
    ref.read(wsServiceProvider).sendInputImages(base64s);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      // With reverse: true, position 0 is the bottom (newest messages).
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _copyChatSnippet({int limit = 20}) async {
    final messages = ref.read(chatProvider);
    if (messages.isEmpty) {
      _showSnack('Чат порожній — нічого копіювати.');
      return;
    }
    final tail = messages.length <= limit
        ? messages
        : messages.sublist(messages.length - limit);
    final workDir = ref.read(workingDirectoryProvider);
    final selectedAgent = ref.read(selectedAgentProvider);
    final now = DateTime.now();

    String two(int n) => n.toString().padLeft(2, '0');
    String fmtTime(DateTime t) {
      final l = t.toLocal();
      return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
    }
    String fmtDate(DateTime t) {
      final l = t.toLocal();
      return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
    }

    final buf = StringBuffer()
      ..writeln('# PixelCode chat snippet — ${fmtDate(now)}')
      ..writeln()
      ..writeln('- **Working dir:** `${workDir ?? '(unset)'}`')
      ..writeln('- **Selected agent:** $selectedAgent (${_agentNickname(ref, selectedAgent)})')
      ..writeln('- **Messages:** last ${tail.length} of ${messages.length}')
      ..writeln()
      ..writeln('---')
      ..writeln();

    for (final m in tail) {
      final who = m.role == ChatRole.user
          ? 'user'
          : '${m.agentId} (${_agentNickname(ref, m.agentId)})';
      final streamingTag = m.isStreaming ? ' _[streaming]_' : '';
      buf
        ..writeln('**${fmtTime(m.timestamp)} — $who:**$streamingTag')
        ..writeln(m.text.trim().isEmpty ? '_(empty)_' : m.text.trim());
      if (m.imageBase64s.isNotEmpty) {
        buf.writeln('_[+${m.imageBase64s.length} image(s)]_');
      }
      buf.writeln();
    }

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    _showSnack('Скопійовано ${tail.length} реплік як markdown.');
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showAgentPicker() {
    final agents = ref.read(agentsProvider);
    final currentAgent = ref.read(selectedAgentProvider);
    final agentList = agents.entries
        .where((e) => e.key != currentAgent)
        .toList();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A1F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
          padding: const EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      color: const Color(0xFF00C0D1),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Вибрати колегу',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Agent list
              Flexible(
                child: agentList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Немає інших колег',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: agentList.length,
                        separatorBuilder: (context, index) => Divider(
                          color: Colors.white.withValues(alpha: 0.05),
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                        ),
                        itemBuilder: (context, index) {
                          final agentEntry = agentList[index];
                          final agentId = agentEntry.key;
                          final agentState = agentEntry.value;
                          final nickname = _agentNickname(ref, agentId);

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                ref.read(selectedAgentProvider.notifier).state = agentId;
                                Navigator.pop(context);
                              },
                              hoverColor: Colors.white.withValues(alpha: 0.05),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: _getAgentGradient(agentId),
                                        border: Border.all(
                                          color: _getAgentColor(agentId),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Icon(
                                        _getAgentIcon(agentId),
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nickname,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            agentState.info.role,
                                            style: TextStyle(
                                              color: Colors.white.withValues(alpha: 0.5),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: agentState.isActive
                                            ? const Color(0xFF00C0D1).withValues(alpha: 0.15)
                                            : Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: agentState.isActive
                                              ? const Color(0xFF00C0D1).withValues(alpha: 0.3)
                                              : Colors.white.withValues(alpha: 0.1),
                                        ),
                                      ),
                                      child: Text(
                                        agentState.isActive ? 'Активен' : 'Вільен',
                                        style: TextStyle(
                                          color: agentState.isActive
                                              ? const Color(0xFF00C0D1)
                                              : Colors.white.withValues(alpha: 0.5),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _getAgentGradient(String agentId) =>
      switch (_roleTypeOf(agentId)) {
        'manager' => const LinearGradient(
            colors: [Color(0xFF00D4E7), Color(0xFF00A5B4)],
          ),
        'tech-lead' => const LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFEE5A52)],
          ),
        'coder' => const LinearGradient(
            colors: [Color(0xFF4ECDC4), Color(0xFF44A5A5)],
          ),
        'reviewer' => const LinearGradient(
            colors: [Color(0xFFFFA500), Color(0xFFFF8C00)],
          ),
        'tester' => const LinearGradient(
            colors: [Color(0xFFFF6B9D), Color(0xFFC44569)],
          ),
        'security' => const LinearGradient(
            colors: [Color(0xFF8E44AD), Color(0xFF6C3483)],
          ),
        'ui-ux-designer' => const LinearGradient(
            colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
          ),
        'llm-specialist' => const LinearGradient(
            colors: [Color(0xFF9B59FF), Color(0xFF6C2BD9)],
          ),
        _ => const LinearGradient(
            colors: [Color(0xFF95A5A6), Color(0xFF7F8C8D)],
          ),
      };

  Color _getAgentColor(String agentId) => switch (_roleTypeOf(agentId)) {
        'manager' => const Color(0xFF00C0D1),
        'tech-lead' => const Color(0xFFFF6B6B),
        'coder' => const Color(0xFF4ECDC4),
        'reviewer' => const Color(0xFFFFA500),
        'tester' => const Color(0xFFFF6B9D),
        'security' => const Color(0xFF8E44AD),
        'ui-ux-designer' => const Color(0xFF3498DB),
        'llm-specialist' => const Color(0xFF9B59FF),
        _ => const Color(0xFF95A5A6),
      };

  IconData _getAgentIcon(String agentId) => switch (_roleTypeOf(agentId)) {
        'manager' => Icons.sentiment_very_satisfied,
        'tech-lead' => Icons.architecture,
        'coder' => Icons.code,
        'reviewer' => Icons.fact_check,
        'tester' => Icons.bug_report,
        'security' => Icons.security,
        'ui-ux-designer' => Icons.palette,
        'llm-specialist' => Icons.smart_toy,
        _ => Icons.person,
      };

  @override
  Widget build(BuildContext context) {
    final selectedAgent = ref.watch(selectedAgentProvider);
    final messages = ref.watch(chatProvider);
    final groupedItems = _buildChatItems(messages);
    final syncState = ref.watch(chatSyncStateProvider);
    final agentStatus = ref.watch(
      agentsProvider.select((m) => m[selectedAgent]?.status ?? AgentStatus.idle),
    );
    final agentToolDesc = ref.watch(
      agentsProvider.select((m) => m[selectedAgent]?.lastToolDescription),
    );
    // Team activity: when the selected agent delegates (common for captain),
    // its own status returns to idle while subagents keep working. Surface a
    // team-busy indicator so the chat doesn't look frozen.
    final busySubagents = ref.watch(
      agentsProvider.select((m) => [
        for (final e in m.entries)
          if (e.key != selectedAgent && e.value.isActive) e.value,
      ]),
    );
    final hasStreamingBubble =
        messages.isNotEmpty && messages.last.isStreaming;
    final selectedIsActive = agentStatus != AgentStatus.idle;
    final showThinking =
        (selectedIsActive || busySubagents.isNotEmpty) && !hasStreamingBubble;
    final thinkingStatus = showThinking
        ? (selectedIsActive ? agentStatus : busySubagents.first.status)
        : agentStatus;
    final thinkingToolDesc = showThinking
        ? (selectedIsActive
            ? agentToolDesc
            : busySubagents.first.lastToolDescription)
        : agentToolDesc;
    final thinkingSubtitle = !showThinking || selectedIsActive
        ? null
        : busySubagents.length == 1
            ? busySubagents.first.info.name
            : '${busySubagents.length} агентів працюють';

    ref.listen(selectedAgentProvider, (prev, next) {
      _autoScroll = true;
      _scrollToBottom();
    });

    ref.listen(chatSyncStateProvider, (prev, next) {
      _skeletonTimer?.cancel();
      if (next == ChatSyncState.syncing) {
        _showSkeleton = false;
        _skeletonTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showSkeleton = true);
        });
      } else {
        setState(() => _showSkeleton = false);
        _autoScroll = true;
        _scrollToBottom();
      }
    });

    ref.listen(chatProvider, (prev, next) {
      if (_autoScroll && syncState == ChatSyncState.ready) _scrollToBottom();
    });

    ref.listen(remoteInputImagesProvider, (prev, next) {
      _applyingRemoteImages = true;
      setState(() {
        _attachedImages
          ..clear()
          ..addAll(next.map((b64) => base64Decode(b64)));
      });
      _applyingRemoteImages = false;
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

    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        if (event.session.items.any((item) =>
            item.canProvide(Formats.png) ||
            item.canProvide(Formats.jpeg) ||
            item.canProvide(Formats.gif) ||
            item.canProvide(Formats.tiff) ||
            item.canProvide(Formats.webp))) {
          return DropOperation.copy;
        }
        return DropOperation.none;
      },
      onPerformDrop: (event) async {
        for (final item in event.session.items) {
          final reader = item.dataReader;
          if (reader == null) continue;
          for (final format in [Formats.png, Formats.jpeg, Formats.tiff, Formats.gif, Formats.webp]) {
            if (item.canProvide(format)) {
              reader.getFile(format, (file) async {
                final allBytes = <int>[];
                await for (final chunk in file.getStream()) {
                  allBytes.addAll(chunk);
                }
                if (!mounted) return;
                setState(() => _attachedImages.add(Uint8List.fromList(allBytes)));
                _syncImages();
              });
              break;
            }
          }
        }
      },
      child: Container(
      color: context.appColors.background,
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
                GestureDetector(
                  onTap: _showAgentPicker,
                  child: Row(
                    children: [
                      const Icon(Icons.chat_outlined, color: Color(0xFF00C0D1), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _agentNickname(ref, ref.watch(selectedAgentProvider)),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _CopySnippetButton(onTap: _copyChatSnippet),
                const SizedBox(width: 8),
                _BypassToggle(),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: syncState == ChatSyncState.syncing
                ? (_showSkeleton
                    ? const _PixelChatSkeleton()
                    : const SizedBox.shrink())
                : (messages.isEmpty && !showThinking)
                    ? _buildEmptyState()
                    : Stack(
                        children: [
                          ListView.builder(
                            reverse: true,
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: groupedItems.length + (showThinking ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (showThinking && index == 0) {
                                return _ThinkingBubble(
                                  status: thinkingStatus,
                                  toolDescription: thinkingToolDesc,
                                  subtitle: thinkingSubtitle,
                                );
                              }
                              final msgIndex = showThinking ? index - 1 : index;
                              final item = groupedItems[groupedItems.length - 1 - msgIndex];
                              return switch (item) {
                                _SingleMessage(:final message) =>
                                  _ChatBubble(message: message),
                                _StatusGroup(:final messages) =>
                                  StatusGroupWidget(
                                    key: ValueKey('sg_${messages.first.timestamp.millisecondsSinceEpoch}'),
                                    messages: messages,
                                  ),
                                _ThreadGroup(:final id, :final messages) =>
                                  ThreadTile(
                                    key: ValueKey('t_$id'),
                                    threadId: id,
                                    messages: messages,
                                    messageBuilder: (msg) => _ChatBubble(message: msg),
                                  ),
                              };
                            },
                          ),
                          if (!_autoScroll)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  setState(() => _autoScroll = true);
                                  if (_scrollController.hasClients) {
                                    _scrollController.jumpTo(0);
                                  }
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
    final c = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(
          top: BorderSide(color: c.divider),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hint: user is addressing a non-manager agent.
          if (_shouldShowDirectMsgHint())
            _DirectMsgHint(
              onDismiss: () => setState(() => _directMsgHintDismissed = true),
              onDontShowAgain: () {
                ref.read(settingsProvider.notifier)
                    .setHideDirectMessagingHint(true);
                setState(() => _directMsgHintDismissed = true);
              },
            ),
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
                    final imageBytes = _attachedImages[index];
                    final isLoading = imageBytes == null;
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: isLoading
                              ? Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.1),
                                    ),
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF00C0D1),
                                      ),
                                    ),
                                  ),
                                )
                              : Image.memory(
                                  imageBytes,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        if (!isLoading)
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Unified input container: action buttons + text field share one frame
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? c.accent
                            : c.border,
                        width: 1,
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                _InputIconButton(
                                  icon: Icons.attach_file_rounded,
                                  tooltip: 'Додати зображення',
                                  onPressed: _pickImages,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            autofocus: MediaQuery.of(context).size.shortestSide >= 600,
                            maxLines: 4,
                            minLines: 1,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText:
                                  'Повідомлення ${_agentNickname(ref, ref.watch(selectedAgentProvider))}...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.25),
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 12),
                            ),
                          ),
                        ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Fixed-size filled send button — rendered variant chosen
                // by the active send-button cosmetic.
                SendButton(onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Direct Messaging Hint ────────────────────────────────────────────────────

class _DirectMsgHint extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onDontShowAgain;

  const _DirectMsgHint({
    required this.onDismiss,
    required this.onDontShowAgain,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00C0D1);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.info_outline, size: 14, color: accent),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Краще писати Капітану — він розподілить роботу по команді. '
                  'Пряме повідомлення конкретному робітнику — тонке керування: '
                  'роби так лише якщо добре розумієш що й кому делегуєш.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onDontShowAgain,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  'Не показувати',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Input Icon Button ────────────────────────────────────────────────────────

class _InputIconButton extends StatelessWidget {
  const _InputIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

// ─── Chat Bubble ──────────────────────────────────────────────────────────────

class _ChatBubble extends ConsumerWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == ChatRole.user;

    // taskLinked messages render as a compact board-announcement row, not a bubble.
    if (message.category == MessageCategory.taskLinked) {
      return BoardAddedBubble(title: message.text);
    }

    final choices =
        (!isUser && !message.isStreaming) ? _extractChoices(message.text) : null;

    final catDecoration = !isUser ? categoryBubbleDecoration(message.category) : null;
    final catTextStyle = !isUser ? categoryTextStyle(message.category) : null;

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
                  decoration: catDecoration ??
                      BoxDecoration(
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
                          style: catTextStyle ??
                              TextStyle(
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
                            .sendMessage('$idx. $label'),
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

class _CopySnippetButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CopySnippetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Скопіювати останні 20 реплік як markdown',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.ios_share_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

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

// ─── Pixel Chat Skeleton ────────────────────────────────────────────────────

class _PixelChatSkeleton extends StatelessWidget {
  const _PixelChatSkeleton();

  static const double _pulse = 0.08;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _skeletonRow(isUser: false, widths: [120, 80, 60]),
          const SizedBox(height: 12),
          _skeletonRow(isUser: true, widths: [90]),
          const SizedBox(height: 12),
          _skeletonRow(isUser: false, widths: [140, 100, 70, 50]),
          const SizedBox(height: 12),
          _skeletonRow(isUser: true, widths: [70, 40]),
          const SizedBox(height: 12),
          _skeletonRow(isUser: false, widths: [110, 90]),
        ],
      ),
    );
  }

  Widget _skeletonRow({
    required bool isUser,
    required List<double> widths,
  }) {
    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) ...[
          ClipOval(
            child: Stack(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  color: Colors.white.withValues(alpha: _pulse),
                ),
                const Positioned.fill(
                  child: IgnorePointer(child: _PixelGarland(sparkCount: 3)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _pulse * 0.6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: _pulse * 0.8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < widths.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      Container(
                        width: widths[i],
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: _pulse * 1.2),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(child: _PixelGarland(sparkCount: 18)),
              ),
            ],
          ),
        ),
        if (isUser) const SizedBox(width: 36),
      ],
    );
  }
}

// Pixel-sparkle overlay — random plus-shaped pixels blink in and out across
// the skeleton surface, like a string of Christmas lights.
class _PixelGarland extends StatefulWidget {
  final int sparkCount;
  const _PixelGarland({this.sparkCount = 10});

  @override
  State<_PixelGarland> createState() => _PixelGarlandState();
}

class _Spark {
  double fx;
  double fy;
  double start;
  double life;
  Color color;
  double size;

  _Spark({
    required this.fx,
    required this.fy,
    required this.start,
    required this.life,
    required this.color,
    required this.size,
  });
}

class _PixelGarlandState extends State<_PixelGarland>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final math.Random _rng = math.Random();
  final List<_Spark> _sparks = [];

  static const List<Color> _palette = [
    Color(0xFF00C0D1),
    Color(0xFF00D4E7),
    Color(0xFFFFFFFF),
    Color(0xFFFF6B9D),
    Color(0xFFFFC107),
    Color(0xFF4ECDC4),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    for (int i = 0; i < widget.sparkCount; i++) {
      _sparks.add(_makeSpark(_rng.nextDouble()));
    }
  }

  _Spark _makeSpark(double startAt) {
    return _Spark(
      fx: _rng.nextDouble(),
      fy: _rng.nextDouble(),
      start: startAt,
      life: 0.04 + _rng.nextDouble() * 0.12,
      color: _palette[_rng.nextInt(_palette.length)],
      size: 1.0 + _rng.nextInt(2),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final now = _ctrl.value;
        for (int i = 0; i < _sparks.length; i++) {
          final s = _sparks[i];
          final phase = (now - s.start + 1.0) % 1.0;
          if (phase > s.life) {
            _sparks[i] = _makeSpark(now);
          }
        }
        return CustomPaint(
          painter: _GarlandPainter(sparks: _sparks, now: now),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _GarlandPainter extends CustomPainter {
  final List<_Spark> sparks;
  final double now;

  _GarlandPainter({required this.sparks, required this.now});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparks) {
      final phase = (now - s.start + 1.0) % 1.0;
      if (phase > s.life) continue;
      final t = phase / s.life;
      final opacity = (t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75)
          .clamp(0.0, 1.0);
      final px = (s.fx * size.width / s.size).floor() * s.size;
      final py = (s.fy * size.height / s.size).floor() * s.size;
      final core = Paint()..color = s.color.withValues(alpha: opacity);
      final edge = Paint()..color = s.color.withValues(alpha: opacity * 0.35);
      canvas.drawRect(Rect.fromLTWH(px, py, s.size, s.size), core);
      canvas.drawRect(Rect.fromLTWH(px - s.size, py, s.size, s.size), edge);
      canvas.drawRect(Rect.fromLTWH(px + s.size, py, s.size, s.size), edge);
      canvas.drawRect(Rect.fromLTWH(px, py - s.size, s.size, s.size), edge);
      canvas.drawRect(Rect.fromLTWH(px, py + s.size, s.size, s.size), edge);
    }
  }

  @override
  bool shouldRepaint(_GarlandPainter oldDelegate) => true;
}

class _ThinkingBubble extends StatelessWidget {
  final AgentStatus status;
  final String? toolDescription;
  final String? subtitle;

  const _ThinkingBubble({
    required this.status,
    this.toolDescription,
    this.subtitle,
  });

  String get _label {
    final tool = toolDescription;
    if (tool != null && tool.isNotEmpty && status == AgentStatus.running) {
      return tool;
    }
    return switch (status) {
      AgentStatus.thinking => 'Thinking',
      AgentStatus.typing => 'Typing',
      AgentStatus.reading => 'Reading',
      AgentStatus.running => 'Working',
      AgentStatus.waiting => 'Waiting',
      AgentStatus.idle => 'Idle',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1F27),
                borderRadius: BorderRadius.circular(12)
                    .copyWith(bottomLeft: const Radius.circular(4)),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _TypingDots(),
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
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
