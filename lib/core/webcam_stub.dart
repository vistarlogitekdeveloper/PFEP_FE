import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// The live webcam is a web-only capability; everywhere else this is false and
/// callers use the native camera instead.
const bool kWebcamSupported = false;

/// Never called on non-web (guarded by [kWebcamSupported]); present so the
/// facade has one shape on every platform.
Future<Uint8List?> captureFromWebcam(BuildContext context, {String? title}) async => null;
