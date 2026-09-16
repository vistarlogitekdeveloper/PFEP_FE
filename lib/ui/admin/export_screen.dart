import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// BRD 4.7 - auto Excel generation.
///
/// Everything collected in the field compiles into the customer PFEP format with
/// no manual re-typing. Photos ride along as embedded thumbnails or as links to
/// the stored image, against the correct part row.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  String? _status;
  DateTime? _from;
  DateTime? _to;
  String _photoMode = 'thumbnails';
  bool _busy = false;
  int? _rows;
  List<PfepRecord> _preview = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  String? get _fromIso => _from?.toIso8601String().substring(0, 10);
  String? get _toIso => _to?.toIso8601String().substring(0, 10);

  Future<void> _refresh() async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;
    try {
      final res = await ref.read(repositoryProvider).exportPreview(
            cid,
            status: _status,
            from: _fromIso,
            to: _toIso,
          );
      if (mounted) {
        setState(() {
          _rows = res.rows;
          _preview = res.preview;
        });
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Preview failed', detail: e.message, error: true);
    }
  }

  Future<void> _download({required bool csv}) async {
    final session = ref.read(sessionProvider);
    final cid = session.activeCustomerId;
    if (cid == null) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final stamp = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');
      if (csv) {
        final bytes = await repo.exportCsv(cid, status: _status, from: _fromIso, to: _toIso);
        await Downloads.save(bytes, 'PFEP_${cid}_$stamp.csv');
      } else {
        final bytes = await repo.exportExcel(
          cid,
          status: _status,
          from: _fromIso,
          to: _toIso,
          photos: _photoMode,
        );
        await Downloads.save(bytes, 'PFEP_${cid}_$stamp.xlsx');
      }
      if (mounted) {
        showToast(context, csv ? 'CSV saved' : 'PFEP Excel saved',
            detail: '${_rows ?? 0} rows in the customer column layout - nothing re-typed by hand.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Export failed', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isFrom ? _from = picked : _to = picked);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {


    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Output ·',
          accent: 'Excel Export',
          title: 'Auto Excel generation',
          blurb: 'The PFEP sheet is generated from the collected data, in the customer column layout: '
              'PART / VENDOR / PRIMARY PKG / AUTO-CALCULATED / STORAGE / LINE FEEDING / PHOTOS / STATUS. '
              'Export everything, or filter by status and collection date.',
          actions: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _download(csv: true),
              icon: Icon(Icons.description_outlined, size: 16),
              label: Text('CSV'),
            ),
            RibbonButton(
              label: 'Export PFEP Excel',
              icon: Icons.download_rounded,
              busy: _busy,
              onPressed: () => _download(csv: false),
            ),
          ],
        ),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              initialValue: _status,
              dropdownColor: Brand.surface2,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('All (full export)')),
                DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                DropdownMenuItem(value: 'Submitted', child: Text('Submitted')),
                DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
              ],
              onChanged: (v) {
                setState(() => _status = v);
                _refresh();
              },
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _pickDate(isFrom: true),
            icon: Icon(Icons.calendar_today_outlined, size: 15),
            label: Text(_from == null ? 'Collected from' : _fromIso!),
          ),
          OutlinedButton.icon(
            onPressed: () => _pickDate(isFrom: false),
            icon: Icon(Icons.calendar_today_outlined, size: 15),
            label: Text(_to == null ? 'Collected to' : _toIso!),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              initialValue: _photoMode,
              dropdownColor: Brand.surface2,
              decoration: const InputDecoration(labelText: 'Photos in the sheet'),
              items: const [
                DropdownMenuItem(value: 'thumbnails', child: Text('Embedded thumbnails')),
                DropdownMenuItem(value: 'links', child: Text('Hyperlinks to the image')),
                DropdownMenuItem(value: 'none', child: Text('Filenames only')),
              ],
              onChanged: (v) => setState(() => _photoMode = v ?? 'thumbnails'),
            ),
          ),
          if (_status != null || _from != null || _to != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _status = null;
                  _from = null;
                  _to = null;
                });
                _refresh();
              },
              child: Text('Reset'),
            ),
        ]),
        const SizedBox(height: 18),
        // Wrap, not Row: on a phone the third pill was clipped off the edge.
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill('${_rows ?? 0} rows will export', color: Brand.pink),
          Pill('Photos tagged per part row', color: Brand.info, icon: Icons.photo_outlined),
          Pill('Calculated columns included', color: Brand.violet, icon: Icons.auto_awesome),
        ]),
        const SizedBox(height: 16),
        ScrollTable(
          emptyMessage: 'Nothing matches this filter yet.',
          columns: const [
            DataColumn(label: Text('S.NO')),
            DataColumn(label: Text('PART')),
            DataColumn(label: Text('DESCRIPTION')),
            DataColumn(label: Text('VENDOR')),
            DataColumn(label: Text('KM')),
            DataColumn(label: Text('LEAD')),
            DataColumn(label: Text('SUPPLIER PKG (MM)')),
            DataColumn(label: Text('DAILY')),
            DataColumn(label: Text('ROP')),
            DataColumn(label: Text('BINS')),
            DataColumn(label: Text('BIN ID')),
            DataColumn(label: Text('PHOTOS')),
            DataColumn(label: Text('STATUS')),
          ],
          rows: [
            for (final r in _preview)
              DataRow(cells: [
                DataCell(Text('${r.sn}', style: mono(size: 11, color: Brand.txt3))),
                DataCell(Text(r.partNo, style: mono(size: 12))),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(r.vendorName, maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
                DataCell(Text(fmtNum(r.data['km']), style: mono(size: 11.5))),
                DataCell(Text(fmtNum(r.data['lead']), style: mono(size: 11.5))),
                DataCell(Text(
                  r.data['sL'] == null ? '-' : '${r.data['sL']}x${r.data['sB']}x${r.data['sH']}',
                  style: mono(size: 11.5, color: Brand.txt2),
                )),
                DataCell(Text(fmtNum(r.computed['dailyConsumption']), style: mono(size: 11.5))),
                DataCell(Text(fmtNum(r.computed['reorderPoint']),
                    style: mono(size: 11.5, color: Brand.violet))),
                DataCell(Text(fmtNum(r.computed['binsRequired']),
                    style: mono(size: 11.5, color: Brand.violet))),
                DataCell(Text('${r.data['bin'] ?? '-'}', style: mono(size: 11.5))),
                DataCell(Text(
                  r.photos.entries.where((e) => e.value != null).map((e) => e.key).join(' '),
                  style: mono(size: 9.5, color: r.missingPhotos.isEmpty ? Brand.ok : Brand.warn),
                )),
                DataCell(StatusPill(r.status, compact: true)),
              ]),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'What lands in the workbook',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            _Line(Icons.view_column_outlined, 'Column groups mirror the approved PFEP master',
                'A merged band row over the headers - PART, VENDOR, PRIMARY PKG, AUTO-CALCULATED, STORAGE, LINE FEEDING, PHOTOS, STATUS.'),
            _Line(Icons.auto_awesome, 'Calculated values are exported, not re-typed',
                'Daily and monthly consumption, safety stock, reorder point, max stock, bins and locations required, storage area and line-side cover.'),
            _Line(Icons.photo_outlined, 'Photos sit against the correct part row',
                'Embedded as thumbnails, or as hyperlinks to the cloud-stored image. A gap reads as MISSING rather than an empty cell.'),
            _Line(Icons.filter_alt_outlined, 'Filtered or full',
                'Export everything, or only what was approved, or only what was collected between two dates.'),
          ]),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.title, this.body);

  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Brand.pink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 12.7, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body, style: TextStyle(color: Brand.txt3, fontSize: 11.7, height: 1.5)),
            ]),
          ),
        ]),
      );
}
