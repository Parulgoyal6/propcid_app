// services/aadhaar_sides_composer.dart
//
// Registration collects BOTH sides of the Aadhaar card. The profile stores one
// Aadhaar document (`aadhaar_card_url`), so the two photos are joined into a
// single tall image - front on top, back below - and that one file is
// uploaded exactly like any other Aadhaar document.
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart' show XFile;

/// Width every side is scaled to; keeps the combined file a sensible size.
const double _kSideWidth = 1400;

/// Gap between the two sides.
const double _kGap = 28;

Future<ui.Image> _decode(XFile file) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// Joins [front] and [back] into one PNG ([XFile]), front above back.
Future<XFile> composeAadhaarSides(XFile front, XFile back) async {
  final f = await _decode(front);
  final b = await _decode(back);
  try {
    final fh = f.height * (_kSideWidth / f.width);
    final bh = b.height * (_kSideWidth / b.width);
    final totalHeight = fh + _kGap + bh;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, _kSideWidth, totalHeight),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    canvas.drawImageRect(
      f,
      ui.Rect.fromLTWH(0, 0, f.width.toDouble(), f.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _kSideWidth, fh),
      paint,
    );
    canvas.drawImageRect(
      b,
      ui.Rect.fromLTWH(0, 0, b.width.toDouble(), b.height.toDouble()),
      ui.Rect.fromLTWH(0, fh + _kGap, _kSideWidth, bh),
      paint,
    );

    final picture = recorder.endRecording();
    final out = await picture.toImage(_kSideWidth.toInt(), totalHeight.ceil());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    picture.dispose();
    return XFile.fromData(
      data!.buffer.asUint8List(),
      name: 'aadhaar_front_back.png',
      mimeType: 'image/png',
    );
  } finally {
    f.dispose();
    b.dispose();
  }
}
