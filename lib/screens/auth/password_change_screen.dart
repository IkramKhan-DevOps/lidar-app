// =============================================================
// PASSWORD CHANGE SCREEN
// Screen for updating the user's password with live strength
// feedback and match validation. Visual style matches Settings.
// =============================================================
//
// FLOW OVERVIEW
// - User types a new password twice.
// - Live: strength meter updates based on simple rules.
// - Live: "passwords match" feedback under confirm field.
// - Submit calls passwordChangeViewModelProvider.notifier.changePassword.
// - Shows success/error messages and returns on success.
//
// INTEGRATION
// - Riverpod provider: passwordChangeViewModelProvider.
//
// UI LAYERS
// - Background image
// - Dark gradient overlay
// - SafeArea with a custom iOS-like back button
// - Centered glassy card containing fields and CTA
//
// SAFETY
// - Text controllers disposed in dispose().
// - mounted checks before navigation/snackbars.
//
// TWEAKS
// - Adjust gradients/opacities to fit branding.
// - Swap ElevatedButton style/label as needed.
// =============================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/auth_provider.dart';

/// Password Change Screen
/// Styling intentionally matches the simplified Settings screen:
/// - Background image + dark gradient
/// - Semi‑transparent rounded card
/// - Light blue accent
/// Added: iOS-style back arrow ("<") in top-left (no default AppBar).
class PasswordChangeScreen extends ConsumerStatefulWidget {
  const PasswordChangeScreen({super.key});

  @override
  ConsumerState<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class _PasswordChangeScreenState extends ConsumerState<PasswordChangeScreen> {
  // -------------------- CONTROLLERS + TOGGLES --------------------
  // Hold inputs for new password and confirmation.
  final _new1Ctl = TextEditingController();
  final _new2Ctl = TextEditingController();
  // Toggles for showing/hiding password fields.
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    // Prevent leaks by disposing controllers.
    _new1Ctl.dispose();
    _new2Ctl.dispose();
    super.dispose();
  }

