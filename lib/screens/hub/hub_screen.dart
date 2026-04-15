import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
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
import '../../widgets/session/session_picker.dart';
import '../../widgets/settings/settings_dialog.dart';
import '../../widgets/painters/pixel_glitch_painter.dart';
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
  double _shutdownHeight = 0;
  int _viewIndex = 0; // 0=Office, 1=Board, 2=Shop
  bool _showGames = false;
  int _mobileTab = 0; // 0=Chat, 1=Office, 2=Board, 3=Shop

  // Icon fly-to-opposite-corner on shutdown
  bool _iconMoving = false;
  Offset _iconStart = Offset.zero;
  Offset _iconEnd = Offset.zero;
  List<Offset> _iconPath = []; // zigzag waypoints: start → H → V → H → V … → end
  late final AnimationController _iconMoveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
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
    const step = 3 * _iconSize;
    const maxStep = 6 * _iconSize;
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

  // Shutdown animation
  late final AnimationController _shutdownCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  // Bright flash at the center
  late final Animation<double> _flash = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.0), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.8), weight: 15),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 0.0), weight: 45),
  ]).animate(_shutdownCtrl);

  // Content lift + fade during native window collapse.
  // Intentionally faster than the native 550ms so it finishes first.
  late final AnimationController _liftCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

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
    setState(() {
      _isShuttingDown = true;
      _iconMoving = true;
      // Icon lives at left padding=16, vertically centred in the 48px title bar
      _iconStart = const Offset(16, (48 - iconSize) / 2);
      // Opposite corner: bottom-right
      _iconEnd = Offset(size.width - iconSize - 16, size.height - iconSize - 16);
      _iconPath = _computeIconPath(_iconStart, _iconEnd, _rng);
    });
    _glitchCtrl.stop();
    _shutdownCtrl.forward();
    _iconMoveCtrl.forward();
    // Start native window collapse slightly after content starts shrinking
    Future.delayed(const Duration(milliseconds: 640), () {
      final platform = defaultTargetPlatform;
      if (platform == TargetPlatform.macOS || platform == TargetPlatform.iOS) {
        _windowChannel.invokeMethod('animateShutdown');
      }
      _liftCtrl.forward();
    });
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
    _liftCtrl.dispose();
    _openCtrl.dispose();
    _iconMoveCtrl.dispose();
    super.dispose();
  }

  bool get _isMobile => MediaQuery.sizeOf(context).width < 600;

  @override
  Widget build(BuildContext context) {
    final isConnected =
        ref.watch(connectionStatusProvider).valueOrNull ?? false;

    // Eagerly initialize providers so they collect data even when their
    // panels are closed.
    ref.watch(debugLogProvider);
    ref.watch(taskBoardProvider);
    ref.watch(gameEconomyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E11),
      body: AnimatedBuilder(
        animation: Listenable.merge([_shutdownCtrl, _liftCtrl, _openCtrl, _iconMoveCtrl]),
        builder: (context, child) {
          final sy = _isShuttingDown
              ? 1.0
              : Curves.easeOut.transform(_openCtrl.value);
          // Lift content UP + fade out, finishing before the native window
          // collapse so the animation never lags behind the shrinking frame.
          final t = Curves.easeOut.transform(_liftCtrl.value);
          final liftY = _isShuttingDown ? -t * (_shutdownHeight - 50) / 2 : 0.0;
          final contentOpacity = _isShuttingDown ? 1.0 - t : 1.0;
          return Stack(
            children: [
              Opacity(
                opacity: contentOpacity,
                child: Transform.translate(
                  offset: Offset(0, liftY),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(1.0, sy, 1.0),
                    child: child,
                  ),
                ),
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
              // Icon flying to opposite corner + glitch trail
              if (_iconMoving && _logoImage != null)
                IgnorePointer(child: _buildIconTrail()),
            ],
          );
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
          // Content — one panel at a time
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_mobileTab),
                child: switch (_mobileTab) {
                  1 => const AgentCanvas(),
                  2 => const TaskBoardPanel(),
                  3 => const ShopPanel(),
                  _ =>
                    _showGames
                        ? EasterEggGames(
                            onClose: () => setState(() => _showGames = false),
                          )
                        : const ChatPanel(),
                },
              ),
            ),
          ),
          // Bottom navigation
          _buildMobileBottomNav(),
        ],
      ),
    );
  }

  Widget _buildMobileTitleBar(bool isConnected) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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
          // Currency
          _GrymniDisplay(grymni: ref.watch(gameEconomyProvider).grymni),
          const SizedBox(width: 8),
          // Stop button
          if (isConnected) const _StopAllButton(iconOnly: true),
          const SizedBox(width: 4),
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
    const items = <(IconData, String)>[
      (Icons.chat_outlined, 'Чат'),
      (Icons.grid_view_rounded, 'Офіс'),
      (Icons.dashboard_outlined, 'Дошка'),
      (Icons.storefront_outlined, 'Крамниця'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1F),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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
                  onTap: () => setState(() => _mobileTab = i),
                ),
            ],
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
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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



class _StopAllButton extends ConsumerStatefulWidget {
  const _StopAllButton({this.iconOnly = false});

  final bool iconOnly;

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
      message: enabled ? 'Зупинити всіх агентів' : 'Немає активних агентів',
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
            padding: EdgeInsets.symmetric(
              horizontal: widget.iconOnly ? 6 : 10,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stop_circle_outlined, size: 14, color: fgColor),
                if (!widget.iconOnly) ...[
                  const SizedBox(width: 4),
                  Text(
                    'Стоп',
                    style: TextStyle(
                      color: fgColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

