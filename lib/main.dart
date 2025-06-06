import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(ModelCraftApp());
}

class ModelCraftApp extends StatelessWidget {
  static const platform = MethodChannel('com.demo.channel/message');

  Future<String> _startScan() async {
    try {
      final String result = await platform.invokeMethod('startScan');
      return result;
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    String display = "Ready to scan your world";

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ModelCraft',
      theme: ThemeData(
        fontFamily: 'SF Pro',
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth > 600;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "ModelCraft",
                        style: TextStyle(
                          fontSize: isTablet ? 48 : 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        display,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet ? 22 : 16,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 40),
                      ElevatedButton.icon(
                        onPressed: () async {
                          String msg = await _startScan();
                          display = msg;
                          (context as Element).markNeedsBuild(); // Rebuild
                        },
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 40 : 24,
                            vertical: isTablet ? 20 : 14,
                          ),
                          backgroundColor: Colors.tealAccent[700],
                          foregroundColor: Colors.black,
                          textStyle: TextStyle(
                            fontSize: isTablet ? 20 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("Start 3D Scan"),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
