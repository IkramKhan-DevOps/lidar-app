import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/auth_provider.dart';
import '../../../repository/auth_repository.dart';
import '../states/forgot_password_state.dart'; // Adjust if you have a different repo provider path

class ForgotPasswordNotifier extends StateNotifier<ForgotPasswordState> {
  final AuthRepository repository;
  ForgotPasswordNotifier(this.repository) : super(const ForgotPasswordState());

  void clear() {
    state = const ForgotPasswordState();
  }

  void updateEmail(String email) {
    state = state.copyWith(email: email, errorMessage: null, successMessage: null);
  }

  Future<void> submit() async {
    final email = state.email.trim();
    if (email.isEmpty) {
      state = state.copyWith(errorMessage: 'Email is required');
      return;
    }
    state = state.copyWith(submitting: true, errorMessage: null, successMessage: null);
    try {
      final detail = await repository.requestPasswordReset(email: email);
      state = state.copyWith(
        submitting: false,
        successMessage: detail,
      );
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

final forgotPasswordViewModelProvider =
StateNotifierProvider<ForgotPasswordNotifier, ForgotPasswordState>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return ForgotPasswordNotifier(repo);
});