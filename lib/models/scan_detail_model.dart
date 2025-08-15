import 'dart:convert';

/// Models for scan detail from API
class ScanDetailModel {
  final int id;
  final int user;
  final String title;
  final String description;
  final int duration;
  final double areaCovered;
  final double height;
  final double dataSizeMb;
  final String status;
  final List<GpsPointModel> gpsPoints;
  final PointCloudModel? pointCloud;
  final UploadStatusModel? uploadStatus;
  final List<ScanImageModel> images;
  final int totalImages;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScanDetailModel({
    required this.id,
    required this.user,
    required this.title,
    required this.description,
    required this.duration,
    required this.areaCovered,
    required this.height,
    required this.dataSizeMb,
    required this.status,
    required this.gpsPoints,
    this.pointCloud,
    this.uploadStatus,
    required this.images,
    required this.totalImages,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ScanDetailModel.fromJson(Map<String, dynamic> json) {
    return ScanDetailModel(
      id: _parseInt(json['id']),
      user: _parseInt(json['user']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      duration: _parseInt(json['duration']),
      areaCovered: _parseDouble(json['area_covered']),
      height: _parseDouble(json['height']),
      dataSizeMb: _parseDouble(json['data_size_mb']),
      status: json['status']?.toString() ?? 'pending',
      gpsPoints: (json['gps_points'] as List<dynamic>?)
          ?.map((item) => GpsPointModel.fromJson(item as Map<String, dynamic>))
          .toList() ??
          [],
      pointCloud: json['point_cloud'] != null
          ? PointCloudModel.fromJson(json['point_cloud'] as Map<String, dynamic>)
          : null,
      uploadStatus: json['upload_status'] != null
          ? UploadStatusModel.fromJson(json['upload_status'] as Map<String, dynamic>)
          : null,
      images: (json['images'] as List<dynamic>?)
          ?.map((item) => ScanImageModel.fromJson(item as Map<String, dynamic>))
          .toList() ??
          [],
      totalImages: _parseInt(json['total_images']), // This was the main issue
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  /// Helper method to safely parse int values
  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Helper method to safely parse double values
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Helper method to safely parse DateTime values
  static DateTime _parseDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) return DateTime.now();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }
}

class GpsPointModel {
  final int id;
  final String latitude;
  final String longitude;
  final double accuracy;
  final DateTime timestamp;

  GpsPointModel({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  factory GpsPointModel.fromJson(Map<String, dynamic> json) {
    return GpsPointModel(
      id: ScanDetailModel._parseInt(json['id']),
      latitude: json['latitude']?.toString() ?? '0.0',
      longitude: json['longitude']?.toString() ?? '0.0',
      accuracy: ScanDetailModel._parseDouble(json['accuracy']),
      timestamp: ScanDetailModel._parseDateTime(json['timestamp']),
    );
  }

  /// Parse GPS coordinates to double for map usage
  double get latitudeAsDouble => double.tryParse(latitude) ?? 0.0;
  double get longitudeAsDouble => double.tryParse(longitude) ?? 0.0;
}

class PointCloudModel {
  final int id;
  final String? grayModel;
  final int pointCount;
  final String? processedModel;
  final String? snapshot;
  final DateTime uploadedAt;

  PointCloudModel({
    required this.id,
    this.grayModel,
    required this.pointCount,
    this.processedModel,
    this.snapshot,
    required this.uploadedAt,
  });

  factory PointCloudModel.fromJson(Map<String, dynamic> json) {
    return PointCloudModel(
      id: ScanDetailModel._parseInt(json['id']),
      grayModel: json['gray_model']?.toString(),
      pointCount: ScanDetailModel._parseInt(json['point_count']),
      processedModel: json['processed_model']?.toString(),
      snapshot: json['snapshot']?.toString(),
      uploadedAt: ScanDetailModel._parseDateTime(json['uploaded_at']),
    );
  }
}

class UploadStatusModel {
  final int id;
  final String status;
  final DateTime lastAttempt;
  final int retryCount;
  final String errorMessage;

  UploadStatusModel({
    required this.id,
    required this.status,
    required this.lastAttempt,
    required this.retryCount,
    required this.errorMessage,
  });

  factory UploadStatusModel.fromJson(Map<String, dynamic> json) {
    return UploadStatusModel(
      id: ScanDetailModel._parseInt(json['id']),
      status: json['status']?.toString() ?? '',
      lastAttempt: ScanDetailModel._parseDateTime(json['last_attempt']),
      retryCount: ScanDetailModel._parseInt(json['retry_count']),
      errorMessage: json['error_message']?.toString() ?? '',
    );
  }
}

class ScanImageModel {
  final int id;
  final String image;
  final String caption;
  final DateTime timestamp;

  ScanImageModel({
    required this.id,
    required this.image,
    required this.caption,
    required this.timestamp,
  });

  factory ScanImageModel.fromJson(Map<String, dynamic> json) {
    return ScanImageModel(
      id: ScanDetailModel._parseInt(json['id']),
      image: json['image']?.toString() ?? '',
      caption: json['caption']?.toString() ?? '',
      timestamp: ScanDetailModel._parseDateTime(json['timestamp']),
    );
  }
}