class AuthUser {
  final String username;
  final String email;

  AuthUser({
    required this.username,
    required this.email,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      username: json['username'] ?? '',
      email: json['email'] ?? '',
    );
  }
}