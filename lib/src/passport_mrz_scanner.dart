import 'dart:async';
import 'dart:io';

import 'mrz_detector.dart';
import 'mrz_passport.dart';
import 'mrz_passport_parser.dart';
import 'mrz_preprocess.dart';
import 'mrz_scan_exception.dart';
import 'text_recognition.dart';

/// Reads a passport's machine-readable zone from a photo on disk.
///
/// One call runs the whole pipeline: downscale, OCR through the platform
/// recogniser, four MRZ detection strategies over the result, then ICAO 9303
/// parsing with check-digit validation. A document that fails its check digits
/// is rejected rather than guessed at — a wrong passport number reaches the
/// airline and fails at check-in, whereas a rejected scan just falls back to
/// typing it in.
class PassportMrzScanner {
  const PassportMrzScanner({this.recognizer = const TextRecognizer()});

  /// The OCR backend. Override it in tests with a fake.
  final TextRecognizer recognizer;

  /// Scans the image at [imagePath].
  ///
  /// Set [preferMrzCrop] when the photo is known to be a passport's photo page:
  /// the MRZ band alone reads best, so it is tried first. Leave it off for an
  /// arbitrary photo, where cropping to the bottom quarter may cut the MRZ out.
  ///
  /// Throws [MrzScanException] — never returns a partially read document.
  Future<MrzPassport> scan(
    String imagePath, {
    bool preferMrzCrop = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      return await _scan(imagePath, preferMrzCrop: preferMrzCrop).timeout(
        timeout,
        onTimeout: () => throw const MrzScanException(
          MrzScanErrorCode.timedOut,
        ),
      );
    } on MrzScanException {
      rethrow;
    } catch (_) {
      throw const MrzScanException(MrzScanErrorCode.unknown);
    }
  }

  Future<MrzPassport> _scan(
    String imagePath, {
    required bool preferMrzCrop,
  }) async {
    // Temp images this scan created, deleted once we are done with them.
    final scratchFiles = <String>{};
    try {
      final normalizedPath = await MrzPreprocess.normalizeForOcr(imagePath);
      if (normalizedPath != imagePath) scratchFiles.add(normalizedPath);

      final detector = MrzDetector(lenTolerance: 8, rowYTolerance: 32.0);

      // Set when a candidate looked like an MRZ but the parser refused it, so
      // the failure can say "this document does not add up" instead of
      // sending the user back for a clearer photo that will not help.
      var sawRejectedMrz = false;

      Future<MrzPassport?> tryExtract(String path, {int rotation = 0}) async {
        try {
          final recognized = await recognizer.processImage(
            path,
            rotationDegrees: rotation,
          );

          final mrzLines =
              detector.detectBestMrz(recognized) ??
              detector.detectFromLayout(recognized) ??
              detector.detectByFragmentStitch(recognized) ??
              detector.detectFromText(recognized.text);

          final candidates = <List<String>>[
            if (mrzLines.isNotEmpty) mrzLines,
            ?detector.detectHeuristicTd3FromRawText(recognized.text),
          ];

          for (final lines in candidates) {
            try {
              return PassportOcrParser.fromMrzLines(lines);
            } catch (_) {
              // Check digits disagreed — try the next candidate rather than
              // accepting a half-read document.
              sawRejectedMrz = true;
            }
          }
        } catch (_) {
          return null;
        }
        return null;
      }

      if (preferMrzCrop) {
        final cropPath = await MrzPreprocess.cropBottomForMrz(normalizedPath);
        if (cropPath != normalizedPath) {
          scratchFiles.add(cropPath);
          final cropped = await tryExtract(cropPath);
          if (cropped != null) return cropped;
        }
      }

      // One image on disk, four orientations — the recogniser rotates natively
      // instead of us re-encoding a JPEG per attempt.
      for (final rotation in const [0, 90, 180, 270]) {
        final passport = await tryExtract(normalizedPath, rotation: rotation);
        if (passport != null) return passport;
      }

      throw MrzScanException(
        sawRejectedMrz
            ? MrzScanErrorCode.mrzChecksumFailed
            : MrzScanErrorCode.mrzNotDetected,
      );
    } on MrzScanException {
      rethrow;
    } catch (_) {
      throw const MrzScanException(MrzScanErrorCode.imageProcessingFailed);
    } finally {
      for (final path in scratchFiles) {
        unawaited(File(path).delete().catchError((_) => File(path)));
      }
    }
  }
}
