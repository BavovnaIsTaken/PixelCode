import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/agent_provider.dart';
import '../../widgets/canvas/agent_canvas.dart';
import '../../widgets/chat/chat_panel.dart';

/// Main split-screen: Chat (left) + Agent Canvas (right)
class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen> {
  @override
  void initState() {
    super.initState();
    // Give the server a moment to start, then connect
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) ref.read(wsServiceProvider).connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(connectionStatusProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      body: Column(
        children: [
          // Title bar
          _buildTitleBar(isConnected),
          // Main content
          Expanded(
            child: Row(
              children: [
                // Left: Chat panel
                const SizedBox(
                  width: 440,
                  child: ChatPanel(),
                ),
                // Divider
                Container(
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                // Right: Agent canvas
                const Expanded(
                  child: AgentCanvas(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(bool isConnected) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Agent Hub',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 12),
          // Connection indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? const Color(0xFF00C0D1) : Colors.red,
              boxShadow: [
                BoxShadow(
                  color: (isConnected ? const Color(0xFF00C0D1) : Colors.red)
                      .withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Text(
            '7 agents',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
