// =============================================================
// CUSTOM EXCEPTIONS
// -------------------------------------------------------------
// Purpose:
// - Provide typed error classes to represent common HTTP/network
//   failure cases in a readable, catchable way.
// - Used by NetworkApiService to map HTTP status codes and network
//   problems into domain-specific exceptions.
//
// Why typed exceptions?
// - Your UI/viewmodels can catch specific errors (e.g., Unauthorized)
//   and react accordingly (e.g., navigate to login).
// - You avoid scattering raw status code checks throughout the app.
//
// Typical mappings in NetworkApiService:
// - 400  -> BadRequestException
// - 401/403 -> UnauthorizedException
// - 404/other/IO -> FetchDataException (with server message when available)
// =============================================================

/// Generic data fetch failure:
/// - No internet connection (SocketException)
/// - Server errors (5xx) or unexpected status codes
/// - Non-JSON/invalid responses, etc.
///
/// UI handling idea:
/// - Show a retry prompt or "Check your connection" message.
class FetchDataException implements Exception {
  /// Human-readable reason for the failure (e.g., server/body message).
  final String message;

  FetchDataException(this.message);

  @override
  String toString() => 'FetchDataException: $message';
}

/// Bad request / validation failure:
/// - Usually HTTP 400 with field errors or constraints.
///
/// UI handling idea:
/// - Surface validation messages next to inputs.
/// - Ask the user to correct the data and retry.
class BadRequestException implements Exception {
  /// Details from the server about what was wrong with the request.
  final String message;

  BadRequestException(this.message);

  @override
  String toString() => 'BadRequestException: $message';
}

/// Unauthorized / forbidden access:
/// - HTTP 401 (not authenticated) or 403 (not allowed).
///
/// UI handling idea:
/// - If 401: prompt re-login or refresh token.
/// - If 403: show "You don't have permission" message.
class UnauthorizedException implements Exception {
  /// Details from the server explaining the auth/permission issue.
  final String message;

  UnauthorizedException(this.message);

  @override
  String toString() => 'UnauthorizedException: $message';
}