import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class ModelViewerScreen extends StatefulWidget {
  final String modelUrl;
  final String modelName;

  const ModelViewerScreen({
    super.key,
    required this.modelUrl,
    required this.modelName,
  });

  @override
  State<ModelViewerScreen> createState() => _ModelViewerScreenState();
}

class _ModelViewerScreenState extends State<ModelViewerScreen> {
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  bool isUsdz = false;
  bool isModelAccessible = false;
  String? localFilePath;
  static const platform = MethodChannel('com.demo.channel/message');

  @override
  void initState() {
    super.initState();
    print('Model URL: ${widget.modelUrl}');
    isUsdz = widget.modelUrl.toLowerCase().endsWith('.usdz');
    _checkModelAccessibility();
  }

  Future<void> _checkModelAccessibility() async {
    setState(() => isLoading = true);
    try {
      if (widget.modelUrl.startsWith('file://')) {
        final file = File(widget.modelUrl.replaceFirst('file://', ''));
        if (await file.exists()) {
          localFilePath = file.path;
          setState(() {
            isModelAccessible = true;
            isLoading = false;
          });
        } else {
          throw Exception('Local USDZ file not found');
        }
      } else {
        final response = await http.head(Uri.parse(widget.modelUrl));
        if (response.statusCode == 200) {
          setState(() {
            isModelAccessible = true;
            isLoading = false;
          });
        } else {
          throw Exception('HTTP ${response.statusCode}: Unable to access model');
        }
      }
    } catch (e) {
      print('Model accessibility check failed: $e');
      setState(() {
        hasError = true;
        isLoading = false;
        errorMessage = 'Unable to access model: $e';
      });
    }
  }

  Future<void> _downloadAndLaunchUsdz() async {
    if (!Platform.isIOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('USDZ files are only supported on iOS devices'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      if (localFilePath == null && !widget.modelUrl.startsWith('file://')) {
        final response = await http.get(Uri.parse(widget.modelUrl));
        if (response.statusCode == 200) {
          final documentsDir = await getApplicationDocumentsDirectory();
          final fileName = widget.modelUrl.split('/').last;
          final file = File('${documentsDir.path}/$fileName');
          await file.writeAsBytes(response.bodyBytes);
          localFilePath = file.path;
          print('USDZ file downloaded to: $localFilePath');
        } else {
          throw Exception('Failed to download USDZ file: HTTP ${response.statusCode}');
        }
      } else if (widget.modelUrl.startsWith('file://')) {
        localFilePath = widget.modelUrl.replaceFirst('file://', '');
      }

      await platform.invokeMethod('openUSDZ', {'path': localFilePath});
      setState(() => isLoading = false);
    } catch (e) {
      print('USDZ handling error: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'Failed to open AR viewer: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open AR viewer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _resetViewer() {
    setState(() {
      isLoading = true;
      hasError = false;
      errorMessage = null;
      isModelAccessible = false;
      localFilePath = null;
    });
    _checkModelAccessibility();
  }

  void _showModelInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Model Information',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name:', widget.modelName),
            _buildInfoRow('URL:', widget.modelUrl),
            _buildInfoRow('Format:', isUsdz ? 'USDZ' : 'Other'),
            _buildInfoRow('Platform:', Platform.operatingSystem),
            _buildInfoRow('Accessible:', isModelAccessible ? 'Yes' : 'No'),
            if (localFilePath != null) _buildInfoRow('Local Path:', localFilePath!),
            _buildInfoRow('Direct AR Launch:', Platform.isIOS && isUsdz ? 'Supported' : 'Not Available'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  Widget _buildModelInfoOverlay() {
    return Positioned(
      top: 20,
      left: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.modelName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isUsdz ? 'USDZ Model' : '3D Model',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            if (localFilePath != null)
              Text(
                'Ready for AR Quick Look',
                style: TextStyle(
                  color: Colors.green.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            icon: Icons.refresh,
            label: 'Reset',
            onPressed: _resetViewer,
          ),
          const SizedBox(width: 12),
          if (isUsdz)
            _buildControlButton(
              icon: Icons.view_in_ar,
              label: Platform.isIOS ? 'AR Quick Look' : 'AR (iOS Only)',
              onPressed: Platform.isIOS ? _downloadAndLaunchUsdz : null,
              isPrimary: Platform.isIOS,
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    if (isUsdz && isModelAccessible && !hasError) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.view_in_ar,
              color: hasError ? Colors.red : Colors.blue,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              hasError ? 'Failed to Load Model' : 'Model Loading Error',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                errorMessage ?? 'Unknown error occurred',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _resetViewer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 16),
            Text(
              isUsdz ? 'Preparing for AR Quick Look...' : 'Checking model accessibility...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (isUsdz)
              const Text(
                'Downloading and setting up direct AR launch...',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              )
            else
              Text(
                widget.modelUrl,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isPrimary ? Colors.blue.withOpacity(0.8) : Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPrimary ? Colors.blue : Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: onPressed != null ? Colors.white : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: onPressed != null ? Colors.white : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelViewer() {
    if (isUsdz) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.view_in_ar,
                color: Colors.blue,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'USDZ Model Ready',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the button below to launch in AR Quick Look.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _downloadAndLaunchUsdz,
                icon: const Icon(Icons.view_in_ar),
                label: const Text('Launch AR Quick Look'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ModelViewer(
      backgroundColor: const Color.fromARGB(0xFF, 0x1A, 0x1A, 0x1A),
      src: widget.modelUrl,
      alt: "3D Model of ${widget.modelName}",
      ar: false,
      autoRotate: true,
      cameraControls: true,
      disableZoom: false,
      loading: Loading.eager,
      onWebViewCreated: (controller) {
        print('ModelViewer WebView created');
      },
    );
  }

  @override
  void dispose() {
    if (localFilePath != null && !widget.modelUrl.startsWith('file://')) {
      File(localFilePath!).delete().catchError((e) => print('Failed to delete temp file: $e'));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.modelName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (isUsdz)
            IconButton(
              icon: const Icon(Icons.view_in_ar, color: Colors.white),
              onPressed: _downloadAndLaunchUsdz,
              tooltip: 'Open in AR Quick Look',
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _resetViewer,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: _showModelInfo,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (isModelAccessible && !hasError && !isLoading) _buildModelViewer(),
          if (isModelAccessible && !hasError && !isLoading) _buildModelInfoOverlay(),
          if (isModelAccessible && !hasError && !isLoading) _buildControlButtons(),
          if (hasError) _buildErrorState(),
          if (isLoading) _buildLoadingState(),
        ],
      ),
    );
  }
}