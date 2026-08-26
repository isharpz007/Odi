import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// IMPORTANT: Task 24 — typed result for ApiClient.sendMessage.
///
/// - On success: `reply` is the assistant text and `error` is null.
/// - On failure: `reply` is null and `error` carries an [ApiError].
///
/// Callers (e.g. ChatScreen) switch on this union to decide whether to
/// append an AI bubble or surface an error to the user.
@immutable
class ApiResult {
  final String? reply;
  final ApiError? error;
  const ApiResult.ok(this.reply) : error = null;
  const ApiResult.fail(this.error) : reply = null;
}

/// IMPORTANT: Task 24 — typed error model that mirrors the wire-format
/// errors defined in `backend/API_DESIGN.md` §5. The Flutter side
/// branches on `kind` rather than on the message string, so a stable
/// enum drives the UI.
@immutable
class ApiError {
  final ApiErrorKind kind;
  final String detail;
  final int? statusCode;
  const ApiError(this.kind, this.detail, {this.statusCode});
}

enum ApiErrorKind {
  /// Server returned HTTP 422 — the request body was invalid.
  validation,

  /// Server returned HTTP 502 — the AI layer failed to produce a reply.
  aiUnavailable,

  /// Server returned HTTP 5xx — generic internal error.
  internal,

  /// The Flutter side timed out waiting for a response.
  timeout,

  /// Network failure: host unreachable, DNS error, refused connection.
  network,

  /// Response body wasn't valid JSON or didn't match the expected shape.
  malformed,
}

/// IMPORTANT: Task 24 — minimal client for the OdiAI chat backend.
///
/// Owns the HTTP transport for `POST /chat`. The rest of the app only
/// depends on `sendMessage(text) → Future<ApiResult>` so the host URL,
/// serialization, and error mapping live in one place.
///
/// API contract (mirrors backend/API_DESIGN.md):
///   request  : POST {baseUrl}/chat   body: {"message": "..."}
///   response : 200 {"reply": "..."}
///   errors   : 4xx/5xx {"error": "...", "detail": "..."}
class ApiClient {
  final Uri baseUrl;
  final http.Client _http;
  final Duration timeout;

  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  /// Fetches the initial greeting from the backend.
  ///
  /// IMPORTANT: Task 25 — replaces the hardcoded welcome bubble that used
  /// to seed the conversation. The greeting now lives on the server
  /// (`GET /welcome`) so every assistant message the user sees comes
  /// from FastAPI. Returns the same [ApiResult] shape as [sendMessage].
  Future<ApiResult> fetchWelcome() async {
    final Uri url = baseUrl.resolve('/welcome');
    try {
      final http.Response response = await _http
          .get(
            url,
            headers: const {
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);

      return _handleResponse(response);
    } on TimeoutException {
      return ApiResult.fail(
        const ApiError(
          ApiErrorKind.timeout,
          'The server took too long to respond. Please try again.',
        ),
      );
    } on http.ClientException catch (e) {
      return ApiResult.fail(
        ApiError(
          ApiErrorKind.network,
          'Could not reach the server: ${e.message}',
        ),
      );
    } catch (e) {
      return ApiResult.fail(
        ApiError(
          ApiErrorKind.network,
          'Network error: $e',
        ),
      );
    }
  }

  /// Sends [message] to the backend and returns the assistant reply.
  ///
  /// NEVER throws — network, timeout, validation, and parsing errors are
  /// captured into [ApiResult.fail]. The caller can `switch` on
  /// [ApiResult.error.kind] to decide what to show.
  Future<ApiResult> sendMessage(String message) async {
    final Uri url = baseUrl.resolve('/chat');
    try {
      final http.Response response = await _http
          .post(
            url,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'message': message}),
          )
          .timeout(timeout);

      return _handleResponse(response);
    } on TimeoutException {
      return ApiResult.fail(
        const ApiError(
          ApiErrorKind.timeout,
          'The server took too long to respond. Please try again.',
        ),
      );
    } on http.ClientException catch (e) {
      return ApiResult.fail(
        ApiError(
          ApiErrorKind.network,
          'Could not reach the server: ${e.message}',
        ),
      );
    } catch (e) {
      return ApiResult.fail(
        ApiError(
          ApiErrorKind.network,
          'Network error: $e',
        ),
      );
    }
  }

  ApiResult _handleResponse(http.Response response) {
    final int status = response.statusCode;
    final String body = response.body;

    // Success: parse { "reply": "..." } and return the reply string.
    if (status >= 200 && status < 300) {
      try {
        final dynamic decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> &&
            decoded['reply'] is String &&
            (decoded['reply'] as String).isNotEmpty) {
          return ApiResult.ok(decoded['reply'] as String);
        }
        return ApiResult.fail(
          ApiError(
            ApiErrorKind.malformed,
            'Server reply was missing the "reply" field.',
            statusCode: status,
          ),
        );
      } catch (_) {
        return ApiResult.fail(
          ApiError(
            ApiErrorKind.malformed,
            'Server reply was not valid JSON.',
            statusCode: status,
          ),
        );
      }
    }

    // Error: try to parse { "error": "...", "detail": "..." }.
    // If the body is not a JSON object (e.g. a plain string from a
    // framework default), fall back to the raw text so the user still
    // gets *something* to read. We also accept the nested form
    // `{ "detail": { "error": "...", "detail": "..." } }` produced by
    // some FastAPI defaults, so older endpoints don't break the UI.
    String errorCode = '';
    String detail = body;
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        errorCode = (decoded['error'] as String?) ?? '';
        detail = (decoded['detail'] as String?) ?? detail;
        // Nested envelope: { "detail": { "error", "detail" } }
        final dynamic nested = decoded['detail'];
        if (errorCode.isEmpty && nested is Map<String, dynamic>) {
          errorCode = (nested['error'] as String?) ?? '';
          final dynamic nestedDetail = nested['detail'];
          if (nestedDetail is String) detail = nestedDetail;
        }
      }
    } catch (_) {
      // Body wasn't JSON — fall back to the raw text.
    }

    final ApiErrorKind kind = _kindFor(status, errorCode);
    return ApiResult.fail(ApiError(kind, detail, statusCode: status));
  }

  /// Maps a non-2xx HTTP status (plus any `error` code in the body) to
  /// a stable [ApiErrorKind]. The body `error` value is authoritative
  /// when present; we only fall back to status code if it's missing.
  ApiErrorKind _kindFor(int status, String errorCode) {
    switch (errorCode) {
      case 'validation_error':
        return ApiErrorKind.validation;
      case 'ai_unavailable':
        return ApiErrorKind.aiUnavailable;
      case 'internal_error':
        return ApiErrorKind.internal;
    }
    switch (status) {
      case 400:
      case 422:
        return ApiErrorKind.validation;
      case 408: // request timeout
      case 504: // gateway timeout
        return ApiErrorKind.timeout;
      case 502:
        return ApiErrorKind.aiUnavailable;
      default:
        // IMPORTANT: any status we don't have a specific mapping for
        // (401, 403, 404, other 4xx, unexpected 5xx) is treated as a
        // server-side issue. Validation errors always come through with
        // a 4xx status the contract recognises; everything else here is
        // an unexpected server state, which is what `internal` means
        // to the UI.
        return ApiErrorKind.internal;
    }
  }

  void dispose() {
    _http.close();
  }
}

/// IMPORTANT: picks the right base URL for the current platform.
///
///   - Desktop / web (local dev):  http://127.0.0.1:8000
///   - Android emulator (local):   http://10.0.2.2:8000   ← host loopback
///   - iOS simulator (local):      http://127.0.0.1:8000
///   - Production:                 overridden via --dart-define
///
/// Android emulators can't reach the host via 127.0.0.1 because that
/// resolves to the emulator itself; 10.0.2.2 is the special alias the
/// emulator uses to reach the host machine.
Uri defaultBaseUrl() {
  const String fromEnv =
      String.fromEnvironment('ODIAI_API_BASE_URL', defaultValue: '');
  if (fromEnv.isNotEmpty) return Uri.parse(fromEnv);

  // IMPORTANT: simple platform switch. Desktop and web point to the
  // loopback address of the dev machine. Android emulator uses 10.0.2.2.
  if (defaultTargetPlatform == TargetPlatform.android) {
    return Uri.parse('http://10.0.2.2:8000');
  }
  return Uri.parse('http://127.0.0.1:8000');
}
