// =============================================================
// SPLASH SCREEN
// Branded intro that restores session and navigates to the proper
// screen after a minimum display time.
// Tech stack: Flutter + Riverpod (authViewModelProvider)
// =============================================================
//
// FLOW OVERVIEW
// 1) initState:
//    - Set up intro animation (logo scales, content fades in).
//    - Start session restore (async) AND a minimum visible delay in parallel.
// 2) After both complete, route once:
//    - If a valid session exists -> Home.
//    - Otherwise -> Login.
// 3) Clean up animation controller in dispose.
//
// CUSTOMIZE QUICKLY
// - _minDisplay: control minimum splash visibility.
// - _backgroundGradient: adjust background colors.
// - Logo/branding: update colors, icon, shadows.
//
// SAFETY GUARDS
// - _navigated prevents double navigation.
// - mounted checks ensure no navigation after widget disposal.
// =============================================================

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
  // --------------- ANIMATION ---------------
  // Drives both scale and fade animations.
  AnimationController? _controller;

  // Scales the circular logo from ~70% to ~100%.
  Animation<double>? _logoScale;

  // Fades in the title/subtitle and progress indicator.
  Animation<double>? _fadeIn;

  // --------------- NAVIGATION GUARD ---------------
  // Ensures navigation happens only once.
  bool _navigated = false;

  // --------------- TIMING ---------------
  // Minimum time the splash stays on screen (prevents instant flicker).
  static const Duration _minDisplay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _setupAnimation(); // Prepare and start the intro animation.
    _startFlow();      // Start auth restore + minimum delay in parallel.
  }

  // =============================================================
  // SETUP: Animation Controller + Curves
  // - Scale uses easeOutBack for a subtle "pop".
  // - Fade uses easeOut for a smooth content reveal.
  // =============================================================
  void _setupAnimation() {
    // Prevents re-initialization during hot reload.
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

    // Start the animation immediately.
    ctrl.forward();
  }

  // =============================================================
  // BOOTSTRAP: Restore Session + Enforce Minimum Display Time
  // - Waits for BOTH to complete (using Future.wait).
  // - Routes once based on auth state.
  // =============================================================

  Future<void> _startFlow() async {
    // This will now call your updated tryRestoreSession() which validates the token
    final restoreFuture = ref.read(authViewModelProvider.notifier).tryRestoreSession();

    // Enforce the minimum splash visibility
    final delayFuture = Future.delayed(_minDisplay);

    // Wait for both operations to finish
    await Future.wait([restoreFuture, delayFuture]);

    if (!mounted || _navigated) return;

    final auth = ref.read(authViewModelProvider);

    // Route based on authentication state
    _navigated = true;
    if (auth.isLoggedIn) {
      Navigator.pushReplacementNamed(context, AppRoutes.homeScreen);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.loginScreen);
    }
  }
  @override
  void dispose() {
    // Always dispose animation controller to prevent leaks.
    _controller?.dispose();
    super.dispose();
  }

  // =============================================================
  // THEME: Background Gradient
  // Adjust these colors to update the splash mood/theme.
  // =============================================================
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

    // Locals for readability and safe null checks.
    final controller = _controller;
    final fade = _fadeIn;
    final scale = _logoScale;

    // =============================================================
    // CONTENT: Either fallback loader (very early build) or animation.
    // =============================================================
    Widget animatedContent;
    if (controller == null || fade == null || scale == null) {
      // Early fallback: shows if the controller hasn't initialized yet.
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
      // Main animated sequence.
      animatedContent = AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Opacity(
            opacity: fade.value.clamp(0.0, 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---------- Brand Badge (Circular Gradient + Icon) ----------
                Transform.scale(
                  // Scale from 0.7 to 1.0 over the first half of the timeline.
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

                // ---------- Title ----------
                Text(
                  'WebGIS 3D',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 10),

                // ---------- Tagline ----------
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

                // ---------- Progress Row ----------
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

    // =============================================================
    // SCAFFOLD: Gradient background + subtle radial glow + footer info.
    // =============================================================
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: _backgroundGradient),
        child: Stack(
          children: [
            // Soft radial glow painted once for depth.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _RadialGlowPainter()),
              ),
            ),

            // Center the animated content.
            Center(child: animatedContent),

            // Footer: version + copyright.
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: 0.65,
                child: Column(
                  children: [
                    Text(
                      'v1.0.0', // Tip: wire this to pubspec/build config for accuracy.
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white60,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '© ${DateTime.now().year} INConnect',
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

// =============================================================
// PAINTER: Subtle radial background glow for added depth.
// - Stateless and does not repaint (performance-friendly).
// =============================================================
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