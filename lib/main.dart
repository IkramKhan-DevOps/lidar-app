import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: ModelCraftApp()));
}

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
      home: const LoginScreen(),
      routes: {
        '/home': (_) => HomeScreen(),
      },
    );
  }
}