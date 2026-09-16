import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import '../widgets/photo_capture.dart';

/// One PFEP line item in full: captured fields, the values the app derived,
/// the five tagged photographs, and the review actions.
class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recordProvider(recordId));
    final user = ref.watch(sessionProvider).user;
    final config = ref.watch(fieldConfigProvider).value;

    return async.when(
      loading: () => const Loading(label: 'Loading record...'),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(recordProvider(recordId))),
      data: (rec) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          PageHeader(
            crumb: 'Data ·',
            accent: 'Record ${rec.sn}',
            title: rec.partNo,
            blurb: '${rec.description} · ${rec.vendorName}',
            blurbHighlight: rec.vendorName,
            actions: [
              OutlinedButton.icon(
                onPressed: () => context.go('/records'),
                icon: Icon(Icons.arrow_back, size: 15),
                label: Text('Back to records'),
              ),
              if (rec.status == 'Approved')
                OutlinedButton.icon(
                  onPressed: () => _label(context, ref, rec),
                  icon: Icon(Icons.local_offer_outlined, size: 15),
                  label: Text('Print label'),
                ),
              if ((user?.canEdit ?? false) && rec.isEditable)
                FilledButton.icon(
                  onPressed: () => context.go('/collect?record=${rec.id}'),
                  icon: Icon(Icons.edit_outlined, size: 16),
                  label: Text('Edit data'),
                ),
            ],
          ),
          _Summary(record: rec),
          if (rec.status == 'Rejected' && rec.reviewNote != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              decoration: BoxDecoration(
                color: Brand.bad.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Brand.bad.withValues(alpha: 0.35)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.undo, size: 16, color: Brand.bad),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Sent back by ${rec.reviewedByName ?? 'the reviewer'}  -  ${fmtDateTime(rec.reviewedAt)}',
                        style: TextStyle(color: Brand.bad, fontSize: 12.3, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(rec.reviewNote!,
                        style: TextStyle(color: Brand.txt2, fontSize: 12, height: 1.5)),
                  ]),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Panel(
            title: 'Photographs',
            trailing: Pill('${rec.photoCount} of ${rec.photoTotal}',
                color: rec.missingPhotos.isEmpty ? Brand.ok : Brand.bad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              PhotoGrid(
                record: rec,
                photoTypes: config?.photoTypes ?? const [],
                onTapPhoto: (type) => _viewPhoto(context, ref, rec, type),
              ),
              const SizedBox(height: 12),
              Text(
                'Each file is named ${rec.partNo}_${rec.vendorId}_<type>, assigned by the server at the moment '
                'of capture - the photograph cannot end up against another part number.',
                style: TextStyle(color: Brand.txt3, fontSize: 11.3, height: 1.5),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          for (final section in rec.sections) ...[
            Panel(
              title: section.label,
              child: Column(children: [
                for (final f in section.active)
                  KvRow(
                    f.labelWithUnit,
                    '${rec.data[f.key] ?? ''}',
                    monospace: f.type == 'number',
                    valueColor: (rec.data[f.key] == null || rec.data[f.key] == '') && f.required ? Brand.bad : null,
                  ),
              ]),
            ),
            const SizedBox(height: 14),
          ],
          Panel(
            title: 'Calculated automatically',
            trailing: Pill('Not typed by the field team', color: Brand.violet, icon: Icons.auto_awesome),
            child: Column(children: [
              for (final c in config?.computedFields ?? const <ComputedFieldInfo>[])
                if (rec.computed[c.key] != null)
                  Tooltip(
                    message: c.formula,
                    child: KvRow(c.label, fmtNum(rec.computed[c.key]), monospace: true, valueColor: Brand.violet),
                  ),
            ]),
          ),
          if (user?.canReview ?? false) ...[
            const SizedBox(height: 16),
            _ReviewActions(record: rec),
          ],
        ],
      ),
    );
  }

  Future<void> _label(BuildContext context, WidgetRef ref, PfepRecord rec) async {
    try {
      final bytes = await ref.read(repositoryProvider).labelFile(rec.id, kind: 'rack', format: 'pdf');
      await Downloads.printPdf(bytes, name: '${rec.partNo} rack label');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, 'Label failed', detail: e.message, error: true);
    }
  }

  void _viewPhoto(BuildContext context, WidgetRef ref, PfepRecord rec, String type) {
    final photo = rec.photos[type];
    if (photo == null) return;
    final api = ref.read(apiClientProvider);
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Brand.surface,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(photo.name, style: mono(size: 12.5)),
                  Text('${rec.partNo}  -  ${rec.vendorName}  -  captured ${fmtDateTime(photo.capturedAt)}',
                      style: TextStyle(color: Brand.txt3, fontSize: 11)),
                ]),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Flexible(
            child: InteractiveViewer(
              child: Image.network(api.fileUrl(photo.url), headers: api.authHeaders),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.record});

  final PfepRecord record;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Brand.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusPill(record.status),
            Pill(record.customerId, color: Brand.violet),
            if (record.partType != null) Pill(record.partType!, color: Brand.txt3),
            Pill('${record.completeness}% complete', color: record.completeness == 100 ? Brand.ok : Brand.pink),
            Pill('${record.photoCount}/${record.photoTotal} photos',
                color: record.missingPhotos.isEmpty ? Brand.ok : Brand.bad),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 28, runSpacing: 12, children: [
            _Meta('Vendor', '${record.vendorId}  ${record.vendorName}'),
            _Meta('Vendor location', record.vendorCity ?? '-'),
            _Meta('Qty per vehicle', fmtNum(record.qtyPerVehicle)),
            _Meta('Assigned to', record.assignedName ?? 'unassigned'),
            _Meta('Collected by', record.collectedByName ?? '-'),
            _Meta('Collected on', fmtDateTime(record.collectedAt)),
            if (record.device != null) _Meta('Device', record.device!),
            if (record.reviewedByName != null) _Meta('Reviewed by', record.reviewedByName!),
          ]),
        ]),
      );
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Brand.txt3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600)),
        ],
      );
}

