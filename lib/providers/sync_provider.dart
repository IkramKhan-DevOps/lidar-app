import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/sync_service.dart';
import '../settings/providers/global_provider.dart';

/// State for sync management
class SyncState {
  final bool isAutoSyncEnabled;
  final bool isSyncing;
  final String? lastSyncMessage;
  final DateTime? lastSyncTime;
  final int pendingScansCount;
  final int initializedScansCount;
  final List<String> recentErrors;

  const SyncState({
    this.isAutoSyncEnabled = false,
    this.isSyncing = false,
    this.lastSyncMessage,
    this.lastSyncTime,
    this.pendingScansCount = 0,
    this.initializedScansCount = 0,
    this.recentErrors = const [],
  });

  SyncState copyWith({
    bool? isAutoSyncEnabled,
    bool? isSyncing,
    String? lastSyncMessage,
    DateTime? lastSyncTime,
    int? pendingScansCount,
    int? initializedScansCount,
    List<String>? recentErrors,
  }) {
    return SyncState(
      isAutoSyncEnabled: isAutoSyncEnabled ?? this.isAutoSyncEnabled,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncMessage: lastSyncMessage,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingScansCount: pendingScansCount ?? this.pendingScansCount,
      initializedScansCount: initializedScansCount ?? this.initializedScansCount,
      recentErrors: recentErrors ?? this.recentErrors,
    );
  }
}

