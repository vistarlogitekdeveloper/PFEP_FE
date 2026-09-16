import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/downloads.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import '../widgets/label_preview.dart';

/// BRD 4.8 - auto-generated warehouse and line-side labels.
///
/// Content comes straight from the data already captured, so there is no
/// separate label design step. Output is print-ready: a PDF sheet for a normal
/// printer, or ZPL for a thermal/barcode printer, one at a time or in bulk.
class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({super.key});

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
  String _kind = 'rack';
  bool _busy = false;

  Future<void> _bulk(String format) async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(repositoryProvider).bulkLabels(cid, kind: _kind, format: format);
      if (format == 'pdf') {
        await Downloads.printPdf(bytes, name: 'PFEP $_kind labels');
      } else {
        await Downloads.save(bytes, 'PFEP_${cid}_LABELS_${_kind.toUpperCase()}.zpl');
      }
      if (!mounted) return;
      showToast(
        context,
        format == 'pdf' ? 'Label sheet ready to print' : 'ZPL file saved',
        detail: format == 'pdf'
            ? 'Every approved record for this customer, in one action.'
            : 'Send it to any Zebra-compatible thermal printer.',
      );
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Labels not generated', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _single(PfepRecord rec, String format) async {
    try {
      final bytes = await ref.read(repositoryProvider).labelFile(rec.id, kind: _kind, format: format);
      if (format == 'pdf') {
        await Downloads.printPdf(bytes, name: '${rec.partNo} $_kind label');
      } else {
        await Downloads.save(bytes, '${rec.partNo}_$_kind.zpl');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Label failed', detail: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(recordsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Output ·',
          accent: 'Label Studio',
          title: 'Auto-generated warehouse & line-side labels',
          blurb: 'Part number, description, vendor, bin location, packaging quantity, barcode and QR are all '
              'pulled from the data already captured - no separate design step. Size and layout are configurable '
              'per customer, because every plant has its own label stock and printer.',
          actions: [
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _bulk('zpl'),
              icon: Icon(Icons.print_outlined, size: 16),
              label: Text('Bulk ZPL'),
            ),
            RibbonButton(
              label: 'Print all approved',
              icon: Icons.local_printshop_outlined,
              busy: _busy,
              onPressed: () => _bulk('pdf'),
            ),
          ],
        ),
        // The full labels carry the stock size, which is worth showing wherever
        // it fits - but on a phone the pair ran off the edge, so the size moves
        // to a shorthand rather than being clipped.
        LayoutBuilder(builder: (context, box) {
          final tight = box.maxWidth < 400;
          // Sizes come from the customer's saved formats rather than being
          // written in here: the moment an admin edits a format in Label
          // Formats, a hard-coded "100 x 50 mm" becomes a lie.
          final cfg = ref.watch(labelTemplatesProvider).maybeWhen(data: (c) => c, orElse: () => null);
          String seg(String kind, String fallbackName, String shortName) {
            LabelTemplate? t;
            for (final x in cfg?.templates ?? const <LabelTemplate>[]) {
              if (x.kind == kind) t = x;
            }
            if (t == null) return tight ? shortName : fallbackName;
            final w = t.widthMm == t.widthMm.roundToDouble() ? '${t.widthMm.round()}' : t.widthMm.toStringAsFixed(1);
            final h = t.heightMm == t.heightMm.roundToDouble() ? '${t.heightMm.round()}' : t.heightMm.toStringAsFixed(1);
            return tight ? '$shortName ${w}x$h' : '${t.name}  $w x $h mm';
          }

          return Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'rack', label: Text(seg('rack', 'Warehouse rack', 'Rack'))),
                ButtonSegment(value: 'line', label: Text(seg('line', 'Line-side bin', 'Bin'))),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
              style: ButtonStyle(
                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Brand.pink.withValues(alpha: 0.2)
                      : Brand.surface,
                ),
              ),
            ),
            if (ref.watch(sessionProvider).user?.isAdmin ?? false)
              GhostButton(
                label: 'Edit layout',
                icon: Icons.crop_free_outlined,
                small: true,
                onPressed: () => context.go('/label-formats'),
              ),
          ]);
        }),
        const SizedBox(height: 18),
        records.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorView(error: e),
          data: (list) {
            final approved = list.where((r) => r.status == 'Approved').toList();
            if (approved.isEmpty) {
              return const Panel(
                title: 'No labels yet',
                child: EmptyState(
                  message: 'Labels unlock once the reviewer approves a record - printing unverified data is '
                      'how wrong labels end up on a rack.',
                  icon: Icons.local_offer_outlined,
                ),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Wrap, not Row: the second pill ran off the edge on a phone.
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill('${approved.length} approved records eligible', color: Brand.ok),
                Pill('QR + Code 128 generated per label', color: Brand.info),
              ]),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final r in approved.take(12))
                    _LabelCard(
                      record: r,
                      kind: _kind,
                      onPdf: () => _single(r, 'pdf'),
                      onZpl: () => _single(r, 'zpl'),
                    ),
                ],
              ),
              if (approved.length > 12)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('+ ${approved.length - 12} more included in the bulk output.',
                      style: TextStyle(color: Brand.txt3, fontSize: 12)),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

/// A visual stand-in for the printed label, rendered from the same tokens the
/// PDF and ZPL generators use on the server.
class _LabelCard extends ConsumerWidget {
  const _LabelCard({required this.record, required this.kind, required this.onPdf, required this.onZpl});

  final PfepRecord record;
  final String kind;
  final VoidCallback onPdf, onZpl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(_labelPreviewProvider((record.id, kind)));
    final isRack = kind == 'rack';

    return SizedBox(
      width: isRack ? 320 : 260,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${record.partNo}  -  ${record.vendorName.split(' ').first}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Brand.txt3, fontSize: 10.8)),
          ),
          TextButton(
            onPressed: onZpl,
            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 6)),
            child: Text('ZPL', style: TextStyle(fontSize: 10.5)),
          ),
          TextButton(
            onPressed: onPdf,
            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 6)),
            child: Text('Print', style: TextStyle(fontSize: 10.5)),
          ),
        ]),
        const SizedBox(height: 5),
        // The same LabelFace the template editor previews against, and drawn
        // from the template's own millimetres rather than a hard-coded ratio,
        // so a resized format shows here at its real shape.
        preview.when(
          loading: () => const AspectRatio(
            aspectRatio: 2,
            child: Center(
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (e, _) => AspectRatio(
            aspectRatio: 2,
            child: Center(
                child: Text('preview unavailable', style: TextStyle(color: Brand.txt3, fontSize: 10))),
          ),
          data: (p) => LabelFace(
            widthMm: p.widthMm,
            heightMm: p.heightMm,
            hasQr: p.hasQr,
            hasBarcode: p.hasBarcode,
            lines: [
              for (final l in p.lines) LabelFaceLine(label: l.label, value: l.value, size: l.size),
            ],
          ),
        ),
      ]),
    );
  }
}

final _labelPreviewProvider =
    FutureProvider.autoDispose.family<LabelPreview, (String, String)>((ref, args) {
  return ref.watch(repositoryProvider).labelPreview(args.$1, args.$2);
});

