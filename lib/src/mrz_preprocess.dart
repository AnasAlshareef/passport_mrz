import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class MrzPreprocess {
  static Future<String> normalizeForOcr(
    String path, {
    int maxSide = 1400,
    int quality = 85,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final tempDirPath = (await getTemporaryDirectory()).path;
      return await Isolate.run(
        () => _normalizeSync(bytes, tempDirPath, path, maxSide, quality),
      );
    } catch (_) {
      return path;
    }
  }

  static Future<String> cropBottomForMrz(
    String path, {
    double bottomFraction = 0.28,
  }) async {
    try {
      final bytes = await File(path).readAsBytes();
      final tempDirPath = (await getTemporaryDirectory()).path;
      return await Isolate.run(
        () => _cropSync(bytes, tempDirPath, path, bottomFraction),
      );
    } catch (_) {
      return path;
    }
  }

  // ---------------------------------------------------------------------------
  // Private sync helpers – run inside Isolate.run(), no platform channels.
  // All dart:io File operations are safe in background isolates.
  // ---------------------------------------------------------------------------

  static String _normalizeSync(
    Uint8List bytes,
    String tempDirPath,
    String fallback,
    int maxSide,
    int quality,
  ) {
    try {
      final src = img.decodeImage(bytes);
      if (src == null) return fallback;

      final longest = math.max(src.width, src.height);
      var normalized = src;
      if (longest > maxSide) {
        normalized = img.copyResize(
          src,
          width: src.width >= src.height ? maxSide : null,
          height: src.height > src.width ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
      }
      return _saveTmp(normalized, tempDirPath, '_mrz_normalized.jpg', quality);
    } catch (_) {
      return fallback;
    }
  }

  static String _cropSync(
    Uint8List bytes,
    String tempDirPath,
    String fallback,
    double bottomFraction,
  ) {
    try {
      final src = img.decodeImage(bytes);
      if (src == null) return fallback;

      final cropH = (src.height * bottomFraction).clamp(60, src.height).toInt();
      final y = src.height - cropH;
      final cropped = img.copyCrop(
        src,
        x: 0,
        y: y,
        width: src.width,
        height: cropH,
      );

      const sharpenKernel = <num>[0, -1, 0, -1, 5, -1, 0, -1, 0];
      final sharpened = img.convolution(
        cropped,
        filter: sharpenKernel,
        div: 1,
        offset: 0,
      );
      img.adjustColor(sharpened, contrast: 1.1, brightness: 0.0);
      final gray = img.grayscale(sharpened);

      return _saveTmp(gray, tempDirPath, '_mrz_crop.jpg', 92);
    } catch (_) {
      return fallback;
    }
  }

  /// Synchronous file write – safe to call from inside an isolate.
  static String _saveTmp(
    img.Image im,
    String tempDirPath,
    String suffix,
    int quality,
  ) {
    final jpg = img.encodeJpg(im, quality: quality);
    final outPath =
        '$tempDirPath/mrz_${DateTime.now().millisecondsSinceEpoch}$suffix';
    File(outPath).writeAsBytesSync(jpg, flush: true);
    return outPath;
  }
}
