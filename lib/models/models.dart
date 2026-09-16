import 'package:flutter/foundation.dart';

/* -------------------------------------------------------------- primitives */

int? _int(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
double? _dbl(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : '$v';

/// Booleans arrive as real booleans from the API, because the server maps them
/// on the way out. They arrive as SQLite's 0/1 from anything that hands over a
/// raw row. `v == true` silently answers `false` for 1, which would read as
/// "no field is mandatory" rather than as an error - so parse both shapes.
bool _flag(dynamic v, {bool orElse = false}) {
  if (v == null) return orElse;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return orElse;
}

/* -------------------------------------------------------------------- user */

class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.empCode,
    this.phone,
    this.device,
    this.email,
    this.active = true,
    this.customers = const [],
  });

  final String id;
  final String username;
  final String name;
  final String role;
  final String? empCode;
  final String? phone;
  final String? device;
  final String? email;
  final bool active;
  final List<String> customers;

  bool get isAdmin => role == 'Admin';
  bool get isCollector => role == 'Collector';
  bool get isReviewer => role == 'Reviewer';
  bool get isViewer => role == 'Viewer';
  bool get canReview => role == 'Admin' || role == 'Reviewer';
  bool get canEdit => role == 'Admin' || role == 'Collector';

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.take(2).map((p) => p.isEmpty ? '' : p[0]).join().toUpperCase();
  }

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _str(j['id']),
        username: _str(j['username']),
        name: _str(j['name']),
        role: _str(j['role']),
        empCode: j['emp_code'] as String?,
        phone: j['phone'] as String?,
        device: j['device'] as String?,
        email: j['email'] as String?,
        active: _flag(j['active'], orElse: true),
        customers: (j['customers'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

/* ---------------------------------------------------------------- customer */

class Customer {
  Customer({
    required this.id,
    required this.name,
    this.program,
    this.status = 'Setup',
    this.startDate,
    this.targetDate,
    this.planPerDay = 0,
    this.plantPincode,
    this.workDays = 26,
    this.shiftHrs = 8,
    this.totalRecords = 0,
    this.byStatus = const {},
  });

  final String id;
  final String name;
  final String? program;
  final String status;
  final String? startDate;
  final String? targetDate;
  final int planPerDay;

  /// Origin the optional vendor-distance lookup measures from (BRD 4.3).
  final String? plantPincode;
  final int workDays;
  final double shiftHrs;
  final int totalRecords;
  final Map<String, int> byStatus;

  int get approved => byStatus['Approved'] ?? 0;
  int get progressPct => totalRecords == 0
      ? 0
      : (((approved + (byStatus['Submitted'] ?? 0)) / totalRecords) * 100).round();

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _str(j['id']),
        name: _str(j['name']),
        program: j['program'] as String?,
        status: _str(j['status']),
        startDate: j['start_date'] as String?,
        targetDate: j['target_date'] as String?,
        planPerDay: _int(j['plan_per_day']) ?? 0,
        plantPincode: (j['plant_pincode'] ?? j['plantPincode']) as String?,
        workDays: _int(j['work_days']) ?? 26,
        shiftHrs: _dbl(j['shift_hrs']) ?? 8,
        totalRecords: _int(j['totalRecords']) ?? 0,
        byStatus: ((j['byStatus'] as Map?) ?? {})
            .map((k, v) => MapEntry('$k', _int(v) ?? 0)),
      );
}

/* ------------------------------------------------------------------ vendor */

class Vendor {
  Vendor({
    required this.id,
    required this.name,
    this.city,
    this.country,
    this.distanceKm,
    this.transportMode,
    this.vehicleType,
    this.pincode,
    this.distanceSource,
    this.partCount = 0,
    this.recordCount = 0,
  });

  final String id;
  final String name;
  final String? city;
  final String? country;
  final double? distanceKm;
  final String? transportMode;
  final String? vehicleType;

  /// What the optional distance lookup resolves (BRD 4.3).
  final String? pincode;

  /// How [distanceKm] was arrived at — surveyed, entered by hand, or routed
  /// from a pincode. A measured estimate and a surveyed figure feed the same
  /// reorder point, so which one it is has to stay visible.
  final String? distanceSource;

  final int partCount;
  final int recordCount;

  bool get distanceIsMeasured => (distanceSource ?? '').contains('route') ||
      (distanceSource ?? '').contains('straight line');

  factory Vendor.fromJson(Map<String, dynamic> j) => Vendor(
        id: _str(j['id']),
        name: _str(j['name']),
        city: j['city'] as String?,
        country: j['country'] as String?,
        distanceKm: _dbl(j['distance_km'] ?? j['distanceKm']),
        transportMode: (j['transport_mode'] ?? j['transportMode']) as String?,
        vehicleType: (j['vehicle_type'] ?? j['vehicleType']) as String?,
        pincode: j['pincode'] as String?,
        distanceSource: (j['distance_source'] ?? j['distanceSource']) as String?,
        partCount: _int(j['partCount']) ?? 0,
        recordCount: _int(j['recordCount']) ?? 0,
      );
}

/// Whether the server's optional distance lookup is configured (BRD 4.3).
class DistanceStatus {
  const DistanceStatus({required this.enabled, required this.provider, this.reason});

  final bool enabled;
  final String provider;

  /// Why it cannot run, phrased for an admin rather than a log.
  final String? reason;

  factory DistanceStatus.fromJson(Map<String, dynamic> j) => DistanceStatus(
        enabled: _flag(j['enabled']),
        provider: _str(j['provider']),
        reason: j['reason'] as String?,
      );
}

/* -------------------------------------------------------------------- part */

/// A vendor as seen from a part: carries the record id for that pairing, which
/// is what the collector actually opens (BRD 4.2).
class PartVendor {
  PartVendor({
    required this.id,
    required this.name,
    this.city,
    this.distanceKm,
    this.transportMode,
    this.vehicleType,
    this.recordId,
    this.recordStatus,
    this.assignedTo,
    this.assignedName,
  });

  final String id;
  final String name;
  final String? city;
  final double? distanceKm;
  final String? transportMode;
  final String? vehicleType;
  final String? recordId;
  final String? recordStatus;

  /// Who this part-vendor row belongs to, when it has been assigned. The server
  /// refuses a save from anyone else, so the collect screen greys the row out
  /// rather than letting a field user type a section they cannot keep.
  final String? assignedTo;
  final String? assignedName;

  /// True when [userId] may not edit this row because it is someone else's.
  bool lockedFor(String? userId) =>
      assignedTo != null && userId != null && assignedTo != userId;

  factory PartVendor.fromJson(Map<String, dynamic> j) => PartVendor(
        id: _str(j['id']),
        name: _str(j['name']),
        city: j['city'] as String?,
        distanceKm: _dbl(j['distanceKm'] ?? j['distance_km']),
        transportMode: (j['transportMode'] ?? j['transport_mode']) as String?,
        vehicleType: (j['vehicleType'] ?? j['vehicle_type']) as String?,
        recordId: j['recordId'] as String?,
        recordStatus: j['recordStatus'] as String?,
        assignedTo: j['assignedTo'] as String?,
        assignedName: j['assignedName'] as String?,
      );
}

class Part {
  Part({
    required this.id,
    required this.partNo,
    required this.description,
    this.partType,
    this.model,
    this.qtyPerVehicle = 1,
    this.unitPrice,
    this.abcClass,
    this.vendors = const [],
  });

  final String id;
  final String partNo;
  final String description;
  final String? partType;
  final String? model;
  final double qtyPerVehicle;
  final double? unitPrice;
  final String? abcClass;
  final List<PartVendor> vendors;

  factory Part.fromJson(Map<String, dynamic> j) => Part(
        id: _str(j['id']),
        partNo: _str(j['part_no'] ?? j['partNo']),
        description: _str(j['description']),
        partType: (j['part_type'] ?? j['partType']) as String?,
        model: j['model'] as String?,
        qtyPerVehicle: _dbl(j['qty_per_vehicle'] ?? j['qtyPerVehicle']) ?? 1,
        unitPrice: _dbl(j['unit_price'] ?? j['unitPrice']),
        abcClass: (j['abc_class'] ?? j['abcClass']) as String?,
        vendors: ((j['vendors'] as List?) ?? [])
            .map((e) => PartVendor.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/* ---------------------------------------------------------- field config */

class FieldDef {
  FieldDef({
    required this.key,
    required this.label,
    required this.type,
    this.unit,
    this.options,
    this.required = false,
    this.enabled = true,
  });

  final String key;
  final String label;
  final String type;
  final String? unit;
  final List<String>? options;
  final bool required;
  final bool enabled;

  String get labelWithUnit => unit == null || unit!.isEmpty ? label : '$label ($unit)';

  factory FieldDef.fromJson(Map<String, dynamic> j) => FieldDef(
        key: _str(j['key']),
        label: _str(j['label']),
        type: _str(j['type']),
        unit: j['unit'] as String?,
        options: (j['options'] as List?)?.map((e) => '$e').toList(),
        required: _flag(j['required']),
        enabled: _flag(j['enabled'], orElse: true),
      );
}

class FieldSection {
  FieldSection({
    required this.key,
    required this.label,
    required this.photo,
    required this.fields,
    this.availableExtras = const [],
  });

  final String key;
  final String label;
  final String photo;
  final List<FieldDef> fields;

  /// Wider-PFEP fields this customer does not have yet, offered as one-click
  /// presets in the Add field dialog so the key, type and dropdown values come
  /// pre-filled rather than being retyped.
  final List<FieldDef> availableExtras;

  List<FieldDef> get active => fields.where((f) => f.enabled).toList();

  factory FieldSection.fromJson(Map<String, dynamic> j) => FieldSection(
        key: _str(j['key']),
        label: _str(j['label']),
        photo: _str(j['photo']),
        fields: ((j['fields'] as List?) ?? [])
            .map((e) => FieldDef.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        availableExtras: ((j['availableExtras'] as List?) ?? [])
            .map((e) => FieldDef.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class FieldConfig {
  FieldConfig({required this.sections, required this.photoTypes, required this.computedFields});

  final List<FieldSection> sections;
  final List<PhotoType> photoTypes;
  final List<ComputedFieldInfo> computedFields;

  factory FieldConfig.fromJson(Map<String, dynamic> j) => FieldConfig(
        sections: ((j['sections'] as List?) ?? [])
            .map((e) => FieldSection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        photoTypes: ((j['photoTypes'] as List?) ?? [])
            .map((e) => PhotoType.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        computedFields: ((j['computedFields'] as List?) ?? [])
            .map((e) => ComputedFieldInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class PhotoType {
  PhotoType({required this.key, required this.label});

  final String key;
  final String label;

  factory PhotoType.fromJson(Map<String, dynamic> j) =>
      PhotoType(key: _str(j['key']), label: _str(j['label']));
}

class ComputedFieldInfo {
  ComputedFieldInfo({required this.key, required this.label, required this.formula});

  final String key;
  final String label;
  final String formula;

  factory ComputedFieldInfo.fromJson(Map<String, dynamic> j) => ComputedFieldInfo(
        key: _str(j['key']),
        label: _str(j['label']),
        formula: _str(j['formula']),
      );
}

/* ------------------------------------------------------------------ photo */

class RecordPhoto {
  RecordPhoto({
    required this.id,
    required this.type,
    required this.url,
    required this.name,
    this.bytes = 0,
    this.width,
    this.height,
    this.capturedAt,
  });

  final String id;
  final String type;
  final String url;
  final String name;
  final int bytes;
  final int? width;
  final int? height;
  final int? capturedAt;

  String get sizeLabel => '${(bytes / 1024).round()} KB';

  factory RecordPhoto.fromJson(Map<String, dynamic> j) => RecordPhoto(
        id: _str(j['id']),
        type: _str(j['type']),
        url: _str(j['url']),
        name: _str(j['name']),
        bytes: _int(j['bytes']) ?? 0,
        width: _int(j['width']),
        height: _int(j['height']),
        capturedAt: _int(j['capturedAt']),
      );
}

/* ----------------------------------------------------------------- record */

class PfepRecord {
  PfepRecord({
    required this.id,
    required this.sn,
    required this.customerId,
    required this.partNo,
    required this.description,
    required this.vendorId,
    required this.vendorName,
    required this.status,
    required this.data,
    required this.computed,
    required this.photos,
    required this.missingPhotos,
    this.customerName = '',
    this.program,
    this.partType,
    this.model,
    this.vendorCity,
    this.qtyPerVehicle = 1,
    this.unitPrice,
    this.assignedTo,
    this.assignedName,
    this.collectedBy,
    this.collectedByName,
    this.collectedAt,
    this.reviewedByName,
    this.reviewedAt,
    this.reviewNote,
    this.device,
    this.version = 1,
    this.completeness = 0,
    this.validation,
    this.sections = const [],
  });

  final String id;
  final int sn;
  final String customerId;
  final String customerName;
  final String? program;
  final String partNo;
  final String description;
  final String? partType;
  final String? model;
  final String vendorId;
  final String vendorName;
  final String? vendorCity;
  final double qtyPerVehicle;
  final double? unitPrice;
  final String status;
  final Map<String, dynamic> data;
  final Map<String, dynamic> computed;
  final Map<String, RecordPhoto?> photos;
  final List<String> missingPhotos;
  final String? assignedTo;
  final String? assignedName;
  final String? collectedBy;
  final String? collectedByName;
  final int? collectedAt;
  final String? reviewedByName;
  final int? reviewedAt;
  final String? reviewNote;
  final String? device;
  final int version;
  final int completeness;
  final Validation? validation;
  final List<FieldSection> sections;

  int get photoCount => photos.values.where((p) => p != null).length;
  int get photoTotal => photos.isEmpty ? 5 : photos.length;
  bool get isLocked => status == 'Approved';
  bool get isEditable => status != 'Approved';

  factory PfepRecord.fromJson(Map<String, dynamic> j) {
    final photos = <String, RecordPhoto?>{};
    ((j['photos'] as Map?) ?? {}).forEach((k, v) {
      photos['$k'] = v == null ? null : RecordPhoto.fromJson(Map<String, dynamic>.from(v));
    });
    return PfepRecord(
      id: _str(j['id']),
      sn: _int(j['sn']) ?? 0,
      customerId: _str(j['customerId']),
      customerName: _str(j['customerName']),
      program: j['program'] as String?,
      partNo: _str(j['partNo']),
      description: _str(j['description']),
      partType: j['partType'] as String?,
      model: j['model'] as String?,
      vendorId: _str(j['vendorId']),
      vendorName: _str(j['vendorName']),
      vendorCity: j['vendorCity'] as String?,
      qtyPerVehicle: _dbl(j['qtyPerVehicle']) ?? 1,
      unitPrice: _dbl(j['unitPrice']),
      status: _str(j['status']),
      data: Map<String, dynamic>.from(j['data'] ?? {}),
      computed: Map<String, dynamic>.from(j['computed'] ?? {}),
      photos: photos,
      missingPhotos: ((j['missingPhotos'] as List?) ?? []).map((e) => '$e').toList(),
      assignedTo: j['assignedTo'] as String?,
      assignedName: j['assignedName'] as String?,
      collectedBy: j['collectedBy'] as String?,
      collectedByName: j['collectedByName'] as String?,
      collectedAt: _int(j['collectedAt']),
      reviewedByName: j['reviewedByName'] as String?,
      reviewedAt: _int(j['reviewedAt']),
      reviewNote: j['reviewNote'] as String?,
      device: j['device'] as String?,
      version: _int(j['version']) ?? 1,
      completeness: _int(j['completeness']) ?? 0,
      validation: j['validation'] == null
          ? null
          : Validation.fromJson(Map<String, dynamic>.from(j['validation'])),
      sections: ((j['sections'] as List?) ?? [])
          .map((e) => FieldSection.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class MissingField {
  MissingField({required this.section, required this.sectionLabel, required this.key, required this.label});

  final String section;
  final String sectionLabel;
  final String key;
  final String label;

  factory MissingField.fromJson(Map<String, dynamic> j) => MissingField(
        section: _str(j['section']),
        sectionLabel: _str(j['sectionLabel']),
        key: _str(j['key']),
        label: _str(j['label']),
      );
}

class Validation {
  Validation({required this.ok, required this.missingFields, required this.missingPhotos});

  final bool ok;
  final List<MissingField> missingFields;
  final List<String> missingPhotos;

  factory Validation.fromJson(Map<String, dynamic> j) => Validation(
        ok: _flag(j['ok']),
        missingFields: ((j['missingFields'] as List?) ?? [])
            .map((e) => MissingField.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        missingPhotos: ((j['missingPhotos'] as List?) ?? []).map((e) => '$e').toList(),
      );
}

/* -------------------------------------------------------------- dashboard */

class DashboardTotals {
  DashboardTotals({
    required this.lineItems,
    required this.parts,
    required this.vendors,
    required this.completed,
    required this.awaitingReview,
    required this.inProgress,
    required this.rejected,
    required this.pending,
    required this.missingPhotoItems,
    required this.photosCaptured,
    required this.photosNeeded,
    required this.progressPct,
    required this.approvedPct,
    required this.avgCompleteness,
  });

  final int lineItems, parts, vendors, completed, awaitingReview, inProgress;
  final int rejected, pending, missingPhotoItems, photosCaptured, photosNeeded;
  final int progressPct, approvedPct, avgCompleteness;

  factory DashboardTotals.fromJson(Map<String, dynamic> j) => DashboardTotals(
        lineItems: _int(j['lineItems']) ?? 0,
        parts: _int(j['parts']) ?? 0,
        vendors: _int(j['vendors']) ?? 0,
        completed: _int(j['completed']) ?? 0,
        awaitingReview: _int(j['awaitingReview']) ?? 0,
        inProgress: _int(j['inProgress']) ?? 0,
        rejected: _int(j['rejected']) ?? 0,
        pending: _int(j['pending']) ?? 0,
        missingPhotoItems: _int(j['missingPhotoItems']) ?? 0,
        photosCaptured: _int(j['photosCaptured']) ?? 0,
        photosNeeded: _int(j['photosNeeded']) ?? 0,
        progressPct: _int(j['progressPct']) ?? 0,
        approvedPct: _int(j['approvedPct']) ?? 0,
        avgCompleteness: _int(j['avgCompleteness']) ?? 0,
      );
}

class PhotoGap {
  PhotoGap({required this.type, required this.label, required this.captured, required this.missing});

  final String type;
  final String label;
  final int captured;
  final int missing;

  factory PhotoGap.fromJson(Map<String, dynamic> j) => PhotoGap(
        type: _str(j['type']),
        label: _str(j['label']),
        captured: _int(j['captured']) ?? 0,
        missing: _int(j['missing']) ?? 0,
      );
}

class CollectorProgress {
  CollectorProgress({
    required this.id,
    required this.name,
    required this.assigned,
    required this.done,
    required this.pending,
    required this.missingPhotos,
    this.device,
    this.empCode,
    this.lastActivity,
  });

  final String id, name;
  final int assigned, done, pending, missingPhotos;
  final String? device, empCode;
  final int? lastActivity;

  factory CollectorProgress.fromJson(Map<String, dynamic> j) => CollectorProgress(
        id: _str(j['id']),
        name: _str(j['name']),
        assigned: _int(j['assigned']) ?? 0,
        done: _int(j['done']) ?? 0,
        pending: _int(j['pending']) ?? 0,
        missingPhotos: _int(j['missingPhotos']) ?? 0,
        device: j['device'] as String?,
        empCode: j['empCode'] as String?,
        lastActivity: _int(j['lastActivity']),
      );
}

class TrendPoint {
  TrendPoint({required this.date, required this.submitted, required this.approved});

  final String date;
  final int submitted, approved;

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        date: _str(j['date']),
        submitted: _int(j['submitted']) ?? 0,
        approved: _int(j['approved']) ?? 0,
      );
}

class AttentionItem {
  AttentionItem({required this.recordId, required this.partNo, required this.vendorName, required this.issue, required this.severity});

  final String recordId, partNo, vendorName, issue, severity;

  factory AttentionItem.fromJson(Map<String, dynamic> j) => AttentionItem(
        recordId: _str(j['recordId']),
        partNo: _str(j['partNo']),
        vendorName: _str(j['vendorName']),
        issue: _str(j['issue']),
        severity: _str(j['severity']),
      );
}

class Dashboard {
  Dashboard({
    required this.customer,
    required this.totals,
    required this.photoGaps,
    required this.collectors,
    required this.trend,
    required this.attention,
  });

  final Customer customer;
  final DashboardTotals totals;
  final List<PhotoGap> photoGaps;
  final List<CollectorProgress> collectors;
  final List<TrendPoint> trend;
  final List<AttentionItem> attention;

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
        customer: Customer.fromJson(Map<String, dynamic>.from(j['customer'])),
        totals: DashboardTotals.fromJson(Map<String, dynamic>.from(j['totals'])),
        photoGaps: ((j['photoGaps'] as List?) ?? [])
            .map((e) => PhotoGap.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        collectors: ((j['collectors'] as List?) ?? [])
            .map((e) => CollectorProgress.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        trend: ((j['trend'] as List?) ?? [])
            .map((e) => TrendPoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        attention: ((j['attention'] as List?) ?? [])
            .map((e) => AttentionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/* ------------------------------------------------------------------ audit */

class AuditEntry {
  AuditEntry({
    required this.ts,
    required this.action,
    this.actorName,
    this.actorRole,
    this.actorDevice,
    this.ref,
    this.customerId,
    this.detail,
    this.before,
    this.after,
  });

  final int ts;
  final String action;
  final String? actorName, actorRole, actorDevice, ref, customerId, detail, before, after;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        ts: _int(j['ts']) ?? 0,
        action: _str(j['action']),
        actorName: j['actor_name'] as String?,
        actorRole: j['actor_role'] as String?,
        actorDevice: j['actor_device'] as String?,
        ref: j['ref'] as String?,
        customerId: j['customer_id'] as String?,
        detail: j['detail'] as String?,
        before: j['before_val'] as String?,
        after: j['after_val'] as String?,
      );
}

/* ------------------------------------------------------ part master import */

class ImportIssue {
  ImportIssue({required this.row, required this.partNo, required this.vendorName, required this.issues});

  final int row;
  final String partNo, vendorName;
  final List<String> issues;

  factory ImportIssue.fromJson(Map<String, dynamic> j) => ImportIssue(
        row: _int(j['row']) ?? 0,
        partNo: _str(j['partNo']),
        vendorName: _str(j['vendorName']),
        issues: ((j['issues'] as List?) ?? [])
            .map((e) => '${e['column']}: ${e['issue']}')
            .toList(),
      );
}

class ImportReport {
  ImportReport({
    required this.ok,
    required this.committed,
    required this.filename,
    required this.headerErrors,
    required this.errors,
    required this.warnings,
    required this.stats,
    this.applied,
  });

  final bool ok, committed;
  final String filename;
  final List<String> headerErrors;
  final List<ImportIssue> errors;
  final List<String> warnings;
  final Map<String, int> stats;
  final Map<String, int>? applied;

  factory ImportReport.fromJson(Map<String, dynamic> j) => ImportReport(
        ok: _flag(j['ok']),
        committed: _flag(j['committed']),
        filename: _str(j['filename']),
        headerErrors: ((j['headerErrors'] as List?) ?? []).map((e) => '$e').toList(),
        errors: ((j['errors'] as List?) ?? [])
            .map((e) => ImportIssue.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        warnings: ((j['warnings'] as List?) ?? []).map((e) => '${e['message'] ?? e}').toList(),
        stats: ((j['stats'] as Map?) ?? {}).map((k, v) => MapEntry('$k', _int(v) ?? 0)),
        applied: j['applied'] == null
            ? null
            : (j['applied'] as Map).map((k, v) => MapEntry('$k', _int(v) ?? 0)),
      );
}

/* ------------------------------------------------------------ label studio */

class LabelLine {
  LabelLine({this.label, required this.value, required this.size});

  final String? label;
  final String value;
  final String size;

  factory LabelLine.fromJson(Map<String, dynamic> j) => LabelLine(
        label: j['label'] as String?,
        value: _str(j['value']),
        size: _str(j['size']),
      );
}

class LabelPreview {
  LabelPreview({
    required this.kind,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.lines,
    required this.qrPayload,
    required this.barcodeValue,
    required this.hasQr,
    required this.hasBarcode,
  });

  final String kind, name, qrPayload, barcodeValue;
  final double widthMm, heightMm;
  final List<LabelLine> lines;
  final bool hasQr, hasBarcode;

  factory LabelPreview.fromJson(Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from(j['template']);
    return LabelPreview(
      kind: _str(j['kind']),
      name: _str(t['name']),
      widthMm: _dbl(t['widthMm']) ?? 100,
      heightMm: _dbl(t['heightMm']) ?? 50,
      hasQr: _flag(t['qr']),
      hasBarcode: _str(t['barcode']) != 'none',
      qrPayload: _str(j['qrPayload']),
      barcodeValue: _str(j['barcodeValue']),
      lines: ((j['lines'] as List?) ?? [])
          .map((e) => LabelLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/* ---------------------------------------------------- label template editor */

/// One line of a stored template: the token to resolve, an optional caption
/// printed above it, and which step of the type scale to use.
class LabelTemplateLine {
  const LabelTemplateLine({this.label, required this.token, this.size = 'sm'});

  final String? label;
  final String token;
  final String size;

  LabelTemplateLine copyWith({Object? label = _keep, String? token, String? size}) =>
      LabelTemplateLine(
        label: label == _keep ? this.label : label as String?,
        token: token ?? this.token,
        size: size ?? this.size,
      );

  factory LabelTemplateLine.fromJson(Map<String, dynamic> j) => LabelTemplateLine(
        label: j['label'] as String?,
        token: _str(j['token']),
        size: _str(j['size']).isEmpty ? 'sm' : _str(j['size']),
      );

  Map<String, dynamic> toJson() => {
        if (label != null && label!.isNotEmpty) 'label': label,
        'token': token,
        'size': size,
      };
}

const _keep = Object();

/// A per-customer label format (BRD 4.8). `kind` is 'rack' or 'line'.
class LabelTemplate {
  const LabelTemplate({
    required this.kind,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    required this.dpmm,
    required this.barcode,
    required this.qr,
    required this.lines,
  });

  final String kind;
  final String name;
  final double widthMm;
  final double heightMm;
  final int dpmm;

  /// 'code128' or 'none'. Both renderers emit Code 128, so this is on/off
  /// rather than a choice of symbology.
  final String barcode;
  final bool qr;
  final List<LabelTemplateLine> lines;

  bool get hasBarcode => barcode != 'none';

  LabelTemplate copyWith({
    String? name,
    double? widthMm,
    double? heightMm,
    int? dpmm,
    String? barcode,
    bool? qr,
    List<LabelTemplateLine>? lines,
  }) =>
      LabelTemplate(
        kind: kind,
        name: name ?? this.name,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        dpmm: dpmm ?? this.dpmm,
        barcode: barcode ?? this.barcode,
        qr: qr ?? this.qr,
        lines: lines ?? this.lines,
      );

  /// The row comes back in the database's snake_case; the preview endpoint uses
  /// camelCase for the same values, so both spellings are accepted.
  factory LabelTemplate.fromJson(Map<String, dynamic> j) => LabelTemplate(
        kind: _str(j['kind']),
        name: _str(j['name']),
        widthMm: _dbl(j['width_mm'] ?? j['widthMm']) ?? 100,
        heightMm: _dbl(j['height_mm'] ?? j['heightMm']) ?? 50,
        dpmm: _int(j['dpmm']) ?? 8,
        barcode: _str(j['barcode']).isEmpty ? 'code128' : _str(j['barcode']),
        qr: _flag(j['qr'], orElse: true),
        lines: ((j['lines'] as List?) ?? [])
            .map((e) => LabelTemplateLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'dpmm': dpmm,
        'barcode': barcode,
        'qr': qr,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  bool sameAs(LabelTemplate o) =>
      name == o.name &&
      widthMm == o.widthMm &&
      heightMm == o.heightMm &&
      dpmm == o.dpmm &&
      barcode == o.barcode &&
      qr == o.qr &&
      lines.length == o.lines.length &&
      List.generate(lines.length, (i) => i).every((i) =>
          lines[i].token == o.lines[i].token &&
          lines[i].size == o.lines[i].size &&
          (lines[i].label ?? '') == (o.lines[i].label ?? ''));
}

/// A token a template line may use, with a real value from a sample record so
/// the editor can show what it will actually print.
class LabelToken {
  const LabelToken({required this.token, required this.label, this.section, this.example});

  final String token;
  final String label;
  final String? section;
  final String? example;

  factory LabelToken.fromJson(Map<String, dynamic> j) => LabelToken(
        token: _str(j['token']),
        label: _str(j['label']),
        section: j['section'] as String?,
        example: j['example'] as String?,
      );
}

class LabelTokenGroup {
  const LabelTokenGroup({required this.group, required this.tokens});

  final String group;
  final List<LabelToken> tokens;

  factory LabelTokenGroup.fromJson(Map<String, dynamic> j) => LabelTokenGroup(
        group: _str(j['group']),
        tokens: ((j['tokens'] as List?) ?? [])
            .map((e) => LabelToken.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Everything the template editor needs in one response.
class LabelTemplateConfig {
  const LabelTemplateConfig({
    required this.templates,
    required this.sizes,
    required this.tokenGroups,
    this.samplePartNo,
  });

  final List<LabelTemplate> templates;
  final List<String> sizes;
  final List<LabelTokenGroup> tokenGroups;
  final String? samplePartNo;

  /// Flattened lookup, for resolving a line's token to its example value.
  Map<String, LabelToken> get tokenIndex => {
        for (final g in tokenGroups)
          for (final t in g.tokens) t.token: t,
      };

  factory LabelTemplateConfig.fromJson(Map<String, dynamic> j) => LabelTemplateConfig(
        templates: ((j['templates'] as List?) ?? [])
            .map((e) => LabelTemplate.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        sizes: ((j['sizes'] as List?) ?? const ['xl', 'lg', 'md', 'sm']).map((e) => '$e').toList(),
        tokenGroups: ((j['tokenGroups'] as List?) ?? [])
            .map((e) => LabelTokenGroup.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        samplePartNo: (j['sampleRecord'] as Map?)?['partNo'] as String?,
      );
}

/* ---------------------------------------------------------- collector home */

class MyWork {
  MyWork({
    required this.assigned,
    required this.done,
    required this.pending,
    required this.rejected,
    required this.missingPhotos,
    required this.next,
    required this.recent,
  });

  final int assigned, done, pending, rejected, missingPhotos;
  final List<PfepRecord> next, recent;

  factory MyWork.fromJson(Map<String, dynamic> j) {
    final t = Map<String, dynamic>.from(j['totals']);
    return MyWork(
      assigned: _int(t['assigned']) ?? 0,
      done: _int(t['done']) ?? 0,
      pending: _int(t['pending']) ?? 0,
      rejected: _int(t['rejected']) ?? 0,
      missingPhotos: _int(t['missingPhotos']) ?? 0,
      next: ((j['next'] as List?) ?? [])
          .map((e) => PfepRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      recent: ((j['recent'] as List?) ?? [])
          .map((e) => PfepRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

@immutable
class SyncResult {
  const SyncResult({required this.applied, required this.duplicates, required this.failed, required this.held});

  final int applied, duplicates, failed, held;
}
