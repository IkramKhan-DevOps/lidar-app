// =============================================================
// PROFILE MODEL (User Details)
// -------------------------------------------------------------
// Matches GET /accounts/auth/user/ response from dj-rest-auth.
//
// Fields:
// - Read-only (usually): pk, email
// - Editable: first_name, last_name, (username if your backend allows)
// -------------------------------------------------------------
//
// Example response (dj-rest-auth):
// {
//   "pk": 1,
//   "username": "johndoe",
//   "email": "john@example.com",
//   "first_name": "John",
//   "last_name": "Doe"
// }
// =============================================================
class ProfileModel {
  /// Database primary key for this user.
  final int pk;

  /// User's email (typically immutable through this endpoint).
  final String email;

  /// Optional username (may be absent depending on backend configuration).
  final String? username;

  /// Optional first name.
  final String? firstName;

  /// Optional last name.
  final String? lastName;

  /// Create a ProfileModel.
  /// - [pk] and [email] are required (sensible defaults applied in fromJson).
  const ProfileModel({
    required this.pk,
    required this.email,
    this.username,
    this.firstName,
    this.lastName,
  });

  /// Build a ProfileModel from JSON returned by the API.
  ///
  /// Safe defaults:
  /// - pk defaults to 0 if missing.
  /// - email defaults to empty string if missing.
  /// - Optional fields can be null if absent.
  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      pk: json['pk'] ?? 0,
      email: json['email'] ?? '',
      username: json['username'], // may be absent
      firstName: json['first_name'],
      lastName: json['last_name'],
    );
  }

  /// Prepare a JSON payload for updating the user's profile.
  ///
  /// By default, only sends first_name and last_name.
  /// Set [includeUsername] to true to include username if it exists.
  ///
  /// Returns a map ready to be sent to PUT/PATCH endpoints.
  Map<String, dynamic> toUpdateJson({bool includeUsername = false}) {
    final map = <String, dynamic>{
      'first_name': firstName ?? '',
      'last_name': lastName ?? '',
    };
    if (includeUsername && username != null) {
      map['username'] = username;
    }
    return map;
  }

  /// A user-friendly display name.
  ///
  /// Priority:
  /// 1) "firstName lastName" if at least one is non-empty
  /// 2) username if present
  /// 3) email as a final fallback
  String get displayName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    if (fn.isNotEmpty || ln.isNotEmpty) return ('$fn $ln').trim();
    if ((username ?? '').isNotEmpty) return username!;
    return email;
  }

  /// Return a new instance with some fields replaced.
  ///
  /// Useful for immutability patterns when updating just a subset of fields.
  ProfileModel copyWith({
    int? pk,
    String? email,
    String? username,
    String? firstName,
    String? lastName,
  }) {
    return ProfileModel(
      pk: pk ?? this.pk,
      email: email ?? this.email,
      username: username ?? this.username,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
    );
  }
}