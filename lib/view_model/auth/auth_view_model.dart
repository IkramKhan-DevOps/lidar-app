// =============================================================
// AUTH VIEW MODEL (StateNotifier)
// Contains UI-triggered methods (login, signup, logout).
// Performs validation, calls repository, maps errors.
// =============================================================
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../repository/auth_repository.dart';
import 'auth_state.dart';

class AuthViewModel extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthViewModel(this._repo) : super(AuthState.initial());

  // --------------- LOGIN ---------------
  Future<void> login({
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Email and password are required.',
      );
      return;
    }

    try {
      state = state.copyWith(
        status: AuthStatus.loading,
        isSubmitting: true,
        errorMessage: null,
        isSignupFlow: false,
      );

      final token = await _repo.login(email: email, password: password);

      state = state.copyWith(
        status: AuthStatus.success,
        token: token,
        isSubmitting: false,
        isSignupFlow: false,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _mapError(e),
        isSubmitting: false,
        isSignupFlow: false,
      );
    }
  }

  // --------------- SIGNUP ---------------
  Future<void> signup({
    required String email,
    required String password,
    required String confirmPassword,
    String? username,
  }) async {
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'All fields are required.',
      );
      return;
    }

    if (password != confirmPassword) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Passwords do not match.',
      );
      return;
    }

    try {
      state = state.copyWith(
        status: AuthStatus.loading,
        isSubmitting: true,
        errorMessage: null,
        isSignupFlow: true,
      );

      final token = await _repo.signup(
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        username: username,
      );

      state = state.copyWith(
        status: AuthStatus.success,
        token: token,
        isSubmitting: false,
        isSignupFlow: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _mapError(e),
        isSubmitting: false,
        isSignupFlow: true,
      );
    }
  }

  // --------------- LOGOUT ---------------
  Future<void> logout() async {
    await _repo.logout();
    state = AuthState.initial();
  }

  // --------------- ERROR MAPPING ---------------
  String _mapError(Object e) {
    final raw = e.toString();

    // Attempt to parse JSON-like error bodies returned by backend.
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      final jsonStr = raw.substring(start, end + 1);
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          if (decoded['email'] is List && decoded['email'].isNotEmpty) {
            return decoded['email'][0].toString();
          }
          if (decoded['password'] is List && decoded['password'].isNotEmpty) {
            return decoded['password'][0].toString();
          }
          if (decoded['non_field_errors'] is List &&
              decoded['non_field_errors'].isNotEmpty) {
            return decoded['non_field_errors'][0].toString();
          }
          // Generic field error extraction:
          for (final entry in decoded.entries) {
            if (entry.value is List && entry.value.isNotEmpty) {
              return entry.value[0].toString();
            }
          }
        }
      } catch (_) {
        // swallow parse error, fallback below
      }
    }

    if (raw.contains('Unauthorized')) return 'Unauthorized. Check credentials.';
    if (raw.contains('password')) return 'Invalid password or mismatch.';
    return raw.replaceAll('Exception: ', '');
  }
}