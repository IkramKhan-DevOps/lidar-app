import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exceptions.dart';
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

  Future<void> login({required String email, required String password}) async {
    if (email.isEmpty || password.isEmpty) {
      _emitError('Email and password required.');
      return;
    }
    state = state.copyWith(flow: AuthFlow.loading, isSubmitting: true, error: null);
    try {
      final token = await _authRepo.login(email: email, password: password);
      final profile = await _profileRepo.fetchProfile();
      _ref.read(profileNotifierProvider.notifier).setProfile(profile);
      state = state.copyWith(
        flow: AuthFlow.authenticated,
        token: token,
        profile: profile,
        isSubmitting: false,
      );
    } catch (e) {
      _emitError(_mapError(e));
    }
  }

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
    state = state.copyWith(flow: AuthFlow.loading, isSubmitting: true, error: null);
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

  Future<void> tryRestoreSession() async {
    final token = await AuthToken.getToken();
    if (token == null) {
      state = AuthState.initial();
      return;
    }
    state = state.copyWith(flow: AuthFlow.loading, isSubmitting: true);
    try {
      final profile = await _profileRepo.fetchProfile();
      _ref.read(profileNotifierProvider.notifier).setProfile(profile);
      state = state.copyWith(
        flow: AuthFlow.authenticated,
        token: token,
        profile: profile,
        isSubmitting: false,
      );
    } catch (_) {
      await _authRepo.logout();
      state = AuthState.initial();
    }
  }

  // Remote + local logout sequence
  Future<void> logout() async {
    // Show a small spinner (UI can listen to isLoggingOut)
    state = state.copyWith(isLoggingOut: true, error: null);

    String serverMessage = '';
    try {
      // Attempt remote logout (ignore result if it fails)
      serverMessage = await _authRepo.logoutRemote();
    } catch (e) {
      // Acceptable failures:
      // - 401 Invalid token (already invalid on server)
      // - Network offline
      final msg = e.toString();
      if (!msg.contains('401') && !msg.contains('Unauthorized')) {
        // If you want to surface the error, set error field (optional)
        // state = state.copyWith(error: 'Logout server error (ignored)');
      }
    } finally {
      // Always clear local state
      await _authRepo.logout();
      _ref.read(profileNotifierProvider.notifier).clear();
      state = AuthState.initial();
    }

    // (Optional) If you want to keep a last server message, you could store it in
    // a separate provider or show a SnackBar from the UI after ref.listen detects state reset.
  }

  void _emitError(String message) {
    state = state.copyWith(
      flow: AuthFlow.error,
      error: message,
      isSubmitting: false,
      isLoggingOut: false,
    );
  }
// Add this method inside AuthViewModel (after existing ones).
  void setProfileFromOutside(ProfileModel profile) {
    if (!state.isLoggedIn) return;
    state = state.copyWith(profile: profile);
  }
  String _mapError(Object e) {
    final raw = e.toString();
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
      } catch (_) {}
    }
    if (raw.contains('Unauthorized')) return 'Invalid credentials.';
    return raw.replaceAll('Exception: ', '');
  }
}