  // =============================================================
  // SUBMIT: Attempt to change password via ViewModel
  // - Unfocus keyboard
  // - Call changePassword(...)
  // - Show success/error via SnackBar
  // - Pop back shortly on success
  // =============================================================
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref.read(passwordChangeViewModelProvider.notifier).changePassword(
      newPassword1: _new1Ctl.text,
      newPassword2: _new2Ctl.text,
    );
    final st = ref.read(passwordChangeViewModelProvider);
    if (st.successMessage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(st.successMessage!),
          backgroundColor: Colors.green,
        ),
      );
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.pop(context);
      });
    } else if (st.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(st.error!),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // =============================================================
  // VISUAL-ONLY PASSWORD STRENGTH HELPERS
  // Simple heuristics for user feedback (not server-side rules).
  // =============================================================
  String _strengthLabel(String p) {
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

  double _strengthValue(String p) {
    if (p.isEmpty) return 0;
    int s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=;]').hasMatch(p)) s++;
    return (s / 4).clamp(0, 1).toDouble();
  }

  Color _strengthColor(String label) {
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

  @override
  Widget build(BuildContext context) {
    // -------------------- STATE + DERIVED FLAGS --------------------
    final state = ref.watch(passwordChangeViewModelProvider);

    final pwd = _new1Ctl.text;
    final confirm = _new2Ctl.text;

    // Match/mismatch feedback toggles.
    final match = pwd.isNotEmpty && confirm.isNotEmpty && pwd == confirm;
    final mismatch = confirm.isNotEmpty && pwd != confirm;

    // Strength values for the progress bar + label.
    final strengthLabel = _strengthLabel(pwd);
    final strengthVal = _strengthValue(pwd);
    final strengthColor = _strengthColor(strengthLabel);

    // Button enabled when both inputs exist and not submitting.
    final canSubmit = pwd.isNotEmpty && confirm.isNotEmpty && !state.submitting;

    // -------------------- LAYOUT --------------------
    return Stack(
      children: [
        Scaffold(
          body: Stack(
            children: [
              // LAYER 1: Background image
              Positioned.fill(
                child: Image.asset(
                  'lib/assets/images/login_image.png',
                  fit: BoxFit.cover,
                ),
              ),
              // LAYER 2: Dark gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.65),
                        Colors.black.withOpacity(0.45),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              // LAYER 3: Content with SafeArea
              SafeArea(
                child: Column(
                  children: [
                    // Top bar with iOS-like back arrow
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Row(
                        children: [
                          _CupertinoBackButton(
                            onTap: () => Navigator.maybePop(context),
                            label: 'Back',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Main card centered with scroll for small screens
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.48),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title row
                                Row(
                                  children: const [
                                    Icon(Icons.lock_reset,
                                        color: Colors.lightBlueAccent, size: 22),
                                    SizedBox(width: 10),
                                    Text(
                                      'Change Password',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Enter your new password twice to confirm.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 13.5,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Inline success/error messages (if any)
                                if (state.error != null)
                                  _InlineMessage(
                                    text: state.error!,
                                    color: Colors.redAccent,
                                    icon: Icons.error_outline,
                                  )
                                else if (state.successMessage != null)
                                  _InlineMessage(
                                    text: state.successMessage!,
                                    color: Colors.greenAccent,
                                    icon: Icons.check_circle_outline,
                                  ),
                                if (state.error != null ||
                                    state.successMessage != null)
                                  const SizedBox(height: 20),

                                // New password field
                                _PasswordField(
                                  label: 'New Password',
                                  controller: _new1Ctl,
                                  obscure: _obscure1,
                                  toggle: () =>
                                      setState(() => _obscure1 = !_obscure1),
                                  onChanged: (_) => setState(() {}),
                                ),

                                // Strength meter + label
                                if (pwd.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: strengthVal,
                                      minHeight: 6,
                                      backgroundColor: Colors.white12,
                                      valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                        strengthColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.shield,
                                          size: 16, color: strengthColor),
                                      const SizedBox(width: 6),
                                      Text(
                                        strengthLabel,
                                        style: TextStyle(
                                          color: strengthColor,
                                          fontSize: 12.2,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                const SizedBox(height: 24),

                                // Confirm password field
                                _PasswordField(
                                  label: 'Confirm New Password',
                                  controller: _new2Ctl,
                                  obscure: _obscure2,
                                  toggle: () =>
                                      setState(() => _obscure2 = !_obscure2),
                                  onChanged: (_) => setState(() {}),
                                ),

                                // Match/mismatch feedback under confirm field
                                if (match || mismatch) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Icon(
                                        match
                                            ? Icons.check_circle
                                            : Icons.error_outline,
                                        size: 18,
                                        color: match
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        match
                                            ? 'Passwords match'
                                            : 'Passwords do not match',
                                        style: TextStyle(
                                          color: match
                                              ? Colors.greenAccent
                                              : Colors.orangeAccent,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                const SizedBox(height: 30),

                                // Submit button (shows spinner when submitting)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: canSubmit ? _submit : null,
                                    icon: state.submitting
                                        ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                        AlwaysStoppedAnimation(
                                            Colors.white),
                                      ),
                                    )
                                        : const Icon(Icons.lock_outline),
                                    label: Text(
                                      state.submitting
                                          ? 'Changing...'
                                          : 'Change Password',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                      const Color(0xFF008CFF),
                                      disabledBackgroundColor:
                                      Colors.blueGrey.shade600,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // Helper text for stronger passwords
                                const Text(
                                  'Must be at least 8 characters. Use uppercase, numbers and symbols for better security.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white54,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ---------------------------- Helper Widgets ---------------------------- */

// =============================================================
// Cupertino-like "Back" button for the top-left corner.
// Uses InkWell for ripple and a subtle glass background.
// =============================================================
class _CupertinoBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String label;
  const _CupertinoBackButton({required this.onTap, this.label = 'Back'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.white.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // iOS style "<"
              const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: Colors.white,
              ),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// Inline message banner for success/error notes inside the card.
// =============================================================
class _InlineMessage extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _InlineMessage({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// Password field used for both "new" and "confirm" inputs.
// Includes visibility toggle and consistent glass styling.
// =============================================================
class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback toggle;
  final ValueChanged<String>? onChanged;
  const _PasswordField({
    required this.label,
    required this.controller,
    required this.obscure,
    required this.toggle,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.white70,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.07),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.white54,
              ),
              onPressed: toggle,
              splashRadius: 22,
            ),
            border: OutlineInputBorder(
              borderRadius: borderRadius,
              borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: borderRadius,
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0xFF008CFF), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}