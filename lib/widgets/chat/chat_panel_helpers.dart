/// Pure helpers carved out of `chat_panel.dart` so they can be unit-tested
/// without spinning up the whole [ChatPanel] integration surface.
///
/// Everything in this file is intentionally side-effect free, has no Flutter
/// dependencies on `BuildContext`, and takes its inputs as plain values. Wider
/// chat features (Riverpod providers, animations, file pickers, …) stay in
/// `chat_panel.dart`.
library;

import '../../models/agent_message.dart';

// ─── Slash-command parser ────────────────────────────────────────────────────

/// Parsed slash command extracted from the composer input.
///
/// `/clear extra args` → `SlashCommand(name: 'clear', args: 'extra args')`.
class SlashCommand {
  final String name;
  final String args;
  const SlashCommand({required this.name, required this.args});

  @override
  bool operator ==(Object other) =>
      other is SlashCommand && other.name == name && other.args == args;

  @override
  int get hashCode => Object.hash(name, args);

  @override
  String toString() => 'SlashCommand(name: $name, args: $args)';
}

/// Parse a composer input string into a [SlashCommand] when the user typed a
/// leading-slash command, or null when the input is not a command.
///
/// Rules:
/// - The very first character must be `/`. Leading whitespace disqualifies the
///   input — the user pressed space first, so they meant a literal slash.
/// - The command name is the run of `[a-zA-Z0-9_-]+` after the slash.
/// - Anything after the first whitespace is the args payload (trimmed).
/// - A bare `/` returns null (no command yet typed).
SlashCommand? parseSlashCommand(String input) {
  if (input.isEmpty || input[0] != '/') return null;
  if (input.length == 1) return null;
  final match = RegExp(r'^/([a-zA-Z0-9_-]+)(?:\s+(.*))?$').firstMatch(input);
  if (match == null) return null;
  return SlashCommand(
    name: match.group(1)!,
    args: (match.group(2) ?? '').trim(),
  );
}

// ─── Mention parser ──────────────────────────────────────────────────────────

/// Match `@role#id` references in a body of text. The role part allows letters,
/// digits and hyphens (e.g. `tech-lead`, `ui-ux-designer`); the id part is
/// digits.
final RegExp _mentionPattern = RegExp(r'@([a-zA-Z][a-zA-Z0-9-]*)#(\d+)');

/// Extract every `@role#id` mention from [text], in order of appearance,
/// duplicates preserved. Returns the canonical instance ids, e.g. `coder#1`.
List<String> extractMentions(String text) {
  if (text.isEmpty) return const [];
  return _mentionPattern
      .allMatches(text)
      .map((m) => '${m.group(1)}#${m.group(2)}')
      .toList(growable: false);
}

// ─── Numbered-choice parser ──────────────────────────────────────────────────

/// Parses numbered choice options from agent text. Returns a list of choice
/// labels only when the numbered list is at the very end of the message.
///
/// Mirrors the original `_extractChoices` behaviour: at least 2 items, must
/// start at 1 and increase by 1, no further text allowed after the last item.
List<String>? extractChoices(String text) {
  final pattern = RegExp(r'(?:^|\n)\s*(\d+)[.)]\s+(.+)', multiLine: true);
  final matches = pattern.allMatches(text).toList();
  if (matches.length < 2) return null;
  final numbers = matches.map((m) => int.tryParse(m.group(1)!) ?? 0).toList();
  if (numbers.first != 1) return null;
  for (int i = 1; i < numbers.length; i++) {
    if (numbers[i] != numbers[i - 1] + 1) return null;
  }
  final lastMatch = matches.last;
  final afterList = text.substring(lastMatch.end).trim();
  if (afterList.isNotEmpty) return null;
  return matches.map((m) => m.group(2)!.trim()).toList();
}

// ─── Agent role / nickname helpers ───────────────────────────────────────────

/// Extract the role-type prefix from an instanceId ("coder#1" → "coder").
String roleTypeOf(String id) {
  final hash = id.indexOf('#');
  return hash > 0 ? id.substring(0, hash) : id;
}

