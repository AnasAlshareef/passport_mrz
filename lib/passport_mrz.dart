/// On-device passport MRZ scanning: native OCR plus ICAO 9303 parsing.
///
/// ```dart
/// try {
///   final passport = await const PassportMrzScanner().scan(file.path);
///   print('${passport.surname} ${passport.number}');
/// } on MrzScanException catch (e) {
///   if (e.code == MrzScanErrorCode.mrzChecksumFailed) {
///     // Another photo will not help — ask the user to type it in.
///   }
/// }
/// ```
library;

export 'package:mrz_parser/mrz_parser.dart' show Sex;

export 'src/mrz_detector.dart';
export 'src/mrz_passport.dart';
export 'src/mrz_passport_parser.dart';
export 'src/mrz_preprocess.dart';
export 'src/mrz_scan_exception.dart';
export 'src/passport_mrz_scanner.dart';
export 'src/text_recognition.dart';
