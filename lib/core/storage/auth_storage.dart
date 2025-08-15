// =============================================================
// AUTH TOKEN STORAGE (SharedPreferences)
// -------------------------------------------------------------
// Purpose:
// - Save, read, and remove the authentication token on the device.
// - This keeps the user logged in between app launches.
//
// Important:
// - SharedPreferences stores data in plain text on the device.
// - For higher security (e.g., access tokens), consider using
//   flutter_secure_storage or platform-specific secure storage.
// =============================================================

import 'package:shared_preferences/shared_preferences.dart';

class AuthToken {
  // Key used to store the token in SharedPreferences.
  static const _tokenKey = 'auth_token';

  // -----------------------------------------------------------
  // saveToken
  // Saves the token string to local storage.
  //
  // Usage:
  //   await AuthToken.saveToken(tokenFromServer);
  // -----------------------------------------------------------
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // -----------------------------------------------------------
  // getToken
  // Reads the token from local storage.
  //
  // Returns:
  //   - String? token if it exists
  //   - null if no token is stored
  //
  // Usage:
  //   final token = await AuthToken.getToken();
  //   if (token != null) { /* user is logged in */ }
  // -----------------------------------------------------------
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // -----------------------------------------------------------
  // removeToken
  // Deletes the stored token (e.g., on logout).
  //
  // Usage:
  //   await AuthToken.removeToken();
  // -----------------------------------------------------------
  static Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}