import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth_user.dart';
import '../../repository/auth_repository.dart';
import 'auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

class AuthViewModel extends StateNotifier<AuthState> {
  final AuthRepository _repo;
  AuthViewModel(this._repo) : super(AuthState.initial());

  Future<void> login({
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Fields cannot be empty',
      );
      return;
    }

    try {
      state = state.copyWith(
        status: AuthStatus.loading,
        isSubmitting: true,
        errorMessage: null,
      );

      final token = await _repo.login(
        email: email,
        password: password,
      );

      // Optionally fetch profile here later if needed

      state = state.copyWith(
        status: AuthStatus.success,
        token: token,
        isSubmitting: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _mapError(e),
        isSubmitting: false,
      );
    }
  }

  String _mapError(Object e) {
    final msg = e.toString();
    if (msg.contains('non_field_errors')) {
      return 'Invalid credentials';
    }
    if (msg.contains('email')) {
      return 'Please enter a valid email and password';
    }
    return msg;
  }

  Future<void> logout() async {
    await _repo.logout();
    state = AuthState.initial();
  }
}