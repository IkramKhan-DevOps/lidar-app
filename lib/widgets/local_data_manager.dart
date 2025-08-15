import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum LocalDataManagerView {
  iconOnly,
  iconWithText,
  fullButton
}

class LocalDataManager extends StatelessWidget {
  final LocalDataManagerView view;
  final VoidCallback? onDataCleared;
  final Color? iconColor;
  final Color? backgroundColor;
  final double? iconSize;

  const LocalDataManager({
    Key? key,
    this.view = LocalDataManagerView.iconOnly,
    this.onDataCleared,
    this.iconColor,
    this.backgroundColor,
    this.iconSize = 24.0,
  }) : super(key: key);

  static const MethodChannel _channel = MethodChannel('com.demo.channel/message');

  Future<void> _clearLocalData(BuildContext context) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Clear All Local Data'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete all locally stored scans from your device.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 12),
              Text(
                '• Uploaded scans will remain safe on the server',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Text(
                '• Pending scans will be lost forever',
                style: TextStyle(fontSize: 14, color: Colors.red),
              ),
              Text(
                '• This action cannot be undone',
                style: TextStyle(fontSize: 14, color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear All Data'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Clearing local data...')),
              ],
            ),
          );
        },
      );

      final result = await _channel.invokeMethod('clearAllLocalData');
      
      // Close loading dialog
      Navigator.of(context).pop();

      if (result != null && result is Map<String, dynamic>) {
        final success = result['success'] ?? false;
        final deletedCount = result['deleted_count'] ?? 0;
        final failedCount = result['failed_count'] ?? 0;
        final message = result['message'] ?? 'Operation completed';

        if (success) {
          // Show success dialog
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Success'),
                  ],
                ),
                content: Text('$message\n\nDeleted: $deletedCount scans'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        } else {
          // Show partial success/error dialog
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Partial Success'),
                  ],
                ),
                content: Text('$message\n\nDeleted: $deletedCount scans\nFailed: $failedCount scans'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        }

        // Call callback if provided
        onDataCleared?.call();
      }
    } catch (e) {
      // Close loading dialog if still open
      Navigator.of(context).pop();
      
      // Show error dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error'),
              ],
            ),
            content: Text('Failed to clear local data: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  Widget _buildIconOnly(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.delete_sweep_rounded,
        size: iconSize,
        color: iconColor ?? Colors.red,
      ),
      tooltip: 'Clear All Local Data',
      onPressed: () => _clearLocalData(context),
    );
  }

  Widget _buildIconWithText(BuildContext context) {
    return InkWell(
      onTap: () => _clearLocalData(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_sweep_rounded,
              size: iconSize,
              color: iconColor ?? Colors.red,
            ),
            const SizedBox(width: 4),
            Text(
              'Clear',
              style: TextStyle(
                color: iconColor ?? Colors.red,
                fontSize: (iconSize ?? 24) * 0.6,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _clearLocalData(context),
      icon: Icon(
        Icons.delete_sweep_rounded,
        size: iconSize,
      ),
      label: const Text('Clear All Local Data'),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? Colors.red.shade50,
        foregroundColor: iconColor ?? Colors.red,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: iconColor ?? Colors.red, width: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (view) {
      case LocalDataManagerView.iconOnly:
        return _buildIconOnly(context);
      case LocalDataManagerView.iconWithText:
        return _buildIconWithText(context);
      case LocalDataManagerView.fullButton:
        return _buildFullButton(context);
    }
  }
}

// Helper widget for app bar actions
class LocalDataManagerAppBarAction extends StatelessWidget {
  final VoidCallback? onDataCleared;

  const LocalDataManagerAppBarAction({
    Key? key,
    this.onDataCleared,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LocalDataManager(
      view: LocalDataManagerView.iconOnly,
      onDataCleared: onDataCleared,
      iconColor: Colors.white,
    );
  }
}

// Helper widget for drawer or menu
class LocalDataManagerMenuItem extends StatelessWidget {
  final VoidCallback? onDataCleared;

  const LocalDataManagerMenuItem({
    Key? key,
    this.onDataCleared,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
      title: const Text('Clear All Local Data'),
      subtitle: const Text('Delete all locally stored scans'),
      onTap: () {
        // Close drawer if open
        if (Scaffold.of(context).isDrawerOpen) {
          Navigator.of(context).pop();
        }
        
        // Delay slightly to allow drawer to close
        Future.delayed(const Duration(milliseconds: 100), () {
          LocalDataManager(
            view: LocalDataManagerView.iconOnly,
            onDataCleared: onDataCleared,
          )._clearLocalData(context);
        });
      },
    );
  }
}

// Helper widget for settings page
class LocalDataManagerSettingsTile extends StatelessWidget {
  final VoidCallback? onDataCleared;

  const LocalDataManagerSettingsTile({
    Key? key,
    this.onDataCleared,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.storage, color: Colors.grey),
                SizedBox(width: 8),
                Text(
                  'Local Data Management',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage locally stored scan data on your device. Uploaded scans are safely stored on the server.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            LocalDataManager(
              view: LocalDataManagerView.fullButton,
              onDataCleared: onDataCleared,
            ),
          ],
        ),
      ),
    );
  }
}
