import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_network.dart';
import '../../core/network/api_network_base.dart';

import '../../repository/auth_repository.dart';
import '../../view_model/auth/auth_state.dart';
import '../../view_model/auth/auth_view_model.dart';


final networkApiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(networkApiServiceProvider);
  return AuthRepository(api);
});

final authViewModelProvider =
StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthViewModel(repo);
});