// =============================================================
// SCAN REPOSITORY
// -------------------------------------------------------------
// Purpose:
// - Provide a clean interface for scan-related API operations.
// - Hide networking details from the rest of the app.
// - Handle scan detail fetching from the server API.
//
// Endpoints used (from APIUrl):
// - scanById(id): GET scan detail by ID -> returns ScanDetailModel
// - scans:        GET all scans -> returns list of scans
// - scansProcess: POST process scan -> returns processing result
//
// Notes:
// - This class depends on a BaseApiService so it can be easily mocked in tests.
// - Methods throw an Exception if the server response is not as expected.
// - Call sites should catch and surface user-friendly messages.
// =============================================================

import '../core/network/api_network_base.dart';
import '../core/network/api_urls.dart';
import '../models/scan_detail_model.dart';

class ScanRepository {
  // Low-level HTTP service (injected for testability and swapping transports).
  final BaseApiService api;

  // Require the API service via constructor injection.
  ScanRepository(this.api);

  // -----------------------------------------------------------
  // getScanDetail
  // Fetches detailed information about a specific scan by ID.
  //
  // Params:
  // - scanId: The ID of the scan to fetch
  //
  // Returns:
  // - ScanDetailModel containing all scan information
  //
  // Throws:
  // - Exception if the scan is not found or response format is unexpected
  // -----------------------------------------------------------
  Future<ScanDetailModel> getScanDetail(int scanId) async {
    print(">>>>>>>>>>> IN getScanDetail with scanId: $scanId");

    try {
      final res = await api.getAPI(APIUrl.scanById(scanId), true);

      if (res is Map<String, dynamic>) {
        print(">>>>>>>>>>> JSON received, parsing...");
        var data = ScanDetailModel.fromJson(res);
        print(">>>>>>>>>>> Model created successfully: ${data.toString()}");
        print(">>>>>>>>>>> Model ID: ${data.id}, Title: ${data.title}");
        return data;
      }

      print(">>>>>>>>>>> ERROR: Unexpected response format");
      throw Exception('Unexpected response format for scan detail');

    } catch (e) {
      print(">>>>>>>>>>> EXCEPTION in getScanDetail: $e");
      print(">>>>>>>>>>> Stack trace: ${StackTrace.current}");
      rethrow;
    }
  }

  // -----------------------------------------------------------
  // getAllScans
  // Fetches a list of all scans for the authenticated user.
  //
  // Returns:
  // - List<ScanDetailModel> containing all user scans
  //
  // Throws:
  // - Exception if the response format is unexpected
  // -----------------------------------------------------------
  Future<List<ScanDetailModel>> getAllScans() async {
    // isToken=true (must be authenticated to access scans)
    final res = await api.getAPI(APIUrl.scans, true);

    if (res is Map<String, dynamic> && res['results'] is List) {
      try {
        final scansList = res['results'] as List<dynamic>;
        return scansList
            .map((scanJson) => ScanDetailModel.fromJson(scanJson as Map<String, dynamic>))
            .toList();
      } catch (e) {
        throw Exception('Failed to parse scans list response: $e');
      }
    } else if (res is List<dynamic>) {
      // Handle case where response is directly a list
      try {
        return res
            .map((scanJson) => ScanDetailModel.fromJson(scanJson as Map<String, dynamic>))
            .toList();
      } catch (e) {
        throw Exception('Failed to parse scans list response: $e');
      }
    }
    throw Exception('Unexpected response format for scans list');
  }

  // -----------------------------------------------------------
  // processScan
  // Triggers server-side processing for a scan.
  //
  // Params:
  // - scanId: The ID of the scan to process
  //
  // Returns:
  // - Map<String, dynamic> containing processing result
  //
  // Throws:
  // - Exception if processing request fails
  // -----------------------------------------------------------
  Future<Map<String, dynamic>> processScan(int scanId) async {
    final body = {'scan_id': scanId};
    
    // isToken=true (must be authenticated), noJson=false (send JSON)
    final res = await api.postAPI(APIUrl.scansProcess, body, true, false);

    if (res is Map<String, dynamic>) {
      return res;
    }
    throw Exception('Unexpected response format for scan processing');
  }

  // -----------------------------------------------------------
  // deleteScan
  // Deletes a scan from the server.
  //
  // Params:
  // - scanId: The ID of the scan to delete
  //
  // Returns:
  // - String message from server (e.g., "Scan deleted successfully")
  //
  // Throws:
  // - Exception if deletion fails
  // -----------------------------------------------------------
  Future<bool> deleteScan(int scanId) async {
    try{
      await api.deleteAPI(APIUrl.scanDeleteById(scanId), true, false);
      return true;
    }catch (e) {
      return false;
    }
  }

  // -----------------------------------------------------------
  // uploadScan
  // Uploads scan data to the server.
  //
  // Params:
  // - scanData: Map containing scan data to upload
  //
  // Returns:
  // - ScanDetailModel of the created scan
  //
  // Throws:
  // - Exception if upload fails
  // -----------------------------------------------------------
  Future<ScanDetailModel> uploadScan(Map<String, dynamic> scanData) async {
    // isToken=true (must be authenticated), noJson=false (send JSON)
    final res = await api.postAPI(APIUrl.scans, scanData, true, false);

    if (res is Map<String, dynamic>) {
      try {
        return ScanDetailModel.fromJson(res);
      } catch (e) {
        throw Exception('Failed to parse upload scan response: $e');
      }
    }
    throw Exception('Unexpected response format for scan upload');
  }




  // Download scan zip file by ID
Future<bool> downloadScanZip(int scanId) async {
    try {
      final res = await api.getAPI(APIUrl.scanDownloadById(scanId), true,);
      if (res is Map<String, dynamic> && res['success'] == true) {
        print(">>>>>>>>>>> Scan zip downloaded successfully for scanId: $scanId");
        // Assuming the response contains a success flag
        return true;
      }
      throw Exception('Failed to download scan zip: unexpected response format');
    } catch (e) {
      print(">>>>>>>>>>> EXCEPTION in downloadScanZip: $e");
      rethrow;
    }
  }


}
