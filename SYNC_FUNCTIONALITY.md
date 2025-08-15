# Sync Functionality Documentation

This document describes the comprehensive sync functionality implemented for the Flutter app to work with the iOS native platform.

## Overview

The sync functionality provides seamless data synchronization between the Flutter UI and iOS native scan management, supporting both online and offline scenarios.

## Architecture

### Components

1. **SyncService** (`lib/services/sync_service.dart`)
   - Platform communication service
   - Method channel bridge to iOS
   - Sync operation handling

2. **SyncProvider** (`lib/providers/sync_provider.dart`)
   - Riverpod state management
   - Sync state tracking
   - Native method call handling

3. **SyncManager Widget** (`lib/widgets/sync_manager.dart`)
   - UI components for sync controls
   - Different view modes (icon, toggle, card)
   - Manual sync triggers

4. **Network Status Indicators** (`lib/widgets/network_status_indicator.dart`)
   - Real-time network status display
   - Sync progress indicators
   - Status badges and notifications

## Key Features

### 1. Auto-Sync Management
- **Toggle Setting**: Users can enable/disable auto-sync
- **Online Detection**: Automatically syncs when coming back online
- **Initialized Scans**: Auto-sync only processes scans with "initialized" status

### 2. Manual Sync
- **Sync Button**: Manual trigger for immediate sync
- **Progress Indicators**: Real-time sync progress display
- **Error Handling**: Graceful error handling with user feedback

### 3. Status Tracking
- **Scan Statuses**:
  - `initialized`: Offline scan awaiting sync
  - `pending`: Online scan synced to server
  - `uploading`: Currently being uploaded
  - `syncing`: Being processed on server
  - `uploaded`: Successfully uploaded
  - `failed`: Upload/sync failed
  - `completed`: Fully processed

### 4. Network Awareness
- **Online/Offline Detection**: Real-time network status monitoring
- **Offline Storage**: Scans stored locally when offline
- **Automatic Sync**: Triggered when connectivity returns

## Platform Integration

### iOS Native Methods
- `getAutoSyncEnabled`: Check auto-sync setting
- `setAutoSyncEnabled`: Toggle auto-sync on/off
- `syncInitializedScans`: Manually sync pending scans
- `uploadScanToBackend`: Upload specific scan
- `getSavedScans`: Fetch all scans with status

### Method Call Handlers
The app listens for native platform notifications:
- `networkStatusChanged`: Network connectivity changes
- `scanComplete`: New scan completed
- `scanUploadComplete`: Scan upload finished
- `offlineSyncComplete`: Batch sync completed
- `initializedSyncComplete`: Auto-sync completed

## Usage

### Settings Screen Integration
```dart
// Add sync management to settings
SyncManager(
  view: SyncManagerView.fullCard,
  backgroundColor: Colors.blue.withOpacity(0.08),
  iconColor: Colors.blue,
  onSyncComplete: () {
    // Handle sync completion
  },
),
```

### App Bar Integration
```dart
// Add sync status to app bar
const SyncAppBarAction(),
```

### Network Status Display
```dart
// Show network status indicator
const NetworkStatusAppBarIndicator(),
```

## Sync Flow

### Online Scan Completion
1. User completes scan while online
2. iOS immediately uploads to server
3. Local status set to `"pending"` (synced)
4. UI shows "Synced" status

### Offline Scan Completion
1. User completes scan while offline
2. iOS saves locally only
3. Local status set to `"initialized"` (awaiting sync)
4. UI shows "Awaiting Sync" status

### Coming Back Online
1. Network connectivity detected
2. iOS automatically syncs pending/failed scans
3. Auto-sync processes initialized scans (if enabled)
4. UI updates with new statuses

### Manual Sync
1. User taps sync button
2. Flutter calls `syncInitializedScans`
3. iOS processes all initialized scans
4. UI shows progress and completion

## Error Handling

### Network Errors
- Failed uploads marked as `"failed"`
- Retry on next connectivity
- User feedback via snackbars

### Sync Errors
- Error messages displayed in sync UI
- Recent errors tracked (last 5)
- Clear errors functionality

### Platform Communication Errors
- Graceful degradation
- Debug logging
- Fallback behaviors

## Status Indicators

### Scan Status Colors
- **Orange**: Awaiting sync (`initialized`)
- **Blue**: Synced (`pending`)
- **Amber**: In progress (`uploading`, `syncing`)
- **Green**: Completed (`uploaded`, `completed`)
- **Red**: Failed (`failed`)

### Network Status
- **Green**: Online and synced
- **Blue**: Online and syncing
- **Orange**: Offline with pending scans
- **Red**: Offline

## Configuration

### Auto-Sync Settings
- Stored in iOS UserDefaults
- Persisted across app launches
- Can be toggled from settings screen

### Sync Timing
- Auto-sync: Triggered on connectivity return
- Manual sync: Immediate on user action
- Background sync: 30-second refresh timer

## Best Practices

### For Users
1. **Enable Auto-Sync**: For seamless experience
2. **Monitor Status**: Check sync indicators regularly
3. **Manual Sync**: Use when needed for immediate upload
4. **Network Awareness**: Understand online/offline behavior

### For Developers
1. **State Management**: Use Riverpod providers consistently
2. **Error Handling**: Implement comprehensive error catching
3. **User Feedback**: Provide clear status indicators
4. **Testing**: Test both online and offline scenarios

## Troubleshooting

### Common Issues
1. **Scans Not Syncing**: Check auto-sync setting and network
2. **Status Not Updating**: Refresh or restart app
3. **Upload Failures**: Check server connectivity and auth

### Debug Information
- Enable debug logging in sync service
- Check iOS console for native logs
- Monitor network status changes
- Track method call handlers

## Future Enhancements

### Planned Features
1. **Batch Sync Progress**: Individual scan progress tracking
2. **Sync Schedule**: Configurable sync intervals
3. **Conflict Resolution**: Handle server/local conflicts
4. **Sync History**: Detailed sync operation logs

### Performance Optimizations
1. **Incremental Sync**: Only sync changed data
2. **Compression**: Reduce upload data size
3. **Background Sync**: iOS background app refresh
4. **Retry Logic**: Exponential backoff for failures

## API Reference

### SyncService Methods
```dart
// Check auto-sync status
static Future<bool> getAutoSyncEnabled()

// Toggle auto-sync
static Future<bool> setAutoSyncEnabled(bool enabled)

// Manual sync trigger
static Future<SyncResult> syncInitializedScans()

// Upload specific scan
static Future<SyncResult> uploadScanToBackend(String folderPath)

// Get all scans
static Future<List<Map<String, dynamic>>> getSavedScans()
```

### SyncProvider State
```dart
class SyncState {
  final bool isAutoSyncEnabled;
  final bool isSyncing;
  final String? lastSyncMessage;
  final DateTime? lastSyncTime;
  final int pendingScansCount;
  final int initializedScansCount;
  final List<String> recentErrors;
}
```

### Widget Components
- `SyncManager`: Main sync control widget
- `SyncAppBarAction`: App bar sync button
- `ScanSyncStatusIndicator`: Individual scan status
- `SyncFloatingActionButton`: Quick sync access
- `NetworkStatusIndicator`: Network status display

This sync functionality provides a robust, user-friendly synchronization system that handles both online and offline scenarios gracefully while maintaining data integrity and providing clear user feedback.
