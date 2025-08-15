// =============================================================
// AUTH RESPONSE MODEL
// -------------------------------------------------------------
// Purpose:
// - Represent the unified response of an authentication request
//   that returns both the authenticated user and an auth token.
//
// Why this model?
// - Different backends can return different token keys (e.g., key,
//   token, auth_token). This model centralizes that handling.
//
// Assumptions:
// - The user payload is at the top level alongside the token fields
//   (i.e., the JSON used by AuthUser.fromJson is the same `json` map).
//   If your backend nests the user under a `user` key, adapt the
//   factory accordingly (see notes in the fromJson factory below).
// =============================================================

import 'auth_user.dart';

class AuthResponse {
  /// The authenticated user details parsed from the response.
  final AuthUser user;

  /// The authentication token (optional, because some endpoints may not return it).
  /// Common keys seen across backends:
  /// - "key"         (dj-rest-auth)
  /// - "token"       (generic JWT/token setups)
  /// - "auth_token"  (some REST APIs)
  final String? token;

  /// Creates an AuthResponse with a [user] and optional [token].
  AuthResponse({required this.user, this.token});

  /// Builds an AuthResponse from a JSON map.
  ///
  /// Token resolution:
  /// - Tries "token", then "key", then "auth_token" in order.
  ///
  /// User resolution:
  /// - This assumes the same top-level map used for [AuthUser.fromJson].
  ///   If your API returns:
  ///     { "user": { ...user fields... }, "key": "..." }
  ///   then change to:
  ///     user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      user: AuthUser.fromJson(json),
      token: json['token'] ?? json['key'] ?? json['auth_token'],
    );
  }
}