/// Notifier for managing sync state and operations
class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier(this._ref) : super(const SyncState()) {
    _initialize();
    _setupNativeMethodHandler();
  }

  final Ref _ref;

  /// Initialize sync state from native platform
  Future<void> _initialize() async {
    try {
      final isEnabled = await SyncService.getAutoSyncEnabled();
      state = state.copyWith(isAutoSyncEnabled: isEnabled);
      
      // Update scan counts
      await _updateScanCounts();
    } catch (e) {
      _addError('Failed to initialize sync state: $e');
    }
  }

  /// Set up handler for native method calls
  void _setupNativeMethodHandler() {
    SyncService.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'networkStatusChanged':
          final args = call.arguments as Map<String, dynamic>;
          final isOnline = args['isOnline'] as bool;
          // Use the native update method to distinguish from Flutter connectivity
          _ref.read(networkStateProvider.notifier).updateNetworkStatusFromNative(isOnline);
          break;
          
        case 'scanComplete':
          // Refresh scan counts when new scan completes
          await _updateScanCounts();
          break;
          
        case 'scanUploadComplete':
          final args = call.arguments as Map<String, dynamic>;
          final success = args['success'] as bool;
          final folderPath = args['folderPath'] as String?;
          
          if (success) {
            state = state.copyWith(
              lastSyncMessage: 'Scan uploaded successfully',
              lastSyncTime: DateTime.now(),
            );
          } else {
            _addError('Failed to upload scan: $folderPath');
          }
          await _updateScanCounts();
          break;
          
        case 'offlineSyncComplete':
          final args = call.arguments as Map<String, dynamic>;
          final success = args['success'] as bool;
          
          state = state.copyWith(
            isSyncing: false,
            lastSyncMessage: success 
              ? 'Offline sync completed successfully'
              : 'Some scans failed to sync',
            lastSyncTime: DateTime.now(),
          );
          
          _ref.read(networkStateProvider.notifier).setSyncComplete(
            success, 
            message: state.lastSyncMessage,
          );
          
          await _updateScanCounts();
          break;
          
        case 'initializedSyncComplete':
          final args = call.arguments as Map<String, dynamic>;
          final success = args['success'] as bool;
          final successCount = args['successCount'] as int? ?? 0;
          final failedCount = args['failedCount'] as int? ?? 0;
          
          state = state.copyWith(
            isSyncing: false,
            lastSyncMessage: success 
              ? 'Auto-sync completed: $successCount synced'
              : 'Auto-sync completed: $successCount synced, $failedCount failed',
            lastSyncTime: DateTime.now(),
          );
          
          await _updateScanCounts();
          break;
          
          
        case 'testConnectivity':
          // Platform is testing method channel connectivity
          return {'status': 'ok', 'timestamp': DateTime.now().millisecondsSinceEpoch};
      }
    });
  }

  /// Update scan counts from native platform
  Future<void> _updateScanCounts() async {
    try {
      final scans = await SyncService.getSavedScans();
      
      int pendingCount = 0;
      int initializedCount = 0;
      
      for (final scan in scans) {
        final status = scan['status'] as String?;
        final originalStatus = scan['originalStatus'] as String?;
        
        // Use original status if available, otherwise use display status
        final actualStatus = originalStatus ?? status ?? 'pending';
        
        if (actualStatus == 'initialized') {
          initializedCount++;
        } else if (actualStatus == 'pending' || actualStatus == 'failed') {
          pendingCount++;
        }
      }
      
      state = state.copyWith(
        pendingScansCount: pendingCount,
        initializedScansCount: initializedCount,
      );
      
      // Update network state provider as well
      _ref.read(networkStateProvider.notifier).updateSyncStatus(
        state.isSyncing,
        pendingCount: pendingCount + initializedCount,
      );
    } catch (e) {
      _addError('Failed to update scan counts: $e');
    }
  }

  /// Toggle auto-sync setting
  Future<bool> setAutoSyncEnabled(bool enabled) async {
    try {
      final success = await SyncService.setAutoSyncEnabled(enabled);
      if (success) {
        state = state.copyWith(
          isAutoSyncEnabled: enabled,
          lastSyncMessage: enabled 
            ? 'Auto-sync enabled' 
            : 'Auto-sync disabled',
          lastSyncTime: DateTime.now(),
        );
        return true;
      }
      return false;
    } catch (e) {
      _addError('Failed to set auto-sync: $e');
      return false;
    }
  }

  /// Manually trigger sync of initialized scans
  Future<bool> syncInitializedScans() async {
    debugPrint('[SYNC_PROVIDER] syncInitializedScans() called');
    debugPrint('[SYNC_PROVIDER] Current state - isSyncing: ${state.isSyncing}, initializedScansCount: ${state.initializedScansCount}');
    
    if (state.isSyncing) {
      debugPrint('[SYNC_PROVIDER] Already syncing, returning false');
      return false;
    }
    
    try {
      debugPrint('[SYNC_PROVIDER] Setting sync state to true');
      state = state.copyWith(
        isSyncing: true,
        lastSyncMessage: 'Starting manual sync...',
      );
      
      _ref.read(networkStateProvider.notifier).updateSyncStatus(
        true,
        message: 'Syncing initialized scans...',
      );
      
      debugPrint('[SYNC_PROVIDER] Calling SyncService.syncInitializedScans()');
      final result = await SyncService.syncInitializedScans();
      debugPrint('[SYNC_PROVIDER] SyncService.syncInitializedScans() returned: ${result.isSuccess}, message: ${result.message}');
      
      state = state.copyWith(
        isSyncing: false,
        lastSyncMessage: result.message,
        lastSyncTime: DateTime.now(),
      );
      
      _ref.read(networkStateProvider.notifier).setSyncComplete(
        result.isSuccess,
        message: result.message,
      );
      
      if (!result.isSuccess) {
        _addError(result.message);
      }
      
      debugPrint('[SYNC_PROVIDER] Updating scan counts after sync');
      await _updateScanCounts();
      debugPrint('[SYNC_PROVIDER] syncInitializedScans() completed with result: ${result.isSuccess}');
      return result.isSuccess;
    } catch (e) {
      debugPrint('[SYNC_PROVIDER] syncInitializedScans() caught exception: $e');
      state = state.copyWith(
        isSyncing: false,
        lastSyncMessage: 'Sync failed: $e',
        lastSyncTime: DateTime.now(),
      );
      
      _ref.read(networkStateProvider.notifier).setSyncComplete(
        false,
        message: 'Sync failed',
      );
      
      _addError('Manual sync failed: $e');
      return false;
    }
  }

  /// Upload a specific scan to backend
  Future<bool> uploadScan(String folderPath) async {
    try {
      final result = await SyncService.uploadScanToBackend(folderPath);
      
      if (result.isSuccess) {
        state = state.copyWith(
          lastSyncMessage: result.message,
          lastSyncTime: DateTime.now(),
        );
      } else {
        _addError(result.message);
      }
      
      await _updateScanCounts();
      return result.isSuccess;
    } catch (e) {
      _addError('Failed to upload scan: $e');
      return false;
    }
  }

  /// Refresh sync state and scan counts
  Future<void> refresh() async {
    await _updateScanCounts();
  }

  /// Clear recent errors
  void clearErrors() {
    state = state.copyWith(recentErrors: []);
  }

  /// Add an error to the recent errors list
  void _addError(String error) {
    final errors = List<String>.from(state.recentErrors);
    errors.insert(0, error);
    
    // Keep only the last 5 errors
    if (errors.length > 5) {
      errors.removeRange(5, errors.length);
    }
    
    state = state.copyWith(recentErrors: errors);
  }
}

/// Provider for sync state management
final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(ref);
});

/// Convenience provider for checking if there are scans that need sync
final hasPendingSyncsProvider = Provider<bool>((ref) {
  final syncState = ref.watch(syncProvider);
  return syncState.initializedScansCount > 0 || syncState.pendingScansCount > 0;
});

/// Convenience provider for total scans needing attention
final totalPendingSyncsProvider = Provider<int>((ref) {
  final syncState = ref.watch(syncProvider);
  return syncState.initializedScansCount + syncState.pendingScansCount;
});
