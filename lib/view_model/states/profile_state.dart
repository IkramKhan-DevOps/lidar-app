
import '../../models/profile_model.dart';
// =============================================================
// PROFILE STATE
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