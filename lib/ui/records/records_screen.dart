import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';

import '../widgets/common.dart';

/// The full PFEP grid: one row per part x vendor, with its status, how complete
/// it is and how many of its five photographs are in.
class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  Timer? _debounce;

  // The collector default (mine: true) is set by RecordFilterNotifier.build(),
  // so the sidebar badge and this screen agree from the first frame.

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(recordFilterProvider);
    final records = ref.watch(recordsProvider);
    final user = ref.watch(sessionProvider).user;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: user?.isCollector ?? false ? 'My work ·' : 'Data ·',
          accent: user?.isCollector ?? false ? 'Submissions' : 'PFEP Records',
          title: user?.isCollector ?? false ? 'My submissions' : 'PFEP records',
          blurb: 'One row per part number and vendor - the grain of the PFEP sheet. Open a row to see every '
              'captured field, the calculated values and the five tagged photographs.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(recordsProvider),
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Refresh'),
            ),
          ],
        ),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search part, description or vendor',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              style: TextStyle(fontSize: 13),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  ref.read(recordFilterProvider.notifier).set(RecordFilter(
                    status: filter.status,
                    query: v.trim().isEmpty ? null : v.trim(),
                    mine: filter.mine,
                  ));
                });
              },
            ),
          ),
          for (final s in [null, 'Pending', 'In Progress', 'Submitted', 'Approved', 'Rejected'])
            ChoiceChip(
              label: Text(s ?? 'All'),
              selected: filter.status == s,
              selectedColor: Brand.pink.withValues(alpha: 0.2),
              onSelected: (_) => ref
                  .read(recordFilterProvider.notifier)
                  .set(RecordFilter(status: s, query: filter.query, mine: filter.mine)),
            ),
          if (!(user?.isCollector ?? false))
            FilterChip(
              label: Text('Assigned to me'),
              selected: filter.mine,
              selectedColor: Brand.violet.withValues(alpha: 0.2),
              onSelected: (v) => ref
                  .read(recordFilterProvider.notifier)
                  .set(RecordFilter(status: filter.status, query: filter.query, mine: v)),
            ),
        ]),
        const SizedBox(height: 18),
        records.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(recordsProvider)),
          data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Pill('${list.length} line items', color: Brand.violet),
                const SizedBox(width: 8),
                Pill('${list.where((r) => r.missingPhotos.isNotEmpty && r.status != 'Pending').length} with photo gaps',
                    color: Brand.bad),
              ]),
            ),
            ScrollTable(
              emptyMessage: 'No records match this filter.',
              columns: const [
                DataColumn(label: Text('S.NO')),
                DataColumn(label: Text('PART')),
                DataColumn(label: Text('DESCRIPTION')),
                DataColumn(label: Text('VENDOR')),
                DataColumn(label: Text('BIN')),
                DataColumn(label: Text('COMPLETE')),
                DataColumn(label: Text('PHOTOS')),
                DataColumn(label: Text('STATUS')),
                DataColumn(label: Text('COLLECTED BY')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final r in list)
                  DataRow(cells: [
                    DataCell(Text('${r.sn}', style: mono(size: 11, color: Brand.txt3))),
                    DataCell(Text(r.partNo, style: mono(size: 12))),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(r.vendorName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text('${r.data['bin'] ?? '-'}', style: mono(size: 11.5, color: Brand.txt2))),
                    DataCell(SizedBox(
                      width: 88,
                      child: Row(children: [
                        Expanded(
                          child: ProgressBar(
                            value: r.completeness / 100,
                            color: r.completeness == 100 ? Brand.ok : Brand.pink,
                            height: 4,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text('${r.completeness}%', style: TextStyle(fontSize: 10.5, color: Brand.txt3)),
                      ]),
                    )),
                    DataCell(Row(children: [
                      Text('${r.photoCount}/${r.photoTotal}',
                          style: mono(
                              size: 11.5,
                              color: r.missingPhotos.isEmpty ? Brand.ok : Brand.bad)),
                      if (r.missingPhotos.isNotEmpty && r.status != 'Pending')
                        Padding(
                          padding: EdgeInsets.only(left: 5),
                          child: Icon(Icons.circle, size: 6, color: Brand.bad),
                        ),
                    ])),
                    DataCell(StatusPill(r.status, compact: true)),
                    DataCell(Text(r.collectedByName ?? '-',
                        style: TextStyle(fontSize: 11.8, color: Brand.txt2))),
                    DataCell(IconButton(
                      icon: Icon(Icons.open_in_new, size: 15),
                      onPressed: () => context.go('/records/${r.id}'),
                    )),
                  ]),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}
