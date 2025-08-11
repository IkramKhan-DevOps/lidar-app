// =============================================================
// AUTH PROVIDERS (Riverpod)
// Expose NetworkApiService, Repository, and ViewModel as providers.
// UI listens to authViewModelProvider for AuthState.
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_network.dart';
import '../../core/network/api_network_base.dart';

import '../../repository/auth_repository.dart';
import '../../repository/profile_repository.dart';
import '../../view_model/auth/password_change_view_model.dart';
import '../../view_model/auth/profile_edit_view_model.dart';
import '../../view_model/notifiers/profile_notifier.dart';
import '../../view_model/states/auth_state.dart';
import '../../view_model/auth/auth_view_model.dart';
import '../../view_model/states/password_change_state.dart';
import '../../view_model/states/profile_state.dart';
import '../../view_model/states/rofile_edit_state.dart';

// Network
final networkApiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

// Repositories
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(networkApiServiceProvider);
  return AuthRepository(api);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final api = ref.watch(networkApiServiceProvider);
  return ProfileRepository(api);
});

// Profile notifier
final profileNotifierProvider =
StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier();
});

// Auth view model (3 positional args)
final authViewModelProvider =
StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  return AuthViewModel(authRepo, profileRepo, ref);
});

// Add provider (after existing ones):
final profileEditViewModelProvider =
StateNotifierProvider<ProfileEditViewModel, ProfileEditState>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileEditViewModel(repo, ref);
});

// NEW Password change provider
final passwordChangeViewModelProvider =
StateNotifierProvider<PasswordChangeViewModel, PasswordChangeState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return PasswordChangeViewModel(authRepo);
});