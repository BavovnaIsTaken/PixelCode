import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/agent_provider.dart';
import '../../providers/connected_devices_provider.dart';
import '../../providers/game_economy_provider.dart';
import '../../widgets/deploy/device_deploy_popover.dart';
import '../../providers/settings_provider.dart';
import '../../providers/shop_navigation_provider.dart';
import '../../services/logo_path_dsl.dart';
import '../../providers/task_board_provider.dart';
import '../../widgets/board/task_board_panel.dart';
import '../../widgets/canvas/agent_canvas.dart';
import '../../widgets/chat/chat_panel.dart';
import '../../widgets/easter_eggs/easter_egg_games.dart';
import '../../widgets/debug/debug_console.dart';
import '../../widgets/project/project_selector.dart';
import '../../widgets/session/party_counter.dart';
import '../../widgets/session/session_picker.dart';
import '../../widgets/settings/settings_dialog.dart';
import '../../widgets/painters/pixel_glitch_painter.dart';
import '../../widgets/shop/shop_panel.dart';
import '../../models/app_theme.dart';

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
  double _shutdownHeight = 0;
  int _viewIndex = 0; // 0=Office, 1=Board, 2=Shop
  bool _showGames = false;
  int _mobileTab = 0; // 0=Chat, 1=Office, 2=Board, 3=Shop
  int _prevMobileTab = 0;

  // Icon fly-to-opposite-corner on shutdown
  bool _iconMoving = false;
  Offset _iconStart = Offset.zero;
  List<Offset> _iconPath = []; // zigzag waypoints: start → H → V → H → V … → end

  // Swipe-between-tabs tracking
  double _swipeDelta = 0;
  late final AnimationController _iconMoveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  late final AnimationController _tabSwitchCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  static const double _iconSize = 24.0;

  /// Chops [total] distance into random steps of [minStep]–[maxStep] px.
  /// The last step takes whatever remains so the sum is always exactly [total].
  static List<double> _randomSteps(
      Random rng, double total, double minStep, double maxStep) {
    if (total.abs() <= minStep) return [total];
    final sign = total.sign;
    final steps = <double>[];
    var remaining = total.abs();
    while (remaining > maxStep) {
      final s = minStep + rng.nextDouble() * (maxStep - minStep);
      steps.add(sign * s);
      remaining -= s;
    }
    steps.add(sign * remaining);
    return steps;
  }

  /// Builds a random zigzag path each call (uses [rng] with no fixed seed).
  /// Interleaves H and V steps at a 1.3 : 1 ratio so horizontal direction
  /// changes happen ~30% more often than vertical ones.
  /// Step sizes are the same range for both axes. Always ends at [end].
  static List<Offset> _computeIconPath(Offset start, Offset end, Random rng) {
    const step = 6 * _iconSize;
    const maxStep = 10 * _iconSize;
    final hSteps = _randomSteps(rng, end.dx - start.dx, step, maxStep);
    final vSteps = _randomSteps(rng, end.dy - start.dy, step, maxStep);

    final path = <Offset>[start];
    var cx = start.dx;
    var cy = start.dy;
    int hi = 0, vi = 0;
    // hCredit accumulates 1.3 per V-step consumed; each whole unit = one H step.
    double hCredit = 0;

    while (hi < hSteps.length || vi < vSteps.length) {
      hCredit += 1.3;
      while (hCredit >= 1.0 && hi < hSteps.length) {
        cx += hSteps[hi++];
        path.add(Offset(cx, cy));
        hCredit -= 1.0;
      }
      if (vi < vSteps.length) {
        cy += vSteps[vi++];
        path.add(Offset(cx, cy));
      } else {
        // V exhausted — drain remaining H steps
        while (hi < hSteps.length) {
          cx += hSteps[hi++];
          path.add(Offset(cx, cy));
        }
      }
    }
    return path;
  }

  final _rng = Random();

  /// Builds the icon path: uses DSL script when set, otherwise the built-in
  /// zigzag algorithm. The DSL path is sampled at 200 uniformly-spaced points
  /// so the existing trail rendering code works unchanged.
  List<Offset> _buildIconPath(Offset start, Offset end, Size screen) {
    final script = ref.read(settingsProvider).logoPathScript;
    if (script != null && script.isNotEmpty) {
      const samples = 200;
      final path = <Offset>[];
      for (int i = 0; i <= samples; i++) {
        final t = i / samples;
        final pos = evalLogoPath(
          script: script,
          start: start,
          end: end,
          screenWidth: screen.width,
          screenHeight: screen.height,
          t: t,
        );
        path.add(pos ?? Offset.lerp(start, end, t)!);
      }
      return path;
    }
    return _computeIconPath(start, end, _rng);
  }

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

  // Glitch effect on the logo (triggered on hover)
  late final AnimationController _glitchCtrl = AnimationController(vsync: this);
  int _glitchSeed = 0;
  ui.Image? _logoImage;
  ByteData? _logoImagePixels;
  bool _logoHovered = false;

  /// Reads glitch settings from the provider.
  AppSettings get _settings => ref.read(settingsProvider);

  Future<void> _loadLogoImage() async {
    final data = await rootBundle.load('assets/logo.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final pixels = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (mounted) {
      setState(() {
        _logoImage = frame.image;
        _logoImagePixels = pixels;
      });
    }
  }

  void _onLogoHoverChanged(bool hovered) {
    _logoHovered = hovered;
    if (hovered && !_isShuttingDown && _settings.glitchEnabled) {
      _startGlitchLoop();
    } else {
      _glitchCtrl
        ..stop()
        ..reset();
    }
  }

  void _startGlitchLoop() {
    if (!_logoHovered || _isShuttingDown || !mounted) return;
    if (!_settings.glitchEnabled) return;
    _glitchSeed = _rng.nextInt(10000);
    final baseDur = 400 + _rng.nextInt(801); // 400–1200ms
    final dur = (baseDur / _settings.glitchSpeed).round();
    _glitchCtrl
      ..duration = Duration(milliseconds: dur)
      ..forward(from: 0.0).then((_) {
        if (_logoHovered) _startGlitchLoop();
      });
  }

  // Shutdown animation — matches the native window collapse duration (1.5s).
  late final AnimationController _shutdownCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  // CRT-style flash — stays dark while the icon flies, then ramps up during
  // the rapid phase of the native easeIn collapse. Holds at peak so the very
  // last frame the user sees is a bright glow before instant blackout.
  late final Animation<double> _flash = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 68),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.9), weight: 18),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.9), weight: 14),
  ]).animate(_shutdownCtrl);

  // Opening animation — content scales up from center
  late final AnimationController _openCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  void _triggerShutdown() {
    if (_isShuttingDown) return;
    final size = MediaQuery.of(context).size;
    _shutdownHeight = size.height;
    const iconSize = 24.0;
    final start = const Offset(16, (48 - iconSize) / 2);
    final end = Offset(size.width - iconSize - 16, size.height - iconSize - 16);
    setState(() {
      _isShuttingDown = true;
      _iconMoving = true;
      _iconStart = start;
      _iconPath = _buildIconPath(start, end, size);
    });
    _glitchCtrl.stop();
    _shutdownCtrl.forward();
    _iconMoveCtrl.forward();
    // Fire-and-forget cleanup — AppDelegate.applicationWillTerminate is the
    // safety net that kills any orphaned server processes.
    _performCleanup();

    final platform = defaultTargetPlatform;
    final isNative =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

    // After the icon finishes (1.1s), start the native window collapse (0.4s).
    Future<void>.delayed(const Duration(milliseconds: 1100)).then((_) {
      if (!mounted) return;
      if (isNative) _windowChannel.invokeMethod('animateShutdown');
    });

    // After ALL Flutter animations complete (1.5s), terminate the process.
    // This decouples the exit from NSAnimationContext/UIView.animate — which
    // can complete instantly when Reduce Motion is on or the window is in the
    // background — eliminating the race condition where terminate() fires
    // before Flutter's shutdown animations have a chance to play.
    _shutdownCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (isNative) _windowChannel.invokeMethod('terminateApp');
      }
    });
  }

  /// Disposes WebSocket and server process so native exit doesn't leave orphans.
  /// Capped at 4 seconds to avoid hanging indefinitely (the server process kill
  /// tree uses a 2-second SIGTERM grace period internally).
  Future<void> _performCleanup() async {
    try {
      await Future.wait([
        ref.read(wsServiceProvider).dispose(),
        ref.read(serverProcessProvider).dispose(),
      ]).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Best-effort — we're shutting down regardless.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLogoImage();
  }

  @override
  void dispose() {
    _arkanoidTimer?.cancel();
    _logoImage?.dispose();
    _glitchCtrl.dispose();
    _shutdownCtrl.dispose();
    _openCtrl.dispose();
    _tabSwitchCtrl.dispose();
    _iconMoveCtrl.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.sizeOf(context).width < 600;

  bool get _isServerConnected =>
      ref.read(connectionStatusProvider).valueOrNull ?? false;

  /// Number of mobile tabs available (2 without server, 4 with).
  int get _mobileTabCount => _isServerConnected ? 4 : 2;

  void _switchMobileTab(int newTab) {
    if (newTab < 0 || newTab >= _mobileTabCount || newTab == _mobileTab) return;
    _prevMobileTab = _mobileTab;
    _mobileTab = newTab;
    _tabSwitchCtrl.forward(from: 0.0);
    setState(() {});
  }

  /// Builds the content widget for the given mobile tab.
  /// Without server: 0=Chat, 1=Office.
  /// With server: 0=Chat, 1=Office, 2=Board, 3=Shop.
  Widget _buildMobileTabContent([int? overrideTab]) {
    final tab = overrideTab ?? _mobileTab;
    if (_isServerConnected) {
      return switch (tab) {
        1 => const AgentCanvas(),
        2 => const TaskBoardPanel(),
        3 => const ShopPanel(),
        _ => _showGames
            ? EasterEggGames(
                onClose: () => setState(() => _showGames = false),
              )
            : const ChatPanel(),
      };
    }
    return switch (tab) {
      1 => const _ConnectionWaiting(),
      _ => _showGames
          ? EasterEggGames(
              onClose: () => setState(() => _showGames = false),
            )
          : const ChatPanel(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;

    // Clamp mobile tab when server-dependent tabs disappear.
    if (_mobileTab >= _mobileTabCount) {
      _mobileTab = _mobileTabCount - 1;
    }
    if (_prevMobileTab >= _mobileTabCount) {
      _prevMobileTab = _mobileTabCount - 1;
      _tabSwitchCtrl.reset();
    }
    // Clamp desktop view index (0=Office always available).
    if (!isConnected && _viewIndex > 0) {
      _viewIndex = 0;
    }

    // Navigate to Shop + specific tab when requested (e.g. from settings).
    ref.listen(shopDeepLinkProvider, (_, tab) {
      if (tab != null) {
        setState(() => _viewIndex = 2); // desktop: Shop
        _switchMobileTab(3);            // mobile: Shop
      }
    });

    // Eagerly initialize providers so they collect data even when their
    // panels are closed.
    ref.watch(debugLogProvider);
    ref.watch(taskBoardProvider);
    ref.watch(gameEconomyProvider);
    ref.watch(connectedDevicesProvider);

    final tc = context.appColors;

    return Scaffold(
      backgroundColor: tc.background,
      body: AnimatedBuilder(
        animation: Listenable.merge([_shutdownCtrl, _openCtrl, _iconMoveCtrl]),
        builder: (context, child) {
          final sy = _isShuttingDown
              ? 1.0
              : Curves.easeOut.transform(_openCtrl.value);
          // Content fades out as the CRT flash ramps up — the flash replaces
          // the content so the last visible frame is a bright glow.
          final contentOpacity = _isShuttingDown ? 1.0 - _flash.value : 1.0;

          Widget body = Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: contentOpacity.clamp(0.0, 1.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(1.0, sy, 1.0),
                  child: child,
                ),
              ),
              // Icon flying to opposite corner + glitch trail
              if (_iconMoving && _logoImage != null)
                IgnorePointer(child: _buildIconTrail()),
              // CRT flash overlay — on top of everything
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

          // During shutdown: freeze the layout at the original window height
          // so content doesn't re-layout as the native frame shrinks.
          // Alignment.center keeps the content's center at the window's center
          // — the native collapse is symmetric, so the center stays put and
          // top/bottom get progressively clipped (old-TV iris effect).
          if (_isShuttingDown) {
            body = OverflowBox(
              maxHeight: _shutdownHeight,
              alignment: Alignment.center,
              child: body,
            );
          }

          return body;
        },
        child: _isMobile
            ? _buildMobileLayout(isConnected)
            : _buildDesktopLayout(isConnected),
      ),
    );
  }

  Widget _buildDesktopLayout(bool isConnected) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.backquote, meta: true): () =>
            setState(() => _debugOpen = !_debugOpen),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
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
                            onClose: () => setState(() => _showGames = false),
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
                    child: AnimatedSwitcher(
                      duration: _viewIndex == 0
                          ? const Duration(milliseconds: 350)
                          : Duration.zero,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, _) {
                            return ClipRect(
                              child: Align(
                                heightFactor: animation.value,
                                widthFactor: animation.value,
                                child: child,
                              ),
                            );
                          },
                        );
                      },
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [...previousChildren, ?currentChild],
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(_viewIndex),
                        child: switch (_viewIndex) {
                          1 => const TaskBoardPanel(),
                          2 => const ShopPanel(),
                          _ => const AgentCanvas(),
                        },
                      ),
                    ),
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
                      _debugHeight = (_debugHeight - d.delta.dy).clamp(
                        100.0,
                        500.0,
                      );
                    });
                  },
                  child: Container(
                    height: 4,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              SizedBox(height: _debugHeight, child: const DebugConsole()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(bool isConnected) {
    return SafeArea(
      bottom: false, // bottom handled by nav bar
      child: Column(
        children: [
          // Compact title bar
          _buildMobileTitleBar(isConnected),
          // Content — one panel at a time, swipeable
          Expanded(
            child: Stack(
              children: [
                // Tab content with push transition
                ClipRect(
                  child: AnimatedBuilder(
                    animation: _tabSwitchCtrl,
                    builder: (context, _) {
                      if (!_tabSwitchCtrl.isAnimating) {
                        return _buildMobileTabContent();
                      }
                      final progress = Curves.easeOutCubic
                          .transform(_tabSwitchCtrl.value);
                      final goingRight = _mobileTab > _prevMobileTab;
                      return Stack(
                        children: [
                          // Outgoing page
                          FractionalTranslation(
                            translation: Offset(
                              goingRight ? -progress : progress,
                              0,
                            ),
                            child: SizedBox.expand(
                              child: _buildMobileTabContent(_prevMobileTab),
                            ),
                          ),
                          // Incoming page
                          FractionalTranslation(
                            translation: Offset(
                              goingRight
                                  ? 1.0 - progress
                                  : -(1.0 - progress),
                              0,
                            ),
                            child: SizedBox.expand(
                              child: _buildMobileTabContent(_mobileTab),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // Overlay gesture detector for swipe-between-tabs
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) {
                      _swipeDelta = 0;
                    },
                    onHorizontalDragUpdate: (d) {
                      _swipeDelta += d.delta.dx;
                    },
                    onHorizontalDragEnd: (d) {
                      const threshold = 50.0;
                      const velocityThreshold = 300.0;
                      final velocity = d.primaryVelocity ?? 0;

                      if (_swipeDelta > threshold ||
                          velocity > velocityThreshold) {
                        // Swipe right → previous tab
                        _switchMobileTab(_mobileTab - 1);
                      } else if (_swipeDelta < -threshold ||
                          velocity < -velocityThreshold) {
                        // Swipe left → next tab
                        _switchMobileTab(_mobileTab + 1);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          // Bottom navigation
          _buildMobileBottomNav(),
        ],
      ),
    );
  }

  Widget _buildMobileTitleBar(bool isConnected) {
    final tc = context.appColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tc.surface,
        border: Border(
          bottom: BorderSide(color: tc.divider),
        ),
      ),
      child: Row(
        children: [
          // Logo
          GestureDetector(
            onTap: _triggerShutdown,
            onLongPressDown: (_) => _onLogoPointerDown(),
            onLongPressUp: _onLogoPointerUp,
            onLongPressCancel: _onLogoPointerUp,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.asset(
                'assets/logo.png',
                width: 22,
                height: 22,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SessionPicker(compact: true),
          const Spacer(),
          // Connected devices indicator (landscape only on iPhone)
          if (isConnected &&
              MediaQuery.orientationOf(context) == Orientation.landscape)
            const PartyCounter(),
          if (isConnected &&
              MediaQuery.orientationOf(context) == Orientation.landscape)
            const SizedBox(width: 6),
          // Currency (server-dependent)
          if (isConnected)
            _GrymniDisplay(grymni: ref.watch(gameEconomyProvider).grymni),
          if (isConnected)
            const SizedBox(width: 8),
          // iOS deploy
          if (isConnected) _DeviceDeployButton(),
          // Settings
          IconButton(
            onPressed: () => showSettingsDialog(context),
            icon: Icon(
              Icons.settings_outlined,
              size: 18,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;
    final items = <(IconData, String)>[
      (Icons.chat_outlined, 'Чат'),
      (Icons.grid_view_rounded, 'Офіс'),
      if (isConnected) (Icons.dashboard_outlined, 'Дошка'),
      if (isConnected) (Icons.storefront_outlined, 'Крамниця'),
    ];

    final tc = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: tc.surface,
        border: Border(
          top: BorderSide(color: tc.divider),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < items.length; i++)
                _MobileNavItem(
                  icon: items[i].$1,
                  label: items[i].$2,
                  isActive: _mobileTab == i,
                  onTap: () => _switchMobileTab(i),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(bool isConnected) {
    final tc = context.appColors;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tc.surface,
        border: Border(
          bottom: BorderSide(color: tc.divider),
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
              onEnter: (_) => _onLogoHoverChanged(true),
              onExit: (_) => _onLogoHoverChanged(false),
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5.5),
                  child: AnimatedBuilder(
                    animation: _glitchCtrl,
                    builder: (context, _) {
                      const size = 24.0;
                      final t = _glitchCtrl.value;
                      final glitching =
                          _glitchCtrl.isAnimating && t > 0 && _logoImage != null;

                      if (!glitching) {
                        return Image.asset(
                          'assets/logo.png',
                          width: size,
                          height: size,
                          filterQuality: FilterQuality.medium,
                        );
                      }

                      final frame = (t * 8).floor();

                      return SizedBox(
                        width: size,
                        height: size,
                        child: CustomPaint(
                          size: const Size(size, size),
                          painter: PixelGlitchPainter(
                            image: _logoImage!,
                            seed: _glitchSeed + frame,
                            pixelPercent: _settings.glitchIntensity,
                            displaySize: size,
                            imagePixels: _logoImagePixels,
                            bandHeightMax: _settings.glitchBandHeight,
                            shiftStrength: _settings.glitchShift,
                            chromaStrength: _settings.glitchChroma,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          const SessionPicker(),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 16,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          const ProjectSelector(),
          const Spacer(),
          // Connected devices indicator
          if (isConnected) const PartyCounter(),
          if (isConnected) const SizedBox(width: 8),
          // Currency display (server-dependent)
          if (isConnected)
            _GrymniDisplay(grymni: ref.watch(gameEconomyProvider).grymni),
          if (isConnected)
            const SizedBox(width: 12),
          // View toggle: Canvas / Board / Shop
          _ViewToggle(
            viewIndex: _viewIndex,
            onChanged: (i) => setState(() => _viewIndex = i),
            showServerTabs: isConnected,
          ),
          if (isConnected)
            const SizedBox(width: 8)
          else
            const SizedBox(width: 8),
          // Games quick-launch (visible when pinned from inside the game)
          if (ref.watch(settingsProvider).showArkanoidButton)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: _showGames ? 'Закрити гру' : 'Ігри',
                child: InkWell(
                  onTap: () => setState(() => _showGames = !_showGames),
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
          if (isConnected) _DeviceDeployButton(),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Налаштування',
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
            message: 'Консоль (Cmd+`)',
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

  /// Returns the current icon position by walking the pre-computed zigzag path.
  /// Each segment gets equal animation-time; easeInOut is applied per segment.
  Offset _currentIconPos() {
    if (_iconPath.length < 2) return _iconStart;
    final segments = _iconPath.length - 1;
    final raw = _iconMoveCtrl.value.clamp(0.0, 1.0);
    final segT = 1.0 / segments;
    final segIdx = (raw / segT).floor().clamp(0, segments - 1);
    final localT = Curves.easeInOut.transform(
      ((raw - segIdx * segT) / segT).clamp(0.0, 1.0),
    );
    return Offset.lerp(_iconPath[segIdx], _iconPath[segIdx + 1], localT)!;
  }

  Widget _buildIconTrail() {
    if (_iconPath.length < 2) return const SizedBox.shrink();
    const iconSize = 24.0;
    const trailStep = 14.0;

    final raw = _iconMoveCtrl.value.clamp(0.0, 1.0);
    final segments = _iconPath.length - 1;
    final segT = 1.0 / segments;
    final currentPos = _currentIconPos();
    final animFrame = (raw * 60).toInt();

    final particles = <Widget>[];

    // Walk every segment that has been (partially) covered
    for (int seg = 0; seg < segments; seg++) {
      final segStartRaw = seg * segT;
      if (raw < segStartRaw) break;

      final localRaw = ((raw - segStartRaw) / segT).clamp(0.0, 1.0);
      final coveredFraction = raw >= (seg + 1) * segT
          ? 1.0
          : Curves.easeInOut.transform(localRaw);

      final from = _iconPath[seg];
      final to = _iconPath[seg + 1];
      final coveredTo = Offset.lerp(from, to, coveredFraction)!;

      final delta = to - from;
      final dist = delta.distance;
      if (dist <= 0) continue;
      final step = delta / dist * trailStep;

      var pos = from;
      var walked = 0.0;
      final coveredDist = (coveredTo - from).distance;
      while (walked <= coveredDist) {
        final seed = (pos.dx * 7 + pos.dy * 13).toInt().abs();
        particles.add(_trailMark(pos: pos, seed: seed, iconSize: iconSize));
        pos = pos + step;
        walked += trailStep;
      }
    }

    // Leading icon — lightly glitched, animated seed
    particles.add(
      Positioned(
        left: currentPos.dx,
        top: currentPos.dy,
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: CustomPaint(
            size: const Size(iconSize, iconSize),
            painter: PixelGlitchPainter(
              image: _logoImage!,
              seed: _glitchSeed + animFrame,
              pixelPercent: 0.18,
              displaySize: iconSize,
              imagePixels: _logoImagePixels,
              bandHeightMax: _settings.glitchBandHeight,
              shiftStrength: _settings.glitchShift,
              chromaStrength: _settings.glitchChroma,
            ),
          ),
        ),
      ),
    );

    return Stack(children: particles);
  }

  Widget _trailMark({
    required Offset pos,
    required int seed,
    required double iconSize,
  }) {
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Opacity(
        opacity: 0.75,
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: CustomPaint(
            size: Size(iconSize, iconSize),
            painter: PixelGlitchPainter(
              image: _logoImage!,
              seed: seed,
              pixelPercent: 0.55,
              displaySize: iconSize,
              imagePixels: _logoImagePixels,
              bandHeightMax: _settings.glitchBandHeight,
              shiftStrength: _settings.glitchShift,
              chromaStrength: _settings.glitchChroma,
            ),
          ),
        ),
      ),
    );
  }
}

class _GrymniDisplay extends ConsumerWidget {
  final int grymni;
  const _GrymniDisplay({required this.grymni});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = grymni >= 1000
        ? '${(grymni / 1000).toStringAsFixed(grymni % 1000 == 0 ? 0 : 1)}K'
        : grymni.toString();
    return Tooltip(
      message: 'Поповнити гримні',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            ref.read(shopDeepLinkProvider.notifier).state = shopTabDonation;
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 3, 8, 3),
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
          ),
        ),
      ),
    );
  }
}

// ─── Device deploy button (opens popover with Android / iOS tabs) ─────────

class _DeviceDeployButton extends StatefulWidget {
  @override
  State<_DeviceDeployButton> createState() => _DeviceDeployButtonState();
}

class _DeviceDeployButtonState extends State<_DeviceDeployButton> {
  OverlayEntry? _popover;

  @override
  void dispose() {
    _removePopover();
    super.dispose();
  }

  void _removePopover() {
    _popover?.remove();
    _popover = null;
  }

  void _togglePopover() {
    if (_popover != null) {
      _removePopover();
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _popover = showDeviceDeployPopover(
      context: context,
      anchor: Offset(offset.dx, offset.dy + size.height + 4),
      onDismiss: _removePopover,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Встановити на пристрій',
      child: InkWell(
        onTap: _togglePopover,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.phone_iphone,
            size: 16,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final int viewIndex;
  final ValueChanged<int> onChanged;
  final bool showServerTabs;

  const _ViewToggle({
    required this.viewIndex,
    required this.onChanged,
    this.showServerTabs = true,
  });

  static const _allItems = <(IconData, String)>[
    (Icons.grid_view_rounded, 'Офіс'),
    (Icons.dashboard_outlined, 'Дошка'),
    (Icons.storefront_outlined, 'Крамниця'),
  ];

  @override
  Widget build(BuildContext context) {
    final items = showServerTabs
        ? _allItems
        : [_allItems[0]]; // Only Office without server
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++)
            _toggleItem(
              icon: items[i].$1,
              label: items[i].$2,
              isActive: viewIndex == i,
              onTap: viewIndex == i ? null : () => onChanged(i),
              isFirst: i == 0,
              isLast: i == items.length - 1,
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
                color: isActive ? accent : Colors.white.withValues(alpha: 0.3),
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

class _MobileNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _MobileNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF00C0D1);
    final color = isActive ? accent : Colors.white.withValues(alpha: 0.3);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionWaiting extends StatelessWidget {
  const _ConnectionWaiting();

  @override
  Widget build(BuildContext context) {
    final tc = context.appColors;
    return Container(
      color: tc.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Очікування зʼєднання...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Офіс буде доступний після підключення до сервера',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.15),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

