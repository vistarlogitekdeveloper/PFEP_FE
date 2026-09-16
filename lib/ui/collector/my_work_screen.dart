import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// The collector home screen: what is assigned to me, what is left, and what
/// came back from the reviewer.
class MyWorkScreen extends ConsumerWidget {
  const MyWorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(myWorkProvider);


    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myWorkProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          PageHeader(
            crumb: 'My work ·',
            accent: 'Assignments',
            title: 'My assignments',
            blurb: 'The part-vendor rows assigned to you for this customer. Open one to capture its data '
                'and photographs on site.',
            actions: [
              FilledButton.icon(
                onPressed: () => context.go('/collect'),
                icon: Icon(Icons.photo_camera_outlined, size: 17),
                label: Text('Collect data'),
              ),
            ],
          ),
          work.when(
            loading: () => const Loading(label: 'Loading your assignments...'),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myWorkProvider)),
            data: (w) => _Body(work: w),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.work});

  final MyWork work;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? 4 : 2;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 196,
        ),
        children: [
          StatTile(label: 'Assigned to me', value: '${work.assigned}', accent: Brand.violet, icon: Icons.assignment_outlined),
          StatTile(label: 'Done', value: '${work.done}', sub: 'submitted or approved', accent: Brand.ok, icon: Icons.check_circle_outline),
          StatTile(label: 'Still to do', value: '${work.pending}', accent: Brand.pink, icon: Icons.pending_actions_outlined),
          StatTile(
            label: 'Sent back',
            value: '${work.rejected}',
            sub: work.rejected > 0 ? 'needs recapture' : 'nothing rejected',
            accent: work.rejected > 0 ? Brand.bad : Brand.txt3,
            icon: Icons.undo,
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (work.next.isEmpty)
        const Panel(
          title: 'Next up',
          child: EmptyState(
            message: 'Everything assigned to you is submitted. Nice work.',
            icon: Icons.task_alt,
          ),
        )
      else
        Panel(
          title: 'Next up',
          trailing: Text('${work.next.length} open',
              style: TextStyle(color: Brand.txt3, fontSize: 11.5)),
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final r in work.next.take(40)) _WorkRow(record: r),
          ]),
        ),
      if (work.recent.isNotEmpty) ...[
        const SizedBox(height: 16),
        Panel(
          title: 'Recently submitted',
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final r in work.recent.take(12)) _WorkRow(record: r, showTime: true),
          ]),
        ),
      ],
    ]);
  }
}

class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.record, this.showTime = false});

  final PfepRecord record;
  final bool showTime;

  /// Six columns do not fit a phone. Below this the row becomes two lines -
  /// identity on top, progress underneath - because squeezed into one, the part
  /// number itself broke across lines ("67861-" / "WSR") and the vendor came
  /// out as "Shakt…". The part number is the one thing a collector scans for.
  static const _stackBelow = 460.0;

  Widget _photos() => Text(
        '${record.photoCount}/${record.photoTotal}',
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: record.missingPhotos.isEmpty ? Brand.ok : Brand.bad),
      );

  Widget _progress() => showTime
      ? Text(fmtAgo(record.collectedAt), style: TextStyle(color: Brand.txt3, fontSize: 10.8))
      : Row(children: [
          Expanded(
            child: ProgressBar(
              value: record.completeness / 100,
              color: record.completeness > 70 ? Brand.ok : Brand.pink,
              height: 4,
            ),
          ),
          const SizedBox(width: 8),
          Text('${record.completeness}%',
              style: TextStyle(color: Brand.txt3, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.go('/collect?record=${record.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: LayoutBuilder(builder: (context, box) {
            if (box.maxWidth < _stackBelow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(
                    width: 28,
                    child: Text('${record.sn}', style: mono(size: 11, color: Brand.txt3)),
                  ),
                  Expanded(
                    child: Text(record.partNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(size: 12.8, weight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  _photos(),
                  const SizedBox(width: 8),
                  StatusPill(record.status, compact: true),
                  Icon(Icons.chevron_right, size: 16, color: Brand.txt3),
                ]),
                const SizedBox(height: 5),
                Padding(
                  padding: const EdgeInsets.only(left: 28, right: 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${record.description}  -  ${record.vendorName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Brand.txt3, fontSize: 11.3)),
                    const SizedBox(height: 5),
                    _progress(),
                  ]),
                ),
              ]);
            }
            return Row(children: [
              SizedBox(
                width: 34,
                child: Text('${record.sn}', style: mono(size: 11, color: Brand.txt3)),
              ),
              Expanded(
                flex: 4,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(record.partNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 12.8, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(record.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Brand.txt3, fontSize: 11.3)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(record.vendorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  _progress(),
                ]),
              ),
              const SizedBox(width: 10),
              _photos(),
              const SizedBox(width: 12),
              StatusPill(record.status, compact: true),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: Brand.txt3),
            ]);
          }),
        ),
      );
}
