import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// BRD 4.10 - the progress dashboard.
///
/// Answers the question the manager actually asks: of the 60-120 line items,
/// how many are done, how many are pending, and which ones are missing a photo -
/// without opening the Excel.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
        children: [
          PageHeader(
            crumb: 'Overview ·',
            accent: 'Progress Dashboard',
            title: 'PFEP progress dashboard',
            blurb: 'Live status of the PFEP collection for this customer - line items completed, '
                'items still pending, and the records still missing a photograph.',
            actions: [
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(dashboardProvider),
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Refresh'),
              ),
            ],
          ),
          async.when(
            loading: () => const Loading(label: 'Loading progress...'),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
            data: (d) => d == null
                ? const EmptyState(message: 'No customer selected yet.')
                : _Body(dash: d),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.dash});

  final Dashboard dash;

  @override
  Widget build(BuildContext context) {
    final t = dash.totals;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 1100 ? 4 : (width > 700 ? 3 : 2);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          // A fixed height keeps the KPI cards uniform regardless of how long
          // the caption under each number runs.
          mainAxisExtent: 196,
        ),
        children: [
          StatTile(
            label: 'Total line items',
            value: '${t.lineItems}',
            sub: '${t.parts} parts across ${t.vendors} vendors',
            accent: Brand.violet,
            icon: Icons.list_alt_outlined,
          ),
          StatTile(
            label: 'Completed',
            value: '${t.completed}',
            sub: '${t.approvedPct}% approved by the reviewer',
            accent: Brand.ok,
            icon: Icons.verified_outlined,
          ),
          StatTile(
            label: 'Pending',
            value: '${t.pending + t.inProgress}',
            sub: '${t.inProgress} in progress, ${t.pending} not started',
            accent: Brand.info,
            icon: Icons.pending_outlined,
          ),
          StatTile(
            label: 'Missing photos',
            value: '${t.missingPhotoItems}',
            sub: '${t.photosCaptured} of ${t.photosNeeded} photos captured',
            accent: t.missingPhotoItems > 0 ? Brand.bad : Brand.ok,
            icon: Icons.photo_camera_back_outlined,
            onTap: () => context.go('/records'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _ProgressPanel(dash: dash),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, c) {
        final stacked = c.maxWidth < 900;
        final photo = _PhotoGapPanel(gaps: dash.photoGaps);
        final trend = _TrendPanel(points: dash.trend);
        return stacked
            ? Column(children: [photo, const SizedBox(height: 16), trend])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: photo),
                const SizedBox(width: 16),
                Expanded(child: trend),
              ]);
      }),
      const SizedBox(height: 16),
      _CollectorPanel(collectors: dash.collectors),
      if (dash.attention.isNotEmpty) ...[
        const SizedBox(height: 16),
        _AttentionPanel(items: dash.attention),
      ],
    ]);
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.dash});

  final Dashboard dash;

  @override
  Widget build(BuildContext context) {
    final t = dash.totals;
    final segments = <(String, int, Color)>[
      ('Approved', t.completed, Brand.ok),
      ('Awaiting review', t.awaitingReview, Brand.warn),
      ('In progress', t.inProgress, Brand.info),
      ('Rejected', t.rejected, Brand.bad),
      ('Not started', t.pending, Brand.txt3),
    ].where((s) => s.$2 > 0).toList();

    return Panel(
      title: 'Collection progress',
      trailing: Text('${t.progressPct}% captured',
          style: TextStyle(color: Brand.pink, fontWeight: FontWeight.w800, fontSize: 13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final s in segments)
                  Expanded(flex: s.$2, child: Container(color: s.$3)),
                if (segments.isEmpty) Expanded(child: Container(color: Brand.surface3)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 16, runSpacing: 8, children: [
          for (final s in segments)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: s.$3, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 7),
              Text('${s.$1}  ', style: TextStyle(fontSize: 12, color: Brand.txt2)),
              Text('${s.$2}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: s.$3)),
            ]),
        ]),
        const SizedBox(height: 16),
        Divider(height: 1),
        const SizedBox(height: 14),
        Wrap(spacing: 24, runSpacing: 10, children: [
          _MiniStat('Average record completeness', '${t.avgCompleteness}%'),
          _MiniStat('Plan per day', '${dash.customer.planPerDay} vehicles'),
          _MiniStat('Target date', dash.customer.targetDate ?? '-'),
          _MiniStat('Project status', dash.customer.status),
        ]),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

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
          Text(value, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        ],
      );
}

class _PhotoGapPanel extends StatelessWidget {
  const _PhotoGapPanel({required this.gaps});

  final List<PhotoGap> gaps;

