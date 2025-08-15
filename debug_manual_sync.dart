import 'package:flutter/services.dart';

/// Debug script to test manual sync functionality
void main() async {
  print('=== Manual Sync Debug Test ===');
  
  const platform = MethodChannel('com.demo.channel/message');
  
  try {
    print('1. Testing auto-sync status...');
    final autoSyncResult = await platform.invokeMethod('getAutoSyncEnabled');
    print('Auto-sync result: $autoSyncResult');
    
    print('\n2. Getting saved scans...');
    final scansResult = await platform.invokeMethod('getSavedScans');
    print('Scans result: $scansResult');
    
    if (scansResult is Map<String, dynamic> && scansResult['scans'] is List) {
      final scans = scansResult['scans'] as List;
      print('Found ${scans.length} scans:');
      
      int initializedCount = 0;
      for (int i = 0; i < scans.length; i++) {
        final scan = scans[i] as Map<String, dynamic>;
        final status = scan['status'] as String?;
        final folderPath = scan['folderPath'] as String?;
        final isFromAPI = scan['isFromAPI'] as bool? ?? false;
        
        print('  Scan $i: status="$status", isFromAPI=$isFromAPI, path=${folderPath?.substring(folderPath.length - 20)}');
        
        if (status == 'initialized' && !isFromAPI) {
          initializedCount++;
        }
      }
      
      print('\nInitialized scans that need sync: $initializedCount');
    }
    
    print('\n3. Testing manual sync method call...');
    final syncResult = await platform.invokeMethod('syncInitializedScans');
    print('Manual sync result: $syncResult');
    
  } catch (e) {
    print('Error during debug test: $e');
    if (e is PlatformException) {
      print('Platform exception code: ${e.code}');
      print('Platform exception message: ${e.message}');
      print('Platform exception details: ${e.details}');
    }
  }
}
