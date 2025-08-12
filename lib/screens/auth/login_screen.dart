// =============================================================
// LOGIN SCREEN
// Branded authentication entry with Riverpod integration and a
// "Forgot password" bottom sheet.
// =============================================================
//
// FLOW OVERVIEW
// - User enters email + password.
// - "Sign In" triggers authViewModelProvider.notifier.login(...).
// - On success -> navigates to Home; on error -> shows snackbar.
// - "Forgot password?" opens a glass-style bottom sheet to request
//   a reset link.
//
// INTEGRATION
// - State observed via authViewModelProvider (Riverpod).
// - Actions dispatched via its notifier.
// - Forgot password uses forgotPasswordViewModelProvider.
//
// UI LAYERS
// - Fullscreen background image
// - Brand gradient overlay
// - Bottom vignette (radial shade)
// - Glass login card docked to the bottom
//
// SAFETY
// - TextEditingControllers disposed in dispose().
// - mounted checks before navigation/snackbars.
//
// NOTE
// - Only comments were added for clarity. No logic changes.
// - Duplicate imports from the provided snippet are preserved intentionally.
// =============================================================

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_channel_swift_demo/core/configs/app_routes.dart';

import '../../settings/providers/auth_provider.dart';
import '../../view_model/auth/forgot_password_view_model.dart';
import '../../view_model/states/auth_state.dart';
import 'signup_screen.dart';
// UPDATED: Added forgot password bottom sheet wiring.
// Only changed parts are commented with // NEW or // UPDATED.

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // -------------------- CONTROLLERS --------------------
  // Holds input for email + password fields.
  final _emailCtl = TextEditingController();
  final _pwdCtl = TextEditingController();

  // Toggles password visibility for the password field.
  bool _obscure = true;

  @override
  void dispose() {
    // Prevent memory leaks by disposing controllers.
    _emailCtl.dispose();
    _pwdCtl.dispose();
    super.dispose();
  }

  // =============================================================
  // ACTION: Attempt login via ViewModel
  // - Unfocus keyboard
  // - Call login(...)
  // - Navigate on success; show error on failure
  // =============================================================
  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();
    await ref.read(authViewModelProvider.notifier).login(
      email: _emailCtl.text.trim(),
      password: _pwdCtl.text,
    );
    final state = ref.read(authViewModelProvider);
    if (state.flow == AuthFlow.authenticated) {
      if (mounted) {
        Navigator.pushNamed(context, AppRoutes.homeScreen);
      }
    } else if (state.flow == AuthFlow.error) {
      _showSnack(state.error ?? 'Login failed');
    }
  }

  // Convenience method to show an error snackbar.
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // Navigate to Signup screen.
  void _goToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  // =============================================================
  // UI: Forgot Password bottom sheet
  // - Clears previous state
  // - Opens a glass-styled modal with email input
  // - Submits to send reset link (if valid)
  // =============================================================
  // NEW: open forgot password sheet
  void _showForgotPasswordSheet() {
    ref.read(forgotPasswordViewModelProvider.notifier).clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => const _ForgotPasswordSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Observe auth state for loading and flow.
    final auth = ref.watch(authViewModelProvider);

    // Enable button only when inputs are present and not submitting.
    final canSubmit = _emailCtl.text.isNotEmpty &&
        _pwdCtl.text.isNotEmpty &&
        !auth.isSubmitting;

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

                // Header: logo + copy
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _AppMiniLogo(),
                      const SizedBox(height: 42),
                      Text(
                        'Welcome Back',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Sign in to continue your 3D spatial journey.',
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

                // Bottom glass login card with fields and actions.
                _LoginCard(
                  emailCtl: _emailCtl,
                  pwdCtl: _pwdCtl,
                  obscure: _obscure,
                  toggleObscure: () => setState(() => _obscure = !_obscure),
                  isLoading: auth.isSubmitting,
                  canSubmit: canSubmit,
                  onSubmit: _onLogin,
                  onSignupTap: _goToSignup,
                  onForgotPasswordTap: _showForgotPasswordSheet, // NEW
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                   CARD                                     */
/* -------------------------------------------------------------------------- */
// Glass-styled bottom sheet-like card containing the login form, CTA, and links.
class _LoginCard extends StatelessWidget {
  final TextEditingController emailCtl;
  final TextEditingController pwdCtl;
  final bool obscure;
  final VoidCallback toggleObscure;
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final VoidCallback onSignupTap;
  final VoidCallback onForgotPasswordTap; // NEW

  const _LoginCard({
    super.key,
    required this.emailCtl,
    required this.pwdCtl,
    required this.obscure,
    required this.toggleObscure,
    required this.isLoading,
    required this.canSubmit,
    required this.onSubmit,
    required this.onSignupTap,
    required this.onForgotPasswordTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 34),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Email field
              _Field(
                label: 'Email',
                controller: emailCtl,
                keyboardType: TextInputType.emailAddress,
                hintText: 'you@example.com',
              ),

              const SizedBox(height: 18),

              // Password field with visibility toggle
              _Field(
                label: 'Password',
                controller: pwdCtl,
                obscureText: obscure,
                hintText: '••••••••',
                suffixIcon: IconButton(
                  splashRadius: 20,
                  icon: Icon(
                    obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.white70,
                  ),
                  onPressed: toggleObscure,
                ),
              ),

              const SizedBox(height: 8),

              // "Forgot password?" link aligned to the right.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onForgotPasswordTap, // UPDATED
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF60A5FA),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Primary "Sign In" CTA
              _PrimaryGradientButton(
                enabled: canSubmit,
                onPressed: canSubmit ? onSubmit : null,
                isLoading: isLoading,
                label: 'Sign In',
              ),

              const SizedBox(height: 22),

              // Link to Signup
              GestureDetector(
                onTap: onSignupTap,
                child: RichText(
                  text: const TextSpan(
                    text: "Don't have an account? ",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                    ),
                    children: [
                      TextSpan(
                        text: 'Create one',
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
    );

    return card;
  }
}

/* -------------------------------------------------------------------------- */
/*                         FORGOT PASSWORD BOTTOM SHEET                       */
/* -------------------------------------------------------------------------- */
// Glass-style modal for requesting a password reset link.
// Validates email, submits via ViewModel, and closes on success.
class _ForgotPasswordSheet extends ConsumerWidget {
  const _ForgotPasswordSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(forgotPasswordViewModelProvider);
    final notifier = ref.read(forgotPasswordViewModelProvider.notifier);

    final email = state.email.trim();
    final emailValid = _validEmail(email);
    final canSubmit = emailValid && !state.submitting;

    return Padding(
      // Make space for the keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.12), width: 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 26,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Grabber
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                // Title
                Row(
                  children: const [
                    Icon(Icons.lock_open_rounded,
                        color: Color(0xFF60A5FA), size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Reset Password',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Support text
                const Text(
                  'Enter the email linked to your account. We will send a reset link if it exists.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13.2,
                    height: 1.25,
                  ),
                ),

                const SizedBox(height: 22),

                // Email label + field
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Email',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: notifier.updateEmail,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.09),
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                      BorderSide(color: Colors.white.withOpacity(0.18)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                      borderSide:
                      BorderSide(color: Color(0xFF3B82F6), width: 1.3),
                    ),
                    // Simple validity icon feedback.
                    suffixIcon: email.isEmpty
                        ? null
                        : Icon(
                      emailValid
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: emailValid
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                  ),
                ),

                // Inline feedback banners.
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _Banner(
                    color: Colors.redAccent,
                    icon: Icons.error_outline_rounded,
                    text: state.errorMessage!,
                  )
                ],
                if (state.successMessage != null) ...[
                  const SizedBox(height: 14),
                  _Banner(
                    color: Colors.greenAccent,
                    icon: Icons.check_circle_outline_rounded,
                    text: state.successMessage!,
                  )
                ],

                const SizedBox(height: 26),

                // Submit button (enabled only when email is valid).
                Opacity(
                  opacity: canSubmit ? 1 : 0.55,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: canSubmit
                        ? () async {
                      await notifier.submit();
                      final s =
                      ref.read(forgotPasswordViewModelProvider);
                      if (s.successMessage != null) {
                        // Give a moment to read the success message, then close sheet.
                        await Future.delayed(
                            const Duration(milliseconds: 1200));
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      }
                    }
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: canSubmit
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
                        boxShadow: canSubmit
                            ? [
                          BoxShadow(
                            color:
                            const Color(0xFF2563EB).withOpacity(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ]
                            : [],
                      ),
                      child: Center(
                        child: state.submitting
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor:
                            AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                            : const Text(
                          'Send Reset Link',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Close the sheet without action.
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Basic email format validation.
  static bool _validEmail(String e) {
    if (e.isEmpty) return false;
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(e);
  }
}

/* -------------------------------------------------------------------------- */
/*                                  BANNER                                    */
/* -------------------------------------------------------------------------- */
// Small inline alert used for success/error feedback in the sheet.
class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({
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

// Keep _PrimaryGradientButton, _Field, _AppMiniLogo unchanged below...
// (They are already defined above in your file.)

/* -------------------------------------------------------------------------- */
/*                           PRIMARY GRADIENT BUTTON                          */
/* -------------------------------------------------------------------------- */
// Reusable CTA with loading spinner and gradient/shadow polish.
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
    final child = AnimatedContainer(
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
            fontSize: 16.5,
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
        child: child,
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                     FIELD                                  */
/* -------------------------------------------------------------------------- */
// Labeled text field with glass fill and optional suffix icon.
// Note: onChanged forces a rebuild to refresh button enabling state.
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;

  const _Field({
    super.key,
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
      fontSize: 13.5,
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
            hintStyle: TextStyle(color: Colors.white54),
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.4),
            ),
          ),
          // Simple rebuild to reflect text presence in "canSubmit".
          onChanged: (_) => (context as Element).markNeedsBuild(),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                                MINI LOGO                                   */
/* -------------------------------------------------------------------------- */
// Compact brand mark (gradient badge + wordmark) used in the header.
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
          child: const Icon(Icons.travel_explore_rounded,
              color: Colors.white, size: 22),
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