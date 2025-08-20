import 'package:flutter/material.dart';

class NavigationHelper {
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static void redirectToLogin() {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login_screen', // Your login route
          (route) => false,
    );
  }
}