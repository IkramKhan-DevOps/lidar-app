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
    final body = {
      'email': email,
      'password': password,
    };

    final resJson = await api.postAPI(APIUrl.signIn, body, false, false);

    if (resJson is Map && resJson['key'] != null) {
      final token = resJson['key'] as String;
      await AuthToken.saveToken(token);
      return token;
    }
    throw Exception('Token not found in response');
  }

  Future<void> logout() async {
    await AuthToken.removeToken();
  }
}