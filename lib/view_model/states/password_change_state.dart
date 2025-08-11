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