import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import '../widgets/dynamic_form.dart';
import '../widgets/photo_capture.dart';

/// BRD 4.2 - 4.6: the field data collection flow.
///
/// Part number -> vendor -> the configured sections -> photos -> review, in one
/// pass, on site. Nothing is written on paper and nothing is re-typed later.
class CollectScreen extends ConsumerStatefulWidget {
  const CollectScreen({super.key, this.recordId});

  final String? recordId;

  @override
  ConsumerState<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends ConsumerState<CollectScreen> {
  String? _recordId;
  int _step = 0; // 0 = pick, 1..n = sections, n+1 = photos, n+2 = review
  PfepRecord? _record;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  final Map<String, dynamic> _dirty = {};
  Timer? _autosave;

  @override
  void initState() {
    super.initState();
    _recordId = widget.recordId;
    if (_recordId != null) {
      _step = 1;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  List<FieldSection> get _sections => _record?.sections ?? const [];
  int get _photoStep => _sections.length + 1;
  int get _reviewStep => _sections.length + 2;

  Future<void> _load() async {
    if (_recordId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rec = await ref.read(repositoryProvider).record(_recordId!);
      if (!mounted) return;
      setState(() {
        _record = rec;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _onField(String key, dynamic value) {
    _dirty[key] = value;
    _record?.data[key] = value;
    _autosave?.cancel();
    // Autosave keeps the collector from losing a section if the phone dies;
    // offline, the repository queues the same payload instead.
    _autosave = Timer(const Duration(milliseconds: 900), () => _save(silent: true));
    setState(() {});
  }

  Future<bool> _save({bool silent = false}) async {
    if (_dirty.isEmpty || _record == null) return true;
    final payload = Map<String, dynamic>.from(_dirty);
    _dirty.clear();
    setState(() => _saving = true);
    try {
      final updated = await ref.read(repositoryProvider).saveData(
            _record!.id,
            payload,
            version: _record!.version,
            label: '${_record!.partNo} - ${payload.length} field(s)',
          );
      if (!mounted) return false;
      setState(() {
        if (updated != null) _record = updated;
        _saving = false;
      });
      if (updated == null && !silent) {
        showToast(context, 'Saved on this device', detail: 'Uploads automatically when back online.');
      }
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      if (e.isConflict) {
        showToast(context, 'Changed on another device',
            detail: 'Reloading the latest version of this record.', error: true);
        await _load();
      } else {
        _dirty.addAll(payload); // keep the edit so it is not silently dropped
        showToast(context, 'Could not save', detail: e.message, error: true);
      }
      return false;
    }
  }

  Future<void> _next() async {
    await _save();
    if (!mounted) return;
    setState(() => _step = (_step + 1).clamp(0, _reviewStep));
  }

  Future<void> _submit() async {
    await _save();
    if (!mounted || _record == null) return;
    setState(() => _saving = true);
    try {
      final res = await ref.read(repositoryProvider).submit(_record!.id, label: _record!.partNo);
      if (!mounted) return;
      ref.invalidate(myWorkProvider);
      ref.invalidate(recordsProvider);
      if (res == null) {
        showToast(context, 'Queued for upload',
            detail: '${_record!.partNo} will be submitted as soon as there is a connection.');
      } else {
        showToast(context, 'Submitted for review',
            detail: '${res.partNo} - ${res.vendorName} is now with the reviewer.');
      }
      context.go('/work');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.isIncomplete) {
        final v = e.details is Map ? Validation.fromJson(Map<String, dynamic>.from(e.details)) : null;
        _showIncomplete(v);
      } else {
        showToast(context, 'Not submitted', detail: e.message, error: true);
      }
    }
  }

  void _showIncomplete(Validation? v) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Not complete yet'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Finish these before submitting - this is the check the paper form never had.',
                  style: TextStyle(color: Brand.txt2, fontSize: 12.5, height: 1.5)),
              const SizedBox(height: 14),
              if (v != null && v.missingPhotos.isNotEmpty) ...[
                Text('Photos missing',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Brand.bad)),
                const SizedBox(height: 5),
                Text(v.missingPhotos.join(', '), style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 14),
              ],
              if (v != null && v.missingFields.isNotEmpty) ...[
                Text('Fields still blank',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Brand.warn)),
                const SizedBox(height: 5),
                for (final f in v.missingFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('${f.sectionLabel}  -  ${f.label}',
                        style: TextStyle(fontSize: 12.3, color: Brand.txt2)),
                  ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Back to the form')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_recordId == null) return _PickView(onPicked: _beginCollect);
    if (_loading && _record == null) return const Loading(label: 'Opening record...');
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final rec = _record;
    if (rec == null) return const Loading();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        _RecordHeader(record: rec, saving: _saving),
        const SizedBox(height: 16),
        _StepStrip(
          sections: _sections,
          step: _step,
          record: rec,
          onTap: (i) async {
            await _save();
            if (mounted) setState(() => _step = i);
          },
        ),
        const SizedBox(height: 20),
        if (_step >= 1 && _step <= _sections.length) _sectionView(rec, _sections[_step - 1]),
        if (_step == _photoStep) _photosView(rec),
        if (_step == _reviewStep) _reviewView(rec),
      ],
    );
  }

  void _beginCollect(String recordId) {
    setState(() {
      _recordId = recordId;
      _step = 1;
      _record = null;
    });
    unawaited(_load());
  }

  /* ------------------------------------------------------------- sections */

  Widget _sectionView(PfepRecord rec, FieldSection section) {
    final config = ref.watch(fieldConfigProvider).value;
    final photoType = config?.photoTypes.where((p) => p.key == section.photo).firstOrNull;
    final missing = rec.validation?.missingFields.where((m) => m.section == section.key).map((m) => m.key).toSet() ?? {};

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: section.label,
        trailing: Text('${section.active.length} fields',
            style: TextStyle(color: Brand.txt3, fontSize: 11.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DynamicForm(
            section: section,
            values: rec.data,
            enabled: rec.isEditable,
            highlightMissing: _step == _reviewStep ? missing : const {},
            onChanged: _onField,
          ),
          const SizedBox(height: 6),
          ComputedStrip(
            computed: rec.computed,
            keys: _computedFor(section.key),
            catalogue: config?.computedFields ?? const [],
          ),
        ]),
      ),
      if (photoType != null) ...[
        const SizedBox(height: 16),
        Panel(
          title: photoType.label,
          trailing: rec.photos[photoType.key] == null
              ? Pill('Required', color: Brand.bad)
              : Pill('Captured', color: Brand.ok, icon: Icons.check),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 150,
              child: PhotoTile(
                record: rec,
                photoType: photoType.key,
                label: photoType.label,
                onChanged: _load,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Take it here, now, while you are at the location.',
                    style: TextStyle(fontSize: 12.5, color: Brand.txt2, height: 1.5)),
                const SizedBox(height: 8),
                Text(
                  'The app stores it as ${rec.partNo}_${rec.vendorId}_${photoType.key}, so it is tied to this '
                  'part and vendor from the moment of capture - no cropping or pasting afterwards.',
                  style: TextStyle(fontSize: 11.5, color: Brand.txt3, height: 1.55),
                ),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      _NavButtons(
        onBack: _step > 1 ? () async {
          await _save();
          if (mounted) setState(() => _step -= 1);
        } : null,
        onNext: _next,
        nextLabel: _step == _sections.length ? 'Photo check' : 'Next section',
      ),
    ]);
  }

  /// Which computed values are worth showing under each section.
  List<String> _computedFor(String sectionKey) => switch (sectionKey) {
        'vendor' => const ['dailyConsumption', 'monthlyConsumption', 'leadTimeDays', 'inboundPkgsPerDay'],
        'inner' => const ['safetyStockNos', 'reorderPoint', 'maxStockNos', 'orderLotNos'],
        'storage' => const ['binCapacityNos', 'binsRequired', 'locationsRequired', 'storageAreaSqm'],
        'line' => const ['lineSideCoverHrs', 'lineSideBins', 'feedQtyPerTrip', 'replenishCycleHrs'],
        _ => const [],
      };

  /* --------------------------------------------------------------- photos */

  Widget _photosView(PfepRecord rec) {
    final config = ref.watch(fieldConfigProvider).value;
    final types = config?.photoTypes ?? const <PhotoType>[];
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? 5 : (width > 560 ? 3 : 2);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: 'Photo check',
        trailing: Pill('${rec.photoCount} of ${rec.photoTotal}',
            color: rec.missingPhotos.isEmpty ? Brand.ok : Brand.bad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            'All five photo types for this part, side by side. A gap is obvious here, on site, '
            'while the team is still at the location - not weeks later in the office.',
            style: TextStyle(color: Brand.txt3, fontSize: 12, height: 1.55),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.82,
            children: [
              for (final t in types)
                PhotoTile(record: rec, photoType: t.key, label: t.label, onChanged: _load),
            ],
          ),
          if (rec.missingPhotos.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Callout(
              tone: Brand.bad,
              icon: Icons.photo_camera_outlined,
              title: '${rec.missingPhotos.length} photo(s) still to take',
              body: 'Tap each red tile to open the camera. The record cannot be submitted until all five are captured.',
            ),
          ],
        ]),
      ),
      const SizedBox(height: 20),
      _NavButtons(
        onBack: () async => setState(() => _step -= 1),
        onNext: _next,
        nextLabel: 'Review & submit',
      ),
    ]);
  }

  /* --------------------------------------------------------------- review */

  Widget _reviewView(PfepRecord rec) {
    final config = ref.watch(fieldConfigProvider).value;
    final v = rec.validation;
    final ready = v?.ok ?? false;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // A complete record that has already moved on - approved, or sitting with
      // a reviewer - is still "complete", so the plain ready/not-ready split
      // told an Admin-signed-off record to "Submit it for review" beside a dead
      // button. The terminal states are called out for what they are instead.
      if (rec.status == 'Approved')
        _Callout(
          tone: Brand.ok,
          icon: Icons.verified,
          title: 'Approved',
          body: 'A reviewer has approved this record. It is locked - there is nothing to add or resubmit.',
        )
      else if (rec.status == 'Submitted')
        _Callout(
          tone: Brand.info,
          icon: Icons.hourglass_top,
          title: 'Awaiting review',
          body: 'Submitted and waiting for a reviewer. It comes back here if anything needs changing.',
        )
      else if (!ready)
        _Callout(
          tone: Brand.warn,
          icon: Icons.rule,
          title: 'Not ready to submit',
          body: [
            if ((v?.missingPhotos.length ?? 0) > 0) '${v!.missingPhotos.length} photo(s) missing',
            if ((v?.missingFields.length ?? 0) > 0) '${v!.missingFields.length} mandatory field(s) blank',
          ].join('  -  '),
        )
      else
        _Callout(
          tone: Brand.ok,
          icon: Icons.verified_outlined,
          title: 'Complete',
          body: 'Every mandatory field is filled and all five photos are tagged. Submit it for review.',
        ),
      const SizedBox(height: 16),
      Panel(
        title: 'Captured data',
        child: Column(children: [
          for (final section in _sections) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Text(section.label.toUpperCase(),
                    style: TextStyle(
                        color: Brand.pink, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ),
            ),
            for (final f in section.active)
              KvRow(
                f.labelWithUnit,
                '${rec.data[f.key] ?? ''}',
                valueColor: (rec.data[f.key] == null || rec.data[f.key] == '') && f.required ? Brand.bad : null,
                monospace: f.type == 'number',
              ),
            const SizedBox(height: 10),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Calculated automatically',
        child: Column(children: [
          for (final c in config?.computedFields ?? const <ComputedFieldInfo>[])
            if (rec.computed[c.key] != null)
              Tooltip(
                message: c.formula,
                child: KvRow(c.label, fmtNum(rec.computed[c.key]), monospace: true, valueColor: Brand.violet),
              ),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Photos',
        child: PhotoGrid(record: rec, photoTypes: config?.photoTypes ?? const []),
      ),
      const SizedBox(height: 20),
      Row(children: [
        OutlinedButton(
          onPressed: () => setState(() => _step -= 1),
          child: Text('Back'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RibbonButton(
            // The label names the actual state, so a locked or already-sent
            // record does not sit behind a button that says "Submit".
            label: rec.status == 'Approved'
                ? 'Approved - locked'
                : rec.status == 'Submitted'
                    ? 'Awaiting review'
                    : ready
                        ? 'Submit for review'
                        : 'Submit (incomplete)',
            icon: Icons.send_rounded,
            busy: _saving,
            expand: true,
            // Editable and not already sent. An incomplete one stays pressable
            // on purpose - the server answers with exactly what is missing.
            onPressed: rec.isEditable && rec.status != 'Submitted' ? _submit : null,
          ),
        ),
      ]),
    ]);
  }
}

/* --------------------------------------------------------------- pick view */

class _PickView extends ConsumerStatefulWidget {
  const _PickView({required this.onPicked});

  final void Function(String recordId) onPicked;

  @override
  ConsumerState<_PickView> createState() => _PickViewState();
}

class _PickViewState extends ConsumerState<_PickView> {
  final _search = TextEditingController();
  String _query = '';
  Part? _part;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        setState(() {
          _query = v.trim();
          _part = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final parts = ref.watch(partSearchProvider(_query));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'My work ·',
          accent: 'Collect Data',
          title: 'PFEP field collection',
          blurb: 'Pick the part number, then the vendor this data set is for. The part description fills '
              'itself in from the part master, and only the vendors mapped to that part are offered.',
        ),
        TextField(
          controller: _search,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: mono(size: 14),
          decoration: const InputDecoration(
            hintText: 'Type any part of the number or description...',
            prefixIcon: Icon(Icons.search, size: 19),
          ),
          onChanged: _onSearch,
        ),
        const SizedBox(height: 16),
        parts.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(partSearchProvider(_query))),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                message: _query.isEmpty
                    ? 'No parts loaded for this customer yet - ask the admin to upload the part master.'
                    : 'No part matches "$_query" in this customer part master.',
                icon: Icons.search_off,
              );
            }
            if (_part != null) return _VendorPicker(part: _part!, onPicked: widget.onPicked, onBack: () => setState(() => _part = null));
            return Column(children: [
              for (final p in list.take(60))
                _PartRow(part: p, onTap: () => setState(() => _part = p)),
            ]);
          },
        ),
      ],
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part, required this.onTap});

  final Part part;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = part.vendors.where((v) => v.recordStatus == 'Approved' || v.recordStatus == 'Submitted').length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Brand.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Brand.line),
          ),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(part.partNo, style: mono(size: 13.5, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(part.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Brand.txt2, fontSize: 12.3)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                if (part.partType != null) Pill(part.partType!, color: Brand.txt3),
                Pill('${part.vendors.length} vendor${part.vendors.length == 1 ? '' : 's'}',
                    color: part.vendors.length > 1 ? Brand.warn : Brand.txt3),
                if (done > 0) Pill('$done done', color: Brand.ok),
              ]),
            ),
            Icon(Icons.chevron_right, size: 18, color: Brand.txt3),
          ]),
        ),
      ),
    );
  }
}

