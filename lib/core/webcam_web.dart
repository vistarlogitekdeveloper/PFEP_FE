import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'theme.dart';

/// Live in-browser webcam capture (BRD 4.5, web build).
///
/// On a laptop `image_picker`'s camera source degrades to a file dialog, so a
/// desktop collector had no way to actually take a photo at the machine. This
/// opens the real camera with `getUserMedia`, shows a live preview in a
/// platform-view `<video>`, and returns a JPEG of the frame the user captures -
/// already downscaled here, so it matches what the phone path produces.
///
/// Fails safe: no camera, denied permission, or an insecure origin all resolve
/// to a clear message and a null result, and the caller still offers "Upload a
/// photo" as the fallback.
const bool kWebcamSupported = true;

/// The longest edge of the captured image, matching the phone path's 1600px.
const int _maxEdge = 1600;

Future<Uint8List?> captureFromWebcam(BuildContext context, {String? title}) {
  return showDialog<Uint8List?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WebcamDialog(title: title ?? 'Take photo'),
  );
}

class _WebcamDialog extends StatefulWidget {
  const _WebcamDialog({required this.title});
  final String title;

  @override
  State<_WebcamDialog> createState() => _WebcamDialogState();
}

class _WebcamDialogState extends State<_WebcamDialog> {
  // A fresh view type per dialog, so a stale factory from a previous open can
  // never be reused.
  final String _viewType = 'pfep-webcam-${DateTime.now().microsecondsSinceEpoch}';

  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  bool _ready = false;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final constraints = web.MediaStreamConstraints(
        video: web.MediaTrackConstraints(facingMode: 'environment'.toJS),
        audio: false.toJS,
      );
      // On an insecure origin (plain http, not localhost) mediaDevices is
      // undefined and this throws; the catch below turns it into a clear
      // "camera unavailable, upload instead" message.
      final stream = await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;

      final video = web.document.createElement('video') as web.HTMLVideoElement
        ..autoplay = true
        ..muted = true
        ..srcObject = stream;
      video.setAttribute('playsinline', 'true');
      video.style.width = '100%';
      video.style.height = '100%';
      video.style.objectFit = 'cover';

      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => video);
      await video.play().toDart;

      if (!mounted) {
        _stopStream(stream);
        return;
      }
      setState(() {
        _stream = stream;
        _video = video;
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('NotAllowedError') || s.contains('Permission')) {
      return 'Camera permission was blocked. Allow it in the browser, or use "Upload a photo" instead.';
    }
    if (s.contains('NotFoundError') || s.contains('DevicesNotFound')) {
      return 'No camera was found on this computer. Use "Upload a photo" instead.';
    }
    if (s.contains('NotReadableError')) {
      return 'The camera is in use by another app. Close it and try again, or upload a photo.';
    }
    return 'The camera could not be started. Use "Upload a photo" instead.';
  }

  void _stopStream(web.MediaStream? stream) {
    final s = stream ?? _stream;
    if (s == null) return;
    final tracks = s.getTracks().toDart;
    for (final t in tracks) {
      t.stop();
    }
    _video?.srcObject = null;
  }

  Future<void> _capture() async {
    final video = _video;
    if (video == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final vw = video.videoWidth;
      final vh = video.videoHeight;
      if (vw == 0 || vh == 0) {
        setState(() => _capturing = false);
        return;
      }
      final scale = (vw > vh ? _maxEdge / vw : _maxEdge / vh).clamp(0.0, 1.0);
      final w = (vw * scale).round();
      final h = (vh * scale).round();

      final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      // The scaling overload of the canvas drawImage; the package:web binding
      // names it drawImageScaled and flags it, but it is the correct call.
      // ignore: deprecated_member_use
      ctx.drawImageScaled(video, 0, 0, w.toDouble(), h.toDouble());

      final dataUrl = canvas.toDataURL('image/jpeg', 0.78.toJS);
      final comma = dataUrl.indexOf(',');
      final bytes = base64Decode(comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl);

      _stopStream(null);
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Could not capture the frame. Try again, or upload a photo.';
        });
      }
    }
  }

  void _cancel() {
    _stopStream(null);
    Navigator.of(context).pop(null);
  }

  @override
  void dispose() {
    _stopStream(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Brand.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.photo_camera_outlined, color: Brand.pink, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              IconButton(onPressed: _cancel, icon: Icon(Icons.close, color: Brand.txt3)),
            ]),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.videocam_off_outlined, color: Brand.txt3, size: 34),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center,
                                style: TextStyle(color: Brand.txt2, fontSize: 13, height: 1.4)),
                          ]),
                        )
                      : _ready
                          ? HtmlElementView(viewType: _viewType)
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              const SizedBox(
                                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(height: 12),
                              Text('Starting camera...',
                                  style: TextStyle(color: Brand.txt3, fontSize: 12.5)),
                            ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              FilledButton(onPressed: _cancel, child: const Text('Close'))
            else
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _capturing ? null : _cancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _ready && !_capturing ? _capture : null,
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: Text(_capturing ? 'Capturing...' : 'Capture'),
                  ),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}
