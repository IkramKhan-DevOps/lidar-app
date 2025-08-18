import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

class ModelViewerScreen extends StatefulWidget {
  final String modelUrl;
  final String modelName;
  final String scanId;

  const ModelViewerScreen({
    super.key,
    required this.modelUrl,
    required this.modelName,
    required this.scanId,
  });

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen> {
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  bool isUsdz = false;
  String? localFilePath;
  double downloadProgress = 0;
  bool isDownloading = false;
  int? fileSizeBytes;
  DateTime? downloadTime;
  static const platform = MethodChannel('com.demo.channel/message');

  @override
  void initState() {
    super.initState();
    isUsdz = widget.modelUrl.toLowerCase().endsWith('.usdz');
    _checkLocalModel();
  }

  Future<void> _checkLocalModel() async {
    setState(() => isLoading = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/models/${widget.scanId}');

      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final fileName = widget.modelUrl.split('/').last;
      final localFile = File('${modelDir.path}/$fileName');

      if (await localFile.exists()) {
        final stat = await localFile.stat();
        setState(() {
          localFilePath = localFile.path;
          fileSizeBytes = stat.size;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('Local model check failed: $e');
      setState(() {
        hasError = true;
        isLoading = false;
        errorMessage = 'Failed to check local storage: $e';
      });
    }
  }

  Future<void> _downloadModel() async {
    if (!isUsdz) return;

    setState(() {
      isDownloading = true;
      downloadProgress = 0;
      fileSizeBytes = null;
      downloadTime = null;
    });

    try {
      if (!await _requestStoragePermission()) {
        throw Exception('Storage permission denied');
      }

      final appDir = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${appDir.path}/models/${widget.scanId}');

      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final fileName = widget.modelUrl.split('/').last;
      final file = File('${modelDir.path}/$fileName');

      final response = await http.Client().send(
          http.Request('GET', Uri.parse(widget.modelUrl))
      );

      final contentLength = response.contentLength ?? 0;
      final bytes = <int>[];

      await for (var chunk in response.stream) {
        bytes.addAll(chunk);
        setState(() {
          downloadProgress = bytes.length / contentLength;
        });
      }

      await file.writeAsBytes(bytes);
      final stat = await file.stat();

      setState(() {
        localFilePath = file.path;
        fileSizeBytes = stat.size;
        downloadTime = DateTime.now();
        isDownloading = false;
      });

    } catch (e) {
      print('Model download failed: $e');
      setState(() {
        isDownloading = false;
        hasError = true;
        errorMessage = 'Download failed: $e';
      });
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> _launchARViewer() async {
    if (!Platform.isIOS || localFilePath == null) return;

    setState(() => isLoading = true);

    try {
      await platform.invokeMethod('openUSDZ', {'path': localFilePath});
    } catch (e) {
      print('AR launch failed: $e');
      setState(() {
        hasError = true;
        errorMessage = 'Failed to launch AR: $e';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _deleteLocalModel() async {
    if (localFilePath == null) return;

    setState(() => isLoading = true);

    try {
      final file = File(localFilePath!);
      if (await file.exists()) {
        await file.delete();
      }
      setState(() {
        localFilePath = null;
        fileSizeBytes = null;
        downloadTime = null;
      });
    } catch (e) {
      print('Failed to delete model: $e');
      setState(() {
        hasError = true;
        errorMessage = 'Failed to delete model: $e';
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  Widget _buildDownloadInfoCard() {
    if (localFilePath == null || fileSizeBytes == null) return const SizedBox();

    final fileSizeMB = (fileSizeBytes! / (1024 * 1024)).toStringAsFixed(2);
    final formattedTime = downloadTime != null
        ? DateFormat('MMM dd, yyyy - hh:mm a').format(downloadTime!)
        : 'Unknown';

    return Positioned(
      top: 16,
      right: 16,
      child: Card(
        color: Colors.black.withOpacity(0.7),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.blue.shade700, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Model Info',
                style: TextStyle(
                  color: Colors.blue.shade300,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Size: $fileSizeMB MB',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Downloaded'
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Card(
          color: Colors.black.withOpacity(0.7),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.blue.shade700, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Download Required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The model will be downloaded in approx 0.5 - 5 minutes\nRequired for AR viewing',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: isDownloading ? null : _downloadModel,
                  icon: const Icon(Icons.download),
                  label: const Text('Download Model'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isDownloading) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.7,
            child: LinearProgressIndicator(
              value: downloadProgress,
              backgroundColor: Colors.grey[800],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(downloadProgress * 100).toStringAsFixed(1)}%',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ],
    );
  }

  Widget _buildARControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton.icon(
          onPressed: _launchARViewer,
          icon: const Icon(Icons.view_in_ar),
          label: const Text('Launch AR Quick Look'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _deleteLocalModel,
          icon: const Icon(Icons.delete, color: Colors.red),
          label: const Text(
            'Delete Local Copy',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  Widget _buildModelViewer() {
    if (isUsdz) {
      return Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Colors.black,
                ],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.view_in_ar,
                      color: Colors.blue,
                      size: 80,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.modelName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (localFilePath != null) _buildARControls(),
                    if (localFilePath == null) _buildDownloadButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
          _buildDownloadInfoCard(),
        ],
      );
    }

    return ModelViewer(
      backgroundColor: const Color.fromARGB(0xFF, 0x1A, 0x1A, 0x1A),
      src: widget.modelUrl,
      alt: "3D Model of ${widget.modelName}",
      ar: false,
      autoRotate: true,
      cameraControls: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.modelName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (localFilePath != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _deleteLocalModel,
              tooltip: 'Delete Model',
            ),
        ],
      ),
      body: Stack(
        children: [
          if (!isLoading && !hasError) _buildModelViewer(),
          if (isLoading) const Center(child: CircularProgressIndicator()),
          if (hasError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage ?? 'Error loading model',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _checkLocalModel,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}