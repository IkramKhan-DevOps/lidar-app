// =============================================================
// AUTH STATE (Immutable value for Auth domain)
// Represents the current authentication lifecycle and related data.
// Exposes: AuthFlow, token, profile, registrationMessage, flags for UI.
//
// This state is intended to be produced/updated by an AuthViewModel
// and consumed by the UI via Riverpod (ref.watch(...)).
// =============================================================
//
// USAGE
// - Read in widgets (watch for changes):
//     final auth = ref.watch(authViewModelProvider);
// - Trigger mutations through the ViewModel, not this class.
//   This class is a pure data holder with copyWith/initial() helpers.
//
// FLOWS
// - idle:          No active auth operation; user might be logged out.
// - loading:       Performing login/register/restore actions.
// - authenticated: User is logged in (token + optionally profile).
// - error:         Last auth action failed (see error string).
// - registered:    Registration succeeded (email verification sent).
//
// FIELDS
// - flow:             High-level auth lifecycle indicator.
// - token:            Current auth token (if authenticated).
// - error:            Last error message, if any.
// - isSubmitting:     UI hint for form submissions (login/register).
// - isLoggingOut:     UI hint for logout progress.
// - profile:          User profile details (optional).
// - registrationMessage: Helpful detail after registration.
//
// NOTES
// - isLoggedIn is true only when flow == authenticated and token != null.
// - copyWith(...) lets callers update selective fields. Passing null for
//   "error" or "registrationMessage" clears them.
// =============================================================

import '../../models/profile_model.dart';

/// High-level flow indicator used by the UI.
enum AuthFlow {
  idle,          // Not doing anything, not authenticated
  loading,       // Performing login / register / restore
  authenticated, // User is logged in (token + profile)
  error,         // Last action failed
  registered,    // Registration success (email verification sent)
}

/// Immutable authentication state.
class AuthState {
  /// High-level lifecycle for auth.
  final AuthFlow flow;

  /// Authentication token if the user is logged in.
  final String? token;

  /// Last error message encountered by an auth action.
  final String? error;

  /// UI flag for active auth form submissions (login/register).
  final bool isSubmitting;

  /// UI flag for logout spinner / disabling UI.
  final bool isLoggingOut;

  /// The current user's profile, if fetched.
  final ProfileModel? profile;

  /// A message shown after successful registration (e.g., verification info).
  final String? registrationMessage;

  const AuthState({
    this.flow = AuthFlow.idle,
    this.token,
    this.error,
    this.isSubmitting = false,
    this.isLoggingOut = false, // default false
    this.profile,
    this.registrationMessage,
  });

  /// Convenience getter to indicate the user is authenticated.
  bool get isLoggedIn => flow == AuthFlow.authenticated && token != null;

  /// Creates a modified copy of this state.
  ///
  /// Note: Passing `null` for [error] or [registrationMessage] will clear them.
  AuthState copyWith({
    AuthFlow? flow,
    String? token,
    String? error,
    bool? isSubmitting,
    bool? isLoggingOut, // allow overriding via copyWith
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

  /// Initial, idle state.
  factory AuthState.initial() => const AuthState();
}