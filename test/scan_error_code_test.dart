import 'package:flutter_test/flutter_test.dart';
import 'package:passport_mrz/passport_mrz.dart';

/// A Polish specimen passport doing the rounds as a stock photo: the MRZ is
/// laid out correctly but every check digit is invented, so the parser refuses
/// it. Reading it again from a better photo cannot help.
const _unverifiableMrz =
    'P<POLMUSIELAK<<<BORYS<ANDRZEJ<<<<<<<<<<<<<<<\n'
    'EM9638245<POL8404238M33012567544<<<<<<<<<<02';

class _FakeRecognizer extends TextRecognizer {
  const _FakeRecognizer(this.text);

  final String text;

  @override
  Future<RecognizedText> processImage(String path, {int rotationDegrees = 0}) =>
      Future.value(RecognizedText(text: text, blocks: const []));
}

Future<MrzScanErrorCode?> _scan(String ocrText) async {
  try {
    await PassportMrzScanner(
      recognizer: _FakeRecognizer(ocrText),
    ).scan('/does/not/exist.jpg');
    return null;
  } on MrzScanException catch (e) {
    return e.code;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an MRZ that fails its check digits is not blamed on the photo', () {
    // "Make sure the image is clear" sends the user back to retake a photo
    // that will fail exactly the same way — the document is what does not add
    // up, so the message has to point at typing the details in instead.
    expect(
      _scan(_unverifiableMrz),
      completion(MrzScanErrorCode.mrzChecksumFailed),
    );
  });

  test('text with no MRZ in it still reports nothing found', () {
    expect(
      _scan('REPUBLIC OF POLAND\nPASSPORT\nMUSIELAK'),
      completion(MrzScanErrorCode.mrzNotDetected),
    );
  });
}