/// Default nickname for a given role type. Falls back to the raw [id] when the
/// role type is not one of the known PixelCode roles.
String defaultAgentNickname(String id) => switch (roleTypeOf(id)) {
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

// ─── Scroll-stick predicate ──────────────────────────────────────────────────

/// Pixel threshold below which we still consider the user "at the bottom" of
/// a reverse: true scrollable. Mirrors the in-place value used by [ChatPanel].
const double kAtBottomThresholdPx = 40.0;

/// Returns true when the reverse-scrolled list is "near the bottom" — i.e. new
/// messages should auto-stick. With `reverse: true`, position 0 is the bottom.
bool isAtBottomReverse(double pixels, {double threshold = kAtBottomThresholdPx}) {
  return pixels <= threshold;
}

/// Decide whether [ChatPanel] should auto-scroll to the latest message given
/// the previous auto-scroll flag and the current scroll-pixel position.
///
/// Returns `true` when the panel should remain stuck-to-bottom.
bool shouldAutoStickToBottom({
  required bool wasAutoScrolling,
  required double currentPixels,
  double threshold = kAtBottomThresholdPx,
}) {
  final atBottom = isAtBottomReverse(currentPixels, threshold: threshold);
  if (wasAutoScrolling && !atBottom) return false;
  if (!wasAutoScrolling && atBottom) return true;
  return wasAutoScrolling;
}

// ─── Empty-state predicate ───────────────────────────────────────────────────

/// Variants of empty-state placeholder shown when the chat has no messages.
enum ChatEmptyStateKind {
  /// Provider hasn't told us its sync state yet — render nothing (or skeleton).
  syncing,

  /// Connected and quiet, but a thinking bubble is being rendered. Caller
  /// should NOT show the placeholder.
  thinkingBubble,

  /// No messages, not syncing — show the "Start a conversation" placeholder.
  empty,

  /// Messages present — caller renders the message list, not a placeholder.
  messages,
}

/// Compute which empty-state surface to render based on the current chat state.
ChatEmptyStateKind chatEmptyStateKind({
  required bool isSyncing,
  required bool isEmpty,
  required bool showThinking,
}) {
  if (isSyncing) return ChatEmptyStateKind.syncing;
  if (!isEmpty) return ChatEmptyStateKind.messages;
  if (showThinking) return ChatEmptyStateKind.thinkingBubble;
  return ChatEmptyStateKind.empty;
}

// ─── Chat item grouping ──────────────────────────────────────────────────────

/// Sealed tag for a renderable run of chat messages.
sealed class ChatItem {}

class SingleMessage extends ChatItem {
  final ChatMessage message;
  SingleMessage(this.message);
}

class StatusGroup extends ChatItem {
  final List<ChatMessage> messages;
  StatusGroup(this.messages);
}

class ThreadGroup extends ChatItem {
  final String id;
  final List<ChatMessage> messages;
  ThreadGroup({required this.id, required this.messages});
}

/// Groups a flat message list into runs for rendering.
///
/// - Consecutive [MessageCategory.status] messages without a `threadId` (≥2)
///   become a [StatusGroup].
/// - Messages sharing a `threadId` become a [ThreadGroup].
/// - Everything else is a [SingleMessage].
List<ChatItem> buildChatItems(List<ChatMessage> messages) {
  final items = <ChatItem>[];
  int i = 0;
  while (i < messages.length) {
    final msg = messages[i];

    if (msg.threadId != null) {
      final id = msg.threadId!;
      final group = <ChatMessage>[];
      while (i < messages.length && messages[i].threadId == id) {
        group.add(messages[i]);
        i++;
      }
      items.add(ThreadGroup(id: id, messages: group));
      continue;
    }

    if (msg.category == MessageCategory.status) {
      final run = <ChatMessage>[];
      while (i < messages.length &&
          messages[i].category == MessageCategory.status &&
          messages[i].threadId == null) {
        run.add(messages[i]);
        i++;
      }
      if (run.length >= 2) {
        items.add(StatusGroup(run));
      } else {
        items.add(SingleMessage(run.first));
      }
      continue;
    }

    items.add(SingleMessage(msg));
    i++;
  }
  return items;
}

// ─── Markdown chat-snippet builder ───────────────────────────────────────────

String _two(int n) => n.toString().padLeft(2, '0');

/// Format a UTC/local timestamp as `HH:MM:SS` for snippet headers.
String formatSnippetTime(DateTime t) {
  final l = t.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
}

/// Format a timestamp as `YYYY-MM-DD HH:MM` for the snippet title.
String formatSnippetDate(DateTime t) {
  final l = t.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// Build the markdown chat snippet body. Pure: takes everything it needs as
/// values. The caller is responsible for tailing the message list and pushing
/// the result onto the system clipboard.
String buildChatSnippet({
  required Iterable<ChatMessage> tail,
  required int totalMessages,
  required String? workingDir,
  required String selectedAgentId,
  required String selectedAgentNickname,
  String Function(String agentId)? nicknameFor,
  DateTime? now,
}) {
  final tailList = tail.toList(growable: false);
  final ts = now ?? DateTime.now();
  final lookup = nicknameFor ?? defaultAgentNickname;

  final buf = StringBuffer()
    ..writeln('# PixelCode chat snippet — ${formatSnippetDate(ts)}')
    ..writeln()
    ..writeln('- **Working dir:** `${workingDir ?? '(unset)'}`')
    ..writeln(
        '- **Selected agent:** $selectedAgentId ($selectedAgentNickname)')
    ..writeln('- **Messages:** last ${tailList.length} of $totalMessages')
    ..writeln()
    ..writeln('---')
    ..writeln();

  for (final m in tailList) {
    final who = m.role == ChatRole.user
        ? 'user'
        : '${m.agentId} (${lookup(m.agentId)})';
    final streamingTag = m.isStreaming ? ' _[streaming]_' : '';
    buf
      ..writeln('**${formatSnippetTime(m.timestamp)} — $who:**$streamingTag')
      ..writeln(m.text.trim().isEmpty ? '_(empty)_' : m.text.trim());
    if (m.imageBase64s.isNotEmpty) {
      buf.writeln('_[+${m.imageBase64s.length} image(s)]_');
    }
    buf.writeln();
  }

  return buf.toString();
}
