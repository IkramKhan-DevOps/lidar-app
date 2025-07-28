import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ModelDetailScreen extends StatefulWidget {
  final Map<String, dynamic> scan;

  const ModelDetailScreen({super.key, required this.scan});

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen>
    with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.demo.channel/message');
  late TabController _tabController;
  List<String> imagePaths = [];
  bool _isFullScreenMap = false;
  late TextEditingController _nameController;
  bool _isProcessing = false;
  String _status = 'pending';
  String _statusMessage = '';
  String? _errorDetails;
  GoogleMapController? _mapController;
  bool _hasShownNoGpsMessage = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.scan['metadata'] == null) {
      widget.scan['metadata'] = <String, dynamic>{
        'scan_id': widget.scan['scanID'] ?? widget.scan['folderPath'].split('/').last,
        'name': widget.scan['name'] ?? 'Unnamed Scan',
        'timestamp': widget.scan['timestamp'] ?? DateTime.now().toIso8601String(),
        'location_name': widget.scan['locationName'] ?? '',
        'coordinates': widget.scan['coordinates'] ?? [],
        'image_count': widget.scan['imageCount'] ?? 0,
        'model_size_bytes': widget.scan['modelSizeBytes'] ?? 0,
        'status': widget.scan['status'] ?? 'pending',
        'snapshot_path': widget.scan['snapshotPath'] ?? null,
        'duration_seconds': 0.0,
      };
    }
    widget.scan['snapshotPath'] = widget.scan['snapshotPath'] ?? widget.scan['metadata']['snapshot_path'];
    _nameController = TextEditingController(text: widget.scan['metadata']['name'] ?? 'Unnamed Scan');
    _fetchImagePaths();
    _syncStatusWithMetadata();
    platform.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return '00:00';
    final int minutes = (durationSeconds / 60).floor();
    final int seconds = (durationSeconds % 60).round();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _syncStatusWithMetadata() async {
    try {
      final folderPath = widget.scan['folderPath']?.toString();
      if (folderPath == null) throw Exception('Invalid folder path');

      final metadataResult = await platform.invokeMethod('getScanMetadata', {'folderPath': folderPath});
      final metadata = (metadataResult as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? widget.scan['metadata'];
      final status = metadata['status']?.toString() ?? 'pending';
      final hasUsdz = metadata['hasUSDZ'] == true;

      setState(() {
        widget.scan['metadata'] = <String, dynamic>{
          ...widget.scan['metadata'],
          ...metadata,
        };
        _status = status;
        _statusMessage = _getStatusMessage(status);
        widget.scan['usdzPath'] = hasUsdz ? '$folderPath/model.usdz' : null;
      });

      if (hasUsdz && status != 'uploaded') {
        await platform.invokeMethod('updateScanStatus', {'folderPath': folderPath, 'status': 'uploaded'});
        setState(() {
          _status = 'uploaded';
          _statusMessage = 'Tap to view 3D model';
          widget.scan['metadata']['status'] = 'uploaded';
          widget.scan['usdzPath'] = '$folderPath/model.usdz';
        });
      }
    } catch (e) {
      print('Error syncing status: $e');
      setState(() {
        _status = 'pending';
        _statusMessage = 'Data has not been processed. Tap to process the model.';
        _errorDetails = e.toString();
      });
    }
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'uploaded':
        return 'Tap to view 3D model';
      case 'failed':
        return 'Model processing failed${_errorDetails != null ? ': $_errorDetails' : '.'} Tap to retry.';
      case 'pending':
      default:
        return 'Data has not been processed. Tap to process the model.';
    }
  }

  Future<void> _fetchImagePaths() async {
    try {
      final result = await platform.invokeMethod('getScanImages', {'folderPath': widget.scan['folderPath']});
      if (result is List) {
        setState(() {
          imagePaths = List<String>.from(result.map((e) => e.toString()));
        });
      } else {
        setState(() {
          imagePaths = [];
        });
      }
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Couldn’t load images. Please try again.', style: TextStyle(color: Colors.white, fontSize: 14)),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      setState(() {
        imagePaths = [];
      });
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'processingComplete') {
      final folderPath = call.arguments['usdzPath']?.toString();
      if (folderPath != null && folderPath.contains(widget.scan['folderPath'])) {
        setState(() {
          _status = 'uploaded';
          _statusMessage = 'Tap to view 3D model';
          _isProcessing = false;
          widget.scan['metadata']['status'] = 'uploaded';
          widget.scan['usdzPath'] = call.arguments['usdzPath'];
          if (call.arguments['snapshotPath'] != null) {
            widget.scan['snapshotPath'] = call.arguments['snapshotPath'];
          }
        });
      }
    } else if (call.method == 'scanComplete') {
      final folderPath = call.arguments['folderPath']?.toString();
      if (folderPath != null && folderPath == widget.scan['folderPath']) {
        setState(() {
          widget.scan['metadata'] = <String, dynamic>{
            ...widget.scan['metadata'],
            'scan_id': call.arguments['scanID'] ?? widget.scan['metadata']['scan_id'],
            'name': call.arguments['name'] ?? widget.scan['metadata']['name'],
            'timestamp': call.arguments['timestamp'] ?? widget.scan['metadata']['timestamp'],
            'location_name': call.arguments['locationName'] ?? widget.scan['metadata']['location_name'],
            'coordinates': call.arguments['coordinates'] ?? widget.scan['metadata']['coordinates'],
            'image_count': call.arguments['imageCount'] ?? widget.scan['metadata']['image_count'],
            'duration_seconds': call.arguments['durationSeconds'] ?? widget.scan['metadata']['duration_seconds'],
            'status': 'pending',
          };
          _nameController.text = widget.scan['metadata']['name'];
          _status = 'pending';
          _statusMessage = 'Data has not been processed. Tap to process the model.';
        });
        await _fetchImagePaths();
      }
    } else if (call.method == 'updateProcessingStatus') {
      final status = call.arguments['status']?.toString() ?? 'processing';
      setState(() {
        _isProcessing = true;
        _statusMessage = _getProcessingStatusMessage(status);
      });
    } else if (call.method == 'closeARModule' || call.method == 'dismiss') {
      if (mounted) Navigator.of(context).pop();
    }
  }

  String _getProcessingStatusMessage(String status) {
    switch (status) {
      case 'uploading':
        return 'Uploading model data...';
      case 'downloading':
        return 'Downloading processed model...';
      case 'processing':
      default:
        return 'Processing model...';
    }
  }

  Future<void> _previewUSDZ() async {
    if (_isProcessing) return;

    if (_status == 'uploaded' && widget.scan['usdzPath'] != null) {
      try {
        await platform.invokeMethod('openUSDZ', {'path': widget.scan['usdzPath']});
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Couldn’t open the 3D model. Please try again.', style: TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } else {
      await _processModel();
    }
  }

  Future<void> _processModel() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing model...';
      _errorDetails = null; // Reset error details on retry
    });

    try {
      final folderPath = widget.scan['folderPath']?.toString();
      if (folderPath == null) {
        throw PlatformException(code: 'INVALID_PATH', message: 'Invalid folder path');
      }

      final zipSizeResult = await platform.invokeMethod('getZipSize', {'folderPath': folderPath});
      final zipSizeMB = (zipSizeResult['zipSizeBytes'] as num) / (1024 * 1024);
      final estimatedMinutes = (zipSizeMB / 50.0) * 2.0;
      final estimatedTimeText = estimatedMinutes.toStringAsFixed(1);

      setState(() {
        _statusMessage = 'Processing model (~$estimatedTimeText minutes)...';
      });

      final result = await platform.invokeMethod('processScan', {'folderPath': folderPath});

      setState(() {
        _status = 'uploaded';
        _statusMessage = 'Tap to view 3D model';
        _isProcessing = false;
        widget.scan['metadata']['status'] = 'uploaded';
        widget.scan['usdzPath'] = result['usdzPath'];
        widget.scan['metadata']['model_size_bytes'] = result['modelSizeBytes'];
        if (result['snapshotPath'] != null) {
          widget.scan['snapshotPath'] = result['snapshotPath'];
        }
      });

      await platform.invokeMethod('updateScanStatus', {'folderPath': folderPath, 'status': 'uploaded'});
    } on PlatformException catch (e) {
      String errorMessage = 'Couldn’t process the model. Please try again.';
      if (e.code == 'API_STATUS_ERROR' || e.code == 'API_REQUEST_FAILED') {
        errorMessage = 'Couldn’t process the model. Please check your internet connection and try again.';
      } else if (e.code == 'INVALID_ZIP_DATA') {
        errorMessage = 'Scan data is incomplete. Please try scanning again.';
      } else if (e.code == 'CAMERA_PERMISSION_DENIED') {
        errorMessage = 'Camera access denied. Please enable camera permissions in Settings.';
      } else if (e.code == 'AR_SESSION_ERROR') {
        errorMessage = 'Unable to start scan. Please try again in a well-lit area.';
      } else if (e.code == 'SERVER_UNAVAILABLE') {
        errorMessage = 'Server is unavailable. Please try again later.';
      }

      setState(() {
        _isProcessing = false;
        _status = 'failed';
        _statusMessage = 'Model processing failed: $errorMessage Tap to retry.';
        _errorDetails = e.message;
        widget.scan['metadata']['status'] = 'failed';
      });
      await platform.invokeMethod('updateScanStatus', {'folderPath': widget.scan['folderPath'], 'status': 'failed'});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage, style: const TextStyle(color: Colors.white, fontSize: 14)),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _deleteModel() async {
    try {
      final folderPath = widget.scan['folderPath']?.toString();
      if (folderPath == null || folderPath.isEmpty) {
        throw PlatformException(code: 'INVALID_PATH', message: 'Folder path is null or empty');
      }

      final result = await platform.invokeMethod('deleteScan', {'path': folderPath});

      if (result == 'Scan deleted successfully' || result == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Model deleted successfully', style: TextStyle(color: Colors.white, fontSize: 14)),
              backgroundColor: Colors.black87,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
          Navigator.of(context).pop();
        }
      } else {
        throw PlatformException(code: 'DELETE_FAILED', message: 'Deletion failed on native side: $result');
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.black87,
          title: const Text('Error Deleting Project', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Couldn’t delete the model. Please try again.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      );
    }
  }

  void _showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('Delete Project', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${widget.scan['metadata']['name'] ?? 'Unnamed Scan'}"? This action cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteModel();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return 'Unknown';
    try {
      final dateTime = DateTime.parse(timestamp);
      final dateFormat = DateFormat('yyyy-MM-dd');
      final timeFormat = DateFormat('HH:mm');
      return '${dateFormat.format(dateTime)} • ${timeFormat.format(dateTime)}';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        title: const Text('Edit Project Name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter project name',
            hintStyle: const TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white54),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.blue),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final newName = _nameController.text.isEmpty ? 'Unnamed Scan' : _nameController.text;
              try {
                await platform.invokeMethod('updateScanName', {
                  'folderPath': widget.scan['folderPath'],
                  'name': newName,
                });
                setState(() {
                  widget.scan['metadata']['name'] = newName;
                });
                Navigator.pop(context);
              } on PlatformException catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Couldn’t update the project name. Please try again.', style: TextStyle(color: Colors.white, fontSize: 14)),
                    backgroundColor: Colors.red[800],
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildMap({bool isFullScreen = false}) {
    final rawCoordinates = widget.scan['metadata']['coordinates'] as List<dynamic>?;
    final defaultPosition = const LatLng(0.0, 0.0);
    const defaultZoom = 2.0;

    List<LatLng> points = [];
    Map<String, LatLng>? bounds;
    LatLng center = defaultPosition;
    double zoom = defaultZoom;

    if (rawCoordinates != null && rawCoordinates.isNotEmpty) {
      final coordinates = rawCoordinates
          .map((coord) {
        if (coord is List<dynamic> && coord.length >= 2) {
          return [double.tryParse(coord[0].toString()) ?? 0.0, double.tryParse(coord[1].toString()) ?? 0.0];
        }
        return null;
      })
          .whereType<List<double>>()
          .toList();

      points = coordinates
          .map((coord) => LatLng(coord[0], coord[1]))
          .where((point) => point.latitude != 0.0 && point.longitude != 0.0)
          .toList();

      if (points.isNotEmpty) {
        bounds = _calculateBounds(points);
        center = bounds['center'] as LatLng;
        zoom = 15.0;
      } else if (!_hasShownNoGpsMessage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No location data available.', style: TextStyle(color: Colors.white, fontSize: 14)),
              backgroundColor: Colors.red[800],
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
          _hasShownNoGpsMessage = true;
        });
      }
    } else if (!_hasShownNoGpsMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No location data available.', style: TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        _hasShownNoGpsMessage = true;
      });
    }

    final polylines = points.isNotEmpty
        ? <Polyline>{
      Polyline(
        polylineId: const PolylineId('scan_path'),
        points: points,
        color: Colors.blue,
        width: 4,
      ),
    }
        : <Polyline>{};

    final markers = points.isNotEmpty
        ? <Marker>{
      Marker(
        markerId: const MarkerId('start_point'),
        position: points.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    }
        : <Marker>{};

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: isFullScreen ? null : 300,
            child: GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                if (points.isNotEmpty && bounds != null) {
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
              polylines: points.isNotEmpty ? polylines : <Polyline>{},
              markers: points.isNotEmpty ? markers : <Marker>{},
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapType: MapType.normal,
            ),
          ),
        ),
        if (!isFullScreen && points.isNotEmpty)
          Positioned(
            bottom: 8,
            right: 8,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.blue,
              onPressed: () {
                setState(() {
                  _isFullScreenMap = true;
                });
              },
              child: const Icon(Icons.fullscreen, size: 20),
            ),
          ),
      ],
    );
  }

  Map<String, LatLng> _calculateBounds(List<LatLng> points) {
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

  Widget _buildScanDetailsCard() {
    final modelSizeMB = (widget.scan['metadata']['model_size_bytes'] / (1024 * 1024)).toStringAsFixed(1);
    final imageCount = widget.scan['metadata']['image_count'].toString();
    final duration = _formatDuration(widget.scan['metadata']['duration_seconds'] as double?);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scan-Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.insert_drive_file, 'File Size:', '$modelSizeMB MB'),
          _infoRow(Icons.image, 'Number of Images:', imageCount),
          _infoRow(Icons.timer, 'Scan Duration:', duration),
          _infoRow(Icons.open_in_full, 'Scan Area:', '10m'),
          _infoRow(Icons.height, 'Height:', '0.5m'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _linkedText('Deviation:'),
              _linkedText('Notes:'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _build3DViewCard() {
    final snapshotPath = widget.scan['snapshotPath'];
    final status = widget.scan['metadata']['status'] ?? 'pending';

    if (status != 'uploaded' || snapshotPath == null || !File(snapshotPath).existsSync()) {
      return GestureDetector(
        onTap: _previewUSDZ,
        child: Container(
          height: 250,
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: status == 'failed' ? Colors.red.withOpacity(0.2) : Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: status == 'failed' ? Colors.red : Colors.white12),
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: _isProcessing
                      ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blue), strokeWidth: 4)
                      : Icon(
                    status == 'failed' ? Icons.error : Icons.model_training,
                    color: status == 'failed' ? Colors.red : Colors.blue,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status == 'failed' ? 'Model Processing Failed' : 'Process 3D Model',
                        style: TextStyle(
                          color: status == 'failed' ? Colors.red : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: status == 'failed' ? Colors.redAccent : Colors.white70,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        height: 250,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(snapshotPath), width: double.infinity, fit: BoxFit.cover),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.blue,
                onPressed: _previewUSDZ,
                child: const Icon(Icons.fullscreen, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _statusIcons(String status) {
    switch (status) {
      case 'uploaded':
        return {'icons': [Icons.check_box, Icons.image], 'color': Colors.green};
      case 'failed':
        return {'icons': [Icons.error_outline, Icons.image_not_supported], 'color': Colors.red};
      case 'pending':
      default:
        return {'icons': [Icons.access_time, Icons.image], 'color': Colors.orange};
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

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white54),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _linkedText(String label) {
    return GestureDetector(
      onTap: () {},
      child: Text(label, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontSize: 14)),
    );
  }

  Widget _commentRow(String comment) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(comment, style: const TextStyle(color: Colors.white70, fontSize: 14))),
        TextButton(onPressed: () {}, child: const Text('View Pin →', style: TextStyle(color: Colors.blue))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawCoordinates = widget.scan['metadata']['coordinates'] as List<dynamic>?;
    final hasValidCoordinates = rawCoordinates != null &&
        rawCoordinates.isNotEmpty &&
        rawCoordinates.any((coord) => coord is List<dynamic> &&
            coord.length >= 2 &&
            double.tryParse(coord[0].toString()) != null &&
            double.tryParse(coord[1].toString()) != null &&
            double.tryParse(coord[0].toString()) != 0.0 &&
            double.tryParse(coord[1].toString()) != 0.0);

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        "PROJECT",
                        style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                        onSelected: (value) {
                          if (value == 'delete') _showDeleteConfirmationDialog();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.scan['metadata']['name'] ?? 'Unnamed Scan',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20, color: Colors.white60),
                            onPressed: _showEditNameDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatTimestamp(widget.scan['metadata']['timestamp']),
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_pin, color: Colors.white54, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              hasValidCoordinates
                                  ? (widget.scan['metadata']['location_name'] ?? 'Unknown Location')
                                  : 'No location data available',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.blue,
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(fontSize: 16),
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: '3D View'),
                    Tab(text: 'Images'),
                  ],
                ),
                Expanded(
                  child: IntrinsicHeight(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 300, child: _buildMap()),
                              const SizedBox(height: 16),
                              _buildScanDetailsCard(),
                            ],
                          ),
                        ),
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _build3DViewCard(),
                              const SizedBox(height: 16),
                              _buildScanDetailsCard(),
                            ],
                          ),
                        ),
                        imagePaths.isEmpty
                            ? const Center(
                          child: Text(
                            'No images to display',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        )
                            : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: GridView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                            itemCount: imagePaths.length,
                            itemBuilder: (context, index) => Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Image.file(
                                File(imagePaths[index]),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_isFullScreenMap)
              GestureDetector(
                onTap: () => setState(() => _isFullScreenMap = false),
                child: Container(
                  color: Colors.grey[900],
                  child: SafeArea(
                    child: Stack(
                      children: [
                        _buildMap(isFullScreen: true),
                        Positioned(
                          top: 16,
                          left: 16,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white, size: 30),
                            onPressed: () => setState(() => _isFullScreenMap = false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}