class _VendorPicker extends ConsumerWidget {
  const _VendorPicker({required this.part, required this.onPicked, required this.onBack});

  final Part part;
  final void Function(String recordId) onPicked;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A row assigned to another collector cannot be saved by this one, so it is
    // shown locked here. Finding that out at save time means the section has
    // already been typed out and is then lost.
    final me = ref.watch(sessionProvider).user?.id;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(
          title: part.partNo,
          trailing: TextButton(onPressed: onBack, child: Text('Change part')),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(part.description, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Description filled in from the part master - read-only'
              '${part.partType == null ? '' : '  -  ${part.partType}'}'
              '  -  ${fmtNum(part.qtyPerVehicle)} per vehicle',
              style: TextStyle(color: Brand.txt3, fontSize: 11.8),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (part.vendors.length > 1)
          _Callout(
            tone: Brand.warn,
            icon: Icons.call_split,
            title: 'This part has more than one vendor',
            body: 'Pick the vendor this data set belongs to. Each vendor gets its own PFEP row and its own photographs.',
          ),
        if (part.vendors.length > 1) const SizedBox(height: 14),
        for (final v in part.vendors)
          Builder(builder: (context) {
            final locked = v.lockedFor(me);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Opacity(
                opacity: locked ? 0.55 : 1,
                child: InkWell(
                  onTap: (v.recordId == null || locked) ? null : () => onPicked(v.recordId!),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Brand.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Brand.line),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(v.id, style: mono(size: 11.5, color: Brand.pink)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(v.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13.3, fontWeight: FontWeight.w700)),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            locked
                                ? 'Assigned to ${v.assignedName ?? 'another collector'} - ask a reviewer to reassign it'
                                : [
                                    v.city,
                                    if (v.distanceKm != null) '${fmtNum(v.distanceKm)} km',
                                    v.transportMode,
                                  ].whereType<String>().join('  -  '),
                            style: TextStyle(
                              color: locked ? Brand.warn : Brand.txt3,
                              fontSize: 11.5,
                            ),
                          ),
                        ]),
                      ),
                      if (v.recordStatus != null) StatusPill(v.recordStatus!, compact: true),
                      const SizedBox(width: 10),
                      Icon(locked ? Icons.lock_outline : Icons.chevron_right,
                          size: 18, color: locked ? Brand.warn : Brand.txt3),
                    ]),
                  ),
                ),
              ),
            );
          }),
      ]);
  }
}

