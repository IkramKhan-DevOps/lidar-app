import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../view_model/states/forgot_password_state.dart';

// =============================================================
// FORGOT PASSWORD VIEWMODEL (Riverpod StateNotifier)
// Sends a password reset request to the backend and exposes
// submitting/success/error state to the UI.
// =============================================================
//
// FLOW OVERVIEW
// - submit(email):
//     1) Set submitting=true and clear previous messages.
//     2) POST the email to the password reset endpoint.
//     3) On 200/201 -> set successMessage (from response or default).
//     4) On non-2xx -> parse and set errorMessage.
//     5) On exception -> set a network error message.
// - clearMessages(): reset success/error to null (keep other fields).
//
// INTEGRATION
// - Expose via forgotPasswordViewModelProvider.
// - UI observes ForgotPasswordState for submitting/success/error.
//
// NOTES
// - Adjust _passwordResetEndpoint to your environment or centralize
//   in a shared API config if desired.
// - Add auth/CSRF headers here if your backend requires them.
// =============================================================

/// Adjust baseUrl if you centralize it somewhere else.
const _passwordResetEndpoint =
    'https://seedswild.com/api/accounts/auth/password/reset/';

class ForgotPasswordNotifier extends StateNotifier<ForgotPasswordState> {
  ForgotPasswordNotifier() : super(const ForgotPasswordState());

  /// Submit a password reset request for the given [email].
  /// Updates [state] to reflect loading, success, or error states.
  Future<void> submit(String email) async {
    // Enter submitting state and clear previous messages.
    state = state.copyWith(
      submitting: true,
      successMessage: null,
      errorMessage: null,
      email: email,
    );

    try {
      // POST email JSON to the reset endpoint.
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
        // Success: prefer "detail" from backend if present.
        final body = jsonDecode(res.body);
        final detail = body['detail']?.toString() ??
            'Password reset e-mail has been sent.';
        state = state.copyWith(
          submitting: false,
          successMessage: detail,
          errorMessage: null,
        );
      } else {
        // Non-2xx: try to extract a readable message from response.
        String msg = 'Failed to send reset email';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body.values.isNotEmpty) {
            msg = body.values.first.toString();
          }
        } catch (_) {
          // Ignore parse errors; keep fallback message.
        }
        state = state.copyWith(
          submitting: false,
          successMessage: null,
          errorMessage: msg,
        );
      }
    } catch (e) {
      // Network/other exception.
      state = state.copyWith(
        submitting: false,
        successMessage: null,
        errorMessage: 'Network error: ${e.toString()}',
      );
    }
  }

  /// Clear only success/error messages (keep email/submitting untouched).
  void clearMessages() {
    state = state.copyWith(successMessage: null, errorMessage: null);
  }
}

// =============================================================
// PROVIDER
// Exposes the ForgotPasswordNotifier and its ForgotPasswordState.
// Consume with: ref.watch(forgotPasswordViewModelProvider)
// Dispatch with: ref.read(forgotPasswordViewModelProvider.notifier)
// =============================================================
final forgotPasswordViewModelProvider =
StateNotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>(
      (ref) => ForgotPasswordNotifier(),
);