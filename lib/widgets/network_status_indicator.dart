import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/providers/global_provider.dart';

/// Network Status Indicator Widget
/// Shows the current online/offline status and sync progress
class NetworkStatusIndicator extends ConsumerWidget {
  const NetworkStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkState = ref.watch(networkStateProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getBackgroundColor(networkState),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getBorderColor(networkState),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusIcon(networkState),
          const SizedBox(width: 6),
          _buildStatusText(networkState),
          if (networkState.isSyncing) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  networkState.isOnline ? Colors.blue : Colors.orange,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(NetworkState state) {
    IconData iconData;
    Color iconColor;

    if (state.isSyncing) {
      iconData = Icons.sync;
      iconColor = state.isOnline ? Colors.blue : Colors.orange;
    } else if (state.isOnline) {
      iconData = Icons.wifi;
      iconColor = Colors.green;
    } else {
      iconData = Icons.wifi_off;
      iconColor = Colors.red;
    }

    return Icon(
      iconData,
      size: 16,
      color: iconColor,
    );
  }

  Widget _buildStatusText(NetworkState state) {
    String text;
    Color textColor;

    if (state.isSyncing) {
      text = 'Syncing...';
      textColor = state.isOnline ? Colors.blue : Colors.orange;
    } else if (state.isOnline) {
      text = 'Online';
      textColor = Colors.green;
    } else {
      text = 'Offline';
      textColor = Colors.red;
    }

    if (state.pendingScansCount > 0 && !state.isSyncing) {
      text += ' (${state.pendingScansCount} pending)';
    }

    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Color _getBackgroundColor(NetworkState state) {
    if (state.isSyncing) {
      return state.isOnline 
        ? Colors.blue.withOpacity(0.1)
        : Colors.orange.withOpacity(0.1);
    } else if (state.isOnline) {
      return Colors.green.withOpacity(0.1);
    } else {
      return Colors.red.withOpacity(0.1);
    }
  }

  Color _getBorderColor(NetworkState state) {
    if (state.isSyncing) {
      return state.isOnline 
        ? Colors.blue.withOpacity(0.3)
        : Colors.orange.withOpacity(0.3);
    } else if (state.isOnline) {
      return Colors.green.withOpacity(0.3);
    } else {
      return Colors.red.withOpacity(0.3);
    }
  }
}

/// Compact version for app bars
class NetworkStatusAppBarIndicator extends ConsumerWidget {
  const NetworkStatusAppBarIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkState = ref.watch(networkStateProvider);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            networkState.isOnline ? Icons.wifi : Icons.wifi_off,
            size: 18,
            color: networkState.isOnline 
              ? (networkState.isSyncing ? Colors.blue : Colors.green)
              : Colors.red,
          ),
          if (networkState.isSyncing)
            Container(
              margin: const EdgeInsets.only(left: 4),
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  networkState.isOnline ? Colors.blue : Colors.orange,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Detailed status card for drawer or settings
class NetworkStatusCard extends ConsumerWidget {
  const NetworkStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkState = ref.watch(networkStateProvider);

    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.grey[850],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  networkState.isOnline ? Icons.wifi : Icons.wifi_off,
                  color: networkState.isOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Network Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                NetworkStatusIndicator(),
              ],
            ),
            if (networkState.lastSyncMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                networkState.lastSyncMessage!,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
            if (networkState.lastSyncTime != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last sync: ${_formatTime(networkState.lastSyncTime!)}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
            ],
            if (networkState.pendingScansCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${networkState.pendingScansCount} scans waiting to sync',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
