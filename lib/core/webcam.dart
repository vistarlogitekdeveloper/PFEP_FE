// Live webcam capture, web only.
//
// The real implementation (webcam_web.dart) uses getUserMedia and a
// platform-view <video>, which only exist in a browser. The stub is compiled
// into the mobile/desktop builds instead, so nothing there references a DOM
// API. Callers guard with [kWebcamSupported] (false off the web) and fall back
// to the native camera or a file upload.
export 'webcam_stub.dart' if (dart.library.html) 'webcam_web.dart';
