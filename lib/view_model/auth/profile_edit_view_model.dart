// =============================================================
// PROFILE EDIT VIEW MODEL
// Coordinates fetching & updating user details for the edit screen.
// On successful update it also refreshes the global ProfileNotifier
// and updates AuthState.profile (if you want).
// =============================================================
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repository/profile_repository.dart';
import '../../settings/providers/auth_provider.dart';
import '../states/rofile_edit_state.dart';


class ProfileEditViewModel extends StateNotifier<ProfileEditState> {
  final ProfileRepository _repo;
  final Ref _ref;

  ProfileEditViewModel(this._repo, this._ref)
      : super(ProfileEditState.initial());

  // Load from repository (fresh)
  Future<void> load() async {
    state = state.copyWith(loading: true, error: null, saved: false);
    try {
      final profile = await _repo.fetchUserDetails();
      // Update global profile store too (optional but recommended)
      _ref.read(profileNotifierProvider.notifier).setProfile(profile);

      // Also sync into AuthState if authenticated
      final auth = _ref.read(authViewModelProvider);
      if (auth.isLoggedIn) {
        _ref.read(authViewModelProvider.notifier)
            .setProfileFromOutside(profile); // We'll add helper method.
      }

      state = state.copyWith(original: profile, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: _mapError(e),
      );
    }
  }

  // Save updates
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
      // Update local + global profile
      _ref.read(profileNotifierProvider.notifier).updateProfile(updated);
      final auth = _ref.read(authViewModelProvider);
      if (auth.isLoggedIn) {
        _ref.read(authViewModelProvider.notifier)
            .setProfileFromOutside(updated);
      }
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

  void clearSavedFlag() {
    if (state.saved) {
      state = state.copyWith(saved: false);
    }
  }

  String _mapError(Object e) {
    final raw = e.toString();
    // Simple extraction
    if (raw.contains('Unauthorized')) return 'Session expired. Log in again.';
    return raw.replaceAll('Exception: ', '');
  }
}