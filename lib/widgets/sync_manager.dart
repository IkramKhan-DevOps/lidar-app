import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../services/sync_service.dart';
import '../settings/providers/global_provider.dart';

/// Widget for managing sync settings and operations
class SyncManager extends ConsumerWidget {
  final SyncManagerView view;
  final VoidCallback? onSyncComplete;
  final Color? iconColor;
  final Color? backgroundColor;

  const SyncManager({
    Key? key,
    this.view = SyncManagerView.fullCard,
    this.onSyncComplete,
    this.iconColor,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    
    switch (view) {
      case SyncManagerView.iconOnly:
        return _buildIconOnly(context, ref, syncState);
      case SyncManagerView.toggle:
        return _buildToggle(context, ref, syncState);
      case SyncManagerView.compactCard:
        return _buildCompactCard(context, ref, syncState);
      case SyncManagerView.fullCard:
        return _buildFullCard(context, ref, syncState);
    }
  }

  Widget _buildIconOnly(BuildContext context, WidgetRef ref, SyncState syncState) {
    return IconButton(
      icon: syncState.isSyncing
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  iconColor ?? Theme.of(context).colorScheme.primary,
                ),
              ),
            )
          : Icon(
              Icons.sync,
              color: iconColor ?? Theme.of(context).colorScheme.primary,
            ),
      tooltip: syncState.isSyncing 
          ? 'Syncing...' 
          : syncState.isAutoSyncEnabled 
            ? 'Auto-sync enabled' 
            : 'Manual Sync',
      onPressed: syncState.isSyncing
          ? null
          : () => _triggerManualSync(context, ref),
    );
  }

  Widget _buildToggle(BuildContext context, WidgetRef ref, SyncState syncState) {
    return SwitchListTile(
      title: const Text('Auto-Sync'),
      subtitle: Text(
        syncState.isAutoSyncEnabled
            ? 'Automatically sync scans when online'
            : 'Manually sync scans',
      ),
      value: syncState.isAutoSyncEnabled,
      onChanged: (enabled) => _toggleAutoSync(context, ref, enabled),
      secondary: Icon(
        syncState.isAutoSyncEnabled ? Icons.sync : Icons.sync_disabled,
        color: iconColor,
      ),
    );
  }

  Widget _buildCompactCard(BuildContext context, WidgetRef ref, SyncState syncState) {
    return Card(
      color: backgroundColor ?? Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sync,
                  color: iconColor ?? Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Sync',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                if (syncState.initializedScansCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${syncState.initializedScansCount}',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (syncState.lastSyncMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                syncState.lastSyncMessage!,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context, WidgetRef ref, SyncState syncState) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.sync,
                color: iconColor ?? Colors.blue,
                size: 22,
              ),
              const SizedBox(width: 12),
              const Text(
                'Sync Management',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (syncState.isSyncing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      iconColor ?? Colors.blue,
                    ),
                  ),
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Status info
          Text(
            syncState.isAutoSyncEnabled
                ? 'Auto-sync is enabled. Scans will be automatically synchronized when you come back online.'
                : 'Auto-sync is disabled. Enable it to synchronized local scans when you come back online.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Sync stats
          if (syncState.initializedScansCount > 0 || syncState.pendingScansCount > 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (syncState.initializedScansCount > 0)
                          Text(
                            '${syncState.initializedScansCount} scans awaiting sync',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (syncState.pendingScansCount > 0)
                          Text(
                            '${syncState.pendingScansCount} scans pending retry',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Controls
          Row(
            children: [
              // Auto-sync toggle
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        syncState.isAutoSyncEnabled ? Icons.sync : Icons.sync_disabled,
                        color: syncState.isAutoSyncEnabled ? Colors.green : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Auto-sync',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: syncState.isAutoSyncEnabled,
                        onChanged: syncState.isSyncing
                            ? null
                            : (enabled) => _toggleAutoSync(context, ref, enabled),
                        activeColor: Colors.green,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Manual sync button
              // ElevatedButton.icon(
              //   onPressed: syncState.isSyncing
              //       ? null
              //       : () => _triggerManualSync(context, ref),
              //   icon: syncState.isSyncing
              //       ? SizedBox(
              //           width: 16,
              //           height: 16,
              //           child: CircularProgressIndicator(
              //             strokeWidth: 2,
              //             valueColor: AlwaysStoppedAnimation<Color>(
              //               Colors.white.withOpacity(0.7),
              //             ),
              //           ),
              //         )
              //       : const Icon(Icons.sync, size: 16),
              //   label: Text(
              //     syncState.isSyncing
              //       ? 'Syncing...'
              //       : 'Manual Sync',
              //     style: const TextStyle(fontSize: 12),
              //   ),
              //   style: ElevatedButton.styleFrom(
              //     backgroundColor: Colors.blue.withOpacity(0.3),
              //     foregroundColor: Colors.white,
              //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              //     shape: RoundedRectangleBorder(
              //       borderRadius: BorderRadius.circular(8),
              //     ),
              //   ),
              // ),
            ],
          ),
          
          // Last sync info
          if (syncState.lastSyncTime != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last sync: ${_formatTime(syncState.lastSyncTime!)}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
              ),
            ),
          ],
          
          // Error messages
          if (syncState.recentErrors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      syncState.recentErrors.first,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref.read(syncProvider.notifier).clearErrors(),
                    icon: const Icon(Icons.close, size: 12, color: Colors.red),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleAutoSync(BuildContext context, WidgetRef ref, bool enabled) async {
    final success = await ref.read(syncProvider.notifier).setAutoSyncEnabled(enabled);
    
    if (context.mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${enabled ? 'enable' : 'disable'} auto-sync'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _triggerManualSync(BuildContext context, WidgetRef ref) async {
    debugPrint('[SYNC_MANAGER] Manual sync button tapped');
    
    // Check sync state
    final syncState = ref.read(syncProvider);
    debugPrint('[SYNC_MANAGER] Current sync state - isSyncing: ${syncState.isSyncing}, initializedScansCount: ${syncState.initializedScansCount}');
    
    if (syncState.isSyncing) {
      debugPrint('[SYNC_MANAGER] Already syncing, ignoring button tap');
      return;
    }
    
    // Check if we're online first
    final networkState = ref.read(networkStateProvider);
    debugPrint('[SYNC_MANAGER] Network state - isOnline: ${networkState.isOnline}');
    
    if (!networkState.isOnline) {
      debugPrint('[SYNC_MANAGER] Not online, showing offline message');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connect to internet for synchronization'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    if (syncState.initializedScansCount == 0) {
      debugPrint('[SYNC_MANAGER] No initialized scans to sync');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No scans available for sync'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      return;
    }
    
    debugPrint('[SYNC_MANAGER] Starting manual sync of ${syncState.initializedScansCount} scans');
    final success = await ref.read(syncProvider.notifier).syncInitializedScans();
    debugPrint('[SYNC_MANAGER] Manual sync completed with success: $success');
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Sync completed successfully' : 'Sync failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      
      if (success) {
        onSyncComplete?.call();
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}

/// Different views for the sync manager widget
enum SyncManagerView {
  iconOnly,
  toggle,
  compactCard,
  fullCard,
}

/// Sync status indicator for individual scans
class ScanSyncStatusIndicator extends StatelessWidget {
  final String status;
  final bool isFromAPI;
  final double size;

  const ScanSyncStatusIndicator({
    Key? key,
    required this.status,
    this.isFromAPI = false,
    this.size = 16,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final syncStatus = ScanSyncStatusExtension.fromString(status);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: syncStatus.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: syncStatus.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFromAPI ? Icons.cloud_done : syncStatus.icon,
            size: size,
            color: syncStatus.color,
          ),
          const SizedBox(width: 4),
          Text(
            isFromAPI ? 'Server' : syncStatus.displayName,
            style: TextStyle(
              color: syncStatus.color,
              fontSize: size * 0.75,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating action button for quick sync access
class SyncFloatingActionButton extends ConsumerWidget {
  const SyncFloatingActionButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncProvider);
    final hasPendingScans = ref.watch(hasPendingSyncsProvider);
    
    if (!hasPendingScans) return const SizedBox.shrink();
    
    return FloatingActionButton(
      onPressed: syncState.isSyncing
          ? null
          : () async {
              // Check if we're online first
              final networkState = ref.read(networkStateProvider);
              
              if (!networkState.isOnline) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Connect to internet for synchronization'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return;
              }
              
              final success = await ref.read(syncProvider.notifier).syncInitializedScans();
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Sync completed' : 'Sync failed'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
      backgroundColor: syncState.isSyncing ? Colors.grey : Colors.orange,
      child: syncState.isSyncing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.cloud_upload),
      tooltip: syncState.isSyncing
          ? 'Syncing...' 
          : '${syncState.initializedScansCount} scans need sync',
    );
  }
}

/// App bar action for sync
class SyncAppBarAction extends ConsumerWidget {
  const SyncAppBarAction({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPendingScans = ref.watch(hasPendingSyncsProvider);
    final totalPending = ref.watch(totalPendingSyncsProvider);
    
    if (!hasPendingScans) return const SizedBox.shrink();
    
    return Stack(
      children: [
        SyncManager(
          view: SyncManagerView.iconOnly,
          iconColor: Colors.white,
        ),
        if (totalPending > 0)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                totalPending > 99 ? '99+' : '$totalPending',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
