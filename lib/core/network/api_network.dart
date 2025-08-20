// NetworkApiService
// -------------------------------------------------------------
// A concrete implementation of BaseApiService that wraps package:http
// to perform GET/POST/PUT/DELETE requests with optional auth headers,
// JSON encoding/decoding, timeouts, and error mapping into custom
// AppException types.
//
// Responsibilities:
// - Build headers (with or without token)
// - Encode Map bodies to JSON when needed
// - Apply sensible timeouts for read/write operations
// - Decode JSON responses (or return raw body if not JSON)
// - Map HTTP errors to domain-specific exceptions
//
// Notes:
// - All network I/O and low-level concerns live here.
// - Repositories should depend on this service instead of http directly.
// -------------------------------------------------------------

import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:platform_channel_swift_demo/core/configs/app_routes.dart';

import '../errors/app_exceptions.dart';
import '../storage/auth_storage.dart';
import '../utils/navigation_helper.dart';
import 'api_network_base.dart';
import 'api_urls.dart';

class NetworkApiService extends BaseApiService {
  // Default timeouts per operation type.
final Duration _getTimeout = const Duration(seconds: 1800);
  final Duration _writeTimeout = const Duration(seconds: 1800);
final Future<void> Function()? onUnauthorized;

// Modify the constructor to accept the callback
NetworkApiService({this.onUnauthorized});

  // -----------------------------------------------------------
  // _headers
  // Builds request headers. Adds Authorization when token exists.
  // If json=true, sets Content-Type and Accept to application/json.
  // -----------------------------------------------------------
  Map<String, String> _headers({String? token, bool json = true}) {
    final h = <String, String>{};
    if (token != null && token.isNotEmpty) {
      // Determine auth scheme: auto/Bearer/Token
      String scheme;
      switch (AppConfig.authHeaderScheme) {
        case 'Bearer':
          scheme = 'Bearer';
          break;
        case 'Token':
          scheme = 'Token';
          break;
        case 'auto':
        default:
          // Heuristic: JWTs usually contain two dots
          final isJwt = token.split('.').length == 3;
          scheme = isJwt ? 'Bearer' : 'Token';
      }
      h['Authorization'] = '$scheme $token';
      // Also send token via cookie for backends that read from session/csrf middleware
      h['Cookie'] = 'token=$token';
      // debug: print masked auth header
      // ignore: avoid_print
      print(
          '[NET] Auth: $scheme ${token.substring(0, token.length > 6 ? 6 : token.length)}***');
    }
    if (json) {
      h['Content-Type'] = 'application/json';
      h['Accept'] = 'application/json';
    }
    return h;
  }

  // -----------------------------------------------------------
  // GET
  // Optionally includes Authorization header when isToken=true.
  // Automatically times out after _getTimeout.
  // Returns decoded JSON or raw body (via _validate).
  // -----------------------------------------------------------
  @override
  Future<dynamic> getAPI(String url, [bool isToken = false]) async {
    try {
      // Resolve token only if needed.
      final token = isToken ? await AuthToken.getToken() : null;

      final res = await http
          .get(Uri.parse(url), headers: _headers(token: token))
          .timeout(_getTimeout);

      _debug('GET', url, res);
      return _validate(res);
    } on SocketException {
      // Network unavailable
      throw FetchDataException('No internet connection.');
    }
  }

  // -----------------------------------------------------------
  // POST
  // - isToken: include Authorization header if true.
  // - noJson: when true, do NOT set JSON headers and do NOT encode Map.
  //           (Useful for multipart/form-data or raw body posts.)
  // Encodes body to JSON only when data is a Map and noJson is false.
  // Times out after _writeTimeout.
  // -----------------------------------------------------------
  @override
  Future<dynamic> postAPI(String url, dynamic data,
      [bool isToken = false, bool noJson = false]) async {
    try {
      final token = isToken ? await AuthToken.getToken() : null;
      final bool sendJson = !noJson;

      // If sending JSON and data is a Map, encode it. Otherwise pass as-is.
      final body = (sendJson && data is Map) ? jsonEncode(data) : data;

      final res = await http
          .post(
            Uri.parse(url),
            headers: _headers(token: token, json: sendJson),
            body: body,
          )
          .timeout(_writeTimeout);

      _debug('POST', url, res, requestBody: body);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection.');
    }
  }

  // -----------------------------------------------------------
  // PUT
  // Always sends JSON when data is a Map. Includes Authorization header.
  // Times out after _writeTimeout.
  // -----------------------------------------------------------
  @override
  Future<dynamic> putAPI(String url, dynamic data) async {
    try {
      final token = await AuthToken.getToken();

      // If caller passed a Map, encode to JSON. Otherwise, send as-is.
      final body = data is Map ? jsonEncode(data) : data;

      final res = await http
          .put(
            Uri.parse(url),
            headers: _headers(token: token),
            body: body,
          )
          .timeout(_writeTimeout);

      _debug('PUT', url, res, requestBody: body);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection.');
    }
  }

  // -----------------------------------------------------------
  // DELETE
  // Note: Method signature includes isToken/noJson, but implementation
  // always sends token (if available) and JSON headers by default.
  // Adjust if you need to support anonymous deletes or non-JSON cases.
  // Times out after _writeTimeout.
  // -----------------------------------------------------------
// ... keep previous imports and class declaration

  @override
  Future<dynamic> deleteAPI(String url,
      [bool isToken = false, bool noJson = false]) async {
    try {
      final token = isToken ? await AuthToken.getToken() : null;
      final bool sendJson = !noJson;

      final res = await http
          .delete(
        Uri.parse(url),
        headers: _headers(token: token, json: sendJson),
      )
          .timeout(_writeTimeout);

      _debug('DELETE', url, res);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection.');
    }
  }

  dynamic _validate(http.Response res) async { // Make this method async
    // Success codes we accept
    if (res.statusCode == 200 ||
        res.statusCode == 201 ||
        res.statusCode == 202 ||
        res.statusCode == 204) {
      if (res.body.isEmpty) return {}; // 204 or empty body
      try {
        return jsonDecode(res.body);
      } catch (_) {
        return res.body;
      }
    }

    final body = res.body;
    switch (res.statusCode) {
      case 400:
        throw BadRequestException(body);
      case 401:
        // _redirectToLogin();
        throw UnauthorizedException(body);
      case 403:
        throw UnauthorizedException(body);
      case 404:
        throw FetchDataException('404 Not Found: $body');
      default:
        throw FetchDataException('Status ${res.statusCode}: $body');
    }
  }

// ... keep rest of file

  // -----------------------------------------------------------
  // _debug
  // Simple console logger for requests and responses.
  // Use for development; consider gating under a debug flag in prod.
  // -----------------------------------------------------------
  void _debug(String method, String url, http.Response res,
      {dynamic requestBody}) {
    // ignore: avoid_print
    print('=== $method $url ===');
    if (requestBody != null) print('Request: $requestBody');
    print('Status: ${res.statusCode}');
    print('Body: ${res.body}');
    print('====================');
  }
  void _redirectToLogin() {
    NavigationHelper.redirectToLogin(); // Call the global helper
  }



// -----------------------------------------------------------
  // _validate
  // Normalizes HTTP responses:
  // - Success (200/201): decode JSON if possible, else return raw body.
  // - Errors: throw domain-specific exceptions with server message included.
  //
  // Extend this to support more success codes (e.g., 204) as needed.
  // -----------------------------------------------------------
}
