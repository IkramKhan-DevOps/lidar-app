import '../core/network/api_network_base.dart';
import '../core/network/api_urls.dart';
import '../core/storage/auth_storage.dart';
class AuthRepository {
  final BaseApiService api;
  AuthRepository(this.api);

  Future<String> login({
    required String email,
    required String password,
  }) async {
    final body = {'email': email, 'password': password};
    final res = await api.postAPI(APIUrl.signIn, body, false, false);
    if (res is Map && res['key'] != null) {
      final token = res['key'] as String;
      await AuthToken.saveToken(token);
      return token;
    }
    throw Exception('Token not found in login response');
  }

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
    final res = await api.postAPI(APIUrl.signUp, body, false, false);
    if (res is Map && res['detail'] != null) {
      return res['detail'].toString();
    }
    throw Exception('Unexpected registration response');
  }

  Future<String> logoutRemote({String? csrfToken}) async {
    final res = await api.postAPI(APIUrl.logout, {}, true, false);
    if (res is Map && res['detail'] != null) {
      return res['detail'].toString();
    }
    return 'Logged out';
  }

  Future<void> logout() async {
    await AuthToken.removeToken();
  }

  Future<String> changePassword({
    required String newPassword1,
    required String newPassword2,
  }) async {
    final body = {
      'new_password1': newPassword1,
      'new_password2': newPassword2,
    };
    final res = await api.postAPI(APIUrl.passwordChange, body, true, false);
    if (res is Map) {
      if (res['detail'] != null) return res['detail'].toString();
      throw Exception(res.toString());
    }
    throw Exception('Unexpected response for password change');
  }

  // NEW: request password reset email
  Future<String> requestPasswordReset({required String email}) async {
    final body = {'email': email};
    final res = await api.postAPI(APIUrl.passwordReset, body, false, false);
    if (res is Map && res['detail'] != null) {
      return res['detail'].toString(); // e.g. "Password reset e-mail has been sent."
    }
    throw Exception('Unexpected password reset response');
  }
}