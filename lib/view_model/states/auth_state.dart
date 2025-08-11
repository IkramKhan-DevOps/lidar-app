
import '../../models/profile_model.dart';

// High-level flow indicator used by the UI.
enum AuthFlow {
  idle,          // Not doing anything, not authenticated
  loading,       // Performing login / register / restore
  authenticated, // User is logged in (token + profile)
  error,         // Last action failed
  registered,    // Registration success (email verification sent)
}

class AuthState {
  final AuthFlow flow;
  final String? token;
  final String? error;
  final bool isSubmitting;        // For forms (login / register)
  final bool isLoggingOut;        // For logout spinner / disabling UI
  final ProfileModel? profile;
  final String? registrationMessage;

  const AuthState({
    this.flow = AuthFlow.idle,
    this.token,
    this.error,
    this.isSubmitting = false,
    this.isLoggingOut = false,    // <-- default false
    this.profile,
    this.registrationMessage,
  });

  bool get isLoggedIn => flow == AuthFlow.authenticated && token != null;

  AuthState copyWith({
    AuthFlow? flow,
    String? token,
    String? error,
    bool? isSubmitting,
    bool? isLoggingOut,           // <-- allow overriding via copyWith
    ProfileModel? profile,
    String? registrationMessage,
  }) {
    return AuthState(
      flow: flow ?? this.flow,
      token: token ?? this.token,
      error: error,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isLoggingOut: isLoggingOut ?? this.isLoggingOut,
      profile: profile ?? this.profile,
      registrationMessage: registrationMessage,
    );
  }

  factory AuthState.initial() => const AuthState();
}