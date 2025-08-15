// =============================================================
// PROFILE STATE (Immutable value for user profile)
// Centralized snapshot of user profile data and loading/error flags.
// Exposes: profile, loading, error.
// =============================================================
//
// USAGE
// - Produced by a StateNotifier (e.g., ProfileNotifier).
// - Consumed in UI via Riverpod:
//     final s = ref.watch(profileNotifierProvider);
// - Update via notifier methods; this class is a pure data holder.
//
// FIELDS
// - profile: current user profile (nullable until loaded).
// - loading: true while profile operations are in-flight.
// - error:   last error message, if any.
//
// NOTES
// - copyWith(...) assigns error directly; pass null to clear it.
// - Initial state is empty with loading=false and no error.
// =============================================================

import '../../models/profile_model.dart';

class ProfileState {
  final ProfileModel? profile;
  final bool loading;
  final String? error;

  const ProfileState({this.profile, this.loading = false, this.error});

  ProfileState copyWith({
    ProfileModel? profile,
    bool? loading,
    String? error,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      loading: loading ?? this.loading,
      error: error,
    );
  }

  factory ProfileState.initial() => const ProfileState();
}