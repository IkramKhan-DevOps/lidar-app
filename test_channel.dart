import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TestScreen(),
    );
  }
}

class TestScreen extends StatefulWidget {
  @override
  _TestScreenState createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  static const platform = MethodChannel('com.demo.channel/message');
  String result = 'Not tested yet';

  Future<void> testGetSavedScans() async {
    try {
      print('🔍 Calling getSavedScans method...');
      final response = await platform.invokeMethod('getSavedScans');
      print('✅ Method channel response: $response');
      setState(() {
        result = 'Success: ${response.toString()}';
      });
    } on PlatformException catch (e) {
      print('❌ Platform Exception: ${e.code} - ${e.message}');
      setState(() {
        result = 'Platform Exception: ${e.code} - ${e.message}';
      });
    } catch (e) {
      print('❌ General Exception: $e');
      setState(() {
        result = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Method Channel Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Result:'),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(16),
              child: Text(
                result,
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: testGetSavedScans,
              child: Text('Test getSavedScans'),
            ),
          ],
        ),
      ),
    );
  }
}
