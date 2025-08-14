// =============================================================
// FORGOT PASSWORD VIEWMODEL (Riverpod StateNotifier)
// Central state management for requesting a password reset email.
// Exposes: ForgotPasswordState (email, submitting, successMessage, errorMessage).
// UI should observe this ViewModel and render feedback accordingly.
// =============================================================
//
// USAGE
// - Read state in widgets:
//     final state = ref.watch(forgotPasswordViewModelProvider);
// - Trigger actions:
//     ref.read(forgotPasswordViewModelProvider.notifier).updateEmail(email);
//     ref.read(forgotPasswordViewModelProvider.notifier).submit();
// - Clear transient messages after showing a snackbar/toast:
//     ref.read(forgotPasswordViewModelProvider.notifier).clearMessages();
//
// LAYERS
// - AuthRepository: injected data layer that performs the reset request.
// - ForgotPasswordNotifier: orchestrates validation + repository call.
// - ForgotPasswordState: simple state object consumed by the UI.
//
// NOTES
// - Keep SnackBar/Toast rendering in the UI layer; this ViewModel
//   only manages state and orchestrates API calls.
// - submitWithEmail(...) is a convenience method to set and submit in one go.
// - _mapError(...) attempts to surface user-friendly error messages.
// =============================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/auth_provider.dart';
import '../../../repository/auth_repository.dart';
import '../states/forgot_password_state.dart';

class ForgotPasswordNotifier extends StateNotifier<ForgotPasswordState> {
  final AuthRepository repository;
  ForgotPasswordNotifier(this.repository) : super(const ForgotPasswordState());

  // Reset to initial state.
  void clear() {
    state = const ForgotPasswordState();
  }

  // Clear only messages (keep current email and submitting).
  void clearMessages() {
    state = state.copyWith(errorMessage: null, successMessage: null);
  }

  // Update email (trims and lowercases for consistency).
  void updateEmail(String email) {
    state = state.copyWith(
      email: email,
      errorMessage: null,
      successMessage: null,
    );
  }

  // Optional: quick submit with a provided email (bypasses manual update).
  Future<void> submitWithEmail(String email) async {
    updateEmail(email);
    await submit();
  }

  // Validate and submit the password reset request.
  Future<void> submit() async {
    final email = state.email.trim().toLowerCase();
    if (email.isEmpty) {
      state = state.copyWith(errorMessage: 'Email is required');
      return;
    }
    // Simple email format check (optional; adjust per requirements).
    final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!emailOk) {
      state = state.copyWith(errorMessage: 'Please enter a valid email address');
      return;
    }

    state = state.copyWith(
      submitting: true,
      errorMessage: null,
      successMessage: null,
      email: email,
    );

    try {
      final detail = await repository.requestPasswordReset(email: email);
      state = state.copyWith(
        submitting: false,
        successMessage: detail.isNotEmpty
            ? detail
            : 'If an account exists for $email, a reset email has been sent.',
      );
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        errorMessage: _mapError(e),
      );
    }
  }

  // Attempts to extract a readable error message from backend responses.
  String _mapError(Object e) {
    final raw = e.toString();
    // Try to extract JSON error object enclosed in braces.
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      try {
        final decoded =
        jsonDecode(raw.substring(start, end + 1)) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final val = entry.value;
          if (val is List && val.isNotEmpty) return val.first.toString();
          if (val is String) return val;
        }
      } catch (_) {
        // ignore parse issues and fall through
      }
    }
    // Common fallbacks
    if (raw.contains('Timeout')) return 'Network timeout. Please try again.';
    if (raw.contains('SocketException') || raw.contains('Network')) {
      return 'Network error. Check your connection and try again.';
    }
    return raw.replaceFirst('Exception: ', '');
  }
}

// =============================================================
// PROVIDER WIRING
// Resolves AuthRepository from DI and exposes the StateNotifier.
// Read state:   ref.watch(forgotPasswordViewModelProvider)
// Call actions: ref.read(forgotPasswordViewModelProvider.notifier).submit()
// =============================================================
final forgotPasswordViewModelProvider =
StateNotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return ForgotPasswordNotifier(repo);
});