import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/webcam.dart';
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
/// **Camera-only on a phone, deliberately.** The BRD is explicit that a field
/// photo is taken inside the app and not picked from the phone's general camera
/// roll: a picture chosen from the roll was taken at some other time, possibly
/// at some other part, and re-introduces exactly the matching problem this
/// module exists to remove. So on mobile the only source offered is the camera.
///
/// **On the web build the tile also offers "Upload a photo".** A laptop has no
/// field camera roll to mismatch against, and `ImageSource.camera` on desktop
/// web cannot open a live camera - it silently degrades to a file dialog - so a
/// desktop collector was left with a camera button that did not behave like one
/// and no honest way to attach an image. A file source is the reliable path
/// there. The anti-mismatch guarantee does not depend on the source anyway: the
/// server still names the file `<PART>_<VENDOR>_<TYPE>` from the record it was
/// posted to, so a wrong-part photo is structurally impossible regardless.
///
/// `maxWidth` / `imageQuality` downscale on the device (and in the browser via
/// canvas), so an image leaves as a few hundred KB instead of several MB - which
/// is what makes this usable on a vendor site with a weak signal.
Future<Uint8List?> captureImage(
  BuildContext context, {
  ImageSource source = ImageSource.camera,
}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
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

  /// Native camera (mobile) or a file dialog (web upload), via image_picker.
  Future<void> _capture({ImageSource source = ImageSource.camera}) async {
    setState(() => _busy = true);
    try {
      await _upload(await captureImage(context, source: source));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Live webcam capture, web only (BRD 4.5). Same upload path as everything
  /// else - the source of the bytes never changes how they are stored.
  Future<void> _captureWebcam() async {
    setState(() => _busy = true);
    try {
      await _upload(await captureFromWebcam(context, title: widget.label));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(Uint8List? bytes) async {
    if (bytes == null) return; // cancelled, or the camera gave nothing back
    try {
      final saved = await ref.read(repositoryProvider).uploadPhoto(
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
    }
  }

  /// The camera action for this build: the live webcam on web, the native
  /// camera on a phone.
  void _takePhoto() => (kIsWeb && kWebcamSupported) ? _captureWebcam() : _capture();

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
        // On a phone an empty tile has one action - the camera - so tapping it
        // goes straight there rather than showing a menu of one. On the web
        // build there are two honest choices (camera or upload), so the sheet
        // is shown. A tile that already has a photo always shows the sheet:
        // retake, upload and remove are distinct intentions, and remove is
        // destructive.
        onTap: _busy || !widget.record.isEditable
            ? null
            : () => (_photo == null && !kIsWeb) ? _capture() : _showSheet(),
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
            title: Text(_photo == null ? 'Take photo' : 'Retake photo'),
            subtitle: Text((kIsWeb && kWebcamSupported)
                ? 'Opens your webcam to take the photo now, tagged to this part and vendor'
                : 'Opens the camera and tags the image to this part and vendor'),
            onTap: () {
              Navigator.of(ctx).pop();
              _takePhoto();
            },
          ),
          // Web only: a laptop has no field camera roll to mismatch against, and
          // it is the reliable way to attach an image on a machine whose browser
          // cannot open a live camera. Not offered on mobile, where camera-only
          // is the point (see captureImage).
          if (kIsWeb)
            ListTile(
              leading: Icon(Icons.upload_file_outlined, color: Brand.violet),
              title: Text('Upload a photo'),
              subtitle: Text('Choose an image file from this computer'),
              onTap: () {
                Navigator.of(ctx).pop();
                _capture(source: ImageSource.gallery);
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
