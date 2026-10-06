import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:vistar_event_tracker/vistar_event_tracker.dart'
    show EventType, TrackerConfig, VistarEventTracker, VistarEvents;

import 'api.dart' show resolveApiRoot;

/// Usage analytics for the PFEP app, sent to the in-house event tracker and
/// read in the Platform Console under Analytics > Event tracker.
///
/// Off unless the build is given both:
///   --dart-define=ET_APP_ID=pfep_app --dart-define=ET_WRITE_KEY=wk_...
/// (register the app in the Platform Console, Settings > Event tracker; the
/// write key only lets a client append events, so it may ship in the app).
/// Optional --dart-define=ET_BASE_URL=... sends a test build's events
/// somewhere other than the API host the app uses (by default, the host of
/// PFEP_API, so a UAT build reports to UAT).
///
/// What is sent:
///   * screen views, by route pattern (`/records/:id`; any value in a path is
///     replaced, see [routePattern])
///   * sign-in / sign-out; the user as `pfep:<user id>` (the opaque `usr_...`
///     key, never the username), with their role as the only trait
///   * named actions from successful API writes (see [_actions]):
///     `record_submitted`, `photo_uploaded`, `record_approved`,
///     `part_master_imported`, ...
///   * failed API calls (5xx or no connection), and client errors by TYPE
///     only (never the message, which can quote a server reply)
/// Never sent: request or response bodies, usernames, names, employee codes,
/// phone numbers, emails, part numbers, supplier (vendor) names, customer
/// codes, quantities, dimensions, photos, notes or any other record content.
/// The camera and webcam flows are not touched: only the resulting successful
/// upload is counted.
///
/// NEVER IN THE WAY OF WORK. Nothing here is awaited by a screen, a save, a
/// sign-in or a sign-out; start-up waits at most [_initBudget]; every call
/// swallows its own failures; the queue is capped at [_maxQueue] events
/// (oldest dropped) and lives in shared preferences; sending is in the
/// background with the SDK's backoff, so a collector offline at a vendor site
/// loses nothing of their own work to it.
abstract final class Telemetry {
  static const _appId = String.fromEnvironment('ET_APP_ID');
  static const _writeKey = String.fromEnvironment('ET_WRITE_KEY');
  static const _baseUrlOverride = String.fromEnvironment('ET_BASE_URL');
  static const _appVersion = String.fromEnvironment('APP_VERSION');
  static const _initBudget = Duration(seconds: 2);
  static const _maxQueue = 200;

  static bool get enabled => _appId != '' && _writeKey != '';

  static VistarEventTracker get _t => VistarEventTracker.instance;
  static bool get _on => enabled && _t.isInitialized;

  static String? _lastScreen;
  static Future<void>? _resetting;

  static String get _origin {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    final u = Uri.parse(resolveApiRoot());
    return '${u.scheme}://${u.authority}';
  }

  static Future<void> init() async {
    if (!enabled) return;
    try {
      await _t
          .init(TrackerConfig(
            appId: _appId,
            writeKey: _writeKey,
            baseUrl: _origin,
            appVersion: _appVersion.isEmpty ? null : _appVersion,
            maxQueueSize: _maxQueue,
            // The SDK's own error capture sends the exception message and
            // stack, and a message here can quote a server reply (a part
            // number, a vendor). [_captureErrors] sends the type only.
            autoCaptureErrors: false,
          ))
          .timeout(_initBudget);
      _captureErrors();
    } catch (_) {
      // Analytics must never stop the app from starting.
    }
  }

  /// Client errors, by type only. Chains to whatever handled them before, so
  /// the app's own error handling is unchanged.
  static void _captureErrors() {
    if (!_on) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _clientError(details.exception, fatal: false, library: details.library);
      previous?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousAsync = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      _clientError(error, fatal: true);
      return previousAsync?.call(error, stack) ?? false;
    };
  }

  static void _clientError(Object e, {required bool fatal, String? library}) {
    try {
      error(VistarEvents.clientError, {
        'error': e.runtimeType.toString(),
        'library': ?library,
        'fatal': fatal,
      });
    } catch (_) {}
  }

  /// A screen, by its route pattern. Repeats are dropped.
  static void screen(String location) {
    if (!_on) return;
    final name = routePattern(location);
    if (name == _lastScreen) return;
    _lastScreen = name;
    _guard(() => _t.screen(name));
  }

  static void track(String name, [Map<String, dynamic>? properties]) {
    if (_on) _guard(() => _t.track(name, properties: properties));
  }

  static void error(String name, Map<String, dynamic> properties) {
    if (_on) _guard(() => _t.track(name, properties: properties, type: EventType.error));
  }

  static void _guard(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Analytics never surfaces as an app error.
    }
  }

  /// Fire and forget: the sign-in never waits for analytics.
  ///
  /// Called just BEFORE the session state changes. With no sign-out in flight
  /// the SDK sets the user synchronously (before its first await), so the
  /// screen the sign-in leads to is already attributed to them.
  static void signedIn({required String userId, String? role}) {
    if (!_on || userId.isEmpty) return;
    final id = 'pfep:$userId';
    final traits = <String, dynamic>{
      if (role != null && role.isNotEmpty) 'role': role,
    };
    final pending = _resetting;
    if (pending == null) {
      _identify(id, traits);
      return;
    }
    // A sign-out just before (a shared phone changing hands) resets the
    // identity; let it finish so this one is not wiped by it.
    unawaited(() async {
      try {
        await pending.timeout(const Duration(seconds: 5), onTimeout: () {});
      } catch (_) {}
      _identify(id, traits);
    }());
  }

  static void _identify(String id, Map<String, dynamic> traits) {
    try {
      unawaited(_t.identify(id, traits: traits).catchError((Object _) {}));
    } catch (_) {}
  }

  /// Fire and forget: the sign-out never waits for analytics (the SDK's reset
  /// sends what is queued first, which can take a while on a poor network).
  static void signedOut() {
    _lastScreen = null;
    if (!_on) return;
    try {
      late final Future<void> done;
      done = _t.reset().catchError((Object _) {}).whenComplete(() {
        if (identical(_resetting, done)) _resetting = null;
      });
      _resetting = done;
    } catch (_) {}
  }

  /// Every fixed segment of this app's screens and of the PFEP API paths it
  /// calls (relative to PFEP_API, `.../api/v1/pfep`).
  static const _static = {
    // API mount
    'api', 'v1', 'pfep',
    // screens
    'login', 'dashboard', 'customers', 'part-master', 'vendors',
    'field-config', 'label-formats', 'users', 'records', 'review', 'export',
    'labels', 'audit', 'work', 'collect', 'sync',
    // API
    'auth', 'me', 'change-password', 'distance', 'status', 'parts', 'import',
    'template.xlsx', 'label-templates', 'submit', 'approve', 'reject',
    'assign', 'photos', 'file', 'label', 'preview', 'my', 'review-queue',
    'xlsx', 'csv', 'ping', 'bootstrap', 'batch',
  };

  /// `/records/rec_m8k2.../photos/bin?x=1` -> `/records/:id/photos/:ref`.
  ///
  /// Stricter than "replace anything with a digit": PFEP's keys include
  /// customer codes with no digit (`AXN`) and generated ids that can happen
  /// to have none, and admins name field-config sections, fields, photo types
  /// and label kinds. So only the segments in [_static] are kept; digits
  /// only, a UUID or a generated id (`rec_...`, `usr_...`) become `:id`;
  /// everything else (customer codes, part numbers, vendor codes, config keys)
  /// becomes `:ref`. The query string is dropped.
  static String routePattern(String location) {
    final path = Uri.tryParse(location)?.path ?? location.split('?').first;
    return path.split('/').map((s) {
      if (s.isEmpty) return s;
      if (RegExp(r'^\d+$').hasMatch(s)) return ':id';
      if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-', caseSensitive: false).hasMatch(s)) return ':id';
      if (_static.contains(s)) return s;
      if (RegExp(r'^[a-z]{2,6}_[0-9a-z]{6,}$').hasMatch(s)) return ':id';
      return ':ref';
    }).join('/');
  }

  /// Successful API writes worth naming, by method and path (ids stripped).
  /// First match wins; anything else (reads, exports, label files, sign-in,
  /// unknown paths) is not reported.
  static final List<(String, RegExp, String)> _actions = [
    // Field collection (BRD 4.4-4.6)
    ('PATCH', RegExp(r'^/records/:(id|ref)$'), 'record_saved'),
    ('POST', RegExp(r'^/records/:(id|ref)/submit$'), 'record_submitted'),
    ('POST', RegExp(r'^/records/:(id|ref)/photos/:(id|ref)$'), 'photo_uploaded'),
    ('DELETE', RegExp(r'^/records/:(id|ref)/photos/:(id|ref)$'), 'photo_deleted'),
    ('POST', RegExp(r'^/sync/batch$'), 'offline_queue_synced'),
    // Review (BRD 4.7)
    ('POST', RegExp(r'^/records/:(id|ref)/approve$'), 'record_approved'),
    ('POST', RegExp(r'^/records/:(id|ref)/reject$'), 'record_rejected'),
    ('POST', RegExp(r'^/records/:(id|ref)/assign$'), 'record_assigned'),
    // Part master
    ('POST', RegExp(r'^/customers/:(id|ref)/parts$'), 'part_created'),
    ('DELETE', RegExp(r'^/customers/:(id|ref)/parts/:(id|ref)$'), 'part_deleted'),
    // POST /customers/:ref/parts/import: see [actionFor] (check vs commit).
    // Customers, vendors
    ('POST', RegExp(r'^/customers$'), 'customer_created'),
    ('PATCH', RegExp(r'^/customers/:(id|ref)$'), 'customer_updated'),
    ('POST', RegExp(r'^/vendors$'), 'vendor_created'),
    ('PATCH', RegExp(r'^/vendors/:(id|ref)$'), 'vendor_updated'),
    ('POST', RegExp(r'^/vendors/:(id|ref)/distance$'), 'vendor_distance_calculated'),
    // Configuration
    ('PATCH', RegExp(r'^/customers/:(id|ref)/field-config/:(id|ref)/:(id|ref)$'), 'field_config_changed'),
    ('POST', RegExp(r'^/customers/:(id|ref)/field-config/:(id|ref)$'), 'field_added'),
    ('PUT', RegExp(r'^/customers/:(id|ref)/label-templates/:(id|ref)$'), 'label_format_saved'),
    // Administration
    ('POST', RegExp(r'^/users$'), 'user_created'),
    ('PATCH', RegExp(r'^/users/:(id|ref)$'), 'user_updated'),
    ('POST', RegExp(r'^/auth/change-password$'), 'password_changed'),
  ];

  static final _import = RegExp(r'^/customers/:(id|ref)/parts/import$');

  /// The business event for a successful API call, or null. [committed] says
  /// whether a part-master import was the real one rather than its check
  /// (the same endpoint, `commit=false` first).
  static String? actionFor(String method, String path, {bool committed = false}) {
    final pattern = routePattern(path);
    final m = method.toUpperCase();
    if (m == 'POST' && _import.hasMatch(pattern)) {
      return committed ? 'part_master_imported' : 'part_master_import_checked';
    }
    for (final (am, re, name) in _actions) {
      if (am == m && re.hasMatch(pattern)) return name;
    }
    return null;
  }

  /// Whether an upload's form says `commit=true` (the part-master import).
  /// Reads that one flag only.
  static bool committed(Object? data) {
    if (data is! FormData) return false;
    for (final f in data.fields) {
      if (f.key == 'commit') return f.value == 'true';
    }
    return false;
  }
}

/// Reports named actions and failed calls from the app's one HTTP client
/// (core/api.dart). Adds no headers and changes nothing about the request or
/// its handling.
class TelemetryInterceptor extends Interceptor {
  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    // This client's validateStatus accepts anything below 500, so a 4xx
    // refusal (an incomplete record, a version conflict) arrives HERE and
    // must not count: only a 2xx is an action that happened.
    final code = response.statusCode ?? 0;
    if (Telemetry.enabled && code >= 200 && code < 300) {
      String? name;
      try {
        final o = response.requestOptions;
        name = Telemetry.actionFor(o.method, o.path, committed: Telemetry.committed(o.data));
      } catch (_) {}
      if (name != null) Telemetry.track(name);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (Telemetry.enabled) {
      try {
        final status = err.response?.statusCode;
        // A 4xx is a decision the server made, and a cancel is the app's own.
        // /sync/ping is the app's own connectivity probe (every 20 s): offline
        // at a vendor site it fails by design, and reporting each one would
        // fill the event queue and push out everything else.
        final probe = Telemetry.routePattern(err.requestOptions.path) == '/sync/ping';
        if ((status == null || status >= 500) && err.type != DioExceptionType.cancel && !probe) {
          Telemetry.error('api_error', {
            'endpoint': Telemetry.routePattern(err.requestOptions.path),
            'method': err.requestOptions.method,
            'status': ?status,
            'kind': err.type.name,
          });
        }
      } catch (_) {}
    }
    handler.next(err);
  }
}
