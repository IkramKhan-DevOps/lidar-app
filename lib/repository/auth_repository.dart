// =============================================================
// AUTH REPOSITORY
// Bridges NetworkApiService and ViewModels.
// Contains business logic for login & signup.
// =============================================================
import '../core/network/api_network_base.dart';
import '../core/network/api_urls.dart';
import '../core/storage/auth_storage.dart';


class AuthRepository {
  final BaseApiService api;
  AuthRepository(this.api);

  // ---------------- LOGIN ----------------
  // Body expected by backend: { "email": "...", "password": "..." }
  // Response: { "key": "TOKEN" }
  Future<String> login({
    required String email,
    required String password,
  }) async {
    final body = {'email': email, 'password': password};
    final res = await api.postAPI(APIUrl.signIn, body, false, false);

    if (res is Map && res['key'] != null) {
      final token = res['key'] as String;
      await AuthToken.save(token);
      return token;
    }
    throw Exception('Token not found in login response');
  }

  // ---------------- SIGNUP ----------------
  // VARIANT B (single password) used here:
  // Body: { "email": "...", "password": "...", "username": "optional" }
  // If your backend requires password1/password2 (Variant A),
  // use the commented block below instead and remove this body.
  Future<String> signup({
    required String email,
    required String password,
    required String confirmPassword,
    String? username,
  }) async {
    // ---------- Variant A (if backend requires password1/password2) ----------
    // final body = {
    //   'email': email,
    //   'password1': password,
    //   'password2': confirmPassword,
    //   if (username != null && username.isNotEmpty) 'username': username,
    // };

    // ---------- Variant B (single password) ----------
    final body = {
      'email': email,
      'password': password,
      if (username != null && username.isNotEmpty) 'username': username,
      // If backend has separate confirm field:
      // 'password2': confirmPassword,
    };

    final resJson = await api.postAPI(APIUrl.signUp, body, false, false);

    if (resJson is Map && resJson['key'] != null) {
      final token = resJson['key'] as String;
      await AuthToken.save(token);
      return token;
    }
    throw Exception('Token not found in signup response');
  }

  // ---------------- LOGOUT ----------------
  Future<void> logout() async {
    await AuthToken.clear();
  }
}