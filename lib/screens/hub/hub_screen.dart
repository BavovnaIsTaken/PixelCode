import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/agent_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_board_provider.dart';
import '../../widgets/board/task_board_panel.dart';
import '../../widgets/canvas/agent_canvas.dart';
import '../../widgets/chat/chat_panel.dart';
import '../../widgets/easter_eggs/easter_egg_games.dart';
import '../../widgets/debug/debug_console.dart';
import '../../widgets/project/project_selector.dart';
import '../../widgets/settings/settings_dialog.dart';
import '../../widgets/shop/shop_panel.dart';

/// Main split-screen: Chat (left) + Agent Canvas (right) + Debug Console (bottom)
class HubScreen extends ConsumerStatefulWidget {
  const HubScreen({super.key});

  @override
  ConsumerState<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends ConsumerState<HubScreen>
    with TickerProviderStateMixin {
  static const _windowChannel = MethodChannel('com.pixelcode/window');

  bool _debugOpen = false;
  double _debugHeight = 200;
  bool _isShuttingDown = false;
  int _viewIndex = 0; // 0=Office, 1=Board, 2=Shop
  bool _showGames = false;

  final _rng = Random();

  // Easter egg: 5-second long press on logo → Games
  Timer? _arkanoidTimer;

  void _onLogoPointerDown() {
    _arkanoidTimer?.cancel();
    _arkanoidTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showGames = true);
    });
  }

  void _onLogoPointerUp() {
    _arkanoidTimer?.cancel();
  }

  // Idle logo flip — single Y-axis rotation at random intervals
  late final AnimationController _idleLogoCtrl = AnimationController(
    vsync: this,
  );

  void _scheduleIdleFlip() {
    if (_isShuttingDown || !mounted) return;
    final delay = 3000 + _rng.nextInt(5000); // 3–8s
    Future.delayed(Duration(milliseconds: delay), () {
      if (_isShuttingDown || !mounted) return;
      final dur = 700 + _rng.nextInt(1301); // 700–2000ms
      _idleLogoCtrl
        ..duration = Duration(milliseconds: dur)
        ..forward(from: 0.0).then((_) => _scheduleIdleFlip());
    });
  }

  // Shutdown animation
  late final AnimationController _shutdownCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  // Logo spins 1× during first 40% of shutdown
  late final Animation<double> _logoSpin = Tween(begin: 0.0, end: 1.0).animate(
    CurvedAnimation(
      parent: _shutdownCtrl,
      curve: const Interval(0.0, 0.4, curve: Curves.easeInOut),
    ),
  );

  // Screen collapses vertically (CRT power-off) during 40%-100%
  late final Animation<double> _scaleY = Tween(begin: 1.0, end: 0.01).animate(
    CurvedAnimation(
      parent: _shutdownCtrl,
      curve: const Interval(0.4, 1.0, curve: Curves.easeInQuart),
    ),
  );

  // Bright flash at the center
  late final Animation<double> _flash = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.8), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.0), weight: 45),
  ]).animate(_shutdownCtrl);

  // Opening animation — content scales up from center
  late final AnimationController _openCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  void _triggerShutdown() {
    if (_isShuttingDown) return;
    setState(() => _isShuttingDown = true);
    _idleLogoCtrl.stop();
    _shutdownCtrl.forward();
    // Start native window collapse slightly after content starts shrinking
    Future.delayed(const Duration(milliseconds: 640), () {
      _windowChannel.invokeMethod('animateShutdown');
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleIdleFlip();
    // Give the server a moment to start, then connect
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        final url = ref.read(settingsProvider).serverUrl;
        ref.read(wsServiceProvider).connect(url: url);
      }
    });
  }

  @override
  void dispose() {
    _arkanoidTimer?.cancel();
    _idleLogoCtrl.dispose();
    _shutdownCtrl.dispose();
    _openCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(connectionStatusProvider).valueOrNull ?? false;

    // Eagerly initialize providers so they collect data even when their
    // panels are closed.
    ref.watch(debugLogProvider);
    ref.watch(taskBoardProvider);
    ref.watch(gameEconomyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      body: AnimatedBuilder(
        animation: Listenable.merge([_shutdownCtrl, _openCtrl]),
        builder: (context, child) {
          final sy = _isShuttingDown
              ? _scaleY.value
              : Curves.easeOut.transform(_openCtrl.value);
          return Stack(
            children: [
              // Main content with CRT power-off / open transform
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(1.0, sy, 1.0),
                child: child,
              ),
              // White flash overlay
              if (_flash.value > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.white.withValues(alpha: _flash.value),
                    ),
                  ),
                ),
            ],
          );
        },
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.backquote, meta: true):
                () => setState(() => _debugOpen = !_debugOpen),
          },
          child: Focus(
            child: Column(
              children: [
                // Title bar
                _buildTitleBar(isConnected),
                // Main content
                Expanded(
                  child: Row(
                    children: [
                      // Left: Chat panel or Easter egg games
                      SizedBox(
                        width: 440,
                        child: _showGames
                            ? EasterEggGames(
                                onClose: () =>
                                    setState(() => _showGames = false),
                              )
                            : const ChatPanel(),
                      ),
                      // Divider
                      Container(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                      // Right: Agent canvas, Task board, or Shop
                      Expanded(
                        child: switch (_viewIndex) {
                          1 => const TaskBoardPanel(),
                          2 => const ShopPanel(),
                          _ => const AgentCanvas(),
                        },
                      ),
                    ],
                  ),
                ),
                // Debug console
                if (_debugOpen) ...[
                  // Resize handle
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      onVerticalDragUpdate: (d) {
                        setState(() {
                          _debugHeight =
                              (_debugHeight - d.delta.dy).clamp(100.0, 500.0);
                        });
                      },
                      child: Container(
                        height: 4,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: _debugHeight,
                    child: const DebugConsole(),
                  ),
                ],
              ],
            ),
          ),
        ),
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
          // Logo easter egg — click to "power off", 5s hold → Arkanoid
          GestureDetector(
            onTap: _triggerShutdown,
            onLongPressDown: (_) => _onLogoPointerDown(),
            onLongPressUp: _onLogoPointerUp,
            onLongPressCancel: _onLogoPointerUp,
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedBuilder(
                  animation: Listenable.merge([_idleLogoCtrl, _logoSpin]),
                  builder: (context, _) {
                    final t = _isShuttingDown
                        ? _logoSpin.value
                        : _idleLogoCtrl.value;
                    final angle = t * 2 * pi;
                    final cosA = cos(angle);
                    final sinA = sin(angle);
                    final showFront = cosA >= 0;

                    // Thick coin with lighting
                    const totalThickness = 8.0;
                    const edgeLayers = 20;
                    const layerSpacing = totalThickness / edgeLayers;
                    const faceColor = Color(0xFF6C3FB5);

                    final faceScaleX = cosA.abs().clamp(0.01, 1.0);
                    final edgeDir = sinA > 0 ? 1.0 : -1.0;

                    // Light source from top-left (-0.7, -0.6)
                    // How much edge faces the light: dot(edgeNormal, lightDir)
                    // Edge normal points along sinA direction
                    final lightDot = (-0.7 * sinA).clamp(-1.0, 1.0);
                    // Face lighting: how much the face normal (cosA) aligns with light
                    final faceLightDot = (-0.7 * cosA).clamp(-1.0, 1.0);
                    // Face brightness overlay
                    final faceHighlight = ((faceLightDot + 1.0) / 2.0)
                        .clamp(0.0, 1.0); // 0=dark, 1=bright

                    // Drop shadow: shifts opposite to light, stronger when edge-on
                    final shadowOpacity =
                        (0.5 * (1.0 - cosA.abs())).clamp(0.0, 0.4);
                    final shadowDx = sinA * 3.0;

                    return SizedBox(
                      width: 40,
                      height: 28, // extra for shadow
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Drop shadow
                          Transform.translate(
                            offset: Offset(shadowDx, 2.5),
                            child: Container(
                              width: 22 * faceScaleX + totalThickness * sinA.abs(),
                              height: 22,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: shadowOpacity),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Edge layers with directional lighting
                          for (int i = edgeLayers; i >= 1; i--)
                            Builder(builder: (context) {
                              final frac = i / edgeLayers;
                              final dx = edgeDir * i * layerSpacing;

                              // Per-layer lighting: layers closer to light are brighter
                              // Map frac to light exposure based on direction
                              final layerLight = ((lightDot + 1.0) / 2.0 *
                                      (1.0 - frac * 0.3))
                                  .clamp(0.0, 1.0);

                              // Base edge color modulated by light
                              final litColor = Color.lerp(
                                const Color(0xFF1E0A3A), // deep shadow
                                const Color(0xFFB088E8), // bright highlight
                                layerLight,
                              )!;

                              // Rim specular: bright line on edge closest to viewer
                              final rimFactor =
                                  frac < 0.1 ? (1.0 - frac / 0.1) * 0.3 : 0.0;
                              final color = Color.lerp(
                                litColor,
                                Colors.white,
                                rimFactor,
                              )!;

                              final heightShrink = frac * 1.2;
                              return Transform.translate(
                                offset: Offset(dx, 0),
                                child: Container(
                                  width: layerSpacing + 0.5,
                                  height: 24 - heightShrink,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                          // Front face with lighting overlay
                          Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.diagonal3Values(
                              faceScaleX, 1.0, 1.0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Stack(
                                children: [
                                  if (showFront)
                                    Image.asset(
                                      'assets/logo.png',
                                      width: 24,
                                      height: 24,
                                      filterQuality: FilterQuality.medium,
                                    )
                                  else
                                    Container(
                                      width: 24,
                                      height: 24,
                                      color: faceColor,
                                    ),
                                  // Light/shadow overlay on face
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.white.withValues(
                                            alpha: faceHighlight * 0.15,
                                          ),
                                          Colors.black.withValues(
                                            alpha: (1.0 - faceHighlight) * 0.25,
                                          ),
                                        ],
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
                  },
                ),
              ),
            ),
          ),
          const Text(
            'PixelCode',
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
          const SizedBox(width: 16),
          Container(
            width: 1,
            height: 16,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          const ProjectSelector(),
          const Spacer(),
          // Currency display
          _GrymniDisplay(grymni: ref.watch(gameEconomyProvider).grymni),
          const SizedBox(width: 12),
          // View toggle: Canvas / Board / Shop
          _ViewToggle(
            viewIndex: _viewIndex,
            onChanged: (i) => setState(() => _viewIndex = i),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 16,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          // Emergency stop button
          if (isConnected) const _StopAllButton(),
          const SizedBox(width: 12),
          // Games quick-launch (visible when pinned from inside the game)
          if (ref.watch(settingsProvider).showArkanoidButton)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: _showGames ? 'Закрити гру' : 'Ігри',
                child: InkWell(
                  onTap: () =>
                      setState(() => _showGames = !_showGames),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.sports_esports_outlined,
                      size: 16,
                      color: _showGames
                          ? const Color(0xFF00C0D1)
                          : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          Tooltip(
            message: 'Settings',
            child: InkWell(
              onTap: () => showSettingsDialog(context),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.settings_outlined,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Debug Console (Cmd+`)',
            child: InkWell(
              onTap: () => setState(() => _debugOpen = !_debugOpen),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.terminal_rounded,
                  size: 16,
                  color: _debugOpen
                      ? const Color(0xFF00C0D1)
                      : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GrymniDisplay extends StatelessWidget {
  final int grymni;
  const _GrymniDisplay({required this.grymni});

  @override
  Widget build(BuildContext context) {
    final label = grymni >= 1000
        ? '${(grymni / 1000).toStringAsFixed(grymni % 1000 == 0 ? 0 : 1)}K'
        : grymni.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFFD700),
            ),
            child: const Center(
              child: Text(
                '₲',
                style: TextStyle(
                  color: Color(0xFF1A1A1F),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final int viewIndex;
  final ValueChanged<int> onChanged;

  const _ViewToggle({required this.viewIndex, required this.onChanged});

  static const _items = <(IconData, String)>[
    (Icons.grid_view_rounded, 'Офіс'),
    (Icons.dashboard_outlined, 'Дошка'),
    (Icons.storefront_outlined, 'Крамниця'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < _items.length; i++)
            _toggleItem(
              icon: _items[i].$1,
              label: _items[i].$2,
              isActive: viewIndex == i,
              onTap: viewIndex == i ? null : () => onChanged(i),
              isFirst: i == 0,
              isLast: i == _items.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _toggleItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isFirst,
    required bool isLast,
    VoidCallback? onTap,
  }) {
    const accent = Color(0xFF00C0D1);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: isActive ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(5) : Radius.zero,
              right: isLast ? const Radius.circular(5) : Radius.zero,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isActive
                    ? accent
                    : Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? accent
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StopAllButton extends ConsumerStatefulWidget {
  const _StopAllButton();

  @override
  ConsumerState<_StopAllButton> createState() => _StopAllButtonState();
}

class _StopAllButtonState extends ConsumerState<_StopAllButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentsProvider);
    final hasActiveAgents = agents.values.any((a) => a.isActive);
    final enabled = hasActiveAgents;

    final Color baseColor;
    final Color borderColor;
    final Color fgColor;

    if (!enabled) {
      baseColor = Colors.white.withValues(alpha: 0.04);
      borderColor = Colors.white.withValues(alpha: 0.08);
      fgColor = Colors.white.withValues(alpha: 0.2);
    } else if (_pressed) {
      baseColor = const Color(0xFF5A1A1E);
      borderColor = const Color(0xFFFF3B3B).withValues(alpha: 0.7);
      fgColor = const Color(0xFFFF5252);
    } else if (_hovered) {
      baseColor = const Color(0xFF4A1619);
      borderColor = const Color(0xFFFF3B3B).withValues(alpha: 0.55);
      fgColor = const Color(0xFFFF4D4D);
    } else {
      baseColor = const Color(0xFF3D1518);
      borderColor = const Color(0xFFFF3B3B).withValues(alpha: 0.4);
      fgColor = const Color(0xFFFF3B3B);
    }

    return Tooltip(
      message: enabled ? 'Stop all agents' : 'No active agents',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  ref.read(wsServiceProvider).interrupt();
                }
              : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stop_circle_outlined, size: 14, color: fgColor),
                const SizedBox(width: 4),
                Text(
                  'Stop All',
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
