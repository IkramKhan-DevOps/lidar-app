import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class GeoTiffDownloadScreen extends ConsumerStatefulWidget {
  final String downloadUrl;
  final String fileName;
  final String scanName;

  const GeoTiffDownloadScreen({
    super.key,
    required this.downloadUrl,
    required this.fileName,
    required this.scanName,
  });

  @override
  ConsumerState<GeoTiffDownloadScreen> createState() => _GeoTiffDownloadScreenState();
}

class _GeoTiffDownloadScreenState extends ConsumerState<GeoTiffDownloadScreen> {
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isPreparing = true;
  bool _isComplete = false;
  bool _hasError = false;
  String _errorMessage = '';
  String _filePath = '';
  CancelToken? _cancelToken;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      try {
        _cancelToken?.cancel('User navigated away');
      } catch (e) {
        print('Error cancelling download token: $e');
      }
    }
    super.dispose();
  }

  Future<void> _startDownload() async {
    final Dio dio = Dio();
    _cancelToken = CancelToken();

    int retryCount = 0;
    const maxRetries = 24; // 2 minutes with 5 sec delay
    const delaySeconds = 5;

    if (mounted && !_isDisposed) {
      setState(() {
        _isPreparing = true;
      });
    }

    while (mounted && !_isDisposed && retryCount <= maxRetries) {
      try {
        if (retryCount > 0) {
          await Future.delayed(const Duration(seconds: delaySeconds));
        }

        // Check with HEAD request
        final headResponse = await dio.head(
          widget.downloadUrl,
          cancelToken: _cancelToken,
        );

        if (headResponse.statusCode == 200) {
          // File is ready, start download
          if (mounted && !_isDisposed) {
            setState(() {
              _isPreparing = false;
              _isDownloading = true;
            });
          }

          final Directory downloadsDirectory = await getApplicationDocumentsDirectory();
          final String downloadsPath = '${downloadsDirectory.path}/Downloads';
          final Directory downloadsDir = Directory(downloadsPath);
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }

          final String savePath = '$downloadsPath/${widget.fileName}';

          await dio.download(
            widget.downloadUrl,
            savePath,
            cancelToken: _cancelToken,
            onReceiveProgress: (received, total) {
              if (_isDisposed || !mounted) return;
              if (total != -1) {
                setState(() {
                  _downloadProgress = received / total;
                });
              }
            },
          );

          if (_isDisposed || !mounted) return;

          setState(() {
            _isDownloading = false;
            _isComplete = true;
            _filePath = savePath;
          });

          return; // Success
        } else {
          // Handle non-200 status codes
          throw DioException.badResponse(
            statusCode: headResponse.statusCode ?? 503, // Fallback to 503 if null
            requestOptions: headResponse.requestOptions,
            response: headResponse,
          );
        }
      } catch (e) {
        if (_isDisposed) return;

        if (e is DioException) {
          if (e.type == DioExceptionType.cancel) {
            if (mounted) {
              Navigator.of(context).pop(false);
            }
            return;
          }

          if (e.response?.statusCode == 404 || e.response?.statusCode == 403) {
            retryCount++;
            if (retryCount > maxRetries) {
              if (mounted) {
                setState(() {
                  _isPreparing = false;
                  _hasError = true;
                  _errorMessage = 'File preparation timed out. Please try again later.';
                });
              }
              return;
            }
            // Continue to retry
            continue;
          }
        }

        // Other errors
        if (mounted && !_isDisposed) {
          setState(() {
            _isPreparing = false;
            _isDownloading = false;
            _hasError = true;
            _errorMessage = e.toString().contains('SocketException')
                ? 'Network error. Please check your internet connection.'
                : 'Download failed: ${e.toString()}';
          });
        }
        return;
      }
    }
  }
  void _cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      try {
        _cancelToken?.cancel('User cancelled download');
      } catch (e) {
        print('Error cancelling download: $e');
      }
    }
    if (mounted && !_isDisposed) {
      Navigator.of(context).pop(false);
    }
  }

  void _openFile() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'GeoTIFF downloaded successfully!',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );

    if (mounted && !_isDisposed) {
      Navigator.of(context).pop(true);
    }
  }

  void _retryDownload() {
    if (mounted && !_isDisposed) {
      setState(() {
        _hasError = false;
        _errorMessage = '';
        _downloadProgress = 0.0;
        _isPreparing = true;
      });
    }
    _startDownload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: (_isDownloading || _isPreparing) ? _cancelDownload : () => Navigator.of(context).pop(_isComplete),
        ),
        title: const Text(
          'Download GeoTIFF',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Header
            Column(
              children: [
                Icon(
                  _hasError ? Icons.error_outline :
                  _isComplete ? Icons.check_circle :
                  _isDownloading ? Icons.download :
                  Icons.hourglass_bottom,
                  color: _hasError ? Colors.red :
                  _isComplete ? Colors.green :
                  _isDownloading ? Colors.blue : Colors.blue,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  _hasError ? 'Download Failed' :
                  _isComplete ? 'Download Complete' :
                  _isDownloading ? 'Downloading GeoTIFF' :
                  'Preparing GeoTIFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.scanName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Progress section
            if (_isPreparing) ...[
              Column(
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Preparing file on server...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],

            if (_isDownloading) ...[
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: Colors.grey[700],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Downloading...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],

            if (_hasError) ...[
              Column(
                children: [
                  Text(
                    _errorMessage,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _retryDownload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry Download'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: _cancelDownload,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            if (_isComplete) ...[
              Column(
                children: [
                  const Text(
                    'Your GeoTIFF file has been downloaded successfully.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _openFile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Open File'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            const SizedBox(height: 40),

            // Cancel button for downloading or preparing state
            if ((_isDownloading || _isPreparing) && !_hasError) ...[
              TextButton(
                onPressed: _cancelDownload,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Cancel Download'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}