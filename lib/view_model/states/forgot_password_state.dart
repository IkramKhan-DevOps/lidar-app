// =============================================================
// FORGOT PASSWORD STATE (Immutable value for reset-password flow)
// Represents UI state for requesting a password reset email.
// Exposes: submitting, successMessage, errorMessage, email.
// =============================================================
//
// USAGE
// - Produced by a StateNotifier (e.g., ForgotPasswordNotifier).
// - Consumed in UI via Riverpod: final s = ref.watch(...);
// - Update via notifier methods; this class is a pure data holder.
//
// FIELDS
// - submitting:     true while the request is in-flight.
// - successMessage: server-provided or generic success detail.
// - errorMessage:   user-friendly error to render in the UI.
// - email:          current email value (useful for re-submission).
//
// NOTES
// - copyWith(...) uses direct assignment for successMessage/errorMessage.
//   Passing null clears them, which is convenient for dismissing banners.
// - Equatable is used so UI only rebuilds when values actually change.
// =============================================================

// If this already exists in your project, keep only one copy.
import 'package:equatable/equatable.dart';

class ForgotPasswordState extends Equatable {
  final bool submitting;
  final String? successMessage;
  final String? errorMessage;
  final String email;

  const ForgotPasswordState({
    this.submitting = false,
    this.successMessage,
    this.errorMessage,
    this.email = '',
  });

  ForgotPasswordState copyWith({
    bool? submitting,
    String? successMessage,
    String? errorMessage,
    String? email,
  }) {
    return ForgotPasswordState(
      submitting: submitting ?? this.submitting,
      successMessage: successMessage,
      errorMessage: errorMessage,
      email: email ?? this.email,
    );
  }

  @override
  List<Object?> get props => [submitting, successMessage, errorMessage, email];
}