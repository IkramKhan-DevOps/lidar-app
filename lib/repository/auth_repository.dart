// =============================================================
// AUTH REPOSITORY
// -------------------------------------------------------------
// Purpose:
// - Provide a clean interface for authentication-related operations.
// - Hide networking details from the rest of the app.
// - Persist/remove auth token via AuthToken storage.
//
// Endpoints used (from APIUrl):
// - signIn:        POST email/password -> returns token (key)
// - signUp:        POST registration data -> returns detail message
// - logout:        POST -> returns detail message (also clears token locally)
// - passwordChange:POST new passwords -> returns detail message
// - passwordReset: POST email -> returns detail message
//
// Notes:
// - This class depends on a BaseApiService so it can be easily mocked in tests.
// - On successful login, the token is saved via AuthToken.saveToken.
// - Methods throw an Exception if the server response is not as expected;
//   call sites should catch and surface a user-friendly message.
// =============================================================

import '../core/network/api_network_base.dart';
import '../core/network/api_urls.dart';
import '../core/storage/auth_storage.dart';

class AuthRepository {
  // Low-level HTTP service (injected for testability and swapping transports).
  final BaseApiService api;

  // Require the API service via constructor injection.
  AuthRepository(this.api);

  // -----------------------------------------------------------
  // login
  // Authenticates the user with email and password.
  //
  // Params:
  // - email: user's email
  // - password: user's password
  //
  // Returns:
  // - String auth token (saved to local storage)
  //
  // Throws:
  // - Exception if the token is missing from the response
  // -----------------------------------------------------------
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final body = {'email': email, 'password': password};

    // isToken=false (not authenticated yet), noJson=false (send JSON)
    print(APIUrl.signIn);
    final res = await api.postAPI(APIUrl.signIn, body, false, false);

    // Accept token from common shapes
    if (res is Map) {
      dynamic tokenVal = res['token'] ?? res['key'] ?? res['auth_token'];
      // Nested under data: {...}
      if (tokenVal == null && res['data'] is Map) {
        final m = res['data'] as Map;
        tokenVal = m['token'] ?? m['key'] ?? m['auth_token'] ?? m['access'];
      }
      // Fallback: access (JWT)
      tokenVal ??= res['access'];
      if (tokenVal is String && tokenVal.isNotEmpty) {
        final token = tokenVal;
        await AuthToken.saveToken(token);
        return token;
      }
    }
    throw Exception('Token not found in login response');
  }

  // -----------------------------------------------------------
  // register
  // Creates a new user account.
  //
  // Params:
  // - username, email, password1, password2 (confirmation)
  //
  // Returns:
  // - String message from server (e.g., "Verification e-mail sent.")
  //
  // Throws:
  // - Exception if server response is not in the expected format
  // -----------------------------------------------------------
  Future<String> register({
    required String username,
    required String email,
    required String password1,
    required String password2,
  }) async {
    final body = {
      'username': username,
      'email': email,
      'password1': password1,
      'password2': password2,
    };

    // isToken=false (not authenticated), noJson=false (send JSON)
    final res = await api.postAPI(APIUrl.signUp, body, false, false);

    // Many backends respond with {"detail": "..."} after registration
    if (res is Map && res['detail'] != null) {
      return res['detail'].toString();
    }
    throw Exception('Unexpected registration response');
  }

  // -----------------------------------------------------------
  // logoutRemote
  // Performs a server-side logout (invalidates token/session).
  //
  // Params:
  // - csrfToken (optional): included for frameworks that require CSRF;
  //   currently not used in this request body/headers.
  //
  // Returns:
  // - String message from server or a default "Logged out"
  // -----------------------------------------------------------
  Future<String> logoutRemote({String? csrfToken}) async {
    try {
      final res = await api.postAPI(APIUrl.logout, {}, true, false);
      if (res is Map && res['detail'] != null) {
        return res['detail'].toString();
      }
      return 'Logged out';
    } catch (_) {
      final res = await api.getAPI(APIUrl.logout, true);
      if (res is Map && res['detail'] != null) {
        return res['detail'].toString();
      }
      return 'Logged out';
    }
  }

  // -----------------------------------------------------------
  // logout
  // Client-side logout: removes the locally stored auth token.
  // -----------------------------------------------------------
  Future<void> logout() async {
    await AuthToken.removeToken();
  }

  // Token refresh if your server supports it (optional placeholder)
  // Future<String> refreshToken() async { ... }

  // -----------------------------------------------------------
  // changePassword
  // Changes the authenticated user's password.
  //
  // Params:
  // - newPassword1: new password
  // - newPassword2: confirmation
  //
  // Returns:
  // - String message from server (e.g., "New password has been saved.")
  //
  // Throws:
  // - Exception with server response content if format is unexpected
  // -----------------------------------------------------------
  Future<String> changePassword({
    required String newPassword1,
    required String newPassword2,
  }) async {
    final body = {
      'new_password1': newPassword1,
      'new_password2': newPassword2,
    };

    // isToken=true (must be authenticated), noJson=false (send JSON)
    final res = await api.postAPI(APIUrl.passwordChange, body, true, false);

    if (res is Map) {
      if (res['detail'] != null) return res['detail'].toString();
      // If server returned a different shape, bubble it up for visibility
      throw Exception(res.toString());
    }
    throw Exception('Unexpected response for password change');
  }

  // -----------------------------------------------------------
  // requestPasswordReset
  // Requests a password reset email to be sent to the user.
  //
  // Params:
  // - email: the user's email address
  //
  // Returns:
  // - String message from server (e.g., "Password reset e-mail has been sent.")
  //
  // Throws:
  // - Exception if server response is not in the expected format
  // -----------------------------------------------------------
  Future<String> requestPasswordReset({required String email}) async {
    final body = {'email': email};

    // isToken=false (anonymous), noJson=false (send JSON)
    final res = await api.postAPI(APIUrl.passwordReset, body, false, false);

    if (res is Map && res['detail'] != null) {
      return res['detail'].toString();
    }
    throw Exception('Unexpected password reset response');
  }
}
