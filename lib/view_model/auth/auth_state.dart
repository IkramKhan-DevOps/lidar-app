// =============================================================
// AUTH STATE (Immutable)
// Represents UI state for login & signup flows.
// =============================================================
import '../../models/auth_user.dart';

enum AuthStatus { idle, loading, success, error }

class AuthState {
  final AuthStatus status;
  final AuthUser? user;         // Future use (profile)
  final String? errorMessage;   // Human-readable error
  final bool isSubmitting;      // For button disabling/spinner
  final String? token;          // Saved token
  final bool isSignupFlow;      // Distinguish which action produced success/error

  const AuthState({
    this.status = AuthStatus.idle,
    this.user,
    this.errorMessage,
    this.isSubmitting = false,
    this.token,
    this.isSignupFlow = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
    bool? isSubmitting,
    String? token,
    bool? isSignupFlow,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      token: token ?? this.token,
      isSignupFlow: isSignupFlow ?? this.isSignupFlow,
    );
  }

  factory AuthState.initial() => const AuthState();
}