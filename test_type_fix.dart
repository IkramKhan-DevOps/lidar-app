// Test script to verify that the type mismatch issue is resolved
// Run this with: flutter test test_type_fix.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'lib/models/scan_detail_model.dart';

void main() {
  group('ScanDetailModel Type Handling Tests', () {
    
    test('should handle API response with proper numeric types', () {
      // Simulate API response with correct numeric types
      final apiResponse = {
        'id': '1',
        'user': '123',
        'title': 'Test Scan',
        'description': 'A test scan',
        'duration': 180,                    // int
        'area_covered': 25.5,              // double
        'height': 3.2,                     // double
        'data_size_mb': 45.8,              // double
        'status': 'completed',
        'gps_points': [
          {
            'id': 1,
            'latitude': 37.7749,            // double
            'longitude': -122.4194          // double
          }
        ],
        'point_cloud': null,
        'upload_status': null,
        'images': [],
        'total_images': 5,                  // int
        'created_at': '2025-08-15T10:30:00Z',
        'updated_at': '2025-08-15T11:30:00Z',
      };
      
      expect(() => ScanDetailModel.fromJson(apiResponse), returnsNormally);
      
      final model = ScanDetailModel.fromJson(apiResponse);
      
      // Verify types are correctly parsed
      expect(model.duration, isA<int>());
      expect(model.duration, equals(180));
      
      expect(model.areaCovered, isA<double>());
      expect(model.areaCovered, equals(25.5));
      
      expect(model.height, isA<double>());
      expect(model.height, equals(3.2));
      
      expect(model.dataSizeMb, isA<double>());
      expect(model.dataSizeMb, equals(45.8));
      
      expect(model.totalImages, isA<int>());
      expect(model.totalImages, equals(5));
      
      // Verify GPS coordinates
      expect(model.gpsPoints.first.latitude, isA<double>());
      expect(model.gpsPoints.first.latitude, equals(37.7749));
      
      expect(model.gpsPoints.first.longitude, isA<double>());
      expect(model.gpsPoints.first.longitude, equals(-122.4194));
    });
    
    test('should handle mixed types from legacy API', () {
      // Simulate API response with mixed string/numeric types (legacy)
      final mixedResponse = {
        'id': '1',
        'user': '123', 
        'title': 'Test Scan',
        'description': 'A test scan',
        'duration': '180',                  // string that should become int
        'area_covered': '25.5',            // string that should become double
        'height': '3.2',                   // string that should become double
        'data_size_mb': '45.8',            // string that should become double
        'status': 'completed',
        'gps_points': [
          {
            'id': 1,
            'latitude': '37.7749',          // string that should become double
            'longitude': '-122.4194'        // string that should become double
          }
        ],
        'point_cloud': null,
        'upload_status': null,
        'images': [],
        'total_images': '5',                // string that should become int
        'created_at': '2025-08-15T10:30:00Z',
        'updated_at': '2025-08-15T11:30:00Z',
      };
      
      expect(() => ScanDetailModel.fromJson(mixedResponse), returnsNormally);
      
      final model = ScanDetailModel.fromJson(mixedResponse);
      
      // Verify string values are correctly converted to proper types
      expect(model.duration, isA<int>());
      expect(model.duration, equals(180));
      
      expect(model.areaCovered, isA<double>());
      expect(model.areaCovered, equals(25.5));
      
      expect(model.height, isA<double>());
      expect(model.height, equals(3.2));
      
      expect(model.dataSizeMb, isA<double>());
      expect(model.dataSizeMb, equals(45.8));
      
      expect(model.totalImages, isA<int>());
      expect(model.totalImages, equals(5));
      
      // Verify GPS coordinates from strings
      expect(model.gpsPoints.first.latitude, isA<double>());
      expect(model.gpsPoints.first.latitude, equals(37.7749));
      
      expect(model.gpsPoints.first.longitude, isA<double>());
      expect(model.gpsPoints.first.longitude, equals(-122.4194));
    });
    
    test('should handle null/invalid values gracefully', () {
      final invalidResponse = {
        'id': '1',
        'user': '123',
        'title': 'Test Scan', 
        'description': 'A test scan',
        'duration': null,
        'area_covered': null,
        'height': 'invalid',
        'data_size_mb': '',
        'status': 'completed',
        'gps_points': [
          {
            'id': 1,
            'latitude': null,
            'longitude': 'invalid'
          }
        ],
        'point_cloud': null,
        'upload_status': null,
        'images': [],
        'total_images': null,
        'created_at': '2025-08-15T10:30:00Z',
        'updated_at': '2025-08-15T11:30:00Z',
      };
      
      expect(() => ScanDetailModel.fromJson(invalidResponse), returnsNormally);
      
      final model = ScanDetailModel.fromJson(invalidResponse);
      
      // Verify defaults are used for invalid values
      expect(model.duration, equals(0));
      expect(model.areaCovered, equals(0.0));
      expect(model.height, equals(0.0));
      expect(model.dataSizeMb, equals(0.0));
      expect(model.totalImages, equals(0));
      expect(model.gpsPoints.first.latitude, equals(0.0));
      expect(model.gpsPoints.first.longitude, equals(0.0));
    });
  });
}
