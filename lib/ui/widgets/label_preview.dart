import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// One rendered line of a label: an optional small caption, the resolved value,
/// and which step of the type scale it uses.
class LabelFaceLine {
  const LabelFaceLine({this.label, required this.value, this.size = 'sm'});

  final String? label;
  final String value;
  final String size;
}

/// The white label face, drawn to the template's real aspect ratio.
///
/// Shared by the Label Studio grid and the template editor, so the preview an
/// admin edits against and the one they print from cannot drift apart.
///
/// Type is sized in **millimetres** against the label's own width rather than in
/// pixels against the card, so a 70x40 bin label and a 100x50 rack label both
/// show text at its true relative size - which is the point of a preview whose
/// whole job is to answer "will this fit on the stock we buy?".
class LabelFace extends StatelessWidget {
  const LabelFace({
    super.key,
    required this.lines,
    required this.widthMm,
    required this.heightMm,
    this.hasQr = true,
    this.hasBarcode = true,
  });

  final List<LabelFaceLine> lines;
  final double widthMm;
  final double heightMm;
  final bool hasQr;
  final bool hasBarcode;

  /// Cap height in mm for each step of the scale.
  static const _mm = {'xl': 6.0, 'lg': 4.7, 'md': 3.4, 'sm': 2.65};

  @override
  Widget build(BuildContext context) {
    final w = widthMm <= 0 ? 100.0 : widthMm;
    final h = heightMm <= 0 ? 50.0 : heightMm;

    return AspectRatio(
      aspectRatio: w / h,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Brand.line2),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, box) {
          final pxMm = box.maxWidth / w;
          double pt(String s) => (_mm[s] ?? _mm['sm']!) * pxMm;
          final pad = 2.4 * pxMm;
          final qrSide = (box.maxHeight * 0.30).clamp(14.0, 64.0);

          return Stack(children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 1.2 * pxMm, decoration: BoxDecoration(gradient: Brand.ribbon)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad + 1.2 * pxMm, pad * 0.8, pad * 0.8, pad * 0.6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final line in lines)
                          Padding(
                            padding: EdgeInsets.only(bottom: 0.4 * pxMm),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (line.label != null && line.label!.isNotEmpty)
                                Text(
                                  line.label!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 1.7 * pxMm,
                                    color: Colors.black45,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              Text(
                                line.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: pt(line.size),
                                  height: 1.1,
                                  fontWeight:
                                      line.size == 'xl' || line.size == 'lg' ? FontWeight.w800 : FontWeight.w600,
                                  color: line.size == 'xl' || line.size == 'lg'
                                      ? const Color(0xFF5A1080)
                                      : Colors.black87,
                                ),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                    if (hasQr) _FaceQr(side: qrSide, gap: pad * 0.6),
                  ]),
                ),
                if (hasBarcode) SizedBox(height: box.maxHeight * 0.17, child: const _FaceBarcode()),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}

class _FaceQr extends StatelessWidget {
  const _FaceQr({required this.side, required this.gap});

  final double side;
  final double gap;

  @override
  Widget build(BuildContext context) => Container(
        width: side,
        height: side,
        margin: EdgeInsets.only(left: gap),
        decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
        child: CustomPaint(painter: _QrPainter()),
      );
}

/// A stand-in pattern, not a real QR - the printed label carries a real one
/// rendered server-side. This only has to read as "a QR goes here".
class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black87;
    const n = 7;
    final cell = size.width / n;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final corner = (x < 2 && y < 2) || (x > n - 3 && y < 2) || (x < 2 && y > n - 3);
        if (corner || (x * 3 + y * 5) % 4 < 2) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell * 0.88, cell * 0.88), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FaceBarcode extends StatelessWidget {
  const _FaceBarcode();

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: double.infinity, child: CustomPaint(painter: _BarPainter()));
}

class _BarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black87;
    var x = 0.0;
    var i = 0;
    while (x < size.width) {
      final w = (i % 3 == 0) ? 2.0 : 1.0;
      if (i % 2 == 0) canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w + 1.2;
      i += 1;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
