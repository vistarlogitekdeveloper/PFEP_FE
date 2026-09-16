import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import 'common.dart';

/// BRD 4.5 - the photo capture module.
///
/// The camera is opened from *inside* the app, after the part number and vendor
/// are already on screen, and the bytes are posted to the record. The server
/// names the file from part + vendor + type, so the photo is tagged at the
/// moment of capture and there is no crop-and-paste step afterwards.
///
/// **`ImageSource.camera` only, deliberately.** The BRD is explicit that every
/// photo is taken inside the app and not picked from the phone's general camera
/// roll: a picture chosen from the roll was taken at some other time, possibly
/// at some other part, and re-introduces exactly the matching problem this
/// module exists to remove. There is no gallery path here on purpose - please
/// do not add one back as a convenience.
///
/// `maxWidth` / `imageQuality` downscale on the device, so a phone photo leaves
/// as a few hundred KB instead of several MB - which is what makes this usable
/// on a vendor site with a weak signal.
Future<Uint8List?> captureImage(BuildContext context) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 78,
    preferredCameraDevice: CameraDevice.rear,
  );
  if (file == null) return null;
  return file.readAsBytes();
}

class PhotoTile extends ConsumerStatefulWidget {
  const PhotoTile({
    super.key,
    required this.record,
    required this.photoType,
    required this.label,
    required this.onChanged,
    this.compact = false,
  });

  final PfepRecord record;
  final String photoType;
  final String label;
  final Future<void> Function() onChanged;
  final bool compact;

  @override
  ConsumerState<PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends ConsumerState<PhotoTile> {
  bool _busy = false;

  RecordPhoto? get _photo => widget.record.photos[widget.photoType];

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      final bytes = await captureImage(context);
      if (bytes == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final repo = ref.read(repositoryProvider);
      final saved = await repo.uploadPhoto(
        recordId: widget.record.id,
        photoType: widget.photoType,
        bytes: bytes,
        filename: '${widget.photoType}.jpg',
        label: '${widget.record.partNo} - ${widget.label}',
      );
      if (!mounted) return;
      if (saved == null) {
        showToast(context, 'Saved on this device',
            detail: '${widget.label} is queued and uploads when the connection returns.');
      } else {
        showToast(context, '${widget.label} captured',
            detail: 'Tagged automatically to ${widget.record.partNo} - ${widget.record.vendorName}.');
      }
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Photo not saved', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deletePhoto(widget.record.id, widget.photoType);
      await widget.onChanged();
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not remove the photo', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final api = ref.watch(apiClientProvider);
    final height = widget.compact ? 104.0 : 128.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        // With the gallery gone there is only one way to fill an empty tile, so
        // tapping it opens the camera rather than a menu of one. The sheet is
        // still worth showing once a photo exists - retake and remove are two
        // different intentions, and removing is destructive.
        onTap: _busy || !widget.record.isEditable
            ? null
            : () => _photo == null ? _capture() : _showSheet(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Brand.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: photo != null ? Brand.ok.withValues(alpha: 0.5) : Brand.bad.withValues(alpha: 0.42),
              width: 1.2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(fit: StackFit.expand, children: [
            if (photo != null)
              Image.network(
                api.fileUrl(photo.url),
                fit: BoxFit.cover,
                headers: api.authHeaders,
                errorBuilder: (_, _, _) => Center(
                    child: Icon(Icons.broken_image_outlined, size: 20, color: Brand.txt3)),
              )
            else
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.photo_camera_outlined, size: widget.compact ? 20 : 24, color: Brand.bad),
                  const SizedBox(height: 6),
                  Text('Tap to capture',
                      style: TextStyle(color: Brand.txt3, fontSize: 10.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            if (photo != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  color: Brand.bg.withValues(alpha: 0.82),
                  child: Row(children: [
                    Icon(Icons.verified, size: 11, color: Brand.ok),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(photo.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono(size: 8.5, color: Brand.ok)),
                    ),
                  ]),
                ),
              ),
            if (_busy)
              Container(
                color: Brand.bg.withValues(alpha: 0.6),
                child: Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: Text(widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.3,
                fontWeight: FontWeight.w700,
                color: photo != null ? Brand.txt2 : Brand.bad,
              )),
        ),
        if (photo != null)
          Text(photo.sizeLabel, style: TextStyle(fontSize: 9.5, color: Brand.txt3)),
      ]),
    ]);
  }

  void _showSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Brand.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
              width: 38, height: 4,
              decoration: BoxDecoration(color: Brand.line2, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${widget.record.partNo}  -  ${widget.record.vendorName}',
                  style: TextStyle(color: Brand.txt3, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: Brand.pink),
            title: Text('Retake photo'),
            subtitle: Text('Opens the camera and tags the image to this part and vendor'),
            onTap: () {
              Navigator.of(ctx).pop();
              _capture();
            },
          ),
          if (_photo != null)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Brand.bad),
              title: Text('Remove photo'),
              subtitle: Text('It must be recaptured before the record can be submitted'),
              onTap: () {
                Navigator.of(ctx).pop();
                _delete();
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

/// Read-only grid used on the review and record detail screens.
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({super.key, required this.record, required this.photoTypes, this.onTapPhoto});

  final PfepRecord record;
  final List<PhotoType> photoTypes;
  final void Function(String type)? onTapPhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 900 ? 5 : (width > 560 ? 3 : 2);

    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.92,
      children: [
        for (final t in photoTypes)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: InkWell(
                onTap: onTapPhoto == null ? null : () => onTapPhoto!(t.key),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Brand.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: record.photos[t.key] != null
                          ? Brand.line
                          : Brand.bad.withValues(alpha: 0.42),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: record.photos[t.key] == null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.no_photography_outlined, size: 18, color: Brand.bad),
                            SizedBox(height: 5),
                            Text('MISSING',
                                style: TextStyle(
                                    color: Brand.bad, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                          ]),
                        )
                      : Image.network(
                          api.fileUrl(record.photos[t.key]!.url),
                          fit: BoxFit.cover,
                          headers: api.authHeaders,
                          errorBuilder: (_, _, _) => Center(
                              child: Icon(Icons.broken_image_outlined, size: 18, color: Brand.txt3)),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(t.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w700,
                    color: record.photos[t.key] != null ? Brand.txt2 : Brand.bad)),
          ]),
      ],
    );
  }
}
