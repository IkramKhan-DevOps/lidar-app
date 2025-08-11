import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../repository/auth_repository.dart';
import '../states/password_change_state.dart';

class PasswordChangeViewModel extends StateNotifier<PasswordChangeState> {
  final AuthRepository _authRepository;
  PasswordChangeViewModel(this._authRepository)
      : super(PasswordChangeState.initial());

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

  void clearMessages() {
    state = state.copyWith(error: null, successMessage: null);
  }

  String _extractFirstError(String raw) {
    // Attempt to parse maps like:
    // {new_password2: [This password is too short...]}
    // or JSON-like substrings.
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
        // If not JSON, best effort regex
      }
    }
    // Generic fallback
    if (raw.contains('short')) return 'Password too short.';
    return raw.replaceAll('Exception: ', '');
  }
}