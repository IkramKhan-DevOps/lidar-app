import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ModelDetailScreen extends StatefulWidget {
  final Map<String, dynamic> scan;

  const ModelDetailScreen({super.key, required this.scan});

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> with SingleTickerProviderStateMixin {
  static const platform = MethodChannel('com.demo.channel/message');
  late TabController _tabController;
  int progress = 0;
  List<String> imagePaths = [];
  bool _isFullScreenMap = false;
  late TextEditingController _nameController;
  bool _isEditingName = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _nameController = TextEditingController(text: widget.scan['name'] ?? 'Unnamed Scan');
    _fetchImagePaths();
    _setProgress();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _setProgress() {
    setState(() {
      progress = widget.scan['hasUSDZ'] == true ? 100 : 20;
    });
  }

  Future<void> _fetchImagePaths() async {
    try {
      final result = await platform.invokeMethod('getScanImages', {'folderPath': widget.scan['folderPath']});
      print('Raw result from getScanImages: $result');
      if (result is List) {
        setState(() {
          imagePaths = List<String>.from(result.map((e) => e.toString()));
        });
      } else {
        print('Error: getScanImages returned non-list result: $result');
        setState(() {
          imagePaths = [];
        });
      }
    } on PlatformException catch (e) {
      print('PlatformException in _fetchImagePaths: ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch images: ${e.message}')),
      );
      setState(() {
        imagePaths = [];
      });
    }
  }

  Future<void> _previewUSDZ() async {
    if (widget.scan['hasUSDZ'] == true && widget.scan['usdzPath'] != null) {
      try {
        await platform.invokeMethod('openUSDZ', {'path': widget.scan['usdzPath']});
      } on PlatformException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to preview USDZ: ${e.message}')),
        );
      }
    }
  }

  Future<void> _openFolder() async {
    try {
      await platform.invokeMethod('openFolder', {'path': widget.scan['folderPath']});
    } on PlatformException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open folder: ${e.message}')),
      );
    }
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
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Edit Project Name',
          style: TextStyle(color: Colors.white),
        ),
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
            onPressed: () {
              setState(() {
                widget.scan['name'] = _nameController.text.isEmpty ? 'Unnamed Scan' : _nameController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App Bar
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
                      const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Title & Address
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.scan['name'] ?? 'Unnamed Scan',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
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
                        _formatTimestamp(widget.scan['timestamp']),
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_pin, color: Colors.white54, size: 20),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.scan['locationName'] ?? 'Unknown Location',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Tab Bar
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

                const SizedBox(height: 12),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Overview Tab
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 300,
                              child: _buildMap(),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Scan ID: ${widget.scan['scanID'] ?? 'Unknown'}",
                              style: const TextStyle(color: Colors.white38, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Status: ${widget.scan['hasUSDZ'] == true ? 'Uploaded' : 'Pending'}",
                              style: const TextStyle(color: Colors.white38, fontSize: 16),
                            ),
                          ],
                        ),
                      ),

                      // 3D View Tab
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: GestureDetector(
                          onTap: _previewUSDZ,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                    strokeWidth: 4,
                                    value: progress / 100.0,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.scan['hasUSDZ'] == true
                                            ? "Tap to view 3D model"
                                            : "The view will load once the data is synchronized.",
                                        style: const TextStyle(color: Colors.white, fontSize: 16),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "Progress: $progress%",
                                        style: const TextStyle(color: Colors.blue, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Images Tab
                      SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: imagePaths.isEmpty
                            ? Container(
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[900],
                          ),
                          child: const Center(
                            child: Text(
                              "No images to display.",
                              style: TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          ),
                        )
                            : GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                          itemCount: imagePaths.length,
                          itemBuilder: (context, index) {
                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Image.file(
                                File(imagePaths[index]),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  print('Image load error for ${imagePaths[index]}: $error');
                                  return const Icon(Icons.error, color: Colors.red);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Static Scan Details
                Container(
                  width: double.infinity,
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(color: Colors.white12, thickness: 1),
                      const SizedBox(height: 12),
                      const Text(
                        "Scan Details",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "File Size: ${widget.scan['fileSizeMB'].toStringAsFixed(1)} MB",
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Number of Images: ${widget.scan['imageCount']}",
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Full-screen map dialog
            if (_isFullScreenMap)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isFullScreenMap = false;
                  });
                },
                child: Container(
                  color: Colors.black,
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
                              setState(() {
                                _isFullScreenMap = false;
                              });
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openFolder,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.folder, size: 28),
        elevation: 6,
      ),
    );
  }

  Widget _buildMap({bool isFullScreen = false}) {
    final rawCoordinates = widget.scan['coordinates'] as List<dynamic>?;
    print('Raw coordinates: $rawCoordinates');
    if (rawCoordinates == null || rawCoordinates.isEmpty) {
      print('No coordinates available, showing fallback UI');
      return Container(
        height: isFullScreen ? null : 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[900],
        ),
        child: const Center(
          child: Text(
            "No location data available.",
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
      );
    }

    final coordinates = rawCoordinates.map((coord) {
      if (coord is List<dynamic> && coord.length >= 2) {
        return [
          double.tryParse(coord[0].toString()) ?? 0.0,
          double.tryParse(coord[1].toString()) ?? 0.0,
        ];
      }
      return null;
    }).whereType<List<double>>().toList();

    if (coordinates.isNotEmpty &&
        coordinates.every((c) => c[0] == coordinates[0][0] && c[1] == coordinates[0][1])) {
      print('Warning: All coordinates are identical, polyline may not be visible');
    }

    final points = coordinates.map((coord) {
      if (coord.length >= 2 && coord[0] is double && coord[1] is double) {
        return LatLng(coord[0], coord[1]);
      } else {
        print('Invalid coordinate: $coord');
        return null;
      }
    }).whereType<LatLng>().toList();

    if (points.isEmpty) {
      print('No valid coordinates, showing fallback UI');
      return Container(
        height: isFullScreen ? null : 300,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey[900],
        ),
        child: const Center(
          child: Text(
            "Invalid location data.",
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ),
      );
    }

    final bounds = LatLngBounds.fromPoints(points);
    final center = bounds.center;
    const zoom = 15.0;

    print('Map center: $center, zoom: $zoom');
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: isFullScreen ? null : 300,
            child: FlutterMap(
              options: MapOptions(
                center: center,
                zoom: zoom,
                minZoom: 10.0,
                maxZoom: 18.0,
                interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.platform_channel_swift_demo',
                  errorTileCallback: (tile, error, stackTrace) {
                    print('Tile load error: $error, StackTrace: $stackTrace');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to load map tiles: $error')),
                    );
                  },
                  errorImage: const AssetImage('assets/fallback_tile.png'),
                ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      strokeWidth: 4.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (points.isNotEmpty)
                      Marker(
                        point: points.first,
                        width: 40.0,
                        height: 40.0,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40.0,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!isFullScreen)
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
}