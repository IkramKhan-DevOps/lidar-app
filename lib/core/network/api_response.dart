// ApiResponse<T>
// -----------------------------------------------------------------------------
// A simple, generic wrapper used to represent the state of an API call.
// It lets your UI or calling code know whether a request is:
// - LOADING   (in progress),
// - COMPLETE  (finished successfully), or
// - ERROR     (failed),
// and optionally carry the resulting data and/or an error message.
//
// Usage example:
//   // Start a request:
//   var res = ApiResponse<User>.loading();
//
//   // On success:
//   res = ApiResponse<User>(user, Status.COMPLETE, null);
//
//   // On error:
//   res = ApiResponse<User>(null, Status.ERROR, 'Unable to fetch user');
//
// Note: The Status enum comes from api_status.dart and is expected to define
// values like LOADING, COMPLETE, and ERROR.
// -----------------------------------------------------------------------------

import 'api_status.dart';

class ApiResponse<T> {
  // The current status of the API call (e.g., LOADING, COMPLETE, ERROR).
  Status? status;

  // The payload returned by the API on success.
  // T is generic so you can carry any model type (e.g., User, List<Post>, etc).
  T? data;

  // An optional message, commonly used for error details or informational text.
  String? message;

  // Primary constructor:
  // Provide all three pieces of information explicitly:
  // - data:    The response data (nullable)
  // - status:  The current state of the API call
  // - message: Optional detail (e.g., error description)
  ApiResponse(this.data, this.status, this.message);

  // Convenience constructor for a "loading" state.
  // Sets status to LOADING; data/message remain null.
  ApiResponse.loading() : status = Status.LOADING;

  // Convenience constructor for a "complete/success" state.
  // Sets status to COMPLETE; data/message are not set here—use the primary
  // constructor to include data when needed.
  ApiResponse.complete() : status = Status.COMPLETE;

  // Convenience constructor for an "error" state.
  // Sets status to ERROR; attach a message via the primary constructor when
  // you need to show more details about the failure.
  ApiResponse.error() : status = Status.ERROR;

  // Helpful for logging/debugging: prints the current state, message, and data.
  @override
  String toString() {
    return 'Status: $status \nMessage: $message \nData: $data';
  }
}