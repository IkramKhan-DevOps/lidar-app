import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final WebViewController controller;
  bool isLoading = true;
  bool hasError = false;
  String? errorMessage;
  bool isUsdz = false;
  bool showArButton = true;

  @override
  void initState() {
    super.initState();
    print('Model URL: ${widget.modelUrl}');
    isUsdz = widget.modelUrl.toLowerCase().endsWith('.usdz');
    _initializeWebView();
  }

  void _initializeWebView() {
    print('Initializing WebView');
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            print('Loading progress: $progress%');
            if (progress == 100) {
              setState(() {
                isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            print('Page started: $url');
            setState(() {
              isLoading = true;
              hasError = false;
              errorMessage = null;
            });
          },
          onPageFinished: (String url) {
            print('Page finished: $url');
            setState(() {
              isLoading = false;
            });
          },
          onHttpError: (HttpResponseError error) {
            print('HTTP Error: ${error.response?.statusCode} - ${error.response}');
            setState(() {
              isLoading = false;
              hasError = true;
              errorMessage = 'HTTP Error: ${error.response?.statusCode} - ${error.response}';
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('WebResourceError: ${error.description}, Code: ${error.errorCode}, Type: ${error.errorType}');
            setState(() {
              isLoading = false;
              hasError = true;
              errorMessage = 'Error loading model: ${error.description} (Code: ${error.errorCode})';
            });
          },
        ),
      );

    if (Platform.isIOS) {
      controller.setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
      );
    }

    _loadModelViewer();
  }

  Future<void> _launchUsdzViewer() async {
    setState(() {
      isLoading = true;
    });

    try {
      final uri = Uri.parse(widget.modelUrl);
      if (await canLaunchUrl(uri)) {
        print('Launching USDZ viewer: ${widget.modelUrl}');
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalNonBrowserApplication,
        );

        if (!launched) {
          throw 'Failed to launch native viewer';
        }
      } else {
        throw 'No viewer available for USDZ files';
      }
    } catch (e) {
      print('USDZ launch error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open AR viewer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _loadModelViewer() {
    if (widget.modelUrl.isEmpty || !Uri.parse(widget.modelUrl).isAbsolute) {
      print('Invalid model URL: ${widget.modelUrl}');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'Invalid or empty model URL';
      });
      return;
    }

    print('Loading model viewer with URL: ${widget.modelUrl}');
    final String htmlContent = '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval'; img-src * data:; media-src *; connect-src *;">
        <title>3D Model Viewer</title>
        <script type="module" src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js"></script>
        <style>
            body {
                margin: 0;
                padding: 0;
                background-color: #1a1a1a;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                overflow: hidden;
            }
            
            model-viewer {
                width: 100vw;
                height: 100vh;
                background-color: #1a1a1a;
                --poster-color: transparent;
                --progress-bar-color: #007AFF;
            }
            
            .loading-overlay {
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(26, 26, 26, 0.9);
                display: flex;
                flex-direction: column;
                justify-content: center;
                align-items: center;
                z-index: 1000;
                color: white;
            }
            
            .loading-spinner {
                width: 40px;
                height: 40px;
                border: 3px solid #333;
                border-top: 3px solid #007AFF;
                border-radius: 50%;
                animation: spin 1s linear infinite;
                margin-bottom: 16px;
            }
            
            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
            
            .error-overlay {
                position: absolute;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background-color: rgba(26, 26, 26, 0.95);
                display: flex;
                flex-direction: column;
                justify-content: center;
                align-items: center;
                z-index: 1000;
                color: white;
                text-align: center;
                padding: 20px;
                box-sizing: border-box;
            }
            
            .error-icon {
                font-size: 48px;
                color: #ff4444;
                margin-bottom: 16px;
            }
            
            .error-title {
                font-size: 20px;
                font-weight: bold;
                margin-bottom: 8px;
                color: #ff4444;
            }
            
            .error-message {
                font-size: 14px;
                color: #ccc;
                line-height: 1.4;
            }
            
            .controls {
                position: absolute;
                bottom: 20px;
                left: 50%;
                transform: translateX(-50%);
                display: flex;
                gap: 12px;
                z-index: 100;
            }
            
            .control-btn {
                background: rgba(0, 0, 0, 0.7);
                border: 1px solid rgba(255, 255, 255, 0.2);
                color: white;
                padding: 8px 12px;
                border-radius: 6px;
                font-size: 12px;
                cursor: pointer;
                transition: all 0.2s ease;
            }
            
            .control-btn:hover {
                background: rgba(0, 0, 0, 0.9);
                border-color: #007AFF;
            }
            
            .model-info {
                position: absolute;
                top: 20px;
                left: 20px;
                background: rgba(0, 0, 0, 0.7);
                color: white;
                padding: 8px 12px;
                border-radius: 6px;
                font-size: 12px;
                max-width: 200px;
                z-index: 100;
            }
            
            .ar-button {
                position: absolute;
                bottom: 80px;
                left: 50%;
                transform: translateX(-50%);
                background: rgba(0, 122, 255, 0.8);
                color: white;
                padding: 10px 16px;
                border-radius: 8px;
                font-size: 14px;
                cursor: pointer;
                border: none;
                z-index: 100;
                display: flex;
                align-items: center;
                gap: 8px;
            }
            
            .ar-button:hover {
                background: rgba(0, 122, 255, 1);
            }
        </style>
    </head>
    <body>
        <div id="loading" class="loading-overlay">
            <div class="loading-spinner"></div>
            <div>Loading 3D Model...</div>
        </div>
        
        <div id="error" class="error-overlay" style="display: none;">
            <div class="error-icon">⚠️</div>
            <div class="error-title">Failed to Load Model</div>
            <div class="error-message" id="error-text">
                Unable to load the 3D model. Please check your internet connection and try again.
            </div>
        </div>
        
        <div class="model-info">
            <div style="font-weight: bold;">${widget.modelName}</div>
            <div style="opacity: 0.7; margin-top: 4px;">3D Model</div>
        </div>
        
        <model-viewer 
            id="modelViewer"
            src="${widget.modelUrl}"
            alt="3D Model of ${widget.modelName}"
            ios-src="${widget.modelUrl}"
            auto-rotate
            camera-controls
            touch-action="pan-y"
            interaction-policy="always-allow"
            loading="lazy"
            ar
            ar-modes="scene-viewer quick-look"
            ar-scale="auto">
            
            <div slot="progress-bar" style="display: none;"></div>
            
            ${isUsdz && Platform.isIOS ? """
            <button slot="ar-button" class="ar-button">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M10 2H14M3 7V17C3 18.1046 3.89543 19 5 19H19C20.1046 19 21 18.1046 21 17V7C21 5.89543 20.1046 5 19 5H5C3.89543 5 3 5.89543 3 7Z" stroke="white" stroke-width="2" stroke-linecap="round"/>
                </svg>
                View in AR
            </button>
            """ : ""}
        </model-viewer>
        
        <div class="controls">
            <button class="control-btn" onclick="resetCamera()">Reset View</button>
            <button class="control-btn" onclick="toggleAutoRotate()">Toggle Rotation</button>
        </div>
        
        <script>
            const modelViewer = document.getElementById('modelViewer');
            const loading = document.getElementById('loading');
            const error = document.getElementById('error');
            const errorText = document.getElementById('error-text');
            let autoRotateEnabled = true;
            
            // Hide loading when model is loaded
            modelViewer.addEventListener('load', () => {
                loading.style.display = 'none';
            });
            
            // Show error if model fails to load
            modelViewer.addEventListener('error', (event) => {
                loading.style.display = 'none';
                error.style.display = 'flex';
                errorText.textContent = 'Failed to load model: ' + (event.detail?.message || 'Unknown error');
            });
            
            // Handle progress updates
            modelViewer.addEventListener('progress', (event) => {
                const progress = event.detail.totalProgress;
                if (progress >= 1) {
                    loading.style.display = 'none';
                } else {
                    loading.style.display = 'flex';
                }
            };
            
            function resetCamera() {
                modelViewer.resetTurntableRotation();
                modelViewer.jumpCameraToGoal();
            }
            
            function toggleAutoRotate() {
                autoRotateEnabled = !autoRotateEnabled;
                if (autoRotateEnabled) {
                    modelViewer.setAttribute('auto-rotate', '');
                } else {
                    modelViewer.removeAttribute('auto-rotate');
                }
            }
            
            // Timeout for slow loading
            setTimeout(() => {
                if (loading.style.display !== 'none') {
                    loading.style.display = 'none';
                    error.style.display = 'flex';
                    errorText.textContent = 'Loading timed out. The model might be too large.';
                }
            }, 30000);
        </script>
    </body>
    </html>
    ''';

    controller.loadHtmlString(htmlContent).catchError((e) {
      print('HTML Load Error: $e');
      setState(() {
        isLoading = false;
        hasError = true;
        errorMessage = 'Failed to load HTML: $e';
      });
    });
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
          if (isUsdz && Platform.isIOS)
            IconButton(
              icon: const Icon(Icons.view_in_ar, color: Colors.white),
              onPressed: _launchUsdzViewer,
              tooltip: 'Open in AR Viewer',
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() {
                isLoading = true;
                hasError = false;
                errorMessage = null;
              });
              _loadModelViewer();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!hasError)
            WebViewWidget(controller: controller),
          if (hasError)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isUsdz ? 'USDZ File Detected' : 'Failed to Load Model',
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
                        errorMessage ??
                            (isUsdz ? 'For the best experience with USDZ files, please use the AR viewer.'
                                : 'Unknown error occurred'),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (isUsdz && Platform.isIOS)
                      ElevatedButton.icon(
                        onPressed: _launchUsdzViewer,
                        icon: const Icon(Icons.view_in_ar),
                        label: const Text('Open in AR Viewer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          hasError = false;
                          errorMessage = null;
                        });
                        _loadModelViewer();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry in Web Viewer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isLoading)
            Container(
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
                      isUsdz ? 'Preparing 3D Viewer...' : 'Loading 3D Model...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}