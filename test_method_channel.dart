import 'package:flutter/services.dart';

void main() async {
  const platform = MethodChannel('com.demo.channel/message');
  
  try {
    print('Testing method channel connectivity...');
    
    // Test getSavedScans method
    final result = await platform.invokeMethod('getSavedScans');
    print('✅ getSavedScans successful: ${result.runtimeType}');
    print('Result keys: ${result?.keys}');
    
    // Test scanning functionality availability
    try {
      await platform.invokeMethod('checkZipFile', {'folderPath': '/test'});
    } catch (e) {
      if (e.toString().contains('INVALID_ARGUMENT')) {
        print('✅ Method channel is responding (expected error for test path)');
      } else {
        print('⚠️ Unexpected error: $e');
      }
    }
    
  } catch (e) {
    print('❌ Method channel error: $e');
    
    if (e.toString().contains('MissingPluginException')) {
      print('\n🔧 Debug steps:');
      print('1. Make sure iOS app is running');
      print('2. Check AppDelegate.swift has method channel setup');  
      print('3. Verify channel name matches: "com.demo.channel/message"');
      print('4. Try hot restart (not hot reload)');
    }
  }
}
