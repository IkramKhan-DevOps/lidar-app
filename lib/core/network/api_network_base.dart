// =============================================================
// BASE ABSTRACT SERVICE (HTTP contract for data layer)
// -------------------------------------------------------------
// Purpose:
// - Define a simple, swappable contract for making HTTP requests.
// - Keep repositories decoupled from any specific HTTP client.
// - Enable easy testing by mocking this interface.
//
// Implementations:
// - Provide a concrete class (e.g., NetworkApiService) that uses
//   package:http, Dio, or any transport of your choice.
// - Map transport-level errors into your domain exceptions in the
//   concrete implementation (not here).
//
// Return type:
// - dynamic by design: implementations typically return decoded JSON
//   (Map/List) or a raw String. Repositories should cast/parse this
//   into typed models (e.g., ProfileModel.fromJson).
//
// Notes on flags:
// - isToken: when true, implementers should attach an auth token.
// - noJson: when true, implementers should avoid JSON headers/encoding
//   (useful for multipart/form-data or raw payloads).
// =============================================================


abstract class BaseApiService {
  Future<dynamic> getAPI(String url, [bool isToken = false]);
  Future<dynamic> postAPI(String url, dynamic data,
      [bool isToken = false, bool noJson = false]);
  Future<dynamic> putAPI(String url, dynamic data);
  Future<dynamic> deleteAPI(String url, [bool isToken = false, bool noJson = false]);
}