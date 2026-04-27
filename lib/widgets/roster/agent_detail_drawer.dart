/// Agent detail bottom sheet with Overview and Traits tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pixelcode/models/game_economy.dart';
import 'package:pixelcode/widgets/personalization/personalization_panel.dart';
import 'package:pixelcode/widgets/roster/agent_overview_tab.dart';

void showAgentDetailDrawer(BuildContext context, AgentGameData agent) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A1F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => AgentDetailDrawer(
        agent: agent,
        scrollController: scrollController,
      ),
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;

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
                    Text(
                      agent.nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${agent.roleType} · Lv ${agent.level}',
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
              AgentOverviewTab(agent: agent),
              PersonalizationPanel(
                agentId: agent.instanceId,
                agentName: agent.nickname,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
