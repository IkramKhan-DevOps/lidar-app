import '../../models/auth_user.dart';

enum AuthStatus { idle, loading, success, error }

class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;
  final bool isSubmitting;
  final String? token; // store token if needed

  const AuthState({
    this.status = AuthStatus.idle,
    this.user,
    this.errorMessage,
    this.isSubmitting = false,
    this.token,
  });

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
    bool? isSubmitting,
    String? token,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      token: token ?? this.token,
    );
  }

  factory AuthState.initial() => const AuthState();
}