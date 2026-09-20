import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passport_mrz/passport_mrz.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextRecognizer channel', () {
    const channel = MethodChannel('passport_mrz/text_recognition');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return <String, dynamic>{'text': '', 'blocks': <dynamic>[]};
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('defaults to no rotation', () async {
      await const TextRecognizer().processImage('/tmp/a.jpg');
      expect(calls.single.method, 'recognize');
      expect(calls.single.arguments, {'path': '/tmp/a.jpg', 'rotation': 0});
    });

    test('forwards each quarter turn to the native recogniser', () async {
      // Replaces re-encoding a rotated JPEG per orientation attempt.
      for (final r in const [90, 180, 270]) {
        await const TextRecognizer().processImage(
          '/tmp/a.jpg',
          rotationDegrees: r,
        );
      }
      expect(calls.map((c) => (c.arguments as Map)['rotation']).toList(), [
        90,
        180,
        270,
      ]);
    });

    test('surfaces a platform failure as TextRecognitionException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'BAD_IMAGE', message: 'cannot read');
          });
      expect(
        () => const TextRecognizer().processImage('/tmp/missing.jpg'),
        throwsA(isA<TextRecognitionException>()),
      );
    });
  });

  group('RecognizedText.fromMap', () {
    test('parses the native payload into blocks, lines, words and rects', () {
      final parsed = RecognizedText.fromMap({
        'text': 'P<UTOERIKSSON\nL898902C36UTO',
        'blocks': [
          {
            'lines': [
              {
                'text': 'P<UTO ERIKSSON',
                'rect': [10, 20, 300, 44],
                'words': ['P<UTO', 'ERIKSSON'],
              },
            ],
          },
        ],
      });

      expect(parsed.blocks, hasLength(1));
      final line = parsed.blocks.single.lines.single;
      expect(line.boundingBox, const Rect.fromLTRB(10, 20, 300, 44));
      // Rejoined without a separator — MRZ carries no real spaces.
      expect(line.words.join(), 'P<UTOERIKSSON');
    });

    test('survives missing and malformed fields rather than throwing', () {
      final empty = RecognizedText.fromMap(const {});
      expect(empty.text, '');
      expect(empty.blocks, isEmpty);

      final ragged = RecognizedText.fromMap({
        'blocks': [
          {
            'lines': [
              {'text': 'x'}, // no rect, no words
              {
                'rect': [1, 2],
                'words': null,
              }, // short rect
            ],
          },
          'not-a-block',
        ],
      });
      final lines = ragged.blocks.single.lines;
      expect(lines, hasLength(2));
      expect(lines[0].boundingBox, Rect.zero);
      expect(lines[0].words, isEmpty);
      expect(lines[1].boundingBox, Rect.zero);
      expect(lines[1].text, '');
    });

    test('accepts ints or doubles for rect coordinates', () {
      final parsed = RecognizedText.fromMap({
        'blocks': [
          {
            'lines': [
              {
                'rect': [1, 2.5, 3, 4.5],
              },
            ],
          },
        ],
      });
      expect(
        parsed.blocks.single.lines.single.boundingBox,
        const Rect.fromLTRB(1, 2.5, 3, 4.5),
      );
    });
  });
}
