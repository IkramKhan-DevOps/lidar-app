// =============================================================
// PROFILE EDIT VIEWMODEL (Riverpod StateNotifier)
// Central state manager for the Profile Edit screen.
// Exposes: ProfileEditState (original, loading, saving, saved, error).
// UI should observe this ViewModel and render feedback accordingly.
// =============================================================
//
// USAGE
// - Read state in widgets:
//     final state = ref.watch(profileEditViewModelProvider);
// - Trigger actions:
//     ref.read(profileEditViewModelProvider.notifier).load();
//     ref.read(profileEditViewModelProvider.notifier).save(
//       firstName: ...,
//       lastName: ...,
//       username: ...,
//     );
// - Clear transient flags after showing a snackbar/toast:
//     ref.read(profileEditViewModelProvider.notifier).clearSavedFlag();
//
// LAYERS
// - ProfileRepository: data layer that fetches/updates user profile.
// - ProfileNotifier (global): lightweight store broadcasting profile changes.
// - AuthViewModel: keeps AuthState.profile in sync when authenticated.
//
// NOTES
// - Keep SnackBar/Toast rendering in the UI layer; this ViewModel only
//   manages state and orchestrates repository calls.
// - load() fetches fresh profile, updates global ProfileNotifier, and
//   syncs AuthState.profile when logged in.
// - save() validates inputs, updates the backend, then updates both local
//   state and global stores, and flips saved=true for one-shot success UI.
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repository/profile_repository.dart';
import '../../settings/providers/auth_provider.dart';
import '../states/profile_edit_state.dart';

class ProfileEditViewModel extends StateNotifier<ProfileEditState> {
  final ProfileRepository _repo;
  final Ref _ref;

  ProfileEditViewModel(this._repo, this._ref)
      : super(ProfileEditState.initial());

  // Load profile from repository (fresh) and broadcast globally.
  Future<void> load() async {
    state = state.copyWith(loading: true, error: null, saved: false);
    try {
      final profile = await _repo.fetchUserDetails();

      // Update global profile store (recommended)
      _ref.read(profileNotifierProvider.notifier).setProfile(profile);

      // Also sync into AuthState if authenticated
      final auth = _ref.read(authViewModelProvider);
      if (auth.isLoggedIn) {
        _ref
            .read(authViewModelProvider.notifier)
            .setProfileFromOutside(profile);
      }

      state = state.copyWith(original: profile, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _mapError(e),
      );
    }
  }

  // Save updates, then update global stores and local state.
  Future<void> save({
    required String firstName,
    required String lastName,
    String? username,
  }) async {
    if (firstName.isEmpty && lastName.isEmpty) {
      state = state.copyWith(error: 'At least one name field required.');
      return;
    }
    state = state.copyWith(saving: true, error: null, saved: false);
    try {
      final updated = await _repo.updateUserDetails(
        firstName: firstName,
        lastName: lastName,
        username: username,
      );

      // Update global profile stores
      _ref.read(profileNotifierProvider.notifier).updateProfile(updated);
      final auth = _ref.read(authViewModelProvider);
      if (auth.isLoggedIn) {
        _ref
            .read(authViewModelProvider.notifier)
            .setProfileFromOutside(updated);
      }

      // Reflect success locally
      state = state.copyWith(
        original: updated,
        saving: false,
        saved: true,
      );
    } catch (e) {
      state = state.copyWith(
        saving: false,
        error: _mapError(e),
      );
    }
  }

  // Clear the "saved" one-shot flag after UI has reacted.
  void clearSavedFlag() {
    if (state.saved) {
      state = state.copyWith(saved: false);
    }
  }

  // Minimal error mapper (extend as needed).
  String _mapError(Object e) {
    final raw = e.toString();
    if (raw.contains('Unauthorized')) return 'Session expired. Log in again.';
    return raw.replaceAll('Exception: ', '');
  }
}