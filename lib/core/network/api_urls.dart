// =============================================================
// API CONFIGURATION AND URL BUILDERS
// -------------------------------------------------------------
// Central place for building API endpoints and handling simple
// environment switching (dev vs prod).
//
// WHY CENTRALIZE?
// - Change environments in one place.
// - Avoid scattering string URLs across the codebase.
// - Keep a consistent convention (e.g., trailing slashes for DRF).
//
// HOW TO SWITCH ENV:
// - Change AppConfig.env to AppEnv.dev while developing locally.
// - For Android emulator with a local Django server use '10.0.2.2:8000'
//   instead of '127.0.0.1:8000'.
// - iOS simulator can use '127.0.0.1:8000'.
//
// TRAILING SLASHES:
// - All endpoints intentionally end with a trailing slash (Django REST Framework
//   default). If your backend is configured without APPEND_SLASH, remove them.
// =============================================================

/// Supported application environments.
enum AppEnv { dev, prod }

/// AppConfig encapsulates environment-aware base URLs and common path segments.
///
/// It composes:
/// - protocol (http/https)
/// - domain (host[:port])
/// - root (protocol + domain)
/// - api (root + "api/")
/// - base segments for accounts/auth and versioned API namespaces
class AppConfig {
  // Force local SeedsWild base as requested
  static const AppEnv env = AppEnv.prod;
  static String get protocol => 'http';
  static String get domain => '213.73.97.120';
  static String get root => '$protocol://$domain/';
  static String get api => root;
  static String get v1 => '${root}api/v1/';

  // Force Token scheme for SeedsWild token-based auth
  static String get authHeaderScheme => 'Token';
}

/// APIUrl exposes concrete, ready-to-use endpoint strings.
/// Keep naming consistent and avoid duplicating the same endpoint under
/// different names. If an endpoint changes, update it here.
class APIUrl {
  // SeedsWild authentication endpoints
  static String get signIn => '${AppConfig.root}auth/login/';
  static String get signUp => '${AppConfig.root}auth/registration/';
  static String get logout => '${AppConfig.root}auth/logout/';

  // Profile (your server exposes auth/profile/ → user_retrieve_update)
  static String get userDetails => '${AppConfig.root}auth/profile/';
  static String get passwordChange => '${AppConfig.root}auth/password/change/';
  static String get passwordReset => '${AppConfig.root}auth/password/reset/';
  static String get passwordResetConfirm =>
      '${AppConfig.root}auth/password/reset/confirm/';
  static String get resendEmail =>
      '${AppConfig.root}auth/registration/resend-email/';
  static String get verifyEmail =>
      '${AppConfig.root}auth/registration/verify-email/';

  static String absolute(String relativeWithoutLeadingSlash) {
    if (relativeWithoutLeadingSlash.startsWith('/')) {
      return '${AppConfig.root}${relativeWithoutLeadingSlash.substring(1)}';
    }
    return '${AppConfig.root}$relativeWithoutLeadingSlash';
  }

  // v1 Scans
  static String get scans => '${AppConfig.v1}scans/';
  static String scanById(int id) => '${AppConfig.v1}scans/$id/';
  static String scanDeleteById(int id) => '${AppConfig.v1}scans/$id/';
  static String scanDownloadById(int id) => '${AppConfig.v1}scans/$id/download-zip/';

  static String get scansProcess => '${AppConfig.v1}scans/process/';

  // Nested
  static String scansGpsPoints(int scanId) =>
      '${AppConfig.v1}scans/$scanId/gps-points/';
  static String scansImages(int scanId) =>
      '${AppConfig.v1}scans/$scanId/images/';
  static String scansPointCloud(int scanId) =>
      '${AppConfig.v1}scans/$scanId/point-cloud/';
  static String scansUploadStatus(int scanId) =>
      '${AppConfig.v1}scans/$scanId/upload-status/';

  // Standalone gps-point by id
  static String scanGpsPointById(int id) =>
      '${AppConfig.v1}scan/gps-points/$id/';
}