class _ReviewActions extends ConsumerStatefulWidget {
  const _ReviewActions({required this.record});

  final PfepRecord record;

  @override
  ConsumerState<_ReviewActions> createState() => _ReviewActionsState();
}

class _ReviewActionsState extends ConsumerState<_ReviewActions> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).approve(widget.record.id);
      ref.invalidate(recordProvider(widget.record.id));
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        showToast(context, 'Approved',
            detail: '${widget.record.partNo} is locked and its labels can now be printed.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not approve', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final result = await showDialog<({String note, List<String> clear})>(
      context: context,
      builder: (_) => _RejectDialog(record: widget.record),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).reject(widget.record.id, result.note, clearPhotos: result.clear);
      ref.invalidate(recordProvider(widget.record.id));
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        showToast(context, 'Sent back to the collector',
            detail: result.clear.isEmpty
                ? 'The collector sees your note on their assignment list.'
                : '${result.clear.length} photo(s) cleared for recapture.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not reject', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.record;
    if (rec.status != 'Submitted') {
      return Panel(
        title: 'Review',
        child: Text(
          rec.status == 'Approved'
              ? 'Approved by ${rec.reviewedByName ?? 'the reviewer'} on ${fmtDateTime(rec.reviewedAt)}.'
              : 'This record is not waiting for review - it is ${rec.status.toLowerCase()}.',
          style: TextStyle(color: Brand.txt3, fontSize: 12.5),
        ),
      );
    }

    return Panel(
      title: 'Review this record',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Check the captured values against the photographs before approving. Approved records feed the '
          'Excel export and unlock label printing.',
          style: TextStyle(color: Brand.txt3, fontSize: 12, height: 1.55),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              icon: Icon(Icons.undo, size: 16, color: Brand.bad),
              label: Text('Send back', style: TextStyle(color: Brand.bad)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: RibbonButton(
              label: 'Approve',
              icon: Icons.verified_outlined,
              busy: _busy,
              expand: true,
              onPressed: _approve,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _RejectDialog extends ConsumerStatefulWidget {
  const _RejectDialog({required this.record});

  final PfepRecord record;

  @override
  ConsumerState<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends ConsumerState<_RejectDialog> {
  final _note = TextEditingController();
  final _clear = <String>{};

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(fieldConfigProvider).value?.photoTypes ?? const <PhotoType>[];
    return AlertDialog(
      title: Text('Send back to the collector'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Say what needs fixing. The note appears on the collector assignment list.',
                style: TextStyle(color: Brand.txt3, fontSize: 12, height: 1.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'e.g. Supplier packaging photo shows the outer carton...'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('Clear a photo so it must be recaptured',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Brand.txt2)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in types)
                FilterChip(
                  label: Text(t.label, style: TextStyle(fontSize: 11.5)),
                  selected: _clear.contains(t.key),
                  selectedColor: Brand.bad.withValues(alpha: 0.2),
                  onSelected: widget.record.photos[t.key] == null
                      ? null
                      : (v) => setState(() => v ? _clear.add(t.key) : _clear.remove(t.key)),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Brand.bad),
          onPressed: _note.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((note: _note.text.trim(), clear: _clear.toList())),
          child: Text('Send back'),
        ),
      ],
    );
  }
}
