// =============================================================
// LOGIN SCREEN (UI Layer)
// Observes AuthState via Riverpod. Triggers login() on ViewModel.
// Provides navigation to SignupScreen.
// =============================================================
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_channel_swift_demo/screens/auth/signup_screen.dart';

import '../../settings/providers/auth_provider.dart';
import '../../view_model/auth/auth_state.dart';


class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ---------------- Controllers ----------------
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // ---------------- UI State ----------------
  bool _staySignedIn = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------- ACTION: Login ----------------
  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();

    await ref.read(authViewModelProvider.notifier).login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    final state = ref.read(authViewModelProvider);
    if (state.status == AuthStatus.success) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else if (state.status == AuthStatus.error) {
      final msg = state.errorMessage ?? 'Login failed';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  void _goToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);

    return Scaffold(
      body: Stack(
        children: [
          // ---------------- Background Image ----------------
          SizedBox.expand(
            child: Image.asset(
              'lib/assets/images/login_image.png',
              fit: BoxFit.cover,
            ),
          ),
          // ---------------- Dark Gradient Overlay ----------------
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.6), Colors.black.withOpacity(0.4)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // ---------------- Content ----------------
          Column(
            children: [
              const SizedBox(height: 60),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _Header(),
              ),
              const Spacer(),
              _LoginCard(
                emailController: _emailController,
                passwordController: _passwordController,
                staySignedIn: _staySignedIn,
                onStaySignedInChanged: (v) => setState(() => _staySignedIn = v ?? false),
                onLoginPressed: authState.isSubmitting ? null : _onLogin,
                isLoading: authState.isSubmitting,
                obscure: _obscure,
                toggleObscure: () => setState(() => _obscure = !_obscure),
                onSignupTap: _goToSignup,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------- Header (Logo + Title) ----------------
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset('lib/assets/images/modelCraft.png', height: 24, width: 24),
            const SizedBox(width: 8),
            const Text(
              'INconnect',
              style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 80),
        const Text(
          'Welcome\nto WebGIS 3D',
          style: TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Log in to your account', style: TextStyle(color: Colors.white70)),
      ],
    );
  }
}

// ---------------- Login Card ----------------
class _LoginCard extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool staySignedIn;
  final ValueChanged<bool?> onStaySignedInChanged;
  final VoidCallback? onLoginPressed;
  final bool isLoading;
  final bool obscure;
  final VoidCallback toggleObscure;
  final VoidCallback onSignupTap;

  const _LoginCard({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.staySignedIn,
    required this.onStaySignedInChanged,
    required this.onLoginPressed,
    required this.isLoading,
    required this.obscure,
    required this.toggleObscure,
    required this.onSignupTap,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = emailController.text.isNotEmpty &&
        passwordController.text.isNotEmpty &&
        onLoginPressed != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CustomTextField(
            label: 'Email',
            hintText: 'example@gmail.com',
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _CustomTextField(
            label: 'Password',
            controller: passwordController,
            obscureText: obscure,
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey[600]),
              onPressed: toggleObscure,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(value: staySignedIn, onChanged: onStaySignedInChanged),
              const Text('Stay signed in', style: TextStyle(color: Colors.black87)),
              const Spacer(),
              TextButton(onPressed: () {}, child: const Text('Forgot password?')),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSubmit ? onLoginPressed : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF008CFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  : const Text('Log in', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onSignupTap,
            child: RichText(
              text: const TextSpan(
                text: "Don't have an account? ",
                style: TextStyle(color: Colors.black87),
                children: [
                  TextSpan(
                    text: 'Sign up',
                    style: TextStyle(color: Color(0xFF008CFF), fontWeight: FontWeight.w600),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Reusable Text Field ----------------
class _CustomTextField extends StatelessWidget {
  final String label;
  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _CustomTextField({
    super.key,
    required this.label,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    required this.controller,
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
        keyboardType: keyboardType,
        obscureText: obscureText,
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