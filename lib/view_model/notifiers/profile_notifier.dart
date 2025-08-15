// =============================================================
// PROFILE NOTIFIER (Riverpod StateNotifier)
// Lightweight, app-wide profile state holder for broadcasting
// user profile changes across the app.
//
// Exposes: ProfileState (profile, loading, error)
// Typically used alongside AuthViewModel and ProfileRepository.
// =============================================================
//
// USAGE
// - Read state in widgets:
//     final profileState = ref.watch(profileNotifierProvider);
// - Trigger updates:
//     ref.read(profileNotifierProvider.notifier).setProfile(profile);
//     ref.read(profileNotifierProvider.notifier).updateProfile(profile);
// - Handle loading/error:
//     ref.read(profileNotifierProvider.notifier).setLoading();
//     ref.read(profileNotifierProvider.notifier).setError('Oops');
//
// RESPONSIBILITIES
// - setProfile: replace current profile and clear errors
// - updateProfile: update profile without touching errors
// - setLoading: set loading=true (e.g., while fetching)
// - setError: set an error message and stop loading
// - clear: reset to initial state
//
// NOTES
// - This notifier is purely state management (no I/O).
// - Keep network/repository calls outside (e.g., in ViewModels).
// - Commonly wired in a provider at app-level for easy access.
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile_model.dart';
import '../states/profile_state.dart';

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(ProfileState.initial());

  // Replace the entire profile and clear any previous error.
  void setProfile(ProfileModel profile) {
    state = state.copyWith(profile: profile, loading: false, error: null);
  }

  // Update the profile while keeping current error state intact.
  void updateProfile(ProfileModel profile) {
    state = state.copyWith(profile: profile, loading: false);
  }

  // Indicate that a profile-related operation is in progress.
  void setLoading() {
    state = state.copyWith(loading: true);
  }

  // Record an error message and stop loading.
  void setError(String msg) {
    state = state.copyWith(error: msg, loading: false);
  }

  // Reset to the initial, empty state.
  void clear() {
    state = ProfileState.initial();
  }
}