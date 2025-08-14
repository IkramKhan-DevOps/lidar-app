// =============================================================
// PASSWORD CHANGE PROVIDER (Riverpod StateNotifier)
// API-driven variant that talks directly to NetworkApiService.
// Exposes a rich PasswordChangeState (submitting, success, error)
// so the UI can render snackbars/banners appropriately.
//
// NOTE
// - Prefer handling UI feedback (SnackBar/Toast) in the UI layer.
// - This provider avoids using BuildContext and only manages state.
// - If you already use PasswordChangeViewModel + PasswordChangeState,
//   keep that for consistency. This is a drop-in API-based alternative.
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_network_base.dart';
import '../../core/network/api_urls.dart';
import '../../view_model/states/password_change_state.dart';

class PasswordChangeProvider extends StateNotifier<PasswordChangeState> {
  final BaseApiService api;

  PasswordChangeProvider(this.api) : super(const PasswordChangeState());

  // Change password using explicit arguments.
  Future<void> changePassword({
    required String newPassword1,
    required String newPassword2,
  }) async {
    state = state.copyWith(
      submitting: true,
      successMessage: null,
      error: null,
    );

    try {
      final payload = {
        'new_password1': newPassword1,
        'new_password2': newPassword2,
      };

      final res = await api.postAPI(APIUrl.passwordChange, payload, true, true);

      // Try to surface a helpful success detail from backend.
      String message = 'Password changed successfully';
      if (res is Map && res['detail'] != null) {
        message = res['detail'].toString();
      }

      state = state.copyWith(
        submitting: false,
        successMessage: message,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        successMessage: null,
        error: e.toString(),
      );
    }
  }

  // Optional: If you need a raw variant accepting a map payload.
  Future<void> changePasswordRaw(Map<String, dynamic> data) async {
    state = state.copyWith(
      submitting: true,
      successMessage: null,
      error: null,
    );

    try {
      final res = await api.postAPI(APIUrl.passwordChange, data, true, true);

      String message = 'Password changed successfully';
      if (res is Map && res['detail'] != null) {
        message = res['detail'].toString();
      }

      state = state.copyWith(
        submitting: false,
        successMessage: message,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        successMessage: null,
        error: e.toString(),
      );
    }
  }

  // Clear any transient messages without altering other fields.
  void clearMessages() {
    state = state.copyWith(successMessage: null, error: null);
  }
}