// =============================================================
// PROFILE MODEL (User Details)
// Matches GET /accounts/auth/user/ response from dj-rest-auth.
// Read-only: pk, email
// Editable: first_name, last_name, (username if your backend includes it).
// =============================================================
class ProfileModel {
  final int pk;
  final String email;
  final String? username;
  final String? firstName;
  final String? lastName;

  const ProfileModel({
    required this.pk,
    required this.email,
    this.username,
    this.firstName,
    this.lastName,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      pk: json['pk'] ?? 0,
      email: json['email'] ?? '',
      username: json['username'],        // may be absent
      firstName: json['first_name'],
      lastName: json['last_name'],
    );
  }

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

  String get displayName {
    final fn = (firstName ?? '').trim();
    final ln = (lastName ?? '').trim();
    if (fn.isNotEmpty || ln.isNotEmpty) return ('$fn $ln').trim();
    if ((username ?? '').isNotEmpty) return username!;
    return email;
  }

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