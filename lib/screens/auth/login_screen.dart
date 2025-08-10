import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/auth_provider.dart';
import '../../view_model/auth/auth_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _staySignedIn = false;
  bool _obscure = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();

    // inside _onLogin()
    await ref.read(authViewModelProvider.notifier).login(
      email: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    final state = ref.read(authViewModelProvider);
    if (state.status == AuthStatus.success) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else if (state.status == AuthStatus.error) {
      final msg = state.errorMessage ?? 'Login failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authViewModelProvider);

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: Image.asset(
              'lib/assets/images/login_image.png',
              fit: BoxFit.cover,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.black.withOpacity(0.4),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 60),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Header(),
              ),
              const Spacer(),
              _LoginCard(
                usernameController: _usernameController,
                passwordController: _passwordController,
                staySignedIn: _staySignedIn,
                onStaySignedInChanged: (v) =>
                    setState(() => _staySignedIn = v ?? false),
                onLoginPressed: authState.isSubmitting ? null : _onLogin,
                isLoading: authState.isSubmitting,
                obscure: _obscure,
                toggleObscure: () =>
                    setState(() => _obscure = !_obscure),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset(
              'lib/assets/images/modelCraft.png',
              height: 24,
              width: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'INconnect',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 80),
        const Text(
          'Welcome\nto WebGIS 3D',
          style: TextStyle(
            fontSize: 32,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Log in to your account',
          style: TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool staySignedIn;
  final ValueChanged<bool?> onStaySignedInChanged;
  final VoidCallback? onLoginPressed;
  final bool isLoading;
  final bool obscure;
  final VoidCallback toggleObscure;

  const _LoginCard({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.staySignedIn,
    required this.onStaySignedInChanged,
    required this.onLoginPressed,
    required this.isLoading,
    required this.obscure,
    required this.toggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    final canSubmit = usernameController.text.isNotEmpty &&
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
            label: 'Username or Email',
            hintText: 'example@gmail.com',
            controller: usernameController,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _CustomTextField(
            label: 'Password',
            controller: passwordController,
            obscureText: obscure,
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey[600],
              ),
              onPressed: toggleObscure,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: staySignedIn,
                onChanged: onStaySignedInChanged,
              ),
              const Text(
                'Stay signed in',
                style: TextStyle(color: Colors.black87),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  // TODO: Forgot password flow
                },
                child: const Text('Forgot password?'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSubmit ? onLoginPressed : null,
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
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : const Text(
                'Log in',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final String label;
  final String? hintText;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _CustomTextField({
    required this.label,
    this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {
            (context as Element).markNeedsBuild();
          },
        ),
      ],
    );
  }
}