/// Agent detail bottom sheet with Overview and Traits tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/providers/game_economy_provider.dart';
import 'package:pixelcode/widgets/hub/app_bottom_sheet.dart';
import 'package:pixelcode/widgets/personalization/personalization_panel.dart';
import 'package:pixelcode/widgets/roster/agent_overview_tab.dart';

void showAgentDetailDrawer(BuildContext context, AgentGameData agent) {
  showAppBottomSheet<void>(
    context: context,
    initialSize: 0.75,
    minSize: 0.4,
    maxSize: 0.95,
    // No internal drag handle — the AgentDetailDrawer header already has its
    // own and we don't want two stacked indicators.
    showDragHandle: false,
    builder: (context, scrollController) => AgentDetailDrawer(
      agent: agent,
      scrollController: scrollController,
    ),
  );
}

class AgentDetailDrawer extends ConsumerStatefulWidget {
  final AgentGameData agent;
  final ScrollController scrollController;

  const AgentDetailDrawer({
    required this.agent,
    required this.scrollController,
    super.key,
  });

  @override
  ConsumerState<AgentDetailDrawer> createState() => _AgentDetailDrawerState();
}

class _AgentDetailDrawerState extends ConsumerState<AgentDetailDrawer>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _nameCtrl;
  late final FocusNode _nameFocus;
  bool _editing = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _nameCtrl = TextEditingController(text: widget.agent.nickname);
    _nameFocus = FocusNode();
    _nameFocus.addListener(() {
      if (_nameFocus.hasFocus || !_editing) return;
      if (_cancelling) {
        _cancelling = false;
        return;
      }
      _commitRename();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _startEditing(String currentName) {
    _nameCtrl.text = currentName;
    _nameCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentName.length,
    );
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  void _commitRename() {
    final trimmed = _nameCtrl.text.trim();
    if (trimmed.isNotEmpty) {
      ref
          .read(gameEconomyProvider.notifier)
          .renameInstance(widget.agent.instanceId, trimmed);
    }
    setState(() => _editing = false);
  }

  void _cancelEditing() {
    _cancelling = true;
    _nameFocus.unfocus();
    setState(() => _editing = false);
  }

  void _rerollName() {
    final game = ref.read(gameEconomyProvider);
    final used = game.agents.values
        .where((a) => a.instanceId != widget.agent.instanceId)
        .map((a) => a.nickname);
    _nameCtrl.text = pickRoleNickname(
      widget.agent.roleType,
      excludeNicknames: used,
    );
    _nameCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameCtrl.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveAgent =
        ref.watch(gameEconomyProvider).agents[widget.agent.instanceId] ??
            widget.agent;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _editing
                        ? _NameEditor(
                            controller: _nameCtrl,
                            focusNode: _nameFocus,
                            onSubmit: _commitRename,
                            onCancel: _cancelEditing,
                            onReroll: _rerollName,
                          )
                        : _NameDisplay(
                            name: liveAgent.nickname,
                            onTap: () => _startEditing(liveAgent.nickname),
                          ),
                    const SizedBox(height: 2),
                    Text(
                      '${liveAgent.roleType} · Lv ${liveAgent.level}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: Colors.white.withValues(alpha: 0.4),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF00C0D1),
          unselectedLabelColor: Colors.white.withValues(alpha: 0.4),
          indicatorColor: const Color(0xFF00C0D1),
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Memory'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              AgentOverviewTab(instanceId: liveAgent.instanceId),
              PersonalizationPanel(
                agentId: liveAgent.instanceId,
                agentName: liveAgent.nickname,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NameDisplay extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _NameDisplay({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.edit_outlined,
              size: 13,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameEditor extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onReroll;

  const _NameEditor({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onCancel,
    required this.onReroll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            cursorColor: const Color(0xFF00C0D1),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF00C0D1)),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Інше імʼя',
          icon: const Icon(Icons.casino_outlined, size: 18),
          color: Colors.white.withValues(alpha: 0.5),
          onPressed: onReroll,
        ),
        IconButton(
          tooltip: 'Скасувати',
          icon: const Icon(Icons.close, size: 18),
          color: Colors.white.withValues(alpha: 0.4),
          onPressed: onCancel,
        ),
      ],
    );
  }
}
