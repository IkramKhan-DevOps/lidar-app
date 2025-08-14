import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'model_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const platform = MethodChannel('com.demo.channel/message');
  List<Map<String, dynamic>> scans = [];
  String currentView = 'list';
  GoogleMapController? _mapController;
  bool _isFullScreenMap = false;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _fetchScans();
    platform.setMethodCallHandler(_handleMethodCall);
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchScans();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchScans() async {
    setState(() {
      _isRefreshing = true;
    });
    try {
      final result = await platform.invokeMethod('getSavedScans');
      final newScans = (result['scans'] as List<dynamic>).map((scan) {
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
      setState(() {
        scans = newScans;
        _isRefreshing = false;
      });
      print('Fetched ${newScans.length} scans');
    } on PlatformException catch (e) {
      print('Error fetching scans: ${e.message}');
      setState(() {
        _isRefreshing = false;
      });
      _showSnack('Couldn’t load scans. Please try again.', isError: true);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'scanComplete' || call.method == 'processingComplete') {
      try {
        print('Received ${call.method} with arguments: ${call.arguments}');
        await _fetchScans();
        // Removed: _showSnack('Scan updated successfully');
      } catch (e) {
        print('Error handling ${call.method}: $e');
        _showSnack('Couldn’t update scans. Please try again.', isError: true);
      }
    } else {
      print('Unhandled method call: ${call.method} with arguments: ${call.arguments}');
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        backgroundColor: isError ? Colors.red[800] : Colors.black87,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _navigateToModelDetail(Map<String, dynamic> scan) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ModelDetailScreen(scan: scan)),
    );
  }

  Map<String, dynamic> _getAllCoordinatesByScan() {
    Map<String, List<LatLng>> scanCoordinates = {};
    List<LatLng> allPoints = [];

    for (var scan in scans) {
      final scanId = scan['metadata']['scan_id'] as String;
      final rawCoordinates = scan['metadata']['coordinates'] as List<dynamic>?;
      List<LatLng> points = [];

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

        points = coordinates
            .map((coord) => LatLng(coord[0], coord[1]))
            .where((point) => point.latitude != 0.0 && point.longitude != 0.0)
            .toList();

        if (points.isNotEmpty) {
          scanCoordinates[scanId] = points;
          allPoints.addAll(points);
        }
      }
    }

    return {
      'scanCoordinates': scanCoordinates,
      'allPoints': allPoints,
    };
  }

  Map<String, LatLng>? _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) return null;
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    final southwest = LatLng(minLat, minLng);
    final northeast = LatLng(maxLat, maxLng);
    final center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    return {
      'southwest': southwest,
      'northeast': northeast,
      'center': center,
    };
  }

  Widget _buildMapView({bool isFullScreen = false}) {
    final coordinatesData = _getAllCoordinatesByScan();
    final scanCoordinates = coordinatesData['scanCoordinates'] as Map<String, List<LatLng>>;
    final allPoints = coordinatesData['allPoints'] as List<LatLng>;
    final defaultPosition = const LatLng(0.0, 0.0);
    const defaultZoom = 2.0;

    LatLng center = defaultPosition;
    double zoom = defaultZoom;
    Map<String, LatLng>? bounds;

    if (allPoints.isNotEmpty) {
      bounds = _calculateBounds(allPoints);
      center = bounds!['center'] as LatLng;
      zoom = 15.0;
    }

    final markers = allPoints.isNotEmpty
        ? scans.asMap().entries.where((entry) {
      final scan = entry.value;
      final scanId = scan['metadata']['scan_id'] as String;
      return scanCoordinates.containsKey(scanId);
    }).map((entry) {
      final index = entry.key;
      final scan = entry.value;
      final points = scanCoordinates[scan['metadata']['scan_id']]!;
      return Marker(
        markerId: MarkerId('scan_$index'),
        position: points.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: scan['metadata']['name'] ?? 'Unnamed Scan',
          snippet: scan['metadata']['location_name'] ?? 'Unknown Location',
        ),
      );
    }).toSet()
        : <Marker>{};

    final polylines = scanCoordinates.isNotEmpty
        ? scanCoordinates.entries.map((entry) {
      final scanId = entry.key;
      final points = entry.value;
      return Polyline(
        polylineId: PolylineId('scan_path_$scanId'),
        points: points,
        color: Colors.blue,
        width: 4,
      );
    }).toSet()
        : <Polyline>{};

    return Container(
      color: Colors.grey[900],
      child: SafeArea(
        child: Stack(
          children: [
            GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                if (allPoints.isNotEmpty && bounds != null) {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngBounds(
                      LatLngBounds(
                        southwest: bounds['southwest'] as LatLng,
                        northeast: bounds['northeast'] as LatLng,
                      ),
                      50.0,
                    ),
                  );
                } else {
                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(target: center, zoom: zoom),
                    ),
                  );
                }
              },
              initialCameraPosition: CameraPosition(
                target: center,
                zoom: zoom,
              ),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () {
                  setState(() {
                    _isFullScreenMap = false;
                    currentView = 'list';
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('LIBRARY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_list, color: Colors.white),
            onPressed: () => setState(() {
              currentView = 'list';
              _isFullScreenMap = false;
            }),
          ),
          IconButton(
            icon: const Icon(Icons.grid_view, color: Colors.white),
            onPressed: () => setState(() {
              currentView = 'grid';
              _isFullScreenMap = false;
            }),
          ),
          IconButton(
            icon: const Icon(Icons.map, color: Colors.white),
            onPressed: () => setState(() {
              currentView = 'map';
              _isFullScreenMap = true;
            }),
          ),
        ],
      ),
      body: Stack(
        children: [
          currentView == 'list' || currentView == 'grid'
              ? (scans.isEmpty
              ? const Center(child: Text('No scans available', style: TextStyle(color: Colors.white54, fontSize: 14)))
              : RefreshIndicator(
            onRefresh: _fetchScans,
            color: Colors.white,
            backgroundColor: Colors.black87,
            child: Stack(
              children: [
                ListView.builder(
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
                if (_isRefreshing)
                  const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
              ],
            ),
          ))
              : _buildMapView(isFullScreen: _isFullScreenMap),
          if (_isFullScreenMap)
            _buildMapView(isFullScreen: true),
        ],
      ),
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
          color: Colors.black,
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
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
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
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
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