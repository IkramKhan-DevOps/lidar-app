import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:platform_channel_swift_demo/screens/home_screen.dart';

void main() {
  runApp(const ModelCraftApp());
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
      home: const HomeScreen(),
    );
  }
}