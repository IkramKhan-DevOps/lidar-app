// =============================================================
// SIGNUP SCREEN
// Mirrors login screen UI pattern. Calls signup() in ViewModel.
// On success: navigates to /home (or back to login if you prefer).
// =============================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/auth_provider.dart';
import '../../view_model/auth/auth_state.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  // ---------------- Controllers ----------------
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController(); // optional
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // ---------------- UI State ----------------
  bool _obscurePwd = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ---------------- ACTION: Signup ----------------
  Future<void> _onSignup() async {
    FocusScope.of(context).unfocus();

    await ref.read(authViewModelProvider.notifier).signup(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      confirmPassword: _confirmController.text,
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
    );

    final state = ref.read(authViewModelProvider);
    if (state.status == AuthStatus.success) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } else if (state.status == AuthStatus.error) {
      final msg = state.errorMessage ?? 'Signup failed';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  void _goBackToLogin() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);

    final canSubmit = _emailController.text.isNotEmpty &&
        _passwordController.text.isNotEmpty &&
        _confirmController.text.isNotEmpty &&
        !authState.isSubmitting;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          SizedBox.expand(
            child: Image.asset(
              'lib/assets/images/login_image.png',
              fit: BoxFit.cover,
            ),
          ),
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.6), Colors.black.withOpacity(0.4)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Content
          Column(
            children: [
              const SizedBox(height: 60),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _SignupHeader(),
              ),
              const Spacer(),
              _SignupCard(
                emailController: _emailController,
                usernameController: _usernameController,
                passwordController: _passwordController,
                confirmController: _confirmController,
                isLoading: authState.isSubmitting,
                canSubmit: canSubmit,
                onSubmit: _onSignup,
                obscurePwd: _obscurePwd,
                togglePwd: () => setState(() => _obscurePwd = !_obscurePwd),
                obscureConfirm: _obscureConfirm,
                toggleConfirm: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                onLoginTap: _goBackToLogin,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------- Header ----------------
class _SignupHeader extends StatelessWidget {
  const _SignupHeader();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        SizedBox(height: 20),
        Text(
          'Create\nan Account',
          style: TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text('Fill the fields to continue', style: TextStyle(color: Colors.white70)),
      ],
    );
  }
}

// ---------------- Signup Card ----------------
class _SignupCard extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool isLoading;
  final bool canSubmit;
  final VoidCallback onSubmit;
  final bool obscurePwd;
  final bool obscureConfirm;
  final VoidCallback togglePwd;
  final VoidCallback toggleConfirm;
  final VoidCallback onLoginTap;

  const _SignupCard({
    super.key,
    required this.emailController,
    required this.usernameController,
    required this.passwordController,
    required this.confirmController,
    required this.isLoading,
    required this.canSubmit,
    required this.onSubmit,
    required this.obscurePwd,
    required this.obscureConfirm,
    required this.togglePwd,
    required this.toggleConfirm,
    required this.onLoginTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _Field(
              label: 'Email',
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              hintText: 'example@gmail.com',
            ),
            const SizedBox(height: 16),
            _Field(
              label: 'Username (optional)',
              controller: usernameController,
              hintText: 'Choose a username',
            ),
            const SizedBox(height: 16),
            _Field(
              label: 'Password',
              controller: passwordController,
              obscureText: obscurePwd,
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePwd ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600],
                ),
                onPressed: togglePwd,
              ),
            ),
            const SizedBox(height: 16),
            _Field(
              label: 'Confirm Password',
              controller: confirmController,
              obscureText: obscureConfirm,
              suffixIcon: IconButton(
                icon: Icon(
                  obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey[600],
                ),
                onPressed: toggleConfirm,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit ? onSubmit : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF008CFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 3,
                ),
                child: isLoading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Text('Sign up',
                    style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onLoginTap,
              child: RichText(
                text: const TextSpan(
                  text: 'Already have an account? ',
                  style: TextStyle(color: Colors.black87),
                  children: [
                    TextSpan(
                      text: 'Log in',
                      style: TextStyle(
                        color: Color(0xFF008CFF),
                        fontWeight: FontWeight.w600,
                      ),
                    )
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

// ---------------- Reusable Field ----------------
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hintText,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) => (context as Element).markNeedsBuild(),
      ),
    ]);
  }
}