// =============================================================
// BASE ABSTRACT SERVICE
// Each concrete implementation must provide CRUD HTTP methods.
// Keeps code testable & swappable (e.g., mock service).
// =============================================================
abstract class BaseApiService {
  Future<dynamic> getAPI(String url, [bool isToken = false]);
  Future<dynamic> postAPI(String url, dynamic data,
      [bool isToken = false, bool noJson = false]);
  Future<dynamic> putAPI(String url, dynamic data);
  Future<dynamic> deleteAPI(String url, [bool isToken = false, bool noJson = false]);
}