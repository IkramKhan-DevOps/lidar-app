import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScanScreen extends StatefulWidget {
  final bool autoStartScan;

  const ScanScreen({super.key, this.autoStartScan = false});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  String display = "Ready to scan your world";
  static const platform = MethodChannel('com.demo.channel/message');

  @override
  void initState() {
    super.initState();
    // Set up method channel listener
    platform.setMethodCallHandler(_handleMethodCall);
    if (widget.autoStartScan) {
      _startScan();
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'closeARModule') {
      setState(() {
        display = "Scan closed. Ready to start a new scan.";
      });
      // Optionally pop the ScanScreen if it's not the root screen
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _startScan() async {
    try {
      final String msg = await platform.invokeMethod('startScan');
      setState(() {
        display = msg;
      });
    } on PlatformException catch (e) {
      setState(() {
        display = "Error starting scan: ${e.message}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
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
          child: widget.autoStartScan
              ? CupertinoActivityIndicator(
            color: CupertinoColors.activeBlue,
            radius: 15,
          )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                display,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _startScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent[700],
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.camera_alt),
                label: const Text("Start 3D Scan"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}