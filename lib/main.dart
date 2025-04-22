import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
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
    String display = "Tap to start scan";

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Flutter + Swift ARKit')),
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    child: Text("Start 3D Scan"),
                    onPressed: () async {
                      String msg = await _startScan();
                      setState(() => display = msg);
                    },
                  ),
                  SizedBox(height: 20),
                  Text(display),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
