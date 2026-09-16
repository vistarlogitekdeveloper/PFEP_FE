import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/offline_queue.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';

/// BRD 5 - offline mode made visible.
///
/// Field staff need to *see* that nothing has been lost while they were out of
/// signal, and be able to push it themselves the moment a bar appears.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _busy = false;

  Future<void> _flush() async {
    setState(() => _busy = true);
    try {
      final online = await ref.read(connectivityProvider.notifier).check();
      if (!online) {
        if (mounted) {
          showToast(context, 'Still offline',
              detail: 'The queue stays on this device and uploads automatically later.', error: true);
        }
        return;
      }
      final res = await ref.read(repositoryProvider).flushQueue();
      ref.invalidate(myWorkProvider);
      ref.invalidate(recordsProvider);
      if (!mounted) return;
      showToast(
        context,
        res.applied == 0 && res.held == 0 ? 'Nothing left to sync' : '${res.applied} item(s) uploaded',
        detail: [
          if (res.duplicates > 0) '${res.duplicates} already on the server',
          if (res.held > 0) '${res.held} held back - still incomplete',
          if (res.failed > 0) '${res.failed} failed',
        ].join('  -  '),
      );
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Sync failed', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(connectivityProvider);
    ref.watch(queueCountProvider);
    final queue = OfflineQueue.instance;
    final ops = queue.ops;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'My work ·',
          accent: 'Offline',
          title: 'Offline sync queue',
          blurb: 'Vendor yards and line-side areas often have no signal. Everything captured while offline is '
              'saved on this device and uploaded automatically when a connection returns - nothing is lost, '
              'and uploading twice cannot duplicate a record.',
          actions: [
            RibbonButton(
              label: online ? 'Sync now' : 'Check connection',
              icon: Icons.sync,
              busy: _busy,
              onPressed: _flush,
            ),
          ],
        ),
        Row(children: [
          Expanded(
            child: StatTile(
              label: 'Connection',
              value: online ? 'Online' : 'Offline',
              sub: ref.watch(apiClientProvider).baseUrl,
              accent: online ? Brand.ok : Brand.warn,
              icon: online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatTile(
              label: 'Waiting to upload',
              value: '${ops.length}',
              sub: ops.isEmpty ? 'everything is synced' : '${(queue.pendingBytes / 1024).round()} KB queued',
              accent: ops.isEmpty ? Brand.ok : Brand.info,
              icon: Icons.cloud_upload_outlined,
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Panel(
          title: 'Queue',
          trailing: ops.isEmpty
              ? Pill('Empty', color: Brand.ok)
              : Pill('${ops.length} item(s)', color: Brand.info),
          padding: EdgeInsets.zero,
          child: ops.isEmpty
              ? const EmptyState(
                  message: 'Nothing is waiting. Every field entry and photograph has reached the server.',
                  icon: Icons.cloud_done_outlined,
                )
              : Column(children: [
                  for (final op in ops)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                      child: Row(children: [
                        Icon(_iconFor(op), size: 16, color: _colorFor(op)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(op.label.isEmpty ? op.type : op.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            Text(
                              '${_typeLabel(op.type)}  -  queued ${fmtAgo(op.queuedAt)}'
                              '${op.sizeBytes > 0 ? '  -  ${(op.sizeBytes / 1024).round()} KB' : ''}',
                              style: TextStyle(color: Brand.txt3, fontSize: 10.8),
                            ),
                          ]),
                        ),
                        Pill('Queued', color: Brand.warn),
                      ]),
                    ),
                ]),
        ),
        const SizedBox(height: 16),
        Panel(
          title: 'How this works',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            _Bullet('Each queued item carries its own id, so re-sending the queue after a dropped connection '
                'cannot create a duplicate record on the server.'),
            _Bullet('Field edits merge field by field, so two collectors working the same customer never '
                'overwrite each other.'),
            _Bullet('A submission that is still missing a photo is held back rather than rejected - the work '
                'stays safe on the server and you finish it on your next visit.'),
            _Bullet('Photos are downscaled on this phone before they are queued, so a full day of capture '
                'uploads over a weak connection.'),
          ]),
        ),
      ],
    );
  }

  IconData _iconFor(QueuedOp op) => switch (op.type) {
        'photo' => Icons.photo_camera_outlined,
        'submit' => Icons.send_outlined,
        _ => Icons.edit_outlined,
      };

  Color _colorFor(QueuedOp op) => switch (op.type) {
        'photo' => Brand.pink,
        'submit' => Brand.ok,
        _ => Brand.info,
      };

  String _typeLabel(String type) => switch (type) {
        'photo' => 'Photograph',
        'submit' => 'Submission',
        _ => 'Field data',
      };
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(color: Brand.pink, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(text, style: TextStyle(color: Brand.txt2, fontSize: 12, height: 1.55)),
          ),
        ]),
      );
}
