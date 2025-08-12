// =============================================================
// AUTH USER MODEL
// -------------------------------------------------------------
// Purpose:
// - Represent basic authenticated user details returned by your API.
// - Typically populated from a "profile" or "user" endpoint.
//
// When to use:
// - After login/signup (once you later fetch user details).
// - Anywhere you need to display or store the user's basic info.
//
// JSON expectations:
// - Expects keys "username" and "email". Falls back to empty strings
//   if keys are missing to avoid null issues.
//
// Example JSON:
// {
//   "username": "johndoe",
//   "email": "john@example.com"
// }
// =============================================================

class AuthUser {
  /// The user's unique handle or identifier.
  final String username;

  /// The user's email address.
  final String email;

  /// Create an AuthUser with [username] and [email].
  AuthUser({required this.username, required this.email});

  /// Build an AuthUser from a JSON map.
  ///
  /// Safely defaults to empty strings if fields are not present.
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      username: json['username'] ?? '',
      email: json['email'] ?? '',
    );
  }
}