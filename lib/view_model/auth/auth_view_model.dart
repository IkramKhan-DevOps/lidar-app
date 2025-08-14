// =============================================================
// AUTH VIEWMODEL (Riverpod StateNotifier)
// Central orchestrator for authentication flows and session state.
// Exposes AuthState to the UI and delegates API calls to repositories.
//
// Responsibilities:
// - login / register
// - tryRestoreSession (from persisted token)
// - logout (remote best-effort + local cleanup)
// - keep Profile state in sync via profileNotifierProvider
//
// Notes:
// - UI should read:   ref.watch(authViewModelProvider)
// - UI should call:   ref.read(authViewModelProvider.notifier).login(...)
// - Error strings are mapped to user-friendly messages via _mapError.
// =============================================================

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/auth_storage.dart';
import '../../models/profile_model.dart';
import '../../repository/auth_repository.dart';
import '../../repository/profile_repository.dart';
import '../../settings/providers/global_provider.dart';
import '../states/auth_state.dart';

class AuthViewModel extends StateNotifier<AuthState> {
  final AuthRepository _authRepo;
  final ProfileRepository _profileRepo;
  final Ref _ref;

  AuthViewModel(this._authRepo, this._profileRepo, this._ref)
      : super(AuthState.initial());

  // -------------------------------------------------------------
  // LOGIN
  // -------------------------------------------------------------
  Future<void> login({
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      _emitError('Email and password required.');
      return;
    }
    if (state.isSubmitting) return; // prevent duplicate submissions

    state =
        state.copyWith(flow: AuthFlow.loading, isSubmitting: true, error: null);
    try {
      final token = await _authRepo.login(email: email, password: password);

      // Immediately mark authenticated so navigation can proceed.
      state = state.copyWith(
        flow: AuthFlow.authenticated,
        token: token,
        isSubmitting: false,
      );

      // Fetch profile in the background; tolerate failures.
      try {
        // Allow SharedPreferences write to flush before first authorized call.
        await Future.delayed(const Duration(milliseconds: 150));
        final profile = await _profileRepo.fetchProfile();
        _ref.read(profileNotifierProvider.notifier).setProfile(profile);
        state = state.copyWith(profile: profile);
      } catch (_) {
        // Keep authenticated; profile can be loaded later.
      }
    } catch (e) {
      _emitError(_mapError(e));
    }
  }

  // -------------------------------------------------------------
  // REGISTER
  // -------------------------------------------------------------
  Future<void> register({
    required String username,
    required String email,
    required String password1,
    required String password2,
  }) async {
    if ([username, email, password1, password2].any((e) => e.isEmpty)) {
      _emitError('All fields are required.');
      return;
    }
    if (password1 != password2) {
      _emitError('Passwords do not match.');
      return;
    }
    if (state.isSubmitting) return;

    state =
        state.copyWith(flow: AuthFlow.loading, isSubmitting: true, error: null);
    try {
      final msg = await _authRepo.register(
        username: username,
        email: email,
        password1: password1,
        password2: password2,
      );
      state = state.copyWith(
        flow: AuthFlow.registered,
        registrationMessage: msg,
        isSubmitting: false,
      );
    } catch (e) {
      _emitError(_mapError(e));
    }
  }

  // -------------------------------------------------------------
  // TRY RESTORE SESSION
  // -------------------------------------------------------------
  Future<void> tryRestoreSession() async {
    final token = await AuthToken.getToken();
    if (token == null) {
      state = AuthState.initial();
      return;
    }

    state = state.copyWith(flow: AuthFlow.loading, isSubmitting: true);
    try {
      // Mark authenticated with token first.
      state = state.copyWith(
        flow: AuthFlow.authenticated,
        token: token,
        isSubmitting: false,
      );
      // Try to fetch profile but don't drop session on failure.
      try {
        final profile = await _profileRepo.fetchProfile();
        _ref.read(profileNotifierProvider.notifier).setProfile(profile);
        state = state.copyWith(profile: profile);
      } catch (_) {
        // ignore; UI remains authenticated and can retry later
      }
    } catch (_) {
      await _authRepo.logout();
      state = AuthState.initial();
    }
  }

  // -------------------------------------------------------------
  // LOGOUT (remote best-effort + local cleanup)
  // -------------------------------------------------------------
  Future<void> logout() async {
    if (state.isLoggingOut) return;

    state = state.copyWith(isLoggingOut: true, error: null);

    try {
      // Attempt remote logout; ignore common "already invalid" errors.
      await _authRepo.logoutRemote();
    } catch (e) {
      // Acceptable failures: 401/Unauthorized or offline
      final msg = e.toString();
      final ignorable = msg.contains('401') || msg.contains('Unauthorized');
      if (!ignorable) {
        // Optionally surface non-ignorable errors by setting state.error.
        // state = state.copyWith(error: 'Logout server error (ignored)');
      }
    } finally {
      // Always clear local state and broadcast profile clear.
      await _authRepo.logout();
      _ref.read(profileNotifierProvider.notifier).clear();
      state = AuthState.initial();
    }
  }

  // -------------------------------------------------------------
  // External profile update (e.g., after editing profile elsewhere)
  // -------------------------------------------------------------
  void setProfileFromOutside(ProfileModel profile) {
    if (!state.isLoggedIn) return;
    state = state.copyWith(profile: profile);
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------
  void _emitError(String message) {
    state = state.copyWith(
      flow: AuthFlow.error,
      error: message,
      isSubmitting: false,
      isLoggingOut: false,
    );
  }

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
        // ignore JSON parse issues and fall through
      }
    }

    if (raw.contains('Unauthorized')) return 'Invalid credentials.';
    return raw.replaceAll('Exception: ', '');
  }
}
