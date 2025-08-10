import 'auth_user.dart';

class AuthResponse {
  final AuthUser user;
  final String? token; // adapt if your key is different, e.g. 'key', 'auth_token'

  AuthResponse({required this.user, this.token});

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: AuthUser.fromJson(json),
      token: json['token'] ?? json['key'] ?? json['auth_token'],
    );
  }
}