/* ------------------------------------------------------------------- bits */

class _RecordHeader extends StatelessWidget {
  const _RecordHeader({required this.record, required this.saving});

  final PfepRecord record;
  final bool saving;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 4, children: [
                Text(record.partNo, style: mono(size: 16, weight: FontWeight.w800)),
                StatusPill(record.status, compact: true),
                if (saving) Pill('Saving', color: Brand.info, icon: Icons.sync),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Text(record.description, style: TextStyle(fontSize: 13, color: Brand.txt2)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.local_shipping_outlined, size: 13, color: Brand.txt3),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${record.vendorId}  -  ${record.vendorName}'
                  '${record.vendorCity == null ? '' : '  -  ${record.vendorCity}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Brand.txt3, fontSize: 11.8)),
            ),
            Text('${record.photoCount}/${record.photoTotal} photos',
                style: TextStyle(
                    fontSize: 11.3,
                    fontWeight: FontWeight.w700,
                    color: record.missingPhotos.isEmpty ? Brand.ok : Brand.bad)),
          ]),
          if (record.status == 'Rejected' && record.reviewNote != null) ...[
            const SizedBox(height: 12),
            _Callout(
              tone: Brand.bad,
              icon: Icons.undo,
              title: 'Sent back by ${record.reviewedByName ?? 'the reviewer'}',
              body: record.reviewNote!,
            ),
          ],
        ]),
      );
}