  @override
  Widget build(BuildContext context) {
    final maxV = gaps.fold<int>(1, (m, g) => g.captured + g.missing > m ? g.captured + g.missing : m);
    return Panel(
      title: 'Photo coverage by type',
      child: Column(children: [
        for (final g in gaps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(g.label, style: TextStyle(fontSize: 12.3))),
                Text('${g.captured}', style: TextStyle(fontSize: 12.3, fontWeight: FontWeight.w800)),
                if (g.missing > 0)
                  Text('  /  ${g.missing} missing',
                      style: TextStyle(fontSize: 11.5, color: Brand.bad, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              ProgressBar(
                value: g.captured / maxV,
                color: g.missing == 0 ? Brand.ok : Brand.pink,
                height: 6,
              ),
            ]),
          ),
        const SizedBox(height: 2),
        Text(
          'Every photo is stored against its part number, vendor and type, so it cannot be filed against the wrong part.',
          style: TextStyle(color: Brand.txt3, fontSize: 11, height: 1.5),
        ),
      ]),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final hasData = points.any((p) => p.submitted > 0 || p.approved > 0);
    return Panel(
      title: 'Last 14 days',
      child: SizedBox(
        height: 178,
        child: !hasData
            ? const EmptyState(message: 'No submissions recorded in the last two weeks.', icon: Icons.timeline)
            : BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(color: Brand.line, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: 2),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i < 0 || i >= points.length || i % 3 != 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(points[i].date.substring(5),
                                style: TextStyle(color: Brand.txt3, fontSize: 9)),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(x: i, barsSpace: 2, barRods: [
                        BarChartRodData(
                            toY: points[i].submitted.toDouble(), color: Brand.pink, width: 5, borderRadius: BorderRadius.circular(2)),
                        BarChartRodData(
                            toY: points[i].approved.toDouble(), color: Brand.ok, width: 5, borderRadius: BorderRadius.circular(2)),
                      ]),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CollectorPanel extends StatelessWidget {
  const _CollectorPanel({required this.collectors});

  final List<CollectorProgress> collectors;

  @override
  Widget build(BuildContext context) => Panel(
        title: 'Field team progress',
        padding: EdgeInsets.zero,
        child: collectors.isEmpty
            ? const EmptyState(message: 'No records are assigned to a collector yet.', icon: Icons.people_outline)
            : Column(children: [
                for (final c in collectors)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(gradient: Brand.ribbonSoft, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: Text(
                          c.name.split(' ').take(2).map((p) => p.isEmpty ? '' : p[0]).join(),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 3,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          Text('${c.empCode ?? ''}  ${c.device ?? ''}  -  last activity ${fmtAgo(c.lastActivity)}',
                              style: TextStyle(color: Brand.txt3, fontSize: 10.8)),
                        ]),
                      ),
                      Expanded(
                        flex: 2,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          LayoutBuilder(builder: (context, box) {
                            // This column is narrow on a phone. "4 photo gaps"
                            // used to be clipped at the card edge; ellipsising
                            // it to "4 pho…" only traded a clip for a word the
                            // manager cannot read, so the label itself shortens.
                            final gaps = box.maxWidth < 150
                                ? '${c.missingPhotos} gaps'
                                : '${c.missingPhotos} photo gaps';
                            return Row(children: [
                              Text('${c.done}/${c.assigned}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              const Spacer(),
                              if (c.missingPhotos > 0)
                                Flexible(
                                  child: Text(gaps,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 10.5, color: Brand.bad, fontWeight: FontWeight.w700)),
                                ),
                            ]);
                          }),
                          const SizedBox(height: 6),
                          ProgressBar(
                            value: c.assigned == 0 ? 0 : c.done / c.assigned,
                            color: c.done == c.assigned ? Brand.ok : Brand.pink,
                            height: 5,
                          ),
                        ]),
                      ),
                    ]),
                  ),
              ]),
      );
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.items});

  final List<AttentionItem> items;

  @override
  Widget build(BuildContext context) => Panel(
        title: 'Needs attention',
        trailing: Pill('${items.length}', color: Brand.warn),
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (final a in items)
            InkWell(
              onTap: () => context.go('/records/${a.recordId}'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                child: Row(children: [
                  Icon(a.severity == 'bad' ? Icons.error_outline : Icons.warning_amber_rounded,
                      size: 16, color: a.severity == 'bad' ? Brand.bad : Brand.warn),
                  const SizedBox(width: 11),
                  SizedBox(width: 110, child: Text(a.partNo, style: mono(size: 12))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(a.vendorName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(a.issue,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Brand.txt3, fontSize: 11, height: 1.4)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: Brand.txt3),
                ]),
              ),
            ),
        ]),
      );
}
