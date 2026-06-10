import 'dart:io';
import 'dart:ui' as ui;

/// Re-encodes a captured photo as a plain, bounded-size PNG before it is
/// handed to ML Kit.
///
/// Modern flagship cameras produce JPEG variants (Ultra HDR gain maps, very
/// high resolutions, vendor-specific encoders) that ML Kit's native decoder
/// may not handle safely — a native decoder crash kills the whole process and
/// cannot be caught from Dart. Decoding with Flutter's own codec (which
/// applies EXIF orientation) and re-encoding to PNG yields a standard image
/// with a bounded long edge, which also caps native memory use in ML Kit.
class ImageSanitizer {
  /// Longest output edge. 1600px keeps small print legible for OCR while
  /// bounding decode memory.
  static const int maxLongEdge = 1600;

  /// Returns the path of the sanitised PNG, or null when decoding fails —
  /// the caller should then fall back to the original file.
  static Future<String?> sanitise(String sourcePath) async {
    ui.Image? image;
    try {
      final bytes = await File(sourcePath).readAsBytes();

      // Read intrinsic dimensions first so the decode itself can downscale —
      // far cheaper than decoding at full resolution and resizing after.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;

      final longEdge = width > height ? width : height;
      final ui.Codec codec;
      if (longEdge > maxLongEdge) {
        final scale = maxLongEdge / longEdge;
        codec = await descriptor.instantiateCodec(
          targetWidth: (width * scale).round(),
          targetHeight: (height * scale).round(),
        );
      } else {
        codec = await descriptor.instantiateCodec();
      }

      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;

      final out = File(
        '${Directory.systemTemp.path}/'
        'ocr_capture_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return out.path;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }
}
