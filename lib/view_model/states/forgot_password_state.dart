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