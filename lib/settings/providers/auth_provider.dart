// =============================================================
// AUTH PROVIDERS (Riverpod)
// Centralized dependency graph for the Auth and Profile feature set.
// Exposes Network layer, Repositories, Notifiers, and ViewModels.
// UI should listen to authViewModelProvider for AuthState updates.
// =============================================================
//
// USAGE GUIDE
// - Read state in widgets with: ref.watch(<provider>)
// - Invoke actions with: ref.read(<provider>.notifier).someMethod()
// - In tests, you can override any provider with ProviderScope overrides.
//
// LIFECYCLE
// - Providers here are app-scoped (one instance per ProviderContainer)
//   unless you override them in nested ProviderScopes.
//
// TESTING TIPS
// - Swap NetworkApiService with a mock by overriding networkApiServiceProvider.
// - Swap repositories or view models similarly for isolation/mocking.
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
import '../../view_model/states/profile_edit_state.dart';

// =============================================================
// NETWORK LAYER
// Provides the BaseApiService implementation used by repositories.
// Override this in tests to inject a mock/fake HTTP layer.
// =============================================================
final networkApiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

// =============================================================
// REPOSITORIES
// Thin data-access layer that talks to the network service.
// Keeps networking details out of ViewModels.
// =============================================================
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(networkApiServiceProvider);
  return AuthRepository(api);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final api = ref.watch(networkApiServiceProvider);
  return ProfileRepository(api);
});

// =============================================================
// NOTIFIERS
// ProfileNotifier: holds lightweight profile state separate from
// the auth flow. Useful for broadcast updates (e.g., after edits).
// =============================================================
final profileNotifierProvider =
StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier();
});

// =============================================================
// VIEW MODELS
// AuthViewModel: orchestrates login/signup/logout/restore session.
// Depends on both AuthRepository and ProfileRepository and requires
// a Ref for side-effects (e.g., updating sibling providers).
// Read state:    ref.watch(authViewModelProvider)
// Call actions:  ref.read(authViewModelProvider.notifier).login(...)
// =============================================================
// Auth view model (3 positional args)
// Auth ViewModel Provider
final authViewModelProvider = StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  return AuthViewModel(authRepo, profileRepo, ref);
});
// =============================================================
// ProfileEditViewModel
// Handles loading/saving editable profile fields.
// UI typically calls: load(), save(...), clearSavedFlag().
// =============================================================
// Add provider (after existing ones):
final profileEditViewModelProvider =
StateNotifierProvider<ProfileEditViewModel, ProfileEditState>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileEditViewModel(repo, ref);
});

// =============================================================
// PasswordChangeViewModel
// Performs password change workflow via AuthRepository.
// UI observes PasswordChangeState and calls changePassword(...).
// =============================================================
// NEW Password change provider
final passwordChangeViewModelProvider =
StateNotifierProvider<PasswordChangeViewModel, PasswordChangeState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  return PasswordChangeViewModel(authRepo);
});