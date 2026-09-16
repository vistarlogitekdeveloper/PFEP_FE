import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// BRD 5 - audit trail. Who entered or edited each field, when, from which
/// device, and what the value was before and after. This is what makes the
/// handed-over PFEP defensible when the customer audits it.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String? _query;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  static final _actionColor = {
    'Approved': Brand.ok,
    'Rejected': Brand.bad,
    'Data Submitted': Brand.warn,
    'Data Entered': Brand.info,
    'Photo Captured': Brand.pink,
    'Photo Recaptured': Brand.pink,
    'Photo Deleted': Brand.bad,
    'Part Master Upload': Brand.violet,
    'Field Config Changed': Brand.violet,
    'Excel Export': Brand.orange,
    'Labels Generated': Brand.orange,
    'Offline Sync': Brand.info,
  };

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(auditProvider(_query));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Output ·',
          accent: 'Audit Trail',
          title: 'Audit trail',
          blurb: 'Every state change on this customer PFEP: the actor, the action, the reference, and the '
              'before and after value. Nothing in the collected data can change without leaving a line here.',
          actions: [
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search part, detail or person',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                style: TextStyle(fontSize: 13),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 320),
                      () => setState(() => _query = v.trim().isEmpty ? null : v.trim()));
                },
              ),
            ),
          ],
        ),
        entries.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(auditProvider(_query))),
          data: (list) => list.isEmpty
              ? const EmptyState(message: 'No audit entries match this search.', icon: Icons.history)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Pill('${list.length} entries', color: Brand.violet),
                  const SizedBox(height: 14),
                  for (final e in list) _AuditRow(entry: e, color: _actionColor[e.action] ?? Brand.txt3),
                ]),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry, required this.color});

  final AuditEntry entry;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Brand.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 9),
            Text(entry.action, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 10),
            if (entry.ref != null)
              Flexible(
                child: Text(entry.ref!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(size: 11.5, color: Brand.txt2)),
              ),
            const Spacer(),
            Text(fmtDateTime(entry.ts), style: TextStyle(color: Brand.txt3, fontSize: 10.8)),
          ]),
          const SizedBox(height: 7),
          if (entry.detail != null)
            Text(entry.detail!, style: TextStyle(color: Brand.txt2, fontSize: 11.8, height: 1.5)),
          const SizedBox(height: 7),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (entry.actorName != null)
              Pill('${entry.actorName}${entry.actorRole == null ? '' : ' (${entry.actorRole})'}',
                  color: Brand.txt3, icon: Icons.person_outline),
            if (entry.actorDevice != null) Pill(entry.actorDevice!, color: Brand.txt3, icon: Icons.smartphone),
            if (entry.before != null && entry.after != null)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(entry.before!, style: mono(size: 10.5, color: Brand.txt3, weight: FontWeight.w400)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 11, color: Brand.txt3),
                ),
                Text(entry.after!, style: mono(size: 10.5, color: color, weight: FontWeight.w600)),
              ]),
          ]),
        ]),
      );
}
