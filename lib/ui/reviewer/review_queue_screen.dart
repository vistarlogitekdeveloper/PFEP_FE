import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';

/// BRD 4.11 - the Reviewer / Supervisor step: records are checked and approved
/// before they can reach the customer export or a printed label.
class ReviewQueueScreen extends ConsumerWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(reviewQueueProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          PageHeader(
            crumb: 'Review ·',
            accent: 'Queue',
            title: 'Review queue',
            blurb: 'Records the field team has submitted, waiting for sign-off. Approving one locks it and '
                'releases it to the Excel export and the label studio; sending it back tells the collector '
                'exactly what to recapture.',
            actions: [
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(reviewQueueProvider),
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Refresh'),
              ),
            ],
          ),
          queue.when(
            loading: () => const Loading(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(reviewQueueProvider)),
            data: (records) => records.isEmpty
                ? const Panel(
                    title: 'Nothing waiting',
                    child: EmptyState(
                      message: 'The queue is clear - every submitted record has been reviewed.',
                      icon: Icons.task_alt,
                    ),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Pill('${records.length} awaiting review', color: Brand.warn),
                      const SizedBox(width: 8),
                      Pill(
                        '${records.where((r) => r.missingPhotos.isNotEmpty).length} with a photo gap',
                        color: Brand.bad,
                      ),
                    ]),
                    const SizedBox(height: 14),
                    for (final r in records)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => context.go('/records/${r.id}'),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
                            decoration: BoxDecoration(
                              color: Brand.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: r.missingPhotos.isEmpty ? Brand.line : Brand.bad.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(r.partNo, style: mono(size: 13, weight: FontWeight.w700)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(r.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Brand.txt2, fontSize: 12.3)),
                                ),
                                Text('${r.photoCount}/${r.photoTotal}',
                                    style: mono(
                                        size: 11.5,
                                        color: r.missingPhotos.isEmpty ? Brand.ok : Brand.bad)),
                                const SizedBox(width: 10),
                                Icon(Icons.chevron_right, size: 17, color: Brand.txt3),
                              ]),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Pill(r.vendorName, color: Brand.txt3, icon: Icons.local_shipping_outlined),
                                Pill(r.collectedByName ?? 'unknown', color: Brand.violet, icon: Icons.person_outline),
                                Pill(fmtAgo(r.collectedAt), color: Brand.txt3, icon: Icons.schedule),
                                if (r.data['bin'] != null)
                                  Pill('Bin ${r.data['bin']}', color: Brand.info),
                                if (r.missingPhotos.isNotEmpty)
                                  Pill('Missing: ${r.missingPhotos.join(', ')}', color: Brand.bad),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }
}