class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.sections, required this.step, required this.record, required this.onTap});

  final List<FieldSection> sections;
  final int step;
  final PfepRecord record;
  final void Function(int step) onTap;

  /// Whether step [i] (0-based) is actually finished, rather than merely behind
  /// the cursor. A tick that only means "you have walked past this" contradicts
  /// the review banner - it would show Photos ticked while the same screen says
  /// five are missing.
  bool _done(int i) {
    if (i == sections.length) return record.missingPhotos.isEmpty;   // Photos
    if (i > sections.length) return false;                           // Review
    final fields = sections[i].fields.where((f) => f.enabled && f.required);
    return fields.isNotEmpty &&
        fields.every((f) {
          final v = record.data[f.key];
          return v != null && '$v'.trim().isNotEmpty;
        });
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final s in sections) s.label,
      'Photos',
      'Review',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Container(width: 18, height: 1, color: Brand.line, margin: const EdgeInsets.symmetric(horizontal: 4)),
          InkWell(
            onTap: () => onTap(i + 1),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: step == i + 1 ? Brand.pink.withValues(alpha: 0.14) : Brand.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: step == i + 1 ? Brand.pink.withValues(alpha: 0.5) : Brand.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _done(i) ? Brand.ok : (step == i + 1 ? Brand.pink : Brand.surface3),
                    shape: BoxShape.circle,
                  ),
                  child: _done(i)
                      ? Icon(Icons.check, size: 11, color: Colors.white)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: step == i + 1 ? Colors.white : Brand.txt3)),
                ),
                const SizedBox(width: 8),
                Text(labels[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: step == i + 1 ? FontWeight.w800 : FontWeight.w600,
                        color: step == i + 1 ? Brand.txt : Brand.txt3)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _NavButtons extends StatelessWidget {
  const _NavButtons({required this.onNext, required this.nextLabel, this.onBack});

  final Future<void> Function() onNext;
  final String nextLabel;
  final Future<void> Function()? onBack;

  @override
  Widget build(BuildContext context) => Row(children: [
        if (onBack != null) ...[
          OutlinedButton(onPressed: onBack, child: Text('Back')),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: RibbonButton(
            label: nextLabel,
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: onNext,
          ),
        ),
      ]);
}

class _Callout extends StatelessWidget {
  const _Callout({required this.tone, required this.icon, required this.title, required this.body});

  final Color tone;
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: tone, fontSize: 12.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(body, style: TextStyle(color: Brand.txt2, fontSize: 11.8, height: 1.5)),
            ]),
          ),
        ]),
      );
}
