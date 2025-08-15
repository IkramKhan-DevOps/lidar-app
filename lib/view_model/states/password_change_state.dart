// =============================================================
// PASSWORD CHANGE STATE (Immutable value for change-password flow)
// Represents UI state for changing the user's password.
// Exposes: submitting, successMessage, error.
// =============================================================
//
// USAGE
// - Produced by a StateNotifier (e.g., PasswordChangeViewModel/Provider).
// - Consumed in UI via Riverpod: final s = ref.watch(...);
// - Update via notifier methods; this class is a pure data holder.
//
// FIELDS
// - submitting:     true while the change request is in-flight.
// - error:          user-friendly error to render in the UI.
// - successMessage: server-provided or generic success detail.
//
// NOTES
// - copyWith(...) uses direct assignment for error/successMessage.
//   Passing null clears them, which is convenient for dismissing banners.
// - Keep SnackBar/Toast rendering in the UI layer.
// =============================================================

class PasswordChangeState {
  final bool submitting;
  final String? error;
  final String? successMessage;

  const PasswordChangeState({
    this.submitting = false,
    this.error,
    this.successMessage,
  });

  PasswordChangeState copyWith({
    bool? submitting,
    String? error,
    String? successMessage,
  }) {
    return PasswordChangeState(
      submitting: submitting ?? this.submitting,
      error: error,
      successMessage: successMessage,
    );
  }

  factory PasswordChangeState.initial() => const PasswordChangeState();
}