import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// IMPORTANT: Task 38 — one prior conversation turn, sent as part of
/// the request so the AI can answer follow-ups. Mirrors the backend's
/// `HistoryTurn` Pydantic model exactly.
///
/// `role` is Flutter-idiomatic (`assistant`) rather than Gemini-idiomatic
/// (`model`). The translation to `model` happens on the backend inside
/// `ai._build_contents`.
@immutable
class HistoryTurn {
  final String role; // 'user' | 'assistant'
  final String text;
  const HistoryTurn({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

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
  /// [history] is optional prior conversation context (Task 38). When
  /// non-null and non-empty it is serialised into the request body so
  /// Gemini can answer follow-ups. When null/empty the request is
  /// single-turn — existing single-message callers keep working.
  ///
  /// NEVER throws — network, timeout, validation, and parsing errors are
  /// captured into [ApiResult.fail]. The caller can `switch` on
  /// [ApiResult.error.kind] to decide what to show.
  Future<ApiResult> sendMessage(
    String message, {
    List<HistoryTurn>? history,
  }) async {
    final Uri url = baseUrl.resolve('/chat');
    // IMPORTANT: only include the history field when we actually have
    // turns to send. An empty list would still serialise as `[]` and
    // Gemini would treat it as a valid empty history; omitting the
    // field entirely matches what single-turn clients send today.
    final Map<String, dynamic> payload = {'message': message};
    if (history != null && history.isNotEmpty) {
      payload['history'] = history.map((t) => t.toJson()).toList();
    }
    try {
      final http.Response response = await _http
          .post(
            url,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
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

  /// Streams the assistant reply as it is being generated.
  ///
  /// IMPORTANT: Task 38½ — opts into the server's `/chat/stream`
  /// endpoint so the Flutter UI can render tokens as they arrive
  /// instead of waiting for the full reply. The first token usually
  /// reaches the client ~600 ms after the request; the rest stream in
  /// at the model's generation rate.
  ///
  /// Yields raw text chunks. The caller (ChatScreen) concatenates them
  /// into the AI bubble so the user sees a typewriter effect.
  ///
  /// Errors are surfaced as a final ApiResult.fail via the controller's
  /// done-future. The chunk stream itself stays clean — the server
  /// encodes mid-stream errors as `ERROR: <detail>\n` which we parse
  /// here and convert into a typed ApiError.
  Stream<String> sendMessageStream(
    String message, {
    List<HistoryTurn>? history,
  }) {
    final Uri url = baseUrl.resolve('/chat/stream');
    final Map<String, dynamic> payload = {'message': message};
    if (history != null && history.isNotEmpty) {
      payload['history'] = history.map((t) => t.toJson()).toList();
    }
    final http.Request request = http.Request('POST', url)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/plain'
      ..body = jsonEncode(payload);

    // We return a Stream<String>. The controller listens to the
    // underlying streaming response and forwards each decoded chunk
    // until the stream closes or an error mid-stream is detected.
    late StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () async {
        http.StreamedResponse? response;
        try {
          response = await _http.send(request).timeout(timeout);
        } on TimeoutException {
          controller.addError(
            const ApiError(
              ApiErrorKind.timeout,
              'The server took too long to respond. Please try again.',
            ),
          );
          await controller.close();
          return;
        } on http.ClientException catch (e) {
          controller.addError(
            ApiError(
              ApiErrorKind.network,
              'Could not reach the server: ${e.message}',
            ),
          );
          await controller.close();
          return;
        } catch (e) {
          controller.addError(
            ApiError(ApiErrorKind.network, 'Network error: $e'),
          );
          await controller.close();
          return;
        }

        // Non-2xx: convert to typed ApiError so the chat screen can
        // show an error bubble instead of an empty AI bubble.
        if (response.statusCode < 200 || response.statusCode >= 300) {
          controller.addError(
            ApiError(
              _kindFor(response.statusCode, ''),
              'Streaming endpoint returned HTTP ${response.statusCode}.',
              statusCode: response.statusCode,
            ),
          );
          await controller.close();
          return;
        }

        // Read the response stream line by line. The wire format
        // sends each text delta on its own line; a single `\n` marks
        // end-of-stream. Mid-stream errors arrive as `ERROR: <msg>\n`.
        try {
          final lines = response.stream
              .transform(const Utf8Decoder())
              .transform(const LineSplitter());
          await for (final line in lines) {
            if (line.isEmpty) {
              // End-of-stream sentinel.
              break;
            }
            if (line.startsWith('ERROR: ')) {
              controller.addError(
                ApiError(
                  ApiErrorKind.aiUnavailable,
                  line.substring('ERROR: '.length).trim(),
                ),
              );
              break;
            }
            controller.add(line);
          }
        } catch (e) {
          controller.addError(
            ApiError(ApiErrorKind.malformed, 'Stream interrupted: $e'),
          );
        } finally {
          await controller.close();
        }
      },
    );
    return controller.stream;
  }

  void dispose() {
    _http.close();
  }
}

/// IMPORTANT: picks the right base URL for the current platform.
///
///   - Desktop / web (local dev):  http://127.0.0.1:8765
///   - Android emulator (local):   http://10.0.2.2:8765   ← host loopback
///   - iOS simulator (local):      http://127.0.0.1:8765
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
    return Uri.parse('http://10.0.2.2:8765');
  }
  return Uri.parse('http://127.0.0.1:8765');
}
