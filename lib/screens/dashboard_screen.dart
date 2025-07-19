import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const platform = MethodChannel('com.demo.channel/message');
  List<Map<String, dynamic>> scans = [];
  bool isListView = true;

  @override
  void initState() {
    super.initState();
    _fetchScans();
  }

  Future<void> _fetchScans() async {
    try {
      final result = await platform.invokeMethod('getSavedScans');
      print('Fetched scans: $result'); // Debug log
      setState(() {
        scans = (result as List<dynamic>).map((scan) {
          final scanMap = (scan as Map<dynamic, dynamic>).cast<String, dynamic>();
          final modelSizeBytes = (scanMap['modelSizeBytes'] as num?)?.toDouble() ?? 0.0;
          final fileSizeMB = modelSizeBytes / (1024 * 1024);
          return {
            ...scanMap,
            'fileSizeMB': fileSizeMB,
            'imageCount': scanMap['imageCount'] ?? 0,
            'locationName': scanMap['locationName'] ?? 'Unknown Location',
          };
        }).toList();
      });
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch scans: ${e.message}')),
      );
    }
  }

  Future<void> _startScan() async {
    try {
      final result = await platform.invokeMethod('startScan');
      print('Scan started: $result');
      await _fetchScans();
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start scan: ${e.message}')),
      );
    }
  }

  Future<void> _deleteScan(String path, String name) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name'),
        content: const Text('Are you sure you want to delete this scan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await platform.invokeMethod('deleteScan', {'path': path});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
      await _fetchScans();
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete scan: ${e.message}')),
      );
    }
  }

  Future<void> _previewUSDZ(String usdzPath) async {
    try {
      final result = await platform.invokeMethod('openUSDZ', {'path': usdzPath});
      print(result);
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to preview USDZ: ${e.message}')),
      );
    }
  }

  Future<void> _shareUSDZ(String usdzPath) async {
    try {
      final result = await platform.invokeMethod('shareUSDZ', {'path': usdzPath});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share model: ${e.message}')),
      );
    }
  }

  void _navigateToModelDetail(Map<String, dynamic> scan) {
    print('Navigating to ModelDetailScreen with scan: $scan'); // Debug log
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ModelDetailScreen(scan: scan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: false,
        toolbarHeight: 70,
        title: const Text(
          'LIBRARY',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isListView ? Icons.grid_view_rounded : Icons.view_list_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                isListView = !isListView;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.map, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Map view not implemented')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _startScan,
          ),
        ],
      ),
      body: scans.isEmpty
          ? const Center(
          child: Text('No scans available', style: TextStyle(color: Colors.white)))
          : RefreshIndicator(
        onRefresh: _fetchScans,
        color: Colors.white,
        backgroundColor: Colors.grey[900],
        child: isListView
            ? ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: scans.length,
          itemBuilder: (context, index) {
            final scan = scans[index];
            final hasUSDZ = scan['hasUSDZ'] as bool;
            return ProjectCard(
              title: scan['name'] ?? 'Unnamed Scan',
              subtitle:
              '${scan['timestamp']?.split('T')[0] ?? 'Unknown'} • ${scan['fileSizeMB'].toStringAsFixed(1)} MB • Images: ${scan['imageCount']} • ${scan['locationName']}',
              statusLabel: hasUSDZ ? 'Uploaded' : 'Pending',
              iconSet: [
                hasUSDZ
                    ? Icons.check_circle_outline
                    : Icons.cloud_upload_outlined
              ],
              iconColor: hasUSDZ ? Colors.green : Colors.blue,
              onTap: () => _navigateToModelDetail(scan),
              onLongPress: hasUSDZ
                  ? () => _shareUSDZ(scan['usdzPath'])
                  : () => _deleteScan(
                scan['folderPath'],
                scan['name'] ?? 'Unnamed Scan',
              ),
            );
          },
        )
            : GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.8,
          ),
          itemCount: scans.length,
          itemBuilder: (context, index) {
            final scan = scans[index];
            final hasUSDZ = scan['hasUSDZ'] as bool;
            return ProjectCard(
              title: scan['name'] ?? 'Unnamed Scan',
              subtitle:
              '${scan['timestamp']?.split('T')[0] ?? 'Unknown'} • ${scan['fileSizeMB'].toStringAsFixed(1)} MB • Images: ${scan['imageCount']} • ${scan['locationName']}',
              statusLabel: hasUSDZ ? 'Uploaded' : 'Pending',
              iconSet: [
                hasUSDZ
                    ? Icons.check_circle_outline
                    : Icons.cloud_upload_outlined
              ],
              iconColor: hasUSDZ ? Colors.green : Colors.blue,
              onTap: () => _navigateToModelDetail(scan),
              onLongPress: hasUSDZ
                  ? () => _shareUSDZ(scan['usdzPath'])
                  : () => _deleteScan(
                scan['folderPath'],
                scan['name'] ?? 'Unnamed Scan',
              ),
            );
          },
        ),
      ),
    );
  }
}

class ProjectCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String statusLabel;
  final List<IconData> iconSet;
  final Color iconColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ProjectCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.iconSet,
    this.iconColor = Colors.green,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        print('ProjectCard tapped: $title'); // Debug log
        onTap?.call();
      },
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque, // Ensure entire card is tappable
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  statusLabel,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: iconSet
                      .map((icon) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(icon, color: iconColor, size: 18),
                  ))
                      .toList(),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.more_horiz, color: Colors.white60),
              ],
            ),
          ],
        ),
      ),
    );
  }
}