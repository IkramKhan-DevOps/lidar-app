// =============================================================
// SIGNUP SCREEN
// User registration UI with password strength meter and Riverpod
// integration. Mirrors the visual style of the login screen.
// =============================================================
//
// FLOW OVERVIEW
// - User enters username, email, password, and confirm password.
// - Password strength and "passwords match" feedback update live.
// - On "Sign Up", calls register(...) on authViewModelProvider.
// - On success: shows a snackbar (e-mail verification notice) and pops.
// - On error: shows inline error banner and snackbar.
//
// INTEGRATION
// - State is read via Riverpod: authViewModelProvider.
// - Actions are invoked on its notifier: register(...).
//
// UI LAYERS
// - Background image
// - Gradient overlay (brand tint)
// - Vignette (radial shade at bottom)
// - Glass-like top card containing inputs
//
// SAFETY
// - Controllers disposed in dispose().
// - mounted checks are used before showing snackbar/navigating.
//
// TWEAKS
// - Adjust texts, gradients, and opacities to match branding.
// - Replace asset path for the background if needed.
// =============================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/auth_provider.dart';
import '../../view_model/states/auth_state.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  // -------------------- TEXT CONTROLLERS --------------------
  // Hold the input text for the form fields.
  final _usernameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _pwd1Ctl = TextEditingController();
  final _pwd2Ctl = TextEditingController();

  // -------------------- PASSWORD VISIBILITY --------------------
  // Toggles for "eye" icons on password fields.
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void initState() {
    super.initState();
    // Add listeners to controllers to rebuild on text changes
    _usernameCtl.addListener(_onInputChanged);
    _emailCtl.addListener(_onInputChanged);
    _pwd1Ctl.addListener(_onInputChanged);
    _pwd2Ctl.addListener(_onInputChanged);
  }

  // Simple method to rebuild the UI when input changes
  void _onInputChanged() {
    setState(() {
      // No need to do anything - just trigger rebuild
    });
  }

  // Proper methods to toggle password visibility with setState
  void _toggleObscure1() {
    setState(() {
      _obscure1 = !_obscure1;
    });
  }

  void _toggleObscure2() {
    setState(() {
      _obscure2 = !_obscure2;
    });
  }

  @override
  void dispose() {
    // Remove listeners before disposing
    _usernameCtl.removeListener(_onInputChanged);
    _emailCtl.removeListener(_onInputChanged);
    _pwd1Ctl.removeListener(_onInputChanged);
    _pwd2Ctl.removeListener(_onInputChanged);

    // Always dispose controllers to avoid memory leaks.
    _usernameCtl.dispose();
    _emailCtl.dispose();
    _pwd1Ctl.dispose();
    _pwd2Ctl.dispose();
    super.dispose();
  }

  // -------------------- VALIDATION HELPERS --------------------
  // Quick check to ensure both passwords are non-empty and equal.
  bool get _passwordsMatch =>
      _pwd1Ctl.text.isNotEmpty &&
          _pwd2Ctl.text.isNotEmpty &&
          _pwd1Ctl.text == _pwd2Ctl.text;

  // -------------------- SUBMIT HANDLER --------------------
  // Orchestrates the signup action and handles success/error UX.
  Future<void> _onSignup() async {
    // Dismiss the keyboard.
    FocusScope.of(context).unfocus();

    // Fire registration via Riverpod notifier.
    await ref.read(authViewModelProvider.notifier).register(
      username: _usernameCtl.text.trim(),
      email: _emailCtl.text.trim(),
      password1: _pwd1Ctl.text,
      password2: _pwd2Ctl.text,
    );

    // Read the latest state (flow + messages).
    final state = ref.read(authViewModelProvider);

    if (state.flow == AuthFlow.registered) {
      // Success: inform user and return to previous screen.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              state.registrationMessage ??
                  'Verification e-mail sent. Please check inbox.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } else if (state.flow == AuthFlow.error) {
      // Failure: display the error.
      final msg = state.error ?? 'Signup failed';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Observe auth state for loading and error handling.
    final authState = ref.watch(authViewModelProvider);

    // Determine whether the "Sign Up" button should be enabled.
    final canSubmit = _usernameCtl.text.isNotEmpty &&
        _emailCtl.text.isNotEmpty &&
        _pwd1Ctl.text.isNotEmpty &&
        _pwd2Ctl.text.isNotEmpty &&
        _passwordsMatch &&
        !authState.isSubmitting;

    return Scaffold(
      body: Stack(
        children: [
          // -------------------- LAYER 1: BACKGROUND IMAGE --------------------
          Positioned.fill(
            child: Image.asset(
              'lib/assets/images/login_image.png',
              fit: BoxFit.cover,
            ),
          ),

          // -------------------- LAYER 2: BRAND GRADIENT OVERLAY --------------------
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: const [
                    Color(0xCC0F172A),
                    Color(0x990B2540),
                    Color(0x660F172A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),

          // -------------------- LAYER 3: VIGNETTE (BOTTOM RADIAL SHADE) --------------------
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.45),
                  ],
                  center: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // -------------------- MAIN CONTENT --------------------
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),

                // Header area: mini logo + screen title and tagline.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AppMiniLogo(),
                      const SizedBox(height: 42),
                      Text(
                        'Create Account',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Join the 3D spatial journey.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Glass-like signup card docked to the bottom.
                _SignupCard(
                  usernameCtl: _usernameCtl,
                  emailCtl: _emailCtl,
                  pwd1Ctl: _pwd1Ctl,
                  pwd2Ctl: _pwd2Ctl,
                  obscure1: _obscure1,
                  obscure2: _obscure2,
                  toggle1: _toggleObscure1, // Use the new toggle methods
                  toggle2: _toggleObscure2, // Use the new toggle methods
                  isLoading: authState.isSubmitting,
                  canSubmit: canSubmit,
                  passwordsMatch: _passwordsMatch,
                  authError: authState.flow == AuthFlow.error ? authState.error : null,
                  onSubmit: _onSignup,
                  onLoginTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------- CARD ---------------------------------- */
// Bottom glass card containing form fields, inline validation, and primary CTA.
class _SignupCard extends StatelessWidget {
  final TextEditingController usernameCtl;
  final TextEditingController emailCtl;
  final TextEditingController pwd1Ctl;
  final TextEditingController pwd2Ctl;
  final bool obscure1;
  final bool obscure2;
  final VoidCallback toggle1;
  final VoidCallback toggle2;
  final bool isLoading;
  final bool canSubmit;
  final bool passwordsMatch;
  final String? authError;
  final VoidCallback onSubmit;
  final VoidCallback onLoginTap;

  const _SignupCard({
    required this.usernameCtl,
    required this.emailCtl,
    required this.pwd1Ctl,
    required this.pwd2Ctl,
    required this.obscure1,
    required this.obscure2,
    required this.toggle1,
    required this.toggle2,
    required this.isLoading,
    required this.canSubmit,
    required this.passwordsMatch,
    required this.onSubmit,
    required this.onLoginTap,
    required this.authError,
  });

  @override
  Widget build(BuildContext context) {
    // Useful flags for strength meter UI.
    final hasPwdInput = pwd1Ctl.text.isNotEmpty;

    // Strength metrics derived from helpers below.
    final strengthValue = _strengthValue(pwd1Ctl.text);
    final strengthLabel = _strengthLabel(pwd1Ctl.text);
    final strengthColor = _strengthColor(strengthLabel);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      child: BackdropFilter(
        // Frosted-glass look.
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 36),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.12), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 28,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Username
                _Field(
                  label: 'Username',
                  controller: usernameCtl,
                  hintText: 'your_username',
                ),
                const SizedBox(height: 18),

                // Email
                _Field(
                  label: 'Email',
                  controller: emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  hintText: 'you@example.com',
                ),
                const SizedBox(height: 18),

                // Password
                _Field(
                  label: 'Password',
                  controller: pwd1Ctl,
                  obscureText: obscure1,
                  hintText: '••••••••',
                  suffixIcon: IconButton(
                    splashRadius: 20,
                    icon: Icon(
                      obscure1
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: toggle1,
                  ),
                ),

                // Password strength indicator (appears when typing).
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: hasPwdInput
                      ? Padding(
                    key: ValueKey(strengthLabel),
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: strengthValue,
                            minHeight: 6,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(strengthColor),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.security_rounded,
                                size: 16, color: strengthColor),
                            const SizedBox(width: 6),
                            Text(
                              strengthLabel,
                              style: TextStyle(
                                color: strengthColor,
                                fontSize: 12.3,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                      : const SizedBox(height: 4),
                ),
                const SizedBox(height: 18),

                // Confirm Password
                _Field(
                  label: 'Confirm Password',
                  controller: pwd2Ctl,
                  obscureText: obscure2,
                  hintText: '••••••••',
                  suffixIcon: IconButton(
                    splashRadius: 20,
                    icon: Icon(
                      obscure2
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: toggle2,
                  ),
                ),

                // Passwords match / mismatch feedback.
                if (pwd2Ctl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          passwordsMatch
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          size: 18,
                          color: passwordsMatch
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          passwordsMatch
                              ? 'Passwords match'
                              : 'Passwords do not match',
                          style: TextStyle(
                            color: passwordsMatch
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 12.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Inline error banner (from backend validation), if any.
                if (authError != null) ...[
                  const SizedBox(height: 18),
                  _InlineBanner(
                    color: Colors.redAccent,
                    icon: Icons.error_outline_rounded,
                    text: authError!,
                  ),
                ],

                const SizedBox(height: 26),

                // Primary CTA
                _PrimaryGradientButton(
                  enabled: canSubmit,
                  isLoading: isLoading,
                  onPressed: canSubmit ? onSubmit : null,
                  label: 'Sign Up',
                ),

                const SizedBox(height: 22),

                // Link to Login
                GestureDetector(
                  onTap: onLoginTap,
                  child: RichText(
                    text: const TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                        letterSpacing: 0.2,
                      ),
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: TextStyle(
                            color: Color(0xFF60A5FA),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------- STRENGTH HELPERS --------------------
  // Returns a normalized 0..1 value based on basic rules.
  static double _strengthValue(String p) {
    if (p.isEmpty) return 0;
    int s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=;]').hasMatch(p)) s++;
    return (s / 4).clamp(0, 1).toDouble();
  }

  // Returns a friendly label for the strength meter.
  static String _strengthLabel(String p) {
    if (p.isEmpty) return '';
    int s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=;]').hasMatch(p)) s++;
    switch (s) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  // Color mapping for strength labels.
  static Color _strengthColor(String label) {
    switch (label) {
      case 'Weak':
        return Colors.redAccent;
      case 'Fair':
        return Colors.orangeAccent;
      case 'Good':
        return Colors.amber;
      case 'Strong':
        return Colors.greenAccent;
      default:
        return Colors.transparent;
    }
  }
}

/* ----------------------------- COMPONENTS ------------------------------ */

// Single labeled text field with glassy styling and optional suffix icon.
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.85),
      fontWeight: FontWeight.w500,
      fontSize: 13.3,
      letterSpacing: 0.2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.white54),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
              borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.4),
            ),
          ),
          // No need for onChanged here - controller listeners handle this
        ),
      ],
    );
  }
}

// Primary gradient button with loading spinner and subtle shadow.
class _PrimaryGradientButton extends StatelessWidget {
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onPressed;
  final String label;

  const _PrimaryGradientButton({
    required this.enabled,
    required this.isLoading,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(
          colors: [
            Color(0xFF2563EB),
            Color(0xFF3B82F6),
            Color(0xFF60A5FA),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        )
            : LinearGradient(
          colors: [
            Colors.blueGrey.shade700,
            Colors.blueGrey.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ]
            : [],
      ),
      child: Center(
        child: isLoading
            ? const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.7,
            valueColor: AlwaysStoppedAnimation(Colors.white),
          ),
        )
            : Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled && !isLoading ? onPressed : null,
        child: container,
      ),
    );
  }
}

// Inline alert/banner used for error display beneath fields.
class _InlineBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _InlineBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Compact brand mark used in the header above the form.
class _AppMiniLogo extends StatelessWidget {
  const _AppMiniLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Circular gradient badge with app icon.
        Container(
          height: 42,
          width: 42,
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
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.travel_explore_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        // Wordmark
        Text(
          'WebGIS 3D',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}