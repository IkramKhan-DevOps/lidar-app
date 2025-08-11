import '../../../../core/network/api_network_base.dart';
import '../../../../core/network/api_urls.dart';
import '../models/profile_model.dart';

// =============================================================
// PROFILE REPOSITORY
// =============================================================


class ProfileRepository {
  final BaseApiService api;
  ProfileRepository(this.api);

  // Fetch user details
  Future<ProfileModel> fetchUserDetails() async {
    final json = await api.getAPI(APIUrl.userDetails, true);
    return ProfileModel.fromJson(json);
  }

  // Full update (PUT). Only sending first_name & last_name (and username optionally).
  Future<ProfileModel> updateUserDetails({
    required String firstName,
    required String lastName,
    String? username,          // optional if backend allows
  }) async {
    final body = {
      'first_name': firstName,
      'last_name': lastName,
      if (username != null && username.isNotEmpty) 'username': username,
    };

    final json = await api.putAPI(APIUrl.userDetails, body);
    return ProfileModel.fromJson(json);
  }


  // ALIAS for backward compatibility with older code
  Future<ProfileModel> fetchProfile() => fetchUserDetails();


}
