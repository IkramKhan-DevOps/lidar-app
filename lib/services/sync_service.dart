import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service for handling sync operations with the native platform
class SyncService {
  static const MethodChannel _channel = MethodChannel('com.demo.channel/message');
  
  /// Check if auto-sync is enabled
  static Future<bool> getAutoSyncEnabled() async {
    try {
      final result = await _channel.invokeMethod('getAutoSyncEnabled');
      if (result is Map<String, dynamic>) {
        return result['enabled'] ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('Error getting auto-sync status: $e');
      return false;
    }
  }
  
  /// Enable or disable auto-sync
  static Future<bool> setAutoSyncEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setAutoSyncEnabled', {
        'enabled': enabled,
      });
      return true;
    } catch (e) {
      debugPrint('Error setting auto-sync: $e');
      return false;
    }
  }
  
  /// Manually trigger sync of initialized scans
  static Future<SyncResult> syncInitializedScans() async {
    debugPrint('[SYNC_SERVICE] syncInitializedScans() called');
    try {
      debugPrint('[SYNC_SERVICE] Invoking method channel: syncInitializedScans');
      final result = await _channel.invokeMethod('syncInitializedScans');
      debugPrint('[SYNC_SERVICE] Method channel returned: $result');
      return SyncResult.success('Sync completed successfully');
    } catch (e) {
      debugPrint('[SYNC_SERVICE] Error syncing initialized scans: $e');
      if (e is PlatformException) {
        debugPrint('[SYNC_SERVICE] PlatformException - code: ${e.code}, message: ${e.message}, details: ${e.details}');
        return SyncResult.error(e.message ?? 'Sync failed');
      }
      return SyncResult.error('Sync failed: $e');
    }
  }
  
  /// Upload a specific scan to backend
  static Future<SyncResult> uploadScanToBackend(String folderPath) async {
    try {
      await _channel.invokeMethod('uploadScanToBackend', {
        'folderPath': folderPath,
      });
      return SyncResult.success('Scan uploaded successfully');
    } catch (e) {
      debugPrint('Error uploading scan: $e');
      if (e is PlatformException) {
        return SyncResult.error(e.message ?? 'Upload failed');
      }
      return SyncResult.error('Upload failed: $e');
    }
  }
  
  /// Get saved scans from native platform
  static Future<List<Map<String, dynamic>>> getSavedScans() async {
    try {
      final result = await _channel.invokeMethod('getSavedScans');
      if (result is Map<String, dynamic> && result['scans'] is List) {
        return List<Map<String, dynamic>>.from(result['scans']);
      }
      return [];
    } catch (e) {
      debugPrint('Error getting saved scans: $e');
      return [];
    }
  }
  
  /// Listen to native platform notifications about sync events
  static void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    _channel.setMethodCallHandler(handler);
  }
}

/// Result of a sync operation
class SyncResult {
  final bool isSuccess;
  final String message;
  final Map<String, dynamic>? data;
  
  const SyncResult._({
    required this.isSuccess,
    required this.message,
    this.data,
  });
  
  factory SyncResult.success(String message, [Map<String, dynamic>? data]) {
    return SyncResult._(
      isSuccess: true,
      message: message,
      data: data,
    );
  }
  
  factory SyncResult.error(String message, [Map<String, dynamic>? data]) {
    return SyncResult._(
      isSuccess: false,
      message: message,
      data: data,
    );
  }
}

/// Sync status for individual scans
enum ScanSyncStatus {
  initialized,   // Offline scan, needs sync
  pending,      // Online scan, synced to server
  uploading,    // Currently being uploaded
  syncing,      // Being processed on server
  uploaded,     // Successfully uploaded
  failed,       // Upload/sync failed
  completed,    // Fully processed
}

extension ScanSyncStatusExtension on ScanSyncStatus {
  static ScanSyncStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'initialized':
        return ScanSyncStatus.initialized;
      case 'pending':
        return ScanSyncStatus.pending;
      case 'uploading':
        return ScanSyncStatus.uploading;
      case 'syncing':
        return ScanSyncStatus.syncing;
      case 'uploaded':
        return ScanSyncStatus.uploaded;
      case 'failed':
        return ScanSyncStatus.failed;
      case 'completed':
        return ScanSyncStatus.completed;
      default:
        return ScanSyncStatus.pending;
    }
  }
  
  String get displayName {
    switch (this) {
      case ScanSyncStatus.initialized:
        return 'Awaiting Sync';
      case ScanSyncStatus.pending:
        return 'Synced';
      case ScanSyncStatus.uploading:
        return 'Uploading';
      case ScanSyncStatus.syncing:
        return 'Syncing';
      case ScanSyncStatus.uploaded:
        return 'Uploaded';
      case ScanSyncStatus.failed:
        return 'Failed';
      case ScanSyncStatus.completed:
        return 'Completed';
    }
  }
  
  Color get color {
    switch (this) {
      case ScanSyncStatus.initialized:
        return Colors.orange;
      case ScanSyncStatus.pending:
        return Colors.blue;
      case ScanSyncStatus.uploading:
      case ScanSyncStatus.syncing:
        return Colors.amber;
      case ScanSyncStatus.uploaded:
      case ScanSyncStatus.completed:
        return Colors.green;
      case ScanSyncStatus.failed:
        return Colors.red;
    }
  }
  
  IconData get icon {
    switch (this) {
      case ScanSyncStatus.initialized:
        return Icons.cloud_upload_outlined;
      case ScanSyncStatus.pending:
        return Icons.cloud_done_outlined;
      case ScanSyncStatus.uploading:
      case ScanSyncStatus.syncing:
        return Icons.cloud_sync_outlined;
      case ScanSyncStatus.uploaded:
      case ScanSyncStatus.completed:
        return Icons.cloud_done;
      case ScanSyncStatus.failed:
        return Icons.cloud_off_outlined;
    }
  }
  
  bool get needsSync => this == ScanSyncStatus.initialized || this == ScanSyncStatus.failed;
  bool get isInProgress => this == ScanSyncStatus.uploading || this == ScanSyncStatus.syncing;
  bool get isCompleted => this == ScanSyncStatus.uploaded || this == ScanSyncStatus.completed;
}
