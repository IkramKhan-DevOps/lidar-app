import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'model_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const platform = MethodChannel('com.demo.channel/message');
  List<Map<String, dynamic>> scans = [];
  String currentView = 'list'; // Track current view: 'list', 'grid', or 'map'

  @override
  void initState() {
    super.initState();
    _fetchScans();
  }

  Future<void> _fetchScans() async {
    try {
      final result = await platform.invokeMethod('getSavedScans');
      setState(() {
        scans = (result['scans'] as List<dynamic>).map((scan) {
          final scanMap = (scan as Map<dynamic, dynamic>).cast<String, dynamic>();
          final modelSizeBytes = (scanMap['modelSizeBytes'] as num?)?.toDouble() ?? 0.0;
          final fileSizeMB = modelSizeBytes / (1024 * 1024);
          final metadata = {
            'scan_id': scanMap['scanID'] ?? scanMap['folderPath'].split('/').last,
            'name': scanMap['name'] ?? 'Unnamed Scan',
            'timestamp': scanMap['timestamp'] ?? DateTime.now().toIso8601String(),
            'location_name': scanMap['locationName'] ?? 'Unknown Location',
            'coordinates': scanMap['coordinates'] ?? [],
            'image_count': scanMap['imageCount'] ?? 0,
            'model_size_bytes': modelSizeBytes,
            'status': scanMap['status'] ?? 'pending',
            'snapshot_path': scanMap['snapshotPath'],
          };
          return {
            ...scanMap,
            'fileSizeMB': fileSizeMB,
            'metadata': metadata,
            'status': metadata['status'],
            'usdzPath': scanMap['usdzPath'] ?? (scanMap['hasUSDZ'] == true ? '${scanMap['folderPath']}/model.usdz' : null),
            'snapshotPath': scanMap['snapshotPath'] != null ? '${scanMap['folderPath']}/${scanMap['snapshotPath']}' : null,
          };
        }).toList();
      });
    } on PlatformException catch (e) {
      _showSnack('Failed to fetch scans: ${e.message}', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  void _navigateToModelDetail(Map<String, dynamic> scan) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ModelDetailScreen(scan: scan)),
    );
  }

  List<LatLng> _getAllCoordinates() {
    List<LatLng> allPoints = [];
    for (var scan in scans) {
      final rawCoordinates = scan['metadata']['coordinates'] as List<dynamic>?;
      if (rawCoordinates != null) {
        final coordinates = rawCoordinates.map((coord) {
          if (coord is List<dynamic> && coord.length >= 2) {
            return [
              double.tryParse(coord[0].toString()) ?? 0.0,
              double.tryParse(coord[1].toString()) ?? 0.0
            ];
          }
          return null;
        }).whereType<List<double>>().toList();

        allPoints.addAll(coordinates.map((coord) => LatLng(coord[0], coord[1])).whereType<LatLng>());
      }
    }
    return allPoints;
  }

  Widget _buildMapView() {
    final allPoints = _getAllCoordinates();
    if (allPoints.isEmpty) {
      return const Center(child: Text('No location data available', style: TextStyle(color: Colors.white)));
    }

    final bounds = LatLngBounds.fromPoints(allPoints);
    final center = bounds.center;
    const zoom = 10.0;

    return FlutterMap(
      options: MapOptions(
        center: center,
        zoom: zoom,
        minZoom: 5.0,
        maxZoom: 18.0,
        interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.example.platform_channel_swift_demo',
        ),
        MarkerLayer(
          markers: allPoints.map((point) => Marker(
            point: point,
            width: 40.0,
            height: 40.0,
            child: const Icon(Icons.location_pin, color: Colors.red, size: 40.0),
          )).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900], // Grey background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('LIBRARY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_list, color: Colors.white),
            onPressed: () => setState(() => currentView = 'list'),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view, color: Colors.white),
            onPressed: () => setState(() => currentView = 'grid'),
          ),
          IconButton(
            icon: const Icon(Icons.map, color: Colors.white),
            onPressed: () => setState(() => currentView = 'map'),
          ),
        ],
      ),
      body: currentView == 'list' || currentView == 'grid'
          ? (scans.isEmpty
          ? const Center(child: Text('No scans available', style: TextStyle(color: Colors.white)))
          : RefreshIndicator(
        onRefresh: _fetchScans,
        color: Colors.white,
        backgroundColor: Colors.black, // Black inner background
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: scans.length,
          itemBuilder: (context, index) {
            final scan = scans[index];
            final status = scan['status'] ?? 'pending';
            final icons = _statusIcons(status);

            return ProjectCard(
              title: scan['metadata']['name'],
              subtitle:
              '${scan['timestamp']?.split('T')[0] ?? 'Unknown'} • ${scan['fileSizeMB'].toStringAsFixed(1)} MB • Images (${scan['metadata']['image_count']})',
              statusLabel: _statusLabel(status),
              iconSet: icons['icons'],
              iconColor: icons['color'],
              isListView: currentView == 'list',
              usdzPath: scan['usdzPath'],
              snapshotPath: scan['snapshotPath'],
              status: status,
              onTap: () => _navigateToModelDetail(scan),
              onLongPress: () {},
            );
          },
        ),
      ))
          : _buildMapView(),
    );
  }

  Map<String, dynamic> _statusIcons(String status) {
    switch (status) {
      case 'uploaded':
        return {
          'icons': [Icons.check_box, Icons.image],
          'color': Colors.green
        };
      case 'failed':
        return {
          'icons': [Icons.error_outline, Icons.image_not_supported],
          'color': Colors.red
        };
      case 'pending':
      default:
        return {
          'icons': [Icons.access_time, Icons.image],
          'color': Colors.orange
        };
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'uploaded':
        return 'Uploaded';
      case 'failed':
        return 'Upload error';
      case 'pending':
      default:
        return 'Pending';
    }
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
  final bool isListView;
  final String? usdzPath;
  final String? snapshotPath;
  final String status;

  const ProjectCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.iconSet,
    required this.iconColor,
    this.onTap,
    this.onLongPress,
    required this.isListView,
    this.usdzPath,
    this.snapshotPath,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black, // Black card color
          // Removed border: Border.all(color: Colors.grey[700]!)
        ),
        child: isListView ? _buildListTile() : _buildGridCard(context),
      ),
    );
  }

  Widget _buildListTile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            Text(statusLabel, style: TextStyle(color: iconColor, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(subtitle, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const Spacer(),
            ...iconSet
                .map((i) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(i, color: iconColor, size: 16),
            ))
                .toList(),
            const SizedBox(width: 4),
            Icon(Icons.more_horiz, color: Colors.grey[400], size: 20),
          ],
        ),
      ],
    );
  }

  Widget _buildGridCard(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _previewContent(),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(statusLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewContent() {
    if (status == 'uploaded' && snapshotPath != null && File(snapshotPath!).existsSync()) {
      return Image.file(File(snapshotPath!), fit: BoxFit.cover);
    } else {
      return Center(child: Icon(Icons.cloud_upload, color: iconColor, size: 40));
    }
  }
}