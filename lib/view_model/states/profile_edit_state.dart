// =============================================================
// PROFILE EDIT STATE
// UI-specific editing state separate from global profile.
// =============================================================
import '../../models/profile_model.dart';

class ProfileEditState {
  final ProfileModel? original;
  final bool loading;      // fetching existing
  final bool saving;       // submitting update
  final String? error;
  final bool saved;        // indicates last save succeeded

  const ProfileEditState({
    this.original,
    this.loading = false,
    this.saving = false,
    this.error,
    this.saved = false,
  });

  ProfileEditState copyWith({
    ProfileModel? original,
    bool? loading,
    bool? saving,
    String? error,
    bool? saved,
  }) {
    return ProfileEditState(
      original: original ?? this.original,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: error,
      saved: saved ?? this.saved,
    );
  }

  factory ProfileEditState.initial() => const ProfileEditState();
}