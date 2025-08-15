import 'package:flutter/material.dart';

class StatusDisplay {
  static const Map<String, StatusInfo> _statusMap = {
    'pending': StatusInfo(
      label: 'Pending',
      color: Colors.orange,
      icon: Icons.schedule,
      description: 'Waiting to be processed',
    ),
    'uploading': StatusInfo(
      label: 'Uploading',
      color: Colors.blue,
      icon: Icons.cloud_upload,
      description: 'Uploading to server',
    ),
    'syncing': StatusInfo(
      label: 'Syncing',
      color: Colors.blue,
      icon: Icons.sync,
      description: 'Syncing with server',
    ),
    'processing': StatusInfo(
      label: 'Processing',
      color: Colors.purple,
      icon: Icons.autorenew,
      description: 'Processing on server',
    ),
    'completed': StatusInfo(
      label: 'Completed',
      color: Colors.green,
      icon: Icons.check_circle,
      description: 'Processing completed',
    ),
    'failed': StatusInfo(
      label: 'Failed',
      color: Colors.red,
      icon: Icons.error,
      description: 'Processing failed',
    ),
  };

  static StatusInfo getStatusInfo(String status) {
    return _statusMap[status] ?? _statusMap['pending']!;
  }

  static Widget buildStatusChip(String status, {double fontSize = 12}) {
    final statusInfo = getStatusInfo(status);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusInfo.color.withOpacity(0.1),
        border: Border.all(color: statusInfo.color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusInfo.icon,
            size: fontSize + 2,
            color: statusInfo.color,
          ),
          const SizedBox(width: 4),
          Text(
            statusInfo.label,
            style: TextStyle(
              color: statusInfo.color,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static Widget buildStatusIndicator(String status, {double size = 16}) {
    final statusInfo = getStatusInfo(status);
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusInfo.color,
        shape: BoxShape.circle,
      ),
      child: status == 'uploading' || status == 'processing' || status == 'syncing'
          ? Padding(
              padding: const EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(
              statusInfo.icon,
              color: Colors.white,
              size: size * 0.6,
            ),
    );
  }

  static List<IconData> getStatusIcons(String status) {
    final statusInfo = getStatusInfo(status);
    return [statusInfo.icon, Icons.image];
  }

  static Color getStatusColor(String status) {
    return getStatusInfo(status).color;
  }

  static String getStatusLabel(String status) {
    return getStatusInfo(status).label;
  }
}

class StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  final String description;

  const StatusInfo({
    required this.label,
    required this.color,
    required this.icon,
    required this.description,
  });
}
