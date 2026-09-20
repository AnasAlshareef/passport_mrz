/// Why a scan produced no passport.
///
/// The distinction that matters to a UI is [mrzNotDetected] versus
/// [mrzChecksumFailed]: the first is worth another photo, the second is not —
/// the document itself does not add up, so the only way forward is typing the
/// details in.
enum MrzScanErrorCode {
  /// No machine-readable zone was found in the image.
  mrzNotDetected,

  /// An MRZ was found and read, but failed its ICAO 9303 check digits.
  mrzChecksumFailed,

  /// The scan exceeded the timeout passed to `PassportMrzScanner.scan`.
  timedOut,

  /// The image could not be decoded, or the platform recogniser failed on it.
  imageProcessingFailed,

  unknown,
}

class MrzScanException implements Exception {
  const MrzScanException(this.code);

  final MrzScanErrorCode code;

  @override
  String toString() => 'MrzScanException: ${code.name}';
}
