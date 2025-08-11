import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/profile_model.dart';
import '../states/profile_state.dart';


class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(ProfileState.initial());

  void setProfile(ProfileModel profile) {
    state = state.copyWith(profile: profile, loading: false, error: null);
  }

  void updateProfile(ProfileModel profile) {
    state = state.copyWith(profile: profile, loading: false);
  }

  void setLoading() {
    state = state.copyWith(loading: true);
  }

  void setError(String msg) {
    state = state.copyWith(error: msg, loading: false);
  }

  void clear() {
    state = ProfileState.initial();
  }
}