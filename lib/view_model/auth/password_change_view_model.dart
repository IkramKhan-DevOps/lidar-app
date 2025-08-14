// =============================================================
// PASSWORD CHANGE VIEWMODEL (Riverpod StateNotifier)
// Central state manager for the "Change Password" flow.
// Exposes: PasswordChangeState (submitting, successMessage, error).
// UI should observe this ViewModel and render feedback accordingly.
// =============================================================
//
// USAGE
// - Read state in widgets:
//     final state = ref.watch(passwordChangeViewModelProvider);
// - Trigger actions:
//     ref.read(passwordChangeViewModelProvider.notifier).changePassword(
//       newPassword1: p1,
//       newPassword2: p2,
//     );
// - Clear transient messages after showing a snackbar/toast:
//     ref.read(passwordChangeViewModelProvider.notifier).clearMessages();
//
// LAYERS
// - AuthRepository: injected data layer that executes the API call.
// - PasswordChangeViewModel: orchestrates validation + repository call.
// - PasswordChangeState: plain state model consumed by the UI.
//
// NOTES
// - Keep SnackBar/Toast rendering in the UI layer; this ViewModel
//   only manages state and orchestrates API calls.
// - _extractFirstError(...) attempts to surface user-friendly errors
//   from structured backend responses.
// =============================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../repository/auth_repository.dart';
import '../states/password_change_state.dart';

class PasswordChangeViewModel extends StateNotifier<PasswordChangeState> {
  final AuthRepository _authRepository;
  PasswordChangeViewModel(this._authRepository)
      : super(PasswordChangeState.initial());

  // Perform password change with simple client-side validation.
  Future<void> changePassword({
    required String newPassword1,
    required String newPassword2,
  }) async {
    if (newPassword1.isEmpty || newPassword2.isEmpty) {
      state = state.copyWith(error: 'Both fields are required.');
      return;
    }
    if (newPassword1 != newPassword2) {
      state = state.copyWith(error: 'Passwords do not match.');
      return;
    }
    if (newPassword1.length < 8) {
      state = state.copyWith(error: 'Password must be at least 8 characters.');
      return;
    }

    state = state.copyWith(submitting: true, error: null, successMessage: null);
    try {
      final detail = await _authRepository.changePassword(
        newPassword1: newPassword1,
        newPassword2: newPassword2,
      );
      state = state.copyWith(
        submitting: false,
        successMessage: detail,
      );
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        error: _extractFirstError(e.toString()),
      );
    }
  }

  // Clear transient messages (useful after showing a snackbar/banner).
  void clearMessages() {
    state = state.copyWith(error: null, successMessage: null);
  }

  // Attempts to extract a readable error message from backend responses.
  // Examples handled:
  // - {new_password2: [This password is too short...]}
  // - JSON-like substrings embedded in Exception strings.
  String _extractFirstError(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      final cut = raw.substring(start, end + 1);
      try {
        final decoded = jsonDecode(cut);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final v = entry.value;
            if (v is List && v.isNotEmpty) return v.first.toString();
            if (v is String) return v;
          }
        }
      } catch (_) {
        // Fall through if not valid JSON
      }
    }
    // Generic fallback
    if (raw.contains('short')) return 'Password too short.';
    return raw.replaceAll('Exception: ', '');
  }
}