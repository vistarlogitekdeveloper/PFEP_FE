import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pfep_frontend/core/telemetry.dart';

void main() {
  const rec = 'rec_mfx3k2a9q0wz7c1d8e';
  const usr = 'usr_mfx3k2a9hgbdtcyekl';
  const uuid = '7f3c2a10-1b2c-4d5e-8f90-a1b2c3d4e5f6';

  test('screen names are the app routes, with record ids replaced', () {
    for (final r in [
      '/login', '/dashboard', '/customers', '/part-master', '/vendors', '/field-config', '/label-formats',
      '/users', '/records', '/review', '/export', '/labels', '/audit', '/work', '/sync',
    ]) {
      expect(Telemetry.routePattern(r), r);
    }
    expect(Telemetry.routePattern('/records/$rec'), '/records/:id');
    expect(Telemetry.routePattern('/collect?record=$rec'), '/collect');
    expect(Telemetry.routePattern('/records?q=90210-ABX&status=Approved'), '/records');
  });

  test('customer codes, part numbers, vendor codes and config keys never survive', () {
    expect(Telemetry.routePattern('/customers/AXN/parts'), '/customers/:ref/parts');
    expect(Telemetry.routePattern('/customers/axn/dashboard'), '/customers/:ref/dashboard');
    expect(Telemetry.routePattern('/customers/AXN/parts/90210-ABX'), '/customers/:ref/parts/:ref');
    expect(Telemetry.routePattern('/vendors/V-1042'), '/vendors/:ref');
    expect(Telemetry.routePattern('/vendors/sharma_auto'), '/vendors/:ref');
    expect(Telemetry.routePattern('/records/$rec/photos/bin'), '/records/:id/photos/:ref');
    expect(Telemetry.routePattern('/customers/TRD/field-config/packaging/bin_qty'),
        '/customers/:ref/field-config/:ref/:ref');
    expect(Telemetry.routePattern('/customers/TRD/label-templates/rack'), '/customers/:ref/label-templates/:ref');
    expect(Telemetry.routePattern('/users/$usr'), '/users/:id');
    expect(Telemetry.routePattern('/users/sandeep'), '/users/:ref');
    expect(Telemetry.routePattern('/records/42'), '/records/:id');
    expect(Telemetry.routePattern('/records/$uuid'), '/records/:id');
    expect(Telemetry.routePattern('https://uat-api.example.com/api/v1/pfep/customers/AXN/parts'),
        '/api/v1/pfep/customers/:ref/parts');
  });

  test('the PFEP journey is named from successful writes', () {
    expect(Telemetry.actionFor('PATCH', '/records/$rec'), 'record_saved');
    expect(Telemetry.actionFor('POST', '/records/$rec/submit'), 'record_submitted');
    expect(Telemetry.actionFor('POST', '/records/$rec/photos/bin'), 'photo_uploaded');
    expect(Telemetry.actionFor('DELETE', '/records/$rec/photos/part'), 'photo_deleted');
    expect(Telemetry.actionFor('POST', '/sync/batch'), 'offline_queue_synced');
    expect(Telemetry.actionFor('POST', '/records/$rec/approve'), 'record_approved');
    expect(Telemetry.actionFor('POST', '/records/$rec/reject'), 'record_rejected');
    expect(Telemetry.actionFor('post', '/records/$rec/assign'), 'record_assigned');
    expect(Telemetry.actionFor('POST', '/customers/AXN/parts'), 'part_created');
    expect(Telemetry.actionFor('DELETE', '/customers/AXN/parts/prt_mfx3k2a9q0wz7c'), 'part_deleted');
    expect(Telemetry.actionFor('POST', '/customers/AXN/parts/import'), 'part_master_import_checked');
    expect(Telemetry.actionFor('POST', '/customers/AXN/parts/import', committed: true), 'part_master_imported');
    expect(Telemetry.actionFor('POST', '/customers'), 'customer_created');
    expect(Telemetry.actionFor('PATCH', '/customers/AXN'), 'customer_updated');
    expect(Telemetry.actionFor('POST', '/vendors'), 'vendor_created');
    expect(Telemetry.actionFor('PATCH', '/vendors/V-1042'), 'vendor_updated');
    expect(Telemetry.actionFor('POST', '/vendors/V-1042/distance'), 'vendor_distance_calculated');
    expect(Telemetry.actionFor('PATCH', '/customers/AXN/field-config/packaging/bin_qty'), 'field_config_changed');
    expect(Telemetry.actionFor('POST', '/customers/AXN/field-config/packaging'), 'field_added');
    expect(Telemetry.actionFor('PUT', '/customers/AXN/label-templates/rack'), 'label_format_saved');
    expect(Telemetry.actionFor('POST', '/users'), 'user_created');
    expect(Telemetry.actionFor('PATCH', '/users/$usr'), 'user_updated');
    expect(Telemetry.actionFor('POST', '/auth/change-password'), 'password_changed');
  });

  test('reads, exports, label files, sign-in and unknown paths are not reported', () {
    expect(Telemetry.actionFor('GET', '/records/$rec'), isNull);
    expect(Telemetry.actionFor('GET', '/customers/AXN/records'), isNull);
    expect(Telemetry.actionFor('GET', '/customers/AXN/export/xlsx'), isNull);
    expect(Telemetry.actionFor('GET', '/records/$rec/label'), isNull);
    expect(Telemetry.actionFor('GET', '/sync/ping'), isNull);
    expect(Telemetry.actionFor('GET', '/sync/bootstrap'), isNull);
    expect(Telemetry.actionFor('POST', '/auth/login'), isNull);
    expect(Telemetry.actionFor('DELETE', '/records/$rec'), isNull);
    expect(Telemetry.actionFor('POST', '/somewhere/new'), isNull);
  });

  test('a part-master import counts as committed only when its form says so', () {
    expect(Telemetry.committed(FormData.fromMap({'commit': 'true', 'replace': 'false'})), isTrue);
    expect(Telemetry.committed(FormData.fromMap({'commit': 'false', 'replace': 'true'})), isFalse);
    expect(Telemetry.committed({'commit': 'true'}), isFalse);
    expect(Telemetry.committed(null), isFalse);
  });

  test('off without ET_APP_ID and ET_WRITE_KEY (the default build); calls are safe', () async {
    expect(Telemetry.enabled, isFalse);
    await Telemetry.init();
    Telemetry.screen('/dashboard');
    Telemetry.track('record_submitted');
    Telemetry.error('api_error', {'endpoint': '/records/:id/submit', 'method': 'POST'});
    Telemetry.signedIn(userId: usr, role: 'Collector');
    Telemetry.signedOut();
  });

  test('the interceptor changes nothing about a request or its outcome', () async {
    // This client's validateStatus: below 500 is a response, not an error.
    final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid', validateStatus: (s) => s != null && s < 500))
      ..httpClientAdapter = _Answer()
      ..interceptors.add(TelemetryInterceptor());
    final ok = await dio.post<dynamic>('/records/$rec/submit', data: {'device': 'MOB-A-014'});
    expect(ok.statusCode, 200);
    expect((ok.data as Map)['ok'], isTrue);
    final incomplete = await dio.post<dynamic>('/records/$rec/approve');
    expect(incomplete.statusCode, 422);
    await expectLater(
      dio.get<dynamic>('/sync/ping'),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 503)),
    );
  });
}

/// 200 for a submission, 422 for an approval, 503 for anything else; no
/// network.
class _Answer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final status = options.path.endsWith('/submit')
        ? 200
        : options.path.endsWith('/approve')
            ? 422
            : 503;
    return ResponseBody.fromString(
      jsonEncode({'ok': status == 200}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
