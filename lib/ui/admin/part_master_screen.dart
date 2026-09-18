import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import 'add_part_dialog.dart';
import '../widgets/common.dart';

/// BRD 4.1 - Part Master upload.
///
/// Bulk, not one by one, and validated *before* anything is written: duplicate
/// part/vendor pairs, blank mandatory fields and non-numeric values are listed
/// row by row so the file can be fixed and re-sent.
class PartMasterScreen extends ConsumerStatefulWidget {
  const PartMasterScreen({super.key});

  @override
  ConsumerState<PartMasterScreen> createState() => _PartMasterScreenState();
}

class _PartMasterScreenState extends ConsumerState<PartMasterScreen> {
  Uint8List? _bytes;
  String? _filename;
  ImportReport? _report;
  bool _busy = false;
  bool _replace = false;
  String _search = '';

  Future<void> _pickFile() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xlsm', 'csv'],
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() {
      _bytes = file!.bytes;
      _filename = file.name;
      _report = null;
    });
    await _validate();
  }

  Future<void> _validate() async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null || _bytes == null) return;
    setState(() => _busy = true);
    try {
      final report = await ref.read(repositoryProvider).importPartMaster(
            customerId: cid,
            bytes: _bytes!,
            filename: _filename!,
          );
      if (mounted) setState(() => _report = report);
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not read the file', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null || _bytes == null) return;
    setState(() => _busy = true);
    try {
      final report = await ref.read(repositoryProvider).importPartMaster(
            customerId: cid,
            bytes: _bytes!,
            filename: _filename!,
            commit: true,
            replace: _replace,
          );
      if (!mounted) return;
      setState(() {
        _report = report;
        _bytes = null;
      });
      ref.invalidate(recordsProvider);
      ref.invalidate(dashboardProvider);
      ref.read(sessionProvider.notifier).refreshCustomers();
      final a = report.applied ?? {};
      showToast(context, 'Part master loaded',
          detail: '${a['partsInserted'] ?? 0} new parts, ${a['partsUpdated'] ?? 0} updated, '
              '${a['recordsCreated'] ?? 0} part-vendor rows opened for collection.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Upload rejected', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _template() async {
    try {
      final bytes = await ref.read(repositoryProvider).partTemplate();
      await Downloads.save(bytes, 'PFEP_Part_Master_Template.xlsx');
      if (mounted) {
        showToast(context, 'Template saved',
            detail: 'Purple columns are mandatory. One row per part and vendor.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Download failed', detail: e.message, error: true);
    }
  }

  /// Create one part by hand, without preparing a spreadsheet (BRD 4.1). Maps
  /// it to one or more vendors; each pairing becomes its own PFEP record, the
  /// same grain the bulk upload produces.
  Future<void> _addPart() async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const AddPartDialog(),
    );
    if (body == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).addPart(cid, body);
      if (!mounted) return;
      // A new part opens new records, so the same things the bulk commit
      // refreshes have to refresh here too.
      ref.invalidate(partSearchProvider);
      ref.invalidate(recordsProvider);
      ref.invalidate(dashboardProvider);
      ref.read(sessionProvider.notifier).refreshCustomers();
      final n = (body['vendorIds'] as List).length;
      showToast(context, 'Part added',
          detail: '${body['partNo']} mapped to $n vendor(s) - $n record(s) opened for collection.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not add the part', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Delete a part and, by cascade, its records and photos. Admin only, and
  /// guarded by a confirm because it discards collection work, not just a name.
  Future<void> _deletePart(Part p) async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;
    final recordCount = p.vendors.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this part?'),
        content: Text(
          '${p.partNo} - ${p.description}\n\n'
          'This removes the part and its $recordCount record(s), including any field data and '
          'photos already collected against them. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.bad),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await ref.read(repositoryProvider).deletePart(cid, p.id);
      if (!mounted) return;
      ref.invalidate(partSearchProvider);
      ref.invalidate(recordsProvider);
      ref.invalidate(dashboardProvider);
      ref.read(sessionProvider.notifier).refreshCustomers();
      showToast(context, 'Part deleted',
          detail: '${res['partNo'] ?? p.partNo} and ${res['recordsRemoved'] ?? recordCount} record(s) removed.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not delete the part', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = ref.watch(partSearchProvider(_search));
    // Delete is destructive and Admin-only. Part Master is already an
    // Admin-only route, but the button is gated on the role too so "view as"
    // previews of other roles never show it.
    final isAdmin = ref.watch(sessionProvider).user?.isAdmin ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Setup ·',
          accent: 'Part Master',
          title: 'Part master',
          blurb: 'Upload the customer part list in bulk from Excel or CSV. The file is validated before '
              'anything is saved - duplicate part/vendor pairs, blank mandatory fields and unmatched formats '
              'are reported row by row. One part number can be mapped to several vendors; each pairing becomes '
              'its own PFEP line item.',
          actions: [
            OutlinedButton.icon(
              onPressed: _template,
              icon: Icon(Icons.download_outlined, size: 16),
              label: Text('Download template'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: Icon(Icons.upload_file, size: 17),
              label: Text('Choose file'),
            ),
            // The single-entry path: add one part without a spreadsheet.
            FilledButton.icon(
              onPressed: _busy ? null : _addPart,
              icon: Icon(Icons.add, size: 18),
              label: Text('Add a part'),
            ),
          ],
        ),
        if (_busy) const Loading(label: 'Validating the file...'),
        if (_report != null && !_busy) _ReportView(
          report: _report!,
          filename: _filename ?? '',
          replace: _replace,
          onReplaceChanged: (v) => setState(() => _replace = v),
          onCommit: _bytes == null ? null : _commit,
        ),
        const SizedBox(height: 20),
        Panel(
          title: 'Loaded parts',
          trailing: SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search part or description',
                prefixIcon: Icon(Icons.search, size: 17),
                isDense: true,
              ),
              style: TextStyle(fontSize: 12.5),
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          padding: EdgeInsets.zero,
          child: parts.when(
            loading: () => const Loading(),
            error: (e, _) => ErrorView(error: e),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    message: 'No parts loaded for this customer yet. Upload the part master to begin.',
                    icon: Icons.inventory_2_outlined,
                  )
                : Column(children: [
                    for (final p in list.take(100))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                        child: Row(children: [
                          Expanded(
                            flex: 3,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.partNo, style: mono(size: 12.5, weight: FontWeight.w700)),
                              Text(p.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Brand.txt3, fontSize: 11.3)),
                            ]),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 4,
                            child: Wrap(spacing: 6, runSpacing: 4, children: [
                              for (final v in p.vendors)
                                Pill(v.name, color: v.recordStatus == 'Approved' ? Brand.ok : Brand.txt3),
                            ]),
                          ),
                          SizedBox(
                            width: 72,
                            child: Text('${fmtNum(p.qtyPerVehicle)}/veh',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: Brand.txt3, fontSize: 11)),
                          ),
                          if (isAdmin)
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: Brand.txt3),
                              tooltip: 'Delete part',
                              onPressed: _busy ? null : () => _deletePart(p),
                            ),
                        ]),
                      ),
                  ]),
          ),
        ),
      ],
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.report,
    required this.filename,
    required this.replace,
    required this.onReplaceChanged,
    required this.onCommit,
  });

  final ImportReport report;
  final String filename;
  final bool replace;
  final void Function(bool) onReplaceChanged;
  final VoidCallback? onCommit;

  @override
  Widget build(BuildContext context) {
    final s = report.stats;
    final committed = report.committed;
    final blocked = report.headerErrors.isNotEmpty || report.errors.isNotEmpty;

    return Panel(
      title: committed ? 'Uploaded' : 'Validation report',
      trailing: Pill(
        committed ? 'Committed' : (blocked ? '${report.errors.length + report.headerErrors.length} problem(s)' : 'Ready to load'),
        color: committed ? Brand.ok : (blocked ? Brand.bad : Brand.ok),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(filename, style: mono(size: 12, color: Brand.txt2)),
        const SizedBox(height: 14),
        Wrap(spacing: 22, runSpacing: 12, children: [
          _Stat('Rows read', '${s['totalRows'] ?? 0}'),
          _Stat('Valid rows', '${s['validRows'] ?? 0}', color: Brand.ok),
          _Stat('Rows with errors', '${s['errorRows'] ?? 0}', color: (s['errorRows'] ?? 0) > 0 ? Brand.bad : Brand.txt3),
          _Stat('Unique parts', '${s['uniqueParts'] ?? 0}'),
          _Stat('Unique vendors', '${s['uniqueVendors'] ?? 0}'),
          _Stat('Part-vendor mappings', '${s['mappings'] ?? 0}', color: Brand.violet),
        ]),
        if (committed && report.applied != null) ...[
          const SizedBox(height: 16),
          Divider(height: 1),
          const SizedBox(height: 14),
          Wrap(spacing: 22, runSpacing: 12, children: [
            _Stat('New parts', '${report.applied!['partsInserted'] ?? 0}', color: Brand.ok),
            _Stat('Parts updated', '${report.applied!['partsUpdated'] ?? 0}'),
            _Stat('Vendors created', '${report.applied!['vendorsCreated'] ?? 0}'),
            _Stat('Line items opened', '${report.applied!['recordsCreated'] ?? 0}', color: Brand.pink),
          ]),
        ],
        if (report.headerErrors.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Issues(
            title: 'The header row does not match the template',
            tone: Brand.bad,
            lines: report.headerErrors,
          ),
        ],
        if (report.errors.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Issues(
            title: '${report.errors.length} row(s) must be fixed before this file can be loaded',
            tone: Brand.bad,
            lines: [
              for (final e in report.errors.take(40))
                'Row ${e.row}  ${e.partNo.isEmpty ? '' : '(${e.partNo})'}  -  ${e.issues.join('; ')}',
              if (report.errors.length > 40) '... and ${report.errors.length - 40} more',
            ],
          ),
        ],
        if (report.warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Issues(title: 'Warnings', tone: Brand.warn, lines: report.warnings.take(20).toList()),
        ],
        if (!committed && onCommit != null) ...[
          const SizedBox(height: 18),
          Divider(height: 1),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: replace,
            onChanged: (v) => onReplaceChanged(v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: Brand.pink,
            title: Text('Replace the existing master', style: TextStyle(fontSize: 12.8)),
            subtitle: Text(
              'Removes line items nobody has started. Records already collected are always kept.',
              style: TextStyle(color: Brand.txt3, fontSize: 11.2),
            ),
          ),
          const SizedBox(height: 10),
          RibbonButton(
            label: blocked ? 'Fix the errors above first' : 'Load into the part master',
            icon: Icons.cloud_upload_outlined,
            expand: true,
            onPressed: blocked ? null : onCommit,
          ),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});

  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Brand.txt3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color ?? Brand.txt)),
        ],
      );
}

class _Issues extends StatelessWidget {
  const _Issues({required this.title, required this.tone, required this.lines});

  final String title;
  final Color tone;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.34)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.error_outline, size: 15, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title, style: TextStyle(color: tone, fontSize: 12.3, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: mono(size: 11, color: Brand.txt2, weight: FontWeight.w400)),
            ),
        ]),
      );
}
