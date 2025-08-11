// =============================================================
// CUSTOM EXCEPTIONS (OPTIONAL)
// Used by NetworkApiService to throw typed errors.
// =============================================================

class FetchDataException implements Exception {
  final String message;
  FetchDataException(this.message);
  @override
  String toString() => 'FetchDataException: $message';
}

class BadRequestException implements Exception {
  final String message;
  BadRequestException(this.message);
  @override
  String toString() => 'BadRequestException: $message';
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}