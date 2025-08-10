// (If you already modified earlier, keep the debug prints until stable)
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../errors/app_exceptions.dart';
import '../storage/auth_storage.dart';
import 'api_network_base.dart';

class NetworkApiService extends BaseApiService {
  final Duration _getTimeout = const Duration(seconds: 12);
  final Duration _writeTimeout = const Duration(seconds: 20);

  Map<String, String> _headers({String? token, bool json = true}) {
    final h = <String, String>{};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Token $token';
    }
    if (json) {
      h['Content-Type'] = 'application/json';
      h['Accept'] = 'application/json';
    }
    return h;
  }

  @override
  Future<dynamic> getAPI(String url, [bool isToken = false]) async {
    try {
      final token = isToken ? await AuthToken.getToken() : null;
      final res = await http
          .get(Uri.parse(url), headers: _headers(token: token))
          .timeout(_getTimeout);
      _debugPrint('GET', url, res);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection available.');
    }
  }

  @override
  Future<dynamic> postAPI(String url, dynamic data,
      [bool isToken = false, bool noJson = false]) async {
    try {
      final token = isToken ? await AuthToken.getToken() : null;
      final bool sendJson = !noJson;
      final dynamic body = (sendJson && data is Map) ? jsonEncode(data) : data;
      final res = await http
          .post(
        Uri.parse(url),
        headers: _headers(token: token, json: sendJson),
        body: body,
      )
          .timeout(_writeTimeout);
      _debugPrint('POST', url, res, requestBody: body);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection available.');
    }
  }

  @override
  Future<dynamic> putAPI(String url, dynamic data) async {
    try {
      final token = await AuthToken.getToken();
      final body = data is Map ? jsonEncode(data) : data;
      final res = await http
          .put(Uri.parse(url),
          headers: _headers(token: token), body: body)
          .timeout(_writeTimeout);
      _debugPrint('PUT', url, res, requestBody: body);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection available.');
    }
  }

  @override
  Future<dynamic> deleteAPI(String url, [bool isToken = false, bool noJson = false]) async {
    try {
      final token = await AuthToken.getToken();
      final res = await http
          .delete(Uri.parse(url), headers: _headers(token: token))
          .timeout(_writeTimeout);
      _debugPrint('DELETE', url, res);
      return _validate(res);
    } on SocketException {
      throw FetchDataException('No internet connection available.');
    }
  }

  void _debugPrint(String method, String url, http.Response res,
      {dynamic requestBody}) {
    // Remove or gate with kDebugMode in production
    print('=== $method $url ===');
    if (requestBody != null) print('Request: $requestBody');
    print('Status: ${res.statusCode}');
    print('Body: ${res.body}');
    print('====================');
  }

  dynamic _validate(http.Response response) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      if (response.body.isEmpty) return {};
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return response.body;
      }
    }
    final body = response.body;
    switch (response.statusCode) {
      case 400:
        throw BadRequestException(body);
      case 401:
      case 403:
        throw UnauthorizedException(body);
      case 404:
        throw FetchDataException('404 Not Found: $body');
      case 500:
      default:
        throw FetchDataException(
            'Status ${response.statusCode}: $body');
    }
  }
}