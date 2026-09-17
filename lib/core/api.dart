import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// The **full API root**, including whatever path the backend is mounted under.
///
/// This is the whole value, not a host: the backend has been mounted under a
/// prefix in the CRM, and a client that appends its own `/api` cannot reach it.
///
///   standalone backend   http://localhost:4000/api
///   inside the CRM       https://uat-api.vistarlogitek.com//api/v1/pfep
///
/// Override at build time:
///   flutter build web --release \
///     --dart-define=PFEP_API=https://uat-api.vistarlogitek.com//api/v1/pfep
///
/// Android emulators reach the host machine on 10.0.2.2, not localhost, so that
/// is the default there - it is the single most common first-run stumble.
String resolveApiRoot() {
  const fromEnv = String.fromEnvironment('PFEP_API');
  if (fromEnv.isNotEmpty) return fromEnv.replaceAll(RegExp(r'/+$'), '');
  try {
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:4000/api';
  } catch (_) {
    // Platform is unavailable on some targets; fall through to localhost.
  }
  // Deliberately localhost, never the page's own origin. A default that points
  // at wherever the app happens to be served from turns a missing --dart-define
  // into a 405 from the static host, which reads like a backend fault rather
  // than a build that was never told where the backend is.
  return 'http://localhost:4000/api';
}

/// True when a deployed web build was never told where its API is: it is being
/// served from a real origin but still points at a developer's own machine.
/// Surfaced in the connection error, because otherwise this is invisible.
bool _looksUnconfigured(String apiRoot) {
  if (!kIsWeb) return false;
  final api = Uri.tryParse(apiRoot);
  final page = Uri.base;
  const local = {'localhost', '127.0.0.1'};
  return api != null && local.contains(api.host) && !local.contains(page.host);
}

/// Thrown for any non-2xx response, carrying the message the API produced so
/// the UI can show the real reason rather than "something went wrong".
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final dynamic details;

  bool get isOffline => statusCode == null;
  bool get isConflict => statusCode == 409;
  bool get isIncomplete => statusCode == 422;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? resolveApiRoot() {
    _dio = Dio(BaseOptions(
      // `baseUrl` is already the API root - nothing is appended. The backend
      // answers at /api on its own, and at /api/v1/pfep inside the CRM, so the
      // prefix is part of the configured value rather than assumed here.
      baseUrl: this.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      validateStatus: (s) => s != null && s < 500,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) options.headers['Authorization'] = 'Bearer $_token';
        handler.next(options);
      },
    ));
  }

  final String baseUrl;
  late final Dio _dio;
  String? _token;

  /// Set once at sign-in; cleared on sign-out or a 401.
  void setToken(String? token) => _token = token;
  String? get token => _token;

  /// The scheme+host of [baseUrl], for resolving paths the API hands back.
  late final String _origin = _originOf(baseUrl);

  static String _originOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasAuthority) return '';
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null).toString();
  }

  /// Absolute URL for an image path returned by the API.
  ///
  /// The server emits those absolute from the site root, already carrying its
  /// mount point (`/api/v1/pfep/photos/x/file`), because they are consumed by
  /// `<img>` tags and by hyperlinks inside an exported workbook. So they
  /// resolve against the **origin**, not the API root - hanging them off the
  /// root would repeat the prefix and 404 every photograph.
  String fileUrl(String path) => path.startsWith('http') ? path : '$_origin$path';

  Map<String, String> get authHeaders => _token == null ? {} : {'Authorization': 'Bearer $_token'};

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _dio.post(path, data: body, queryParameters: _clean(query)));

  Future<dynamic> patch(String path, {Object? body}) => _send(() => _dio.patch(path, data: body));

  Future<dynamic> put(String path, {Object? body}) => _send(() => _dio.put(path, data: body));

  Future<dynamic> delete(String path) => _send(() => _dio.delete(path));

  Future<dynamic> upload(String path, FormData form) => _send(() => _dio.post(path, data: form));

  /// Binary fetch for Excel/PDF/ZPL output.
  Future<Uint8List> download(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.statusCode! >= 400) {
        throw ApiException(_messageFromBytes(res.data), statusCode: res.statusCode);
      }
      return Uint8List.fromList(res.data!);
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  Future<dynamic> _send(Future<Response> Function() run) async {
    try {
      final res = await run();
      if (res.statusCode! >= 400) {
        final data = res.data;
        final msg = data is Map && data['error'] != null ? '${data['error']}' : 'Request failed (${res.statusCode})';
        throw ApiException(msg, statusCode: res.statusCode, details: data is Map ? data['details'] : null);
      }
      return res.data;
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  ApiException _fromDio(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      if (_looksUnconfigured(baseUrl)) {
        return ApiException(
          'This build was not told where the PFEP API is, so it is still '
          'pointing at $baseUrl. Rebuild with '
          '--dart-define=PFEP_API=https://<host>/api/v1/pfep',
        );
      }
      return ApiException('No connection to the PFEP server at $baseUrl');
    }
    final data = e.response?.data;
    final msg = data is Map && data['error'] != null ? '${data['error']}' : (e.message ?? 'Network error');
    return ApiException(msg, statusCode: e.response?.statusCode, details: data is Map ? data['details'] : null);
  }

  String _messageFromBytes(List<int>? bytes) {
    if (bytes == null) return 'Download failed';
    try {
      final text = String.fromCharCodes(bytes);
      final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(text);
      return match?.group(1) ?? 'Download failed';
    } catch (_) {
      return 'Download failed';
    }
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v != null && v != '') out[k] = v;
    });
    return out;
  }
}
