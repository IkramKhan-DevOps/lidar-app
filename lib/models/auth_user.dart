// =============================================================
// AUTH USER MODEL (Optional)
// If your profile endpoint returns user details, parse them here.
// Currently unused directly after login/signup because those
// endpoints only return a token. Keep for future profile fetch.
// =============================================================
class AuthUser {
  final String username;
  final String email;

  AuthUser({required this.username, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      username: json['username'] ?? '',
      email: json['email'] ?? '',
    );
  }
}