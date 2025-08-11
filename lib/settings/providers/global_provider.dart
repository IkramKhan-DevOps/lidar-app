import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_network.dart';
import '../../core/network/api_network_base.dart';
import '../../repository/auth_repository.dart';
import '../../repository/profile_repository.dart';
import '../../view_model/auth/auth_view_model.dart';
import '../../view_model/notifiers/profile_notifier.dart';
import '../../view_model/states/auth_state.dart';
import '../../view_model/states/profile_state.dart';



// Network service
final apiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

// Repositories
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AuthRepository(api);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ProfileRepository(api);
});

// Profile notifier
final profileNotifierProvider =
StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier();
});

// Auth ViewModel
final authViewModelProvider =
StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  return AuthViewModel(authRepo, profileRepo, ref);
});