import 'dart:io';
import 'dart:ui' as ui;

/// Prepares a captured photo for ML Kit.
///
/// Modern flagship cameras produce JPEG variants (Ultra HDR gain maps, very
/// high resolutions, vendor-specific encoders) that ML Kit's native decoder
/// may not handle safely. Decoding with Flutter's own codec and re-encoding to
/// PNG yields a standard, bounded image. The same decode is reused to crop the
/// two cards apart for the combiner so each card can be recognised on its own —
/// far more accurate than reading both cards in a single pass.
class ImageSanitizer {
  /// Longest output edge for the full-frame sanitised image. 1600px keeps
  /// small print legible for OCR while bounding decode memory.
  static const int maxLongEdge = 1600;

  /// Longest edge used when splitting the frame into two cards. A little higher
  /// than [maxLongEdge] so each half retains enough detail for a single glyph.
  static const int splitMaxLongEdge = 2200;

  /// Returns the path of the sanitised full-frame PNG, or null when decoding
  /// fails — the caller should then fall back to the original file.
  static Future<String?> sanitise(String sourcePath) async {
    ui.Image? image;
    try {
      image = await _decodeBounded(sourcePath, maxLongEdge);
      if (image == null) return null;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return _writeTemp(data.buffer.asUint8List(), 'ocr_capture');
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  /// Splits the photo into a left-card crop and a right-card crop, each padded
  /// with a white margin and re-encoded as a PNG for separate OCR.
  ///
  /// Returns null when decoding or rendering fails, so the caller can fall back
  /// to whole-frame recognition.
  static Future<({String left, String right})?> sanitiseHalves(
    String sourcePath,
  ) async {
    ui.Image? full;
    try {
      full = await _decodeBounded(sourcePath, splitMaxLongEdge);
      if (full == null) return null;

      final w = full.width.toDouble();
      final h = full.height.toDouble();
      // Full-width halves with a small central dead-zone (cards are placed in
      // the left/right guide boxes, which leave a gap in the middle) and a
      // little vertical trim to drop edge background.
      final top = h * 0.06;
      final cropHeight = h * 0.88;
      final halfWidth = w * 0.48;
      final leftRect = ui.Rect.fromLTWH(0, top, halfWidth, cropHeight);
      final rightRect =
          ui.Rect.fromLTWH(w * 0.52, top, halfWidth, cropHeight);

      final leftPath = await _renderCrop(full, leftRect, 'ocr_left');
      final rightPath = await _renderCrop(full, rightRect, 'ocr_right');
      if (leftPath == null || rightPath == null) return null;
      return (left: leftPath, right: rightPath);
    } catch (_) {
      return null;
    } finally {
      full?.dispose();
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Decodes [sourcePath], downscaling during decode so the longest edge is at
  /// most [maxEdge]. Returns null on failure.
  static Future<ui.Image?> _decodeBounded(
    String sourcePath,
    int maxEdge,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    final longEdge = width > height ? width : height;

    final ui.Codec codec;
    if (longEdge > maxEdge) {
      final scale = maxEdge / longEdge;
      codec = await descriptor.instantiateCodec(
        targetWidth: (width * scale).round(),
        targetHeight: (height * scale).round(),
      );
    } else {
      codec = await descriptor.instantiateCodec();
    }
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Draws [srcRect] of [src] onto a white, padded canvas and writes it as a
  /// PNG. The white margin gives ML Kit clean space around the glyph, which
  /// markedly improves single-character recognition.
  static Future<String?> _renderCrop(
    ui.Image src,
    ui.Rect srcRect,
    String prefix,
  ) async {
    ui.Image? out;
    try {
      final pad = srcRect.width * 0.08;
      final dstWidth = srcRect.width + pad * 2;
      final dstHeight = srcRect.height + pad * 2;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, dstWidth, dstHeight),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      // A mild contrast boost (factor 1.4, centred at mid-grey 128) sharpens
      // the boundary between ink strokes and the card background, which
      // markedly improves ML Kit's ability to read simplified component forms
      // whose strokes are few and thin (e.g. 氵, 亻, 讠, 忄, 扌).
      // ColorFilter.matrix offsets are in the 0-255 unnormalised colour space;
      // offset = 128 * (1 - 1.4) = -51.2.
      canvas.drawImageRect(
        src,
        srcRect,
        ui.Rect.fromLTWH(pad, pad, srcRect.width, srcRect.height),
        ui.Paint()
          ..filterQuality = ui.FilterQuality.high
          ..colorFilter = const ui.ColorFilter.matrix(<double>[
            1.4, 0, 0, 0, -51.2,
            0, 1.4, 0, 0, -51.2,
            0, 0, 1.4, 0, -51.2,
            0, 0, 0, 1, 0,
          ]),
      );
      final picture = recorder.endRecording();
      out = await picture.toImage(dstWidth.round(), dstHeight.round());
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return _writeTemp(data.buffer.asUint8List(), prefix);
    } catch (_) {
      return null;
    } finally {
      out?.dispose();
    }
  }

  static Future<String> _writeTemp(List<int> bytes, String prefix) async {
    final file = File(
      '${Directory.systemTemp.path}/'
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
