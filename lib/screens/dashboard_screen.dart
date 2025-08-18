import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'model_detail_screen.dart';
import '../widgets/status_display.dart';
import '../widgets/local_data_manager.dart';
import '../widgets/network_status_indicator.dart';
import '../widgets/sync_manager.dart';
import '../settings/providers/global_provider.dart';
import '../providers/sync_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
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
        // Normalize status for consistent display
        String normalizedStatus = scanMap['status'] ?? 'pending';
        switch (normalizedStatus.toLowerCase()) {
          case 'syncing':
          case 'uploaded':
            normalizedStatus = 'syncing';
            break;
          case 'uploading':
            normalizedStatus = 'uploading';
            break;
          case 'processing':
            normalizedStatus = 'processing';
            break;
          case 'completed':
          case 'done':
            normalizedStatus = 'completed';
            break;
          case 'failed':
          case 'error':
            normalizedStatus = 'failed';
            break;
          default:
            normalizedStatus = 'pending';
        }

        final metadata = {
          'scan_id': scanMap['scanID'] ?? scanMap['folderPath']?.split('/').last ?? 'unknown',
          'name': scanMap['name'] ?? 'Unnamed Scan',
          'timestamp': scanMap['timestamp'] ?? DateTime.now().toIso8601String(),
          'location_name': scanMap['locationName'] ?? 'Unknown Location',
          'coordinates': scanMap['coordinates'] ?? [],
          'image_count': scanMap['imageCount'] ?? 0,
          'model_size_bytes': modelSizeBytes,
          'status': normalizedStatus,
          'original_status': scanMap['originalStatus'] ?? scanMap['status'], // Keep original for debugging
          'snapshot_path': scanMap['snapshotPath'],
          'is_from_api': scanMap['isFromAPI'] ?? false,
        };
        return {
          ...scanMap,
          'fileSizeMB': fileSizeMB,
          'metadata': metadata,
          'status': normalizedStatus,
          'originalStatus': metadata['original_status'],
          'isFromAPI': metadata['is_from_api'],
          'usdzPath': scanMap['usdzPath'] ?? (scanMap['hasUSDZ'] == true && scanMap['folderPath'] != null ? '${scanMap['folderPath']}/model.usdz' : null),
          'snapshotPath': scanMap['snapshotPath'] != null && scanMap['folderPath'] != null ? '${scanMap['folderPath']}/${scanMap['snapshotPath']}' : null,
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
      _showSnack('Couldn\'t load scans. Please try again.', isError: true);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'scanComplete':
      case 'processingComplete':
        try {
          print('Received ${call.method} with arguments: ${call.arguments}');
          await _fetchScans();
          // Show success message for new scans
          if (call.method == 'scanComplete') {
            final folderPath = call.arguments?['folderPath'] as String?;
            final scanName = folderPath?.split('/').last ?? 'New scan';
            _showSnack('📱 $scanName saved locally', isError: false);
          }
        } catch (e) {
          print('Error handling ${call.method}: $e');
          _showSnack('Couldn\'t update scans. Please try again.', isError: true);
        }
        break;

      case 'offlineSyncComplete':
        try {
          final success = call.arguments?['success'] as bool? ?? false;
          final networkNotifier = ref.read(networkStateProvider.notifier);

          if (success) {
            _showSnack('🌐 All offline scans synced to server', isError: false);
            networkNotifier.setSyncComplete(true, message: 'All offline scans synced successfully');
          } else {
            _showSnack('⚠️ Some scans failed to sync. Will retry when online.', isError: true);
            networkNotifier.setSyncComplete(false, message: 'Some scans failed to sync');
          }

          // Refresh scan list to show updated statuses
          await _fetchScans();
        } catch (e) {
          print('Error handling offlineSyncComplete: $e');
          final networkNotifier = ref.read(networkStateProvider.notifier);
          networkNotifier.setSyncComplete(false, message: 'Sync status unknown');
        }
        break;

      case 'networkStatusChanged':
        try {
          final isOnline = call.arguments?['isOnline'] as bool? ?? true;
          final networkNotifier = ref.read(networkStateProvider.notifier);

          networkNotifier.updateNetworkStatus(isOnline);

          if (isOnline) {
            _showSnack('🌐 Back online - syncing offline scans...', isError: false);
            networkNotifier.updateSyncStatus(true, message: 'Syncing offline scans...');
          } else {
            _showSnack('📱 Offline - scans will be stored locally', isError: false);
          }
        } catch (e) {
          print('Error handling networkStatusChanged: $e');
        }
        break;

      case 'scanUploadComplete':
        try {
          final success = call.arguments?['success'] as bool? ?? false;
          final folderPath = call.arguments?['folderPath'] as String?;
          final scanName = folderPath?.split('/').last ?? 'Scan';

          if (success) {
            _showSnack('✅ $scanName uploaded to server successfully', isError: false);
          } else {
            _showSnack('⚠️ $scanName failed to upload. Will retry when online.', isError: true);
          }

          // Refresh scan list to show updated statuses
          await _fetchScans();
        } catch (e) {
          print('Error handling scanUploadComplete: $e');
        }
        break;

      default:
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

  String? _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;

    try {
      DateTime dateTime;

      if (timestamp is String) {
        // Handle ISO string format
        dateTime = DateTime.parse(timestamp);
      } else if (timestamp is num) {
        // Handle Unix timestamp (seconds since epoch)
        dateTime = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round());
      } else {
        return null;
      }

      // Format as YYYY-MM-DD
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      print('Error formatting timestamp: $e');
      return null;
    }
  }

  String _safeFormatSize(dynamic sizeValue) {
    try {
      if (sizeValue == null) return '0.0';
      if (sizeValue is double) return sizeValue.toStringAsFixed(1);
      if (sizeValue is int) return sizeValue.toDouble().toStringAsFixed(1);
      if (sizeValue is String) {
        final parsed = double.tryParse(sizeValue);
        return parsed?.toStringAsFixed(1) ?? '0.0';
      }
      return '0.0';
    } catch (e) {
      print('Error formatting size: $e');
      return '0.0';
    }
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
          const NetworkStatusAppBarIndicator(),
          const SyncAppBarAction(),
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
      drawer: Drawer(
        child: Container(
          color: Colors.grey[900],
          child: Column(
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.blueAccent],
                  ),
                ),
                child: Center(
                  child: Text(
                    '3D Scanner App',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home, color: Colors.white),
                title: const Text('Home', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.library_books, color: Colors.white),
                title: const Text('Library', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(),
              ),
              const Divider(color: Colors.grey),
              // Network status card in drawer
              const NetworkStatusCard(),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Total scans: ${scans.length}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
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

                    return ProjectCard(
                      title: scan['metadata']['name'],
                      subtitle:
                      '${_formatTimestamp(scan['timestamp']) ?? 'Unknown'} • ${_safeFormatSize(scan['fileSizeMB'])} MB • Images (${scan['metadata']['image_count']})',
                      statusLabel: StatusDisplay.getStatusLabel(status),
                      iconSet: StatusDisplay.getStatusIcons(status),
                      iconColor: StatusDisplay.getStatusColor(status),
                      isListView: currentView == 'list',
                      usdzPath: scan['usdzPath'],
                      snapshotPath: scan['snapshotPath'],
                      status: status,
                      onTap: () => _navigateToModelDetail(scan),
                      onLongPress: () {},
                    );
                  },
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