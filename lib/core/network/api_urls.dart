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
  /// Current environment target.
  static const AppEnv env = AppEnv.prod;

  /// URL scheme. Defaults to https in prod and http in dev.
  /// Change to 'http' if your local server is not using HTTPS.
  static String get protocol => env == AppEnv.prod ? 'https' : 'http';

  /// Host (and optional port) for the current environment.
  /// - Android emulator tip: use 10.0.2.2:8000 to reach the host machine.
  /// - iOS simulator tip: use 127.0.0.1:8000.
  static String get domain {
    switch (env) {
      case AppEnv.dev:
        return '127.0.0.1:8000';
      case AppEnv.prod:
        return 'seedswild.com';
    }
  }

  /// Root URL (e.g., https://seedswild.com/).
  static String get root => '$protocol://$domain/';

  /// API root (e.g., https://seedswild.com/api/).
  static String get api => '${root}api/';

  // -----------------------------------------------------------
  // Namespaced bases (compose specific endpoint groups below)
  // -----------------------------------------------------------

  /// Base for account-related APIs (e.g., https://.../api/accounts/).
  static String get accountsBase => '${api}accounts/';

  /// Base for auth-related APIs under accounts (e.g., https://.../api/accounts/auth/).
  static String get authBase => '${accountsBase}auth/';

  /// Versioned API base (e.g., https://.../api/v1/).
  static String get v1 => '${api}v1/';
}

/// APIUrl exposes concrete, ready-to-use endpoint strings.
/// Keep naming consistent and avoid duplicating the same endpoint under
/// different names. If an endpoint changes, update it here.
class APIUrl {
  // -----------------------------------------------------------
  // Authentication / Registration (dj-rest-auth)
  // -----------------------------------------------------------

  /// Sign in: POST credentials.
  static String get signIn => '${AppConfig.authBase}login/';

  /// Sign up: POST new user registration data.
  static String get signUp => '${AppConfig.authBase}registration/';

  /// Logout: POST to invalidate token/session.
  static String get logout => '${AppConfig.authBase}logout/';

  // -----------------------------------------------------------
  // User profile/info (dj-rest-auth user endpoint)
  // -----------------------------------------------------------

  /// Authenticated user's details: GET (read), PUT/PATCH (update).
  static String get userDetails => '${AppConfig.authBase}user/';

  // -----------------------------------------------------------
  // Password management (dj-rest-auth)
  // -----------------------------------------------------------

  /// Change password (authenticated): POST old_password/new_passwords.
  /// Example: https://seedswild.com/api/accounts/auth/password/change/
  static String get passwordChange => '${AppConfig.authBase}password/change/';

  /// Request password reset email (anonymous): POST email.
  static String get passwordReset => '${AppConfig.authBase}password/reset/';

  // -----------------------------------------------------------
  // Example feature endpoints (versioned API)
  // -----------------------------------------------------------

  /// Example home feed or landing data (versioned).
  static String get home => '${AppConfig.v1}home/';

  /// Mark all notifications as read (example).
  static String get notificationsMarkRead =>
      '${AppConfig.v1}notification/mark-all-as-read/';

  // -----------------------------------------------------------
  // Utilities
  // -----------------------------------------------------------

  /// Build a fully-qualified API URL from a relative path (without leading slash).
  ///
  /// Example:
  ///   APIUrl.absolute('accounts/auth/login/')
  ///   -> https://<domain>/api/accounts/auth/login/
  ///
  /// If the input starts with '/', it will be normalized to avoid '//' in the URL.
  static String absolute(String relativeWithoutLeadingSlash) {
    if (relativeWithoutLeadingSlash.startsWith('/')) {
      return '${AppConfig.api}${relativeWithoutLeadingSlash.substring(1)}';
    }
    return '${AppConfig.api}$relativeWithoutLeadingSlash';
  }
}