import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// BRD 5 - offline mode.
///
/// Vendor yards and line-side areas have poor signal, so every edit, photo and
/// submission is written to this queue first and replayed against
/// `POST /api/sync/batch` when a connection returns. Each entry carries a
/// client-minted `opId`, so replaying a queue twice is a no-op server-side.
///
/// The queue is persisted, which is the part that matters: if the phone dies in
/// a vendor yard the morning's work is still there when it comes back on.
class QueuedOp {
  QueuedOp({
    required this.opId,
    required this.type,
    required this.recordId,
    required this.queuedAt,
    this.data,
    this.photoType,
    this.base64,
    this.mime,
    this.width,
    this.height,
    this.capturedAt,
    this.device,
    this.label = '',
  });

  final String opId;
  final String type; // data | photo | submit
  final String recordId;
  final int queuedAt;
  final Map<String, dynamic>? data;
  final String? photoType;
  final String? base64;
  final String? mime;
  final int? width;
  final int? height;
  final int? capturedAt;
  final String? device;

  /// Human-readable summary shown on the sync screen.
  final String label;

  int get sizeBytes => (base64?.length ?? 0) * 3 ~/ 4;

  Map<String, dynamic> toWire() => {
        'opId': opId,
        'type': type,
        'recordId': recordId,
        if (data != null) 'data': data,
        if (photoType != null) 'photoType': photoType,
        if (base64 != null) 'base64': base64,
        if (mime != null) 'mime': mime,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (capturedAt != null) 'capturedAt': capturedAt,
        if (device != null) 'device': device,
      };

  Map<String, dynamic> toJson() => {...toWire(), 'queuedAt': queuedAt, 'label': label};

  factory QueuedOp.fromJson(Map<String, dynamic> j) => QueuedOp(
        opId: '${j['opId']}',
        type: '${j['type']}',
        recordId: '${j['recordId']}',
        queuedAt: j['queuedAt'] as int? ?? 0,
        data: j['data'] == null ? null : Map<String, dynamic>.from(j['data']),
        photoType: j['photoType'] as String?,
        base64: j['base64'] as String?,
        mime: j['mime'] as String?,
        width: j['width'] as int?,
        height: j['height'] as int?,
        capturedAt: j['capturedAt'] as int?,
        device: j['device'] as String?,
        label: '${j['label'] ?? ''}',
      );
}

class OfflineQueue extends ChangeNotifier {
  OfflineQueue._();

  // Keyed per user. The queue used to live under one device-global key, which
  // let a user who signed in on a shared device flush the PREVIOUS user's queued
  // ops under their own token. Each user's queue is now its own key, so a user's
  // unsynced work is kept across sign-out and restored only for them.
  static const _legacyKey = 'pfep.offline.queue.v1';
  static String _keyFor(String? userId) =>
      userId == null ? 'pfep.offline.queue.v1.anon' : 'pfep.offline.queue.v1.$userId';
  static final OfflineQueue instance = OfflineQueue._();

  final List<QueuedOp> _ops = [];
  bool _loaded = false;
  String? _userId;

  List<QueuedOp> get ops => List.unmodifiable(_ops);
  int get length => _ops.length;
  bool get isEmpty => _ops.isEmpty;
  int get pendingBytes => _ops.fold(0, (s, o) => s + o.sizeBytes);

  /// Point the queue at a user's own stored ops — call after sign-in / session
  /// restore, and with null on sign-out. A no-op if already on that user.
  Future<void> useUser(String? userId) async {
    if (_loaded && _userId == userId) return;
    _userId = userId;
    _loaded = false;
    _ops.clear();
    await _load();
  }

  /// Ensure the current user's queue is loaded (used before a flush).
  Future<void> load() async {
    if (_loaded) return;
    await _load();
  }

  Future<void> _load() async {
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    // One-time migration off the old device-global key: adopt it for the first
    // signed-in user to load after the upgrade — on a single device that is the
    // person who created it — then drop the shared copy so no one else flushes it.
    if (_userId != null) {
      final legacy = prefs.getString(_legacyKey);
      if (legacy != null) {
        if (prefs.getString(_keyFor(_userId)) == null) {
          await prefs.setString(_keyFor(_userId), legacy);
        }
        await prefs.remove(_legacyKey);
      }
    }
    final raw = prefs.getString(_keyFor(_userId));
    if (raw == null) {
      notifyListeners();
      return;
    }
    try {
      final list = jsonDecode(raw) as List;
      _ops
        ..clear()
        ..addAll(list.map((e) => QueuedOp.fromJson(Map<String, dynamic>.from(e))));
      notifyListeners();
    } catch (_) {
      // A corrupt queue must not brick the app; drop it and carry on.
      await prefs.remove(_keyFor(_userId));
    }
  }

  Future<void> add(QueuedOp op) async {
    // One pending op per (record, type, photoType): a re-taken photo or a
    // re-edited field replaces the queued version rather than stacking up.
    _ops.removeWhere((o) =>
        o.recordId == op.recordId &&
        o.type == op.type &&
        o.photoType == op.photoType &&
        o.type != 'submit');
    _ops.add(op);
    await _persist();
  }

  Future<void> removeIds(Iterable<String> opIds) async {
    final set = opIds.toSet();
    _ops.removeWhere((o) => set.contains(o.opId));
    await _persist();
  }

  Future<void> clear() async {
    _ops.clear();
    await _persist();
  }

  /// Ops belonging to one record, used to badge it as "waiting to sync".
  List<QueuedOp> forRecord(String recordId) => _ops.where((o) => o.recordId == recordId).toList();

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(_userId), jsonEncode(_ops.map((o) => o.toJson()).toList()));
    notifyListeners();
  }
}
