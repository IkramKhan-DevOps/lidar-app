import 'package:flutter/material.dart';

import '../../screens/auth/password_change_screen.dart';
import '../../screens/auth/splash_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/auth/signup_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/profile_screen.dart';

import '../../screens/settings_screen.dart';

class AppRoutes {
  // Route names
  static const String splashScreen = '/splash_screen';
  static const String loginScreen = '/login_screen';
  static const String signupScreen = '/signup_screen';
  static const String homeScreen = '/home_screen';
  static const String settingsScreen = '/settings_screen';
  static const String profileChangeScreen = '/profile_change_screen';
  static const String passwordChangeScreen = '/password_change_screen';



  // Central map
  static final Map<String, WidgetBuilder> routes = {
    splashScreen: (_) => const SplashScreen(),
    passwordChangeScreen: (_) =>  PasswordChangeScreen(),
    loginScreen: (_) => const LoginScreen(),
    signupScreen: (_) => const SignupScreen(),
    homeScreen: (_) => HomeScreen(),
    settingsScreen: (_) => const SettingsScreen(),
    profileChangeScreen: (_) => const ProfileEditScreen(),
  };

  // Optional: catch unknown routes
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    return null; // use if you add dynamic argument routes later
  }

  static Route<dynamic> onUnknownRoute(RouteSettings settings) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Route not found')),
        body: Center(child: Text('Unknown route: ${settings.name}')),
      ),
    );
  }
}