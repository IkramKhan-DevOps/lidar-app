import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/configs/app_routes.dart';

class ModelCraftApp extends StatelessWidget {
  static const platform = MethodChannel('com.demo.channel/message');
  const ModelCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ModelCraft',
      theme: ThemeData(
        fontFamily: 'SF Pro',
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.splashScreen, // or AppRoutes.splashScreen
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      onUnknownRoute: AppRoutes.onUnknownRoute,
    );
  }
}

void main() {
  runApp(const ProviderScope(child: ModelCraftApp()));
}