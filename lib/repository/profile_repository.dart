// =============================================================
// PROFILE REPOSITORY
// -------------------------------------------------------------
// Purpose:
// - Provide a simple, testable interface to load and update the
//   authenticated user's profile via HTTP.
// - Hide networking details from the rest of the app.
// - Return strongly-typed ProfileModel instances.
//
// Endpoints used (from APIUrl):
// - userDetails: GET -> fetch profile
// - userDetails: PUT -> full update of profile
//
// Notes:
// - Requires an authenticated token for all calls here (user endpoints).
// - This class depends on BaseApiService for easy mocking in tests.
// =============================================================

import '../core/network/api_network_base.dart';
import '../core/network/api_urls.dart';
import '../models/profile_model.dart';

class ProfileRepository {
  // Low-level HTTP service (injected for testability and transport swap).
  final BaseApiService api;

  ProfileRepository(this.api);

  // -----------------------------------------------------------
  // fetchUserDetails
  // Fetch the authenticated user's profile data.
  //
  // Returns:
  // - ProfileModel parsed from the server's JSON.
  //
  // Throws:
  // - Whatever exceptions the API service surfaces (e.g., Unauthorized).
  // -----------------------------------------------------------
  Future<ProfileModel> fetchUserDetails() async {
    // isToken=true: include Authorization header
    final json = await api.getAPI(APIUrl.userDetails, true);
    return ProfileModel.fromJson(json);
  }

  // -----------------------------------------------------------
  // updateUserDetails (PUT)
  // Perform a full update of the user's profile fields.
  //
  // Params:
  // - firstName, lastName: required fields.
  // - username: optional; only sent if provided.
  //
  // Behavior:
  // - Sends a PUT with first_name, last_name, and optional username.
  // - Returns the updated ProfileModel from the server response.
  // -----------------------------------------------------------
  Future<ProfileModel> updateUserDetails({
    required String firstName,
    required String lastName,
    String? username, // optional if backend allows
  }) async {
    final body = {
      'first_name': firstName,
      'last_name': lastName,
      if (username != null && username.isNotEmpty) 'username': username,
    };

    final json = await api.putAPI(APIUrl.userDetails, body);
    return ProfileModel.fromJson(json);
  }

  // -----------------------------------------------------------
  // fetchProfile
  // Alias kept for backward compatibility with older code.
  // Internally calls fetchUserDetails().
  // -----------------------------------------------------------
  Future<ProfileModel> fetchProfile() => fetchUserDetails();
}