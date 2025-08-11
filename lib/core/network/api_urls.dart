/// Central place for building API endpoints and handling simple
/// environment switching (dev vs prod).
///
/// HOW TO SWITCH ENV:
///   - Change [AppConfig.env] to AppEnv.dev while developing locally.
///   - For Android emulator with a local Django server use '10.0.2.2:8000'
///     instead of '127.0.0.1:8000'.
///
/// All endpoints intentionally end with a trailing slash (Django REST Framework
/// default). If your backend is configured without APPEND_SLASH, remove them.
enum AppEnv { dev, prod }

class AppConfig {
  static const AppEnv env = AppEnv.prod;

  // Change to 'http' if your local server is not using HTTPS.
  static String get protocol => env == AppEnv.prod ? 'https' : 'http';

  static String get domain {
    switch (env) {
      case AppEnv.dev:
      // Use 10.0.2.2 for Android emulator, 127.0.0.1 for iOS simulator.
        return '127.0.0.1:8000';
      case AppEnv.prod:
        return 'seedswild.com';
    }
  }

  static String get root => '$protocol://$domain/';
  static String get api => '${root}api/';

  // Accounts/Auth bases
  static String get accountsBase => '${api}accounts/';
  static String get authBase => '${accountsBase}auth/';

  // Versioned (if you add more versioned APIs)
  static String get v1 => '${api}v1/';
}

/// Public API URL helper.
///
/// NOTE:
/// - Keep naming consistent: verbs or nouns.
/// - Avoid duplicating the same endpoint under two different names.
/// - If an endpoint changes you only update here.
class APIUrl {
  // Authentication / Registration
  static String get signIn => '${AppConfig.authBase}login/';
  static String get signUp => '${AppConfig.authBase}registration/';
  static String get logout => '${AppConfig.authBase}logout/';

  // User (dj-rest-auth user detail) – GET (read), PUT/PATCH (update)
  // Duplicate old "profile" name removed to avoid confusion.
  static String get userDetails => '${AppConfig.authBase}user/';

  // Password Change (dj-rest-auth)
  // Endpoint you asked to add: https://seedswild.com/api/accounts/auth/password/change/
  static String get passwordChange => '${AppConfig.authBase}password/change/';
  static String get passwordReset => '${AppConfig.authBase}password/reset/';

  // Example v1 feature endpoint(s)
  static String get home => '${AppConfig.v1}home/';

  // Notifications (example)
  static String get notificationsMarkRead =>
      '${AppConfig.v1}notification/mark-all-as-read/';

  /// Utility: build a fully-qualified URL if you only have a relative path.
  /// Example: APIUrl.absolute('accounts/auth/login/') -> https://.../api/accounts/auth/login/
  static String absolute(String relativeWithoutLeadingSlash) {
    if (relativeWithoutLeadingSlash.startsWith('/')) {
      return '${AppConfig.api}${relativeWithoutLeadingSlash.substring(1)}';
    }
    return '${AppConfig.api}$relativeWithoutLeadingSlash';
  }
}