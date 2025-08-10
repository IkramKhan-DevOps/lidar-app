/// Central place for building API endpoints.
/// Supports simple environment switching (dev vs prod).
///
/// Adjust [AppConfig.env] to switch between seedswild.com (prod)
/// and 127.0.0.1:8000 (dev). For Android emulator + local server,
/// you may need 10.0.2.2:8000 instead of 127.0.0.1.
enum AppEnv { dev, prod }

class AppConfig {
  static const AppEnv env = AppEnv.prod;

  static String get protocol => 'https';

  static String get domain {
    switch (env) {
      case AppEnv.dev:
        return '127.0.0.1:8000'; // or '10.0.2.2:8000' for Android emulator
      case AppEnv.prod:
        return 'seedswild.com';
    }
  }

  static String get root => '$protocol://$domain/';
  static String get api => '${root}api/';
  static String get v1 => '${api}v1/';
  static String get accountsBase => '${api}accounts/';
  static String get authBase => '${accountsBase}auth/';
}

/// Public API URL helper.
///
/// NOTE: All endpoints include trailing slashes to match typical DRF style.
/// If your backend rejects trailing slashes, remove them.
class APIUrl {
  // AUTH (Accounts/Auth)
  static String get signIn => '${AppConfig.authBase}login/';
  static String get signUp => '${AppConfig.authBase}registration/';
  static String get logout => '${AppConfig.authBase}logout/';
  static String get profile => '${AppConfig.authBase}profile/';
  static String get passwordChange => '${AppConfig.authBase}password/change/';

  // SOCIAL / OAUTH (if implemented)
  static String get signInGoogle => '${AppConfig.authBase}google/';
  static String get signInApple => '${AppConfig.authBase}apple/';

  // V1 Feature Endpoints
  static String get home => '${AppConfig.v1}home/';
  static String get favorite => '${AppConfig.v1}favorite/';
  static String get favoriteAdd => favorite;
  static String favouriteDelete(String id) => '${AppConfig.v1}favorite/$id/delete/';
  static String productDetail(String id) => '${AppConfig.v1}product/$id/';

  static String subscriptionSync(String id) => '${AppConfig.v1}subscription/$id/sync/';

  // Notifications
  static String get notifications => '${AppConfig.api}v1/notification/';
  static String get notificationsMarkRead => '${AppConfig.api}v1/notification/mark-all-as-read/';

  // Hand Scan (LIST / DETAIL / RECOMMENDATIONS)
  static String get handScan => '${AppConfig.v1}hand-scan/';
  static String handScanDetail(String id) => '${AppConfig.v1}hand-scan/$id/';
  static String handScanRecommendations(String id) =>
      '${AppConfig.v1}hand-scan/$id/recommendations/';

  // FCM (Future use)
  static String get fcm => '${AppConfig.root}fcm/';
  static String get deviceRegister => '${fcm}api/device/register';
  static String get deviceRegisterOrUpdate => '${fcm}api/device/register-or-change/';

  // Newsletter / Products
  static String get newsLetterSubscribe => '${AppConfig.v1}newsletter/subscribe/';
  static String productsHome(String manufacturerQuery) =>
      '${AppConfig.v1}product-home/?manufacturer=$manufacturerQuery';
  static String productsHomeV2(String manufacturerQuery) =>
      '${AppConfig.v1}product-home-v2/?manufacturer=$manufacturerQuery';
}

class APIWebUrl {
  static String get protocol => AppConfig.protocol;
  static String get domain => AppConfig.domain;
  static String get base => '$protocol://$domain/';

  static String get termsAndConditions => '${base}terms-and-conditions/';
  static String get privacyPolicy => '${base}privacy-policy/';
  static String get contactUs => '${base}contact-us/';
  static String get resetPassword => '${base}accounts/password/reset/';
}