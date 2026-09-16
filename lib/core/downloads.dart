import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// Saving the generated Excel / CSV / ZPL, and handing a label PDF straight to
/// the OS print dialog (BRD 4.7 and 4.8 - print-ready output, no manual step).
class Downloads {
  static Future<String> save(Uint8List bytes, String filename) async {
    final dot = filename.lastIndexOf('.');
    final name = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot + 1) : 'bin';

    return FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: ext,
      mimeType: _mime(ext),
    );
  }

  /// Opens the platform print preview so a label sheet can go straight to a
  /// printer, or be saved as PDF.
  static Future<void> printPdf(Uint8List bytes, {String name = 'PFEP labels'}) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  static MimeType _mime(String ext) => switch (ext.toLowerCase()) {
        'xlsx' => MimeType.microsoftExcel,
        'csv' => MimeType.csv,
        'pdf' => MimeType.pdf,
        'png' => MimeType.png,
        'jpg' || 'jpeg' => MimeType.jpeg,
        _ => MimeType.text,
      };
}
