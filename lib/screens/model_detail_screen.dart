import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repository/scan_repository.dart';
import '../core/network/api_network.dart';
import '../core/network/api_urls.dart';
import '../models/scan_detail_model.dart';
import '../settings/providers/global_provider.dart';
import '../widgets/model_viewer.dart';
import '../core/errors/app_exceptions.dart';
import 'dashboard_screen.dart';

class ModelDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> scan;
  const ModelDetailScreen({super.key, required this.scan});
  @override
  ConsumerState<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends ConsumerState<ModelDetailScreen>
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
  String? _selectedTopViewImage;
  LatLng? _selectedMarkerPosition;
  late Timer _statusRefreshTimer;
  bool _isAutoRefreshing = false;
  ScanRepository? _scanRepository;
  ScanDetailModel? _apiScanDetail;
  bool _isLoadingApiData = false;
  bool _isFromAPI = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _scanRepository = ScanRepository(NetworkApiService());
    _isFromAPI = widget.scan['isFromAPI'] == true;
    _startAutoRefreshTimer();
    if (widget.scan['metadata'] == null) {
      widget.scan['metadata'] = <String, dynamic>{
        'scan_id': widget.scan['scanID'] ?? widget.scan['id'] ?? widget.scan['folderPath']?.split('/').last ?? 'unknown',
        'name': widget.scan['name'] ?? widget.scan['title'] ?? 'Unnamed Scan',
        'timestamp': widget.scan['timestamp'] ?? DateTime.now().toIso8601String(),
        'location_name': widget.scan['locationName'] ?? '',
        'coordinates': widget.scan['coordinates'] ?? [],
        'image_count': widget.scan['imageCount'] ?? 0,
        'model_size_bytes': widget.scan['modelSizeBytes'] ?? 0,
        'status': widget.scan['status'] ?? 'pending',
        'snapshot_path': widget.scan['snapshotPath'] ?? null,
        'duration_seconds': widget.scan['duration_seconds'] ?? 0.0,
      };
    }
    widget.scan['snapshotPath'] = widget.scan['snapshotPath'] ?? widget.scan['metadata']['snapshot_path'];
    _nameController = TextEditingController(text: widget.scan['metadata']['name'] ?? 'Unnamed Scan');
    if (_isFromAPI) {
      _loadApiScanData();
    } else {
      _fetchImagePaths();
      _syncStatusWithMetadata();
    }
    platform.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    _statusRefreshTimer.cancel();
    _tabController.dispose();
    _nameController.dispose();
    _mapController?.dispose();
    platform.setMethodCallHandler(null);
    super.dispose();
  }

  String _formatDuration(double? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) return '00:00';
    final int minutes = (durationSeconds / 60).floor();
    final int seconds = (durationSeconds % 60).round();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshScanStatus() async {
    if (_scanRepository == null || !mounted || _isAutoRefreshing) return;
    if (mounted) {
      setState(() {
        _isAutoRefreshing = true;
      });
    }
    try {
      final scanId = widget.scan['metadata']?['scan_id'] ?? widget.scan['id'];
      if (scanId is int || (scanId is String && int.tryParse(scanId) != null)) {
        final scanIdInt = scanId is int ? scanId : int.parse(scanId);
        final apiScanDetail = await _scanRepository!.getScanDetail(scanIdInt);
        if (mounted) {
          setState(() {
            _apiScanDetail = apiScanDetail;
            _status = apiScanDetail.status;
            _statusMessage = _getApiStatusMessage(apiScanDetail.status);
            _isAutoRefreshing = false;
          });
          _updateScanMetadataFromApi(apiScanDetail);
          if (_status == 'completed' || _status == 'failed' || _status == 'uploaded') {
            _statusRefreshTimer.cancel();
            if (_status == 'completed') {
              _tabController.animateTo(0); // Switch to 3D View tab
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAutoRefreshing = false;
          _errorDetails = e.toString();
        });
      }
    }
  }

  void _startAutoRefreshTimer() {
    if (_isFromAPI) {
      _statusRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_status != 'completed' && _status != 'failed' && _status != 'uploaded') {
          await _refreshScanStatus();
        } else {
          timer.cancel();
        }
      });
    }
  }

  double _parseDurationSeconds(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Future<void> _loadApiScanData() async {
    if (_scanRepository == null) return;
    if (mounted) {
      setState(() {
        _isLoadingApiData = true;
      });
    }
    try {
      final scanId = widget.scan['metadata']?['scan_id'] ?? widget.scan['id'];
      if (scanId is int || (scanId is String && int.tryParse(scanId) != null)) {
        final scanIdInt = scanId is int ? scanId : int.parse(scanId);
        final apiScanDetail = await _scanRepository!.getScanDetail(scanIdInt);
        if (mounted) {
          setState(() {
            _apiScanDetail = apiScanDetail;
            _status = apiScanDetail.status;
            _statusMessage = _getApiStatusMessage(apiScanDetail.status);
            _nameController.text = apiScanDetail.title;
            _isLoadingApiData = false;
          });
          _updateScanMetadataFromApi(apiScanDetail);
          if (_status == 'completed') {
            _tabController.animateTo(0); // Switch to 3D View tab
          }
        }
      } else {
        throw Exception('Invalid scan ID: $scanId');
      }
    } catch (e) {
      print('Error loading API scan data: $e');
      if (mounted) {
        setState(() {
          _isLoadingApiData = false;
          _errorDetails = e.toString();
          _statusMessage = 'Failed to load scan details from server.';
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load scan details: ${e.toString()}', style: const TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  void _updateScanMetadataFromApi(ScanDetailModel apiData) {
    final coordinates = apiData.gpsPoints.map((gps) => [gps.latitude, gps.longitude]).toList();
    final dataSizeMb = apiData.dataSizeMb;
    final modelSizeBytes = (dataSizeMb * 1024 * 1024).toInt();
    if (mounted) {
      setState(() {
        widget.scan['metadata'] = {
          ...widget.scan['metadata'],
          'scan_id': apiData.id,
          'name': apiData.title,
          'description': apiData.description,
          'duration_seconds': apiData.duration,
          'area_covered': apiData.areaCovered,
          'height': apiData.height,
          'model_size_bytes': modelSizeBytes,
          'coordinates': coordinates,
          'image_count': apiData.totalImages,
          'status': apiData.status,
          'created_at': apiData.createdAt,
          'updated_at': apiData.updatedAt,
        };
        _status = apiData.status;
        _statusMessage = _getApiStatusMessage(apiData.status);
      });
    }
  }

  String _getApiStatusMessage(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Scan completed and available for viewing';
      case 'processing':
        return 'Scan is being processed on the server. This may take several minutes.';
      case 'uploaded':
        return 'Scan uploaded successfully';
      case 'failed':
        return 'SScan processing failed Kindly Scan Properly and Try again.';
      case 'pending':
      default:
        return 'Scan is pending processing';
    }
  }

  Future<void> _syncStatusWithMetadata() async {
    try {
      final folderPath = widget.scan['folderPath']?.toString();
      if (folderPath == null) throw Exception('Invalid folder path');
      final metadataResult = await platform.invokeMethod('getScanMetadata', {'folderPath': folderPath});
      final metadata = (metadataResult as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? widget.scan['metadata'];
      final status = metadata['status']?.toString() ?? 'pending';
      final hasUsdz = metadata['hasUSDZ'] == true;
      if (mounted) {
        setState(() {
          widget.scan['metadata'] = <String, dynamic>{
            ...widget.scan['metadata'],
            ...metadata,
          };
          _status = status;
          _statusMessage = _getStatusMessage(status);
          widget.scan['usdzPath'] = hasUsdz ? '$folderPath/model.usdz' : null;
        });
      }
      if (hasUsdz && status != 'uploaded') {
        await platform.invokeMethod('updateScanStatus', {'folderPath': folderPath, 'status': 'uploaded'});
        if (mounted) {
          setState(() {
            _status = 'uploaded';
            _statusMessage = 'Tap to view 3D model';
            widget.scan['metadata']['status'] = 'uploaded';
            widget.scan['usdzPath'] = '$folderPath/model.usdz';
            _tabController.animateTo(0); // Switch to 3D View tab
          });
        }
      }
    } catch (e) {
      print('Error syncing status: $e');
      if (mounted) {
        setState(() {
          _status = 'pending';
          _statusMessage = 'Data has not been processed. Tap to process the model.';
          _errorDetails = e.toString();
        });
      }
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
        if (mounted) {
          setState(() {
            imagePaths = List<String>.from(result.map((e) => e.toString()));
          });
        }
      } else {
        if (mounted) {
          setState(() {
            imagePaths = [];
          });
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          imagePaths = [];
        });
      }
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'processingComplete') {
      final folderPath = call.arguments['usdzPath']?.toString();
      if (folderPath != null && folderPath.contains(widget.scan['folderPath'])) {
        if (mounted) {
          setState(() {
            _status = 'uploaded';
            _statusMessage = 'Tap to view 3D model';
            _isProcessing = false;
            widget.scan['metadata']['status'] = 'uploaded';
            widget.scan['usdzPath'] = call.arguments['usdzPath'];
            if (call.arguments['snapshotPath'] != null) {
              widget.scan['snapshotPath'] = call.arguments['snapshotPath'];
            }
            _tabController.animateTo(0); // Switch to 3D View tab
          });
        }
      }
    } else if (call.method == 'scanComplete') {
      final folderPath = call.arguments['folderPath']?.toString();
      if (folderPath != null && folderPath == widget.scan['folderPath']) {
        if (mounted) {
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
      }
    } else if (call.method == 'updateProcessingStatus') {
      final status = call.arguments['status']?.toString() ?? 'processing';
      if (mounted) {
        setState(() {
          _isProcessing = true;
          _statusMessage = _getProcessingStatusMessage(status);
        });
      }
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
    if (_isProcessing || !mounted) return;
    final networkState = ref.read(networkStateProvider);
    if (!networkState.isOnline && _status != 'uploaded') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('For processing, you need to connect to the internet.', style: TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    if (_status == 'uploaded' && widget.scan['usdzPath'] != null) {
      try {
        await platform.invokeMethod('openUSDZ', {'path': widget.scan['usdzPath']});
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Couldn\'t open the 3D model. Please try again.', style: TextStyle(color: Colors.white, fontSize: 14)),
              backgroundColor: Colors.red[800],
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      try {
        await _processModel();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('For processing, you need to connect to the internet.', style: TextStyle(color: Colors.white, fontSize: 14)),
              backgroundColor: Colors.red[800],
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _processModel() async {
    if (_isProcessing) return;
    final status = widget.scan['metadata']['status'] ?? 'pending';
    final isApiScan = _isFromAPI || widget.scan['isFromAPI'] == true;
    if (isApiScan) {
      await _processModelOnServer();
    } else {
      await _processModelLocally();
    }
  }

  Future<void> _processModelOnServer() async {
    if (!mounted) return;
    if (mounted) {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Starting server processing...';
        _errorDetails = null;
      });
    }
    try {
      final scanIdStr = widget.scan['metadata']['id'] ?? widget.scan['metadata']['scan_id'] ?? widget.scan['id'];
      int scanId;
      if (scanIdStr is int) {
        scanId = scanIdStr;
      } else if (scanIdStr is String) {
        scanId = int.tryParse(scanIdStr) ?? 0;
      } else {
        throw PlatformException(code: 'INVALID_SCAN_ID', message: 'Invalid scan ID: $scanIdStr');
      }
      if (scanId == 0) {
        throw PlatformException(code: 'INVALID_SCAN_ID', message: 'Scan ID is required for server processing');
      }
      double fileSizeMB;
      if (_apiScanDetail?.dataSizeMb != null) {
        fileSizeMB = _apiScanDetail!.dataSizeMb;
      } else {
        final modelSizeBytes = widget.scan['metadata']['model_size_bytes'] ?? 0;
        fileSizeMB = (modelSizeBytes / (1024 * 1024));
      }
      final estimatedMinutes = (fileSizeMB / 50.0) * 2.0;
      final estimatedTimeText = estimatedMinutes.toStringAsFixed(1);
      if (mounted) {
        setState(() {
          _statusMessage = 'Sending processing request to server...\nEstimated time: ~$estimatedTimeText minutes';
        });
      }
      final result = await platform.invokeMethod('processModelOnServer', {
        'scanId': scanId,
      });
      if (result['success'] == true && mounted) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _status = 'processing';
            _statusMessage = 'Processing started on server.';
            widget.scan['metadata']['status'] = 'processing';
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Processing started successfully!', style: const TextStyle(color: Colors.white, fontSize: 14)),
              backgroundColor: Colors.green[800],
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw PlatformException(code: 'PROCESSING_FAILED', message: result['message'] ?? 'Failed to start server processing');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'failed';
          _statusMessage = 'Scan processing failed Kindly Scan Properly and Try again.';
          _errorDetails = e.message;
          widget.scan['metadata']['status'] = 'failed';
        });
      }
    }
  }

  Future<void> _processModelLocally() async {
    if (mounted) {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Processing model...';
        _errorDetails = null;
      });
    }
    try {
      final folderPath = widget.scan['folderPath']?.toString();
      if (folderPath == null) {
        throw PlatformException(code: 'INVALID_PATH', message: 'Invalid folder path');
      }
      final zipSizeResult = await platform.invokeMethod('getZipSize', {'folderPath': folderPath});
      final zipSizeMB = (zipSizeResult['zipSizeBytes'] as num) / (1024 * 1024);
      final estimatedMinutes = (zipSizeMB / 50.0) * 2.0;
      final estimatedTimeText = estimatedMinutes.toStringAsFixed(1);
      if (mounted) {
        setState(() {
          _statusMessage = 'Processing model (~$estimatedTimeText minutes)...';
        });
      }
      final result = await platform.invokeMethod('processScan', {'folderPath': folderPath});
      if (mounted) {
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
          _tabController.animateTo(0); // Switch to 3D View tab
        });
      }
      await platform.invokeMethod('updateScanStatus', {'folderPath': folderPath, 'status': 'uploaded'});
    } on PlatformException catch (e) {
      String errorMessage = "Couldn't process the model. Please try again.";
      if (e.code == 'API_STATUS_ERROR' || e.code == 'API_REQUEST_FAILED') {
        errorMessage = "Couldn't process the model. Please check your internet connection and try again.";
      } else if (e.code == 'INVALID_ZIP_DATA') {
        errorMessage = 'Scan data is incomplete. Please try scanning again.';
      } else if (e.code == 'CAMERA_PERMISSION_DENIED') {
        errorMessage = 'Camera access denied. Please enable camera permissions in Settings.';
      } else if (e.code == 'AR_SESSION_ERROR') {
        errorMessage = 'Unable to start scan. Please try again in a well-lit area.';
      } else if (e.code == 'SERVER_UNAVAILABLE') {
        errorMessage = 'Server is unavailable. Please try again later.';
      }
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'failed';
          _statusMessage = 'Model processing failed: $errorMessage Tap to retry.';
          _errorDetails = e.message;
          widget.scan['metadata']['status'] = 'failed';
        });
      }
      await platform.invokeMethod('updateScanStatus', {'folderPath': widget.scan['folderPath'], 'status': 'failed'});
      if (mounted) {
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
  }

  Future<void> _deleteModel() async {
    try {
      final folderPath = widget.scan['folderPath']?.toString();
      final scanId = widget.scan['metadata']['scan_id'] ?? widget.scan['id'];
      bool deleteSuccess = true;
      if (_isFromAPI && scanId != null) {
        final scanIdInt = scanId is int ? scanId : int.tryParse(scanId.toString()) ?? 0;
        if (scanIdInt > 0) {
          bool? isDeleted = await _scanRepository?.deleteScan(scanId);
          if (isDeleted != true) {
            deleteSuccess = false;
          }
        } else {
          deleteSuccess = false;
        }
      }
      if (folderPath != null && folderPath.isNotEmpty) {
        final result = await platform.invokeMethod('deleteScan', {'path': folderPath});
        if (result != 'Scan deleted successfully' && result != true) {
          deleteSuccess = false;
          throw PlatformException(code: 'DELETE_FAILED', message: 'Local deletion failed: $result');
        }
      }
      if (deleteSuccess) {
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
        throw Exception('Deletion partially failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t delete the model: $e', style: const TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }
  }

  Future<void> _downloadZipFile() async {
    try {
      if (_isFromAPI && widget.scan['id'] != null) {
        final scanIdInt = widget.scan['id'] is int ? widget.scan['id'] : int.tryParse(widget.scan['id'].toString()) ?? 0;
        if (scanIdInt > 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Zip file downloaded successfully to temporary storage', style: TextStyle(color: Colors.white, fontSize: 14)),
                backgroundColor: Colors.black87,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          }
        } else {
          throw Exception('Invalid scan ID for API download');
        }
      } else {
        final folderPath = widget.scan['folderPath']?.toString();
        if (folderPath == null || folderPath.isEmpty) {
          throw Exception('Folder path is null or empty');
        }
        final result = await platform.invokeMethod('downloadZipFile', {'folderPath': folderPath});
        if (result != 'Zip file downloaded successfully' && result != true) {
          throw Exception('Local download failed: $result');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Zip file downloaded successfully', style: TextStyle(color: Colors.white, fontSize: 14)),
              backgroundColor: Colors.black87,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t download the zip file: $e', style: const TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
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
                if (mounted) {
                  setState(() {
                    widget.scan['metadata']['name'] = newName;
                  });
                }
                Navigator.pop(context);
              } on PlatformException catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Couldn’t update the project name. Please try again.', style: TextStyle(color: Colors.white, fontSize: 14)),
                      backgroundColor: Colors.red[800],
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                }
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
      }
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
        onTap: () {
          final topViewImage = _apiScanDetail?.pointCloud?.topViewImage;
          if (topViewImage != null && topViewImage.isNotEmpty) {
            if (mounted) {
              setState(() {
                _selectedTopViewImage = topViewImage;
                _selectedMarkerPosition = points.first;
              });
            }
          }
        },
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
                if (mounted) {
                  setState(() {
                    _isFullScreenMap = true;
                  });
                }
              },
              child: const Icon(Icons.fullscreen, size: 20),
            ),
          ),
        if (_selectedTopViewImage != null && _selectedMarkerPosition != null)
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: () {
                if (mounted) {
                  setState(() {
                    _selectedTopViewImage = null;
                    _selectedMarkerPosition = null;
                  });
                }
              },
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    _selectedTopViewImage!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.error,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
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
    String modelSizeMB;
    if (_apiScanDetail?.dataSizeMb != null) {
      final dataSizeMb = _apiScanDetail!.dataSizeMb;
      modelSizeMB = dataSizeMb.toStringAsFixed(1);
    } else {
      final modelSizeBytes = widget.scan['metadata']['model_size_bytes'] ?? 0;
      final sizeMB = (modelSizeBytes / (1024 * 1024));
      modelSizeMB = sizeMB.toStringAsFixed(1);
    }
    final imageCount = _apiScanDetail?.totalImages.toString() ?? widget.scan['metadata']['image_count']?.toString() ?? '0';
    String duration;
    if (_apiScanDetail?.duration != null) {
      final durationSeconds = _apiScanDetail!.duration.toDouble();
      duration = _formatDuration(durationSeconds);
    } else {
      final durationSecondsValue = _parseDurationSeconds(widget.scan['metadata']['duration_seconds']);
      duration = _formatDuration(durationSecondsValue);
    }
    String areaCovered;
    String height;
    if (_apiScanDetail?.areaCovered != null) {
      areaCovered = _apiScanDetail!.areaCovered.toStringAsFixed(1);
    } else {
      areaCovered = '0.0';
    }
    if (_apiScanDetail?.height != null) {
      height = _apiScanDetail!.height.toStringAsFixed(2);
    } else {
      height = '0.0';
    }
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
          _infoRow(Icons.open_in_full, 'Scan Area:', '${areaCovered}m²'),
          _infoRow(Icons.height, 'Height:', '${height}m'),
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
    final networkState = ref.read(networkStateProvider);
    final isOnline = networkState.isOnline;
    final status = widget.scan['metadata']['status'] ?? 'pending';
    final isApiScan = _isFromAPI || widget.scan['isFromAPI'] == true;

    // Offline mode
    if (!isOnline && status != 'uploaded') {
      return Container(
        height: 250,
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 48),
              SizedBox(height: 16),
              Text('Offline Mode', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Connect to the internet to process and view 3D models.', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    // API scan with completed status
    final processedModelUrl = _apiScanDetail?.pointCloud?.processedModel;
    final hasProcessedModel = processedModelUrl != null && processedModelUrl.isNotEmpty;
    if (isApiScan && status == 'completed' && hasProcessedModel) {
      final scanId = widget.scan['metadata']['id'].toString();
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ModelViewerScreen(
                modelUrl: processedModelUrl,
                modelName: widget.scan['metadata']['name'] ?? 'Unnamed Scan',
                scanId: scanId,
              ),
            ),
          );
        },
        child: Container(
          height: 250,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.view_in_ar, color: Colors.green, size: 50),
                SizedBox(height: 16),
                Text('3D Model Ready', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Tap to view processed model', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    // Local scan with uploaded status
    final snapshotPath = widget.scan['snapshotPath'];
    if (status == 'uploaded' && snapshotPath != null && File(snapshotPath).existsSync()) {
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

    // Failed API or local scan
    if (status == 'failed') {
      return GestureDetector(
        onTap: _previewUSDZ,
        child: Container(
          height: 250,
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3), width: 1),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 50),
                const SizedBox(height: 16),
                const Text('Processing Failed', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_statusMessage, style: const TextStyle(color: Colors.redAccent, fontSize: 14), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _previewUSDZ,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[800],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry Processing'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Processing or pending states for API and local scans
    final double fileSizeMB;
    if (_apiScanDetail?.dataSizeMb != null) {
      fileSizeMB = _apiScanDetail!.dataSizeMb;
    } else {
      final modelSizeBytes = widget.scan['metadata']['model_size_bytes'] ?? 0;
      fileSizeMB = (modelSizeBytes / (1024 * 1024));
    }
    final estimatedMinutes = (fileSizeMB / 50.0) * 2.0;
    final estimatedTimeText = estimatedMinutes.toStringAsFixed(1);
    return GestureDetector(
      onTap: status == 'pending' ? _previewUSDZ : null,
      child: Container(
        height: 250,
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: _isProcessing || status == 'processing'
                    ? CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  strokeWidth: 4,
                )
                    : const Icon(Icons.model_training, color: Colors.blue, size: 50),
              ),
              const SizedBox(height: 16),
              Text(
                status == 'processing' ? 'Processing in Progress' : 'Process 3D Model',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                status == 'processing'
                    ? 'Estimated time: ~$estimatedTimeText minutes\n$_statusMessage'
                    : _statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (status == 'processing' && isApiScan)
                ElevatedButton(
                  onPressed: _refreshScanStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Refresh Status'),
                ),
            ],
          ),
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

  Widget _buildImagesTab() {
    if (_isLoadingApiData) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }
    if (_isFromAPI && _apiScanDetail != null) {
      final apiImages = _apiScanDetail!.images;
      if (apiImages.isEmpty) {
        return const Center(
          child: Text(
            'No images available',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GridView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: apiImages.length,
          itemBuilder: (context, index) => Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                apiImages[index].image,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.error,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      if (imagePaths.isEmpty) {
        return const Center(
          child: Text(
            'No images to display',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        );
      }
      return Padding(
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
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print("WIDGET SCAN ........... ${widget.scan.toString()}");
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
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                      const Text(
                        "PROJECT",
                        style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteConfirmationDialog();
                          } else if (value == 'download') {
                            _downloadZipFile();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'download',
                            child: Text('Download Zip', style: TextStyle(color: Colors.blue)),
                          ),
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
                        widget.scan['metadata']['scan_id']?.toString() ?? 'Unknown ID',
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
                        _buildImagesTab(),
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
                            onPressed: () {
                              if (mounted) {
                                setState(() => _isFullScreenMap = false);
                              }
                            },
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