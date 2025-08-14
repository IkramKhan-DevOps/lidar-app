// =============================================================
// AUTH PROVIDERS (Riverpod)
// Central DI wiring for Auth + Profile features.
// Exposes: Network service, Repositories, Profile notifier, Auth ViewModel.
// UI should listen to authViewModelProvider for AuthState updates.
// =============================================================
//
// USAGE
// - Read reactive state in widgets with: ref.watch(<provider>)
// - Invoke actions with: ref.read(<provider>.notifier).someMethod()
// - Override providers in tests using ProviderScope(overrides: [...]).
//
// LAYERS
// - apiServiceProvider: low-level HTTP/API client (BaseApiService).
// - Repositories: thin data-access layer using the API service.
// - ProfileNotifier: lightweight profile state holder.
// - AuthViewModel: orchestrates auth flows and exposes AuthState.
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_network.dart';
import '../../core/network/api_network_base.dart';
import '../../repository/auth_repository.dart';
import '../../repository/profile_repository.dart';
import '../../view_model/auth/auth_view_model.dart';
import '../../view_model/notifiers/profile_notifier.dart';
import '../../view_model/states/auth_state.dart';
import '../../view_model/states/profile_state.dart';

// =============================================================
// NETWORK SERVICE
// Provides the BaseApiService implementation used by repositories.
// Override in tests to supply a mock/fake network layer.
// =============================================================
final apiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

// =============================================================
// REPOSITORIES
// Encapsulate data access and API calls, keeping ViewModels clean.
// =============================================================
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AuthRepository(api);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ProfileRepository(api);
});

// =============================================================
// PROFILE NOTIFIER
// Holds lightweight profile state separate from auth flow.
// Useful for broadcasting profile updates across the app.
// =============================================================
final profileNotifierProvider =
StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier();
});

// =============================================================
// AUTH VIEWMODEL
// Orchestrates authentication (login/logout/restore) and exposes
// AuthState to the UI.
// Read state:   ref.watch(authViewModelProvider)
// Call actions: ref.read(authViewModelProvider.notifier).login(...)
// =============================================================
final authViewModelProvider =
StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  return AuthViewModel(authRepo, profileRepo, ref);
});