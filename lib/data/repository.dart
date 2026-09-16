import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/offline_queue.dart';
import '../models/models.dart';

/// Every call the app makes to the Node backend lives here, so the widgets stay
/// free of transport details and the offline path has one place to live.
class PfepRepository {
  PfepRepository(this.api);

  final ApiClient api;
  final OfflineQueue queue = OfflineQueue.instance;

  /* ------------------------------------------------------------------ auth */

  Future<({String token, AppUser user})> login(String username, String password, {String? device}) async {
    final j = await api.post('/auth/login', body: {
      'username': username,
      'password': password,
      'device': ?device,
    }) as Map<String, dynamic>;
    return (token: '${j['token']}', user: AppUser.fromJson(Map<String, dynamic>.from(j['user'])));
  }

  Future<({AppUser user, List<Customer> customers, bool scoped})> me() async {
    final j = await api.get('/auth/me') as Map<String, dynamic>;
    return (
      user: AppUser.fromJson(Map<String, dynamic>.from(j['user'])),
      customers: (j['customers'] as List).map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList(),
      scoped: j['scoped'] == true,
    );
  }

  /* ------------------------------------------------------------- customers */

  Future<List<Customer>> customers() async {
    final j = await api.get('/customers') as List;
    return j.map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Customer> createCustomer(Map<String, dynamic> body) async =>
      Customer.fromJson(Map<String, dynamic>.from(await api.post('/customers', body: body)));

  Future<Customer> updateCustomer(String id, Map<String, dynamic> body) async =>
      Customer.fromJson(Map<String, dynamic>.from(await api.patch('/customers/$id', body: body)));

  /* ---------------------------------------------------------------- vendors */

  Future<List<Vendor>> vendors({String? q}) async {
    final j = await api.get('/vendors', query: {'q': q}) as List;
    return j.map((e) => Vendor.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Vendor> createVendor(Map<String, dynamic> body) async =>
      Vendor.fromJson(Map<String, dynamic>.from(await api.post('/vendors', body: body)));

  /// BRD 4.3 - whether the server can measure distances at all.
  Future<DistanceStatus> distanceStatus() async =>
      DistanceStatus.fromJson(Map<String, dynamic>.from(await api.get('/vendors/distance/status')));

  /// Measures this vendor from the customer's plant and stores the result with
  /// its provenance. Explicit, never automatic: it can overwrite a surveyed
  /// number, so it stays something an admin asks for.
  Future<Vendor> measureVendorDistance(String vendorId, String customerId) async =>
      Vendor.fromJson(Map<String, dynamic>.from(
          await api.post('/vendors/$vendorId/distance', body: {'customerId': customerId})));

  Future<Vendor> updateVendor(String id, Map<String, dynamic> body) async =>
      Vendor.fromJson(Map<String, dynamic>.from(await api.patch('/vendors/$id', body: body)));

  /* ------------------------------------------------------------------ parts */

  Future<List<Part>> parts(String customerId, {String? q}) async {
    final j = await api.get('/customers/$customerId/parts', query: {'q': q}) as List;
    return j.map((e) => Part.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Uint8List> partTemplate() => api.download('/parts/template.xlsx');

  /// BRD 4.1 - two-phase upload: validate, show the report, then commit.
  Future<ImportReport> importPartMaster({
    required String customerId,
    required Uint8List bytes,
    required String filename,
    bool commit = false,
    bool replace = false,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'commit': commit.toString(),
      'replace': replace.toString(),
    });
    final j = await api.upload('/customers/$customerId/parts/import', form);
    return ImportReport.fromJson(Map<String, dynamic>.from(j));
  }

  Future<void> addPart(String customerId, Map<String, dynamic> body) =>
      api.post('/customers/$customerId/parts', body: body);

  /* ----------------------------------------------------------- field config */

  Future<FieldConfig> fieldConfig(String customerId) async =>
      FieldConfig.fromJson(Map<String, dynamic>.from(await api.get('/customers/$customerId/field-config')));

  Future<void> toggleField(String customerId, String section, String key,
          {bool? enabled, bool? required}) =>
      api.patch('/customers/$customerId/field-config/$section/$key', body: {
        'enabled': ?enabled,
        'required': ?required,
      });

  Future<void> addField(String customerId, String section, Map<String, dynamic> body) =>
      api.post('/customers/$customerId/field-config/$section', body: body);

  /* ---------------------------------------------------------------- records */

  Future<List<PfepRecord>> records(
    String customerId, {
    String? status,
    String? q,
    bool mine = false,
  }) async {
    final j = await api.get('/customers/$customerId/records', query: {
      'status': status,
      'q': q,
      if (mine) 'mine': 'true',
    }) as List;
    return j.map((e) => PfepRecord.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<PfepRecord> record(String id) async =>
      PfepRecord.fromJson(Map<String, dynamic>.from(await api.get('/records/$id')));

  /// Saves field values. When the phone is offline the edit is queued and the
  /// caller gets `null` back, meaning "kept locally, will sync".
  Future<PfepRecord?> saveData(
    String recordId,
    Map<String, dynamic> data, {
    int? version,
    String? device,
    String label = '',
    bool allowQueue = true,
  }) async {
    try {
      final j = await api.patch('/records/$recordId', body: {
        'data': data,
        'version': ?version,
        'device': ?device,
      });
      return PfepRecord.fromJson(Map<String, dynamic>.from(j));
    } on ApiException catch (e) {
      if (e.isOffline && allowQueue) {
        await queue.add(QueuedOp(
          opId: _opId(),
          type: 'data',
          recordId: recordId,
          data: data,
          device: device,
          queuedAt: DateTime.now().millisecondsSinceEpoch,
          label: label.isEmpty ? '${data.length} field(s)' : label,
        ));
        return null;
      }
      rethrow;
    }
  }

  Future<PfepRecord?> submit(String recordId, {String? device, String label = ''}) async {
    try {
      final j = await api.post('/records/$recordId/submit', body: {'device': device});
      return PfepRecord.fromJson(Map<String, dynamic>.from(j));
    } on ApiException catch (e) {
      if (e.isOffline) {
        await queue.add(QueuedOp(
          opId: _opId(),
          type: 'submit',
          recordId: recordId,
          device: device,
          capturedAt: DateTime.now().millisecondsSinceEpoch,
          queuedAt: DateTime.now().millisecondsSinceEpoch,
          label: label.isEmpty ? 'Submission' : label,
        ));
        return null;
      }
      rethrow;
    }
  }

  Future<PfepRecord> approve(String recordId, {String? note}) async =>
      PfepRecord.fromJson(Map<String, dynamic>.from(
          await api.post('/records/$recordId/approve', body: {'note': note})));

  Future<PfepRecord> reject(String recordId, String note, {List<String> clearPhotos = const []}) async =>
      PfepRecord.fromJson(Map<String, dynamic>.from(await api.post('/records/$recordId/reject', body: {
        'note': note,
        'clearPhotos': clearPhotos,
      })));

  Future<PfepRecord> assign(String recordId, String? userId) async =>
      PfepRecord.fromJson(Map<String, dynamic>.from(
          await api.post('/records/$recordId/assign', body: {'userId': userId})));

  /* ----------------------------------------------------------------- photos */

  /// BRD 4.5 - the app posts the bytes; the *server* names the file from the
  /// record's part number, vendor and photo type. The client never chooses a
  /// filename, which is what makes a mismatched photo structurally impossible.
  Future<PfepRecord?> uploadPhoto({
    required String recordId,
    required String photoType,
    required Uint8List bytes,
    required String filename,
    String mime = 'image/jpeg',
    int? capturedAt,
    String label = '',
  }) async {
    try {
      final form = FormData.fromMap({
        'photo': MultipartFile.fromBytes(bytes, filename: filename),
        'capturedAt': '${capturedAt ?? DateTime.now().millisecondsSinceEpoch}',
      });
      await api.upload('/records/$recordId/photos/$photoType', form);
      return record(recordId);
    } on ApiException catch (e) {
      if (e.isOffline) {
        await queue.add(QueuedOp(
          opId: _opId(),
          type: 'photo',
          recordId: recordId,
          photoType: photoType,
          base64: base64Encode(bytes),
          mime: mime,
          capturedAt: capturedAt ?? DateTime.now().millisecondsSinceEpoch,
          queuedAt: DateTime.now().millisecondsSinceEpoch,
          label: label.isEmpty ? '$photoType photo' : label,
        ));
        return null;
      }
      rethrow;
    }
  }

  Future<PfepRecord> deletePhoto(String recordId, String photoType) async {
    await api.delete('/records/$recordId/photos/$photoType');
    return record(recordId);
  }

  /* -------------------------------------------------------------- dashboard */

  Future<Dashboard> dashboard(String customerId) async =>
      Dashboard.fromJson(Map<String, dynamic>.from(await api.get('/customers/$customerId/dashboard')));

  Future<MyWork> myWork({String? customerId}) async =>
      MyWork.fromJson(Map<String, dynamic>.from(await api.get('/my/work', query: {'customer': customerId})));

  Future<List<PfepRecord>> reviewQueue({String? customerId}) async {
    final j = await api.get('/my/review-queue', query: {'customer': customerId}) as Map<String, dynamic>;
    return (j['records'] as List).map((e) => PfepRecord.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /* ----------------------------------------------------------------- output */

  Future<Uint8List> exportExcel(
    String customerId, {
    String? status,
    String? from,
    String? to,
    String photos = 'thumbnails',
  }) =>
      api.download('/customers/$customerId/export/xlsx',
          query: {'status': status, 'from': from, 'to': to, 'photos': photos});

  Future<Uint8List> exportCsv(String customerId, {String? status, String? from, String? to}) =>
      api.download('/customers/$customerId/export/csv', query: {'status': status, 'from': from, 'to': to});

  Future<({int rows, List<PfepRecord> preview})> exportPreview(
    String customerId, {
    String? status,
    String? from,
    String? to,
  }) async {
    final j = await api.get('/customers/$customerId/export/preview',
        query: {'status': status, 'from': from, 'to': to}) as Map<String, dynamic>;
    return (
      rows: j['rows'] as int,
      preview: (j['records'] as List).map((e) => PfepRecord.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }

  Future<LabelPreview> labelPreview(String recordId, String kind) async =>
      LabelPreview.fromJson(Map<String, dynamic>.from(
          await api.get('/records/$recordId/label/preview', query: {'kind': kind})));

  Future<Uint8List> labelFile(String recordId, {required String kind, required String format}) =>
      api.download('/records/$recordId/label', query: {'kind': kind, 'format': format});

  /// BRD 4.8 - the per-customer label formats, plus the token vocabulary and a
  /// worked example for each, which is what makes the editor's preview real.
  Future<LabelTemplateConfig> labelTemplates(String customerId) async =>
      LabelTemplateConfig.fromJson(Map<String, dynamic>.from(
          await api.get('/customers/$customerId/label-templates')));

  Future<LabelTemplate> saveLabelTemplate(String customerId, LabelTemplate template) async =>
      LabelTemplate.fromJson(Map<String, dynamic>.from(await api.put(
        '/customers/$customerId/label-templates/${template.kind}',
        body: template.toJson(),
      )));

  Future<Uint8List> bulkLabels(
    String customerId, {
    required String kind,
    required String format,
    String status = 'Approved',
  }) =>
      api.download('/customers/$customerId/labels',
          query: {'kind': kind, 'format': format, 'status': status});

  /* ------------------------------------------------------------------ audit */

  Future<List<AuditEntry>> audit({String? customerId, String? q, int limit = 200}) async {
    final j = await api.get('/audit', query: {'customer': customerId, 'q': q, 'limit': limit})
        as Map<String, dynamic>;
    return (j['entries'] as List).map((e) => AuditEntry.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /* ------------------------------------------------------------------ users */

  Future<List<AppUser>> users() async {
    final j = await api.get('/users') as List;
    return j.map((e) => AppUser.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> createUser(Map<String, dynamic> body) => api.post('/users', body: body);

  Future<void> updateUser(String id, Map<String, dynamic> body) => api.patch('/users/$id', body: body);

  /* ------------------------------------------------------------------- sync */

  Future<bool> ping() async {
    try {
      await api.get('/sync/ping');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Replays the offline queue. Ops the server accepts (or already knows) are
  /// dropped locally; an op held back as incomplete stays queued so the
  /// collector can finish it.
  Future<SyncResult> flushQueue({String? device}) async {
    await queue.load();
    if (queue.isEmpty) return const SyncResult(applied: 0, duplicates: 0, failed: 0, held: 0);

    final ops = queue.ops.map((o) => o.toWire()).toList();
    final j = await api.post('/sync/batch', body: {'ops': ops, 'device': device}) as Map<String, dynamic>;

    final results = (j['results'] as List).cast<Map<String, dynamic>>();
    final settled = results
        .where((r) => r['ok'] == true && r['held'] != true)
        .map((r) => '${r['opId']}')
        .toList();
    await queue.removeIds(settled);

    return SyncResult(
      applied: j['applied'] as int? ?? 0,
      duplicates: j['duplicates'] as int? ?? 0,
      failed: j['failed'] as int? ?? 0,
      held: results.where((r) => r['held'] == true).length,
    );
  }

  /// Pulls everything the phone needs to work a whole shift with no signal.
  Future<Map<String, dynamic>> bootstrap(String customerId) async =>
      Map<String, dynamic>.from(await api.get('/sync/bootstrap', query: {'customer': customerId}));

  String _opId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${identityHashCode(this).toRadixString(36)}';
}
