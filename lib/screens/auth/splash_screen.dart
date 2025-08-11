import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_channel_swift_demo/core/configs/app_routes.dart';

import '../../settings/providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _logoScale;
  Animation<double>? _fadeIn;
  bool _navigated = false;

  static const Duration _minDisplay = Duration(seconds: 2 );

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    _startFlow();
  }

  void _setupAnimation() {
    if (_controller != null) return;
    final ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _controller = ctrl;

    _logoScale = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _fadeIn = CurvedAnimation(
      parent: ctrl,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    ctrl.forward();
  }

  Future<void> _startFlow() async {
    final restoreFuture =
    ref.read(authViewModelProvider.notifier).tryRestoreSession();
    final delayFuture = Future.delayed(_minDisplay);

    // Wait for BOTH auth restore and minimum splash duration
    await Future.wait([restoreFuture, delayFuture]);

    if (!mounted || _navigated) return;
    final auth = ref.read(authViewModelProvider);

    _navigated = true;
    if (auth.isLoggedIn) {
      Navigator.pushReplacementNamed(context, AppRoutes.homeScreen);
    } else {
      Navigator.pushNamed(context, AppRoutes.loginScreen);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  LinearGradient get _backgroundGradient => const LinearGradient(
    colors: [
      Color(0xFF0F172A),
      Color(0xFF0B2540),
      Color(0xFF111827),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final fade = _fadeIn;
    final scale = _logoScale;

    Widget animatedContent;
    if (controller == null || fade == null || scale == null) {
      animatedContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            height: 60,
            width: 60,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          SizedBox(height: 24),
          Text(
            'Initializing...',
            style: TextStyle(color: Colors.white70, letterSpacing: 0.5),
          ),
        ],
      );
    } else {
      animatedContent = AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Opacity(
            opacity: fade.value.clamp(0.0, 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.7 + (scale.value * 0.3),
                  child: Container(
                    height: 110,
                    width: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF2563EB),
                          Color(0xFF3B82F6),
                          Color(0xFF60A5FA),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withOpacity(0.35),
                          blurRadius: 28,
                          spreadRadius: 4,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.travel_explore_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'WebGIS 3D',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: 0.85,
                  child: Text(
                    'Exploring spatial intelligence',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                        backgroundColor: Colors.white12,
                      ),
                    ),
                    SizedBox(width: 14),
                    Text(
                      'Initializing...',
                      style: TextStyle(
                        color: Colors.white70,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: _backgroundGradient),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _RadialGlowPainter()),
              ),
            ),
            Center(child: animatedContent),
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: 0.65,
                child: Column(
                  children: [
                    Text(
                      'v1.0.0',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white60,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '© ${DateTime.now().year} SeedsWild',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white38,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.55;
    final gradient = RadialGradient(
      colors: [
        const Color(0xFF1E3A8A).withOpacity(0.18),
        const Color(0xFF1E3A8A).withOpacity(0.05),
        Colors.transparent,
      ],
      stops: const [0.0, 0.45, 1.0],
    );
    final paint =
    Paint()..shader = gradient.createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}