// =============================================================
// PROFILE PROVIDERS (Riverpod)
// Lightweight data access wrapper for Profile API calls.
//
// What this file provides:
// - profileApiServiceProvider: local API service for profile ops
// - profileProvider: exposes a ProfileNotifier (uses injected API)
// - profileNetworkProvider: FutureProvider that loads ProfileModel
// - profileLoadingProvider: simple loading flag controller
//
// Notes:
// - Avoids instantiating NetworkApiService directly inside methods.
// - Keeps business logic minimal and UI-friendly.
// - Errors thrown by API will surface through FutureProvider as AsyncError.
// =============================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_network.dart';
import '../../../core/network/api_network_base.dart';
import '../../../core/network/api_urls.dart';
import '../../models/profile_model.dart';

// Local API service provider (scoped to this feature). If you already
// have a global API service provider, you can replace this with that.
final profileApiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

// Exposes the notifier that performs profile API calls.
final profileProvider = Provider<ProfileNotifier>((ref) {
  final api = ref.watch(profileApiServiceProvider);
  return ProfileNotifier(api);
});

// Fetches the current profile via ProfileNotifier.getProfile().
// UI can watch this to get AsyncValue<ProfileModel>.
final profileNetworkProvider = FutureProvider<ProfileModel>((ref) async {
  final user = ref.watch(profileProvider);
  return user.getProfile();
});

// Simple loading state controller if the UI needs an explicit flag.
class ProfileLoadingNotifier extends StateNotifier<bool> {
  ProfileLoadingNotifier() : super(false);
  void setLoading(bool isLoading) => state = isLoading;
}

// Create a provider for the loading state.
final profileLoadingProvider =
StateNotifierProvider<ProfileLoadingNotifier, bool>((ref) {
  return ProfileLoadingNotifier();
});

// =============================================================
// Notifier for Profile API calls
// =============================================================
class ProfileNotifier {
  final BaseApiService _api;
  ProfileNotifier(this._api);

  // Get the current user's profile.
  Future<ProfileModel> getProfile() async {
    final response = await _api.getAPI(APIUrl.userDetails, true);
    return ProfileModel.fromJson(response);
  }

  // Update profile with the provided map of fields.
  // Keep signature as void to match existing usage; throws on error.
  Future<void> updateProfile(Map<String, dynamic> updatedData) async {
    await _api.putAPI(APIUrl.userDetails, updatedData);
  }
}