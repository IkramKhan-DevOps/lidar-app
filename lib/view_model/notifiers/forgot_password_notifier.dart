// =============================================================
// FORGOT PASSWORD VIEWMODEL (Riverpod StateNotifier, direct HTTP)
// Central state manager for requesting a password reset email,
// implemented with a direct http.post call (no repository layer).
// Exposes: ForgotPasswordState (email, submitting, successMessage, errorMessage).
// UI should observe this ViewModel and render feedback accordingly.
// =============================================================
//
// USAGE
// - Read state in widgets:
//     final state = ref.watch(forgotPasswordViewModelProvider);
// - Trigger actions:
//     ref.read(forgotPasswordViewModelProvider.notifier).submit(email);
// - Clear transient messages after showing a snackbar/toast:
//     ref.read(forgotPasswordViewModelProvider.notifier).clearMessages();
//
// LAYERS
// - http (package:http): used to call the password reset endpoint directly.
// - _passwordResetEndpoint: backend URL for initiating password resets.
// - ForgotPasswordState: simple state object consumed by the UI.
//
// NOTES
// - Prefer keeping SnackBar/Toast rendering in the UI layer; this ViewModel
//   only manages state and orchestrates the HTTP call.
// - If you centralize base URLs or auth headers, inject them here (or refactor
//   to use a repository for better testability and consistency).
// - Add CSRF/auth headers here if your backend requires them.
// =============================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../states/forgot_password_state.dart';

/// Adjust baseUrl if you centralize it somewhere else.
const _passwordResetEndpoint =
    'https://seedswild.com/api/accounts/auth/password/reset/';

class ForgotPasswordNotifier extends StateNotifier<ForgotPasswordState> {
  ForgotPasswordNotifier() : super(const ForgotPasswordState());

  Future<void> submit(String email) async {
    state = state.copyWith(
      submitting: true,
      successMessage: null,
      errorMessage: null,
      email: email,
    );
    try {
      final res = await http.post(
        Uri.parse(_passwordResetEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // If your backend requires auth or CSRF token, inject here.
        },
        body: jsonEncode({'email': email}),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        final body = jsonDecode(res.body);
        final detail = body['detail']?.toString() ??
            'Password reset e-mail has been sent.';
        state = state.copyWith(
          submitting: false,
          successMessage: detail,
          errorMessage: null,
        );
      } else {
        String msg = 'Failed to send reset email';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body.values.isNotEmpty) {
            msg = body.values.first.toString();
          }
        } catch (_) {}
        state = state.copyWith(
          submitting: false,
          successMessage: null,
          errorMessage: msg,
        );
      }
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        successMessage: null,
        errorMessage: 'Network error: ${e.toString()}',
      );
    }
  }

  void clearMessages() {
    state = state.copyWith(successMessage: null, errorMessage: null);
  }
}

// Provider wiring: exposes the StateNotifier for UI consumption.
final forgotPasswordViewModelProvider =
StateNotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>(
      (ref) => ForgotPasswordNotifier(),
);