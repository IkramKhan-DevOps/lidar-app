// =============================================================
// APP ENTRYPOINT (Flutter + Riverpod)
// Hosts ProviderScope and configures the root MaterialApp.
// Centralizes routing via AppRoutes and sets global theming.
// =============================================================
//
// WHAT THIS FILE DOES
// - Wraps the app with Riverpod's ProviderScope for DI/state.
// - Configures MaterialApp (title, theme, routing, fallbacks).
// - Exposes a MethodChannel for platform-specific calls.
// - Sets the initial route to AppRoutes.splashScreen.
//
// USAGE
// - Navigate by name:
//     Navigator.of(context).pushNamed(AppRoutes.home);
// - Generate routes dynamically via AppRoutes.onGenerateRoute.
// - Handle unknown routes in AppRoutes.onUnknownRoute for safety.
// - Read Riverpod providers anywhere below ProviderScope:
//     final value = ref.watch(someProvider);
//
// LAYERS
// - AppRoutes: central route table + onGenerateRoute + onUnknownRoute.
// - ThemeData: M3 dark theme with custom font (SF Pro).
// - MethodChannel: bridge to native iOS/Android code if needed.
//
// NOTES
// - Keep SnackBar/Toast logic within screens; this file stays minimal.
// - The MethodChannel is defined but not invoked here; call like:
//     await ModelCraftApp.platform.invokeMethod('someNativeMethod', args);
// - For tests, wrap the widget under test with ProviderScope:
//     await tester.pumpWidget(const ProviderScope(child: ModelCraftApp()));
// =============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/configs/app_routes.dart';
import 'core/utils/navigation_helper.dart';

class ModelCraftApp extends StatelessWidget {
  static const platform = MethodChannel('com.demo.channel/message');
  const ModelCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationHelper.navigatorKey, // ← Use the global key
      debugShowCheckedModeBanner: false,
      title: 'ModelCraft',
      theme: ThemeData(
        fontFamily: 'SF Pro',
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.splashScreen,
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      onUnknownRoute: AppRoutes.onUnknownRoute,
    );
  }
}

void main() {
  runApp(const ProviderScope(child: ModelCraftApp()));
}