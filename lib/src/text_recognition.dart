import 'package:flutter/services.dart';

/// On-device OCR backed by each platform's native text recogniser:
/// Vision on iOS, ML Kit on Android.
///
/// This avoids the `google_mlkit_text_recognition` plugin, whose iOS
/// dependencies ship legacy fat frameworks with no arm64-simulator slice and
/// therefore cannot run on an Apple Silicon simulator at any version.
class TextRecognizer {
  const TextRecognizer();

  static const MethodChannel _channel = MethodChannel(
    'passport_mrz/text_recognition',
  );

  /// Runs OCR over the image at [path].
  ///
  /// [rotationDegrees] (0, 90, 180 or 270, clockwise) is applied natively by
  /// the recogniser. Rotating here rather than re-encoding a rotated JPEG in
  /// Dart avoids a decode/encode/disk round-trip per orientation attempt;
  /// reported bounding boxes are already in the rotated image's space.
  ///
  /// Throws [TextRecognitionException] if the image cannot be read or the
  /// platform recogniser fails.
  Future<RecognizedText> processImage(
    String path, {
    int rotationDegrees = 0,
  }) async {
    assert(
      const [0, 90, 180, 270].contains(rotationDegrees),
      'rotationDegrees must be 0, 90, 180 or 270',
    );
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'recognize',
        {'path': path, 'rotation': rotationDegrees},
      );
      if (result == null) {
        throw const TextRecognitionException('recogniser returned no result');
      }
      return RecognizedText.fromMap(result);
    } on PlatformException catch (e) {
      throw TextRecognitionException(e.message ?? e.code);
    }
  }
}

class TextRecognitionException implements Exception {
  const TextRecognitionException(this.message);

  final String message;

  @override
  String toString() => 'TextRecognitionException: $message';
}

/// Full OCR result for one image.
class RecognizedText {
  const RecognizedText({required this.text, required this.blocks});

  factory RecognizedText.fromMap(Map<String, dynamic> map) => RecognizedText(
    text: map['text'] as String? ?? '',
    blocks: _listOf(map['blocks'], TextBlock.fromMap),
  );

  /// Every recognised line joined by newlines, in reading order.
  final String text;
  final List<TextBlock> blocks;
}

/// A paragraph-level grouping of lines.
///
/// Vision has no block concept, so iOS returns every line in a single block.
/// Consumers iterate `blocks -> lines`, which stays correct either way.
class TextBlock {
  const TextBlock({required this.lines});

  factory TextBlock.fromMap(Map<String, dynamic> map) =>
      TextBlock(lines: _listOf(map['lines'], TextLine.fromMap));

  final List<TextLine> lines;
}

class TextLine {
  const TextLine({
    required this.text,
    required this.boundingBox,
    required this.words,
  });

  factory TextLine.fromMap(Map<String, dynamic> map) => TextLine(
    text: map['text'] as String? ?? '',
    boundingBox: _rectOf(map['rect']),
    words:
        (map['words'] as List?)?.map((w) => w.toString()).toList() ??
        const <String>[],
  );

  final String text;

  /// Pixel coordinates in the source image, origin top-left — matching ML Kit.
  /// The MRZ row-grouping heuristics use pixel distances, so normalised
  /// Vision coordinates are converted natively before crossing the channel.
  final Rect boundingBox;

  /// The line split on whitespace.
  ///
  /// MRZ lines carry no real spaces, so callers rejoin these with no separator
  /// to undo spurious spaces the recogniser inserts between glyph groups.
  final List<String> words;
}

List<T> _listOf<T>(dynamic raw, T Function(Map<String, dynamic>) build) {
  if (raw is! List) return <T>[];
  return raw
      .whereType<Map>()
      .map((e) => build(Map<String, dynamic>.from(e)))
      .toList();
}

Rect _rectOf(dynamic raw) {
  if (raw is! List || raw.length < 4) return Rect.zero;
  final v = raw.map((e) => (e as num).toDouble()).toList();
  return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
}
