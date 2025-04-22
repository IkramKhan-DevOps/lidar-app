import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  static const platform = MethodChannel('com.demo.channel/message');

  Future<String> _getMessage() async {
    try {
      final String result = await platform.invokeMethod('getMessage');
      return result;
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    String display = "Press the button";

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Android + Swift Setup')),
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    child: Text("Get Native Message"),
                    onPressed: () async {
                      String msg = await _getMessage();
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
