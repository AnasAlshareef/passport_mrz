import 'package:flutter_test/flutter_test.dart';
import 'package:passport_mrz/passport_mrz.dart';

/// ICAO 9303 canonical specimens — the published worked examples.
const _icaoTd3 = [
  'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
  'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
];
const _icaoTd2 = [
  'I<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<',
  'D231458907UTO7408122F1204159<<<<<<<6',
];
const _icaoTd1 = [
  'I<UTOD231458907<<<<<<<<<<<<<<<',
  '7408122F1204159UTO<<<<<<<<<<<6',
  'ERIKSSON<<ANNA<MARIA<<<<<<<<<<',
];

// Synthetic but check-digit-correct documents isolating one variable each.
const _docWithO = [
  'P<SAUALSHAREEF<<ANAS<<<<<<<<<<<<<<<<<<<<<<<<',
  'O1234567<4SAU9001158M3001145<<<<<<<<<<<<<<00',
];
const _docWithB = [
  'P<SAUALSHAREEF<<ANAS<<<<<<<<<<<<<<<<<<<<<<<<',
  'B7654321<1SAU9001158M3001145<<<<<<<<<<<<<<06',
];
const _surnameWithKK = [
  'P<SAUMAKKAWI<<AHMED<<<<<<<<<<<<<<<<<<<<<<<<<',
  'A1234567<6SAU9001158M3001145<<<<<<<<<<<<<<06',
];

void main() {
  group('ICAO 9303 specimens', () {
    test('TD3 passport parses every field', () {
      final p = PassportOcrParser.fromMrzLines(_icaoTd3);
      expect(p.number, 'L898902C3');
      expect(p.surname, 'Eriksson');
      expect(p.givenName, 'Anna Maria');
      expect(p.nationality, 'UTO');
      expect(p.countryOfIssuance, 'UTO');
      expect(p.dateOfBirth, DateTime.utc(1974, 8, 12));
      expect(p.expiryDate, DateTime.utc(2012, 4, 15));
      expect(p.title, 'Mrs');
    });

    test('TD2 travel document parses', () {
      final p = PassportOcrParser.fromMrzLines(_icaoTd2);
      expect(p.number, 'D23145890');
      expect(p.surname, 'Eriksson');
      expect(p.dateOfBirth, DateTime.utc(1974, 8, 12));
    });

    test('TD1 identity card parses', () {
      final p = PassportOcrParser.fromMrzLines(_icaoTd1);
      expect(p.number, 'D23145890');
      expect(p.surname, 'Eriksson');
      expect(p.givenName, 'Anna Maria');
    });
  });

  group('document number is alphanumeric and must survive verbatim', () {
    // Regression: _fixNumericField mapped O->0 / D->0 / I->1 / B->8 ... on the
    // document number, which ICAO 9303 defines as alphanumeric. That both
    // rejected valid passports and wrote a wrong number onto the booking.
    test('a document number containing O is accepted and preserved', () {
      final p = PassportOcrParser.fromMrzLines(_docWithO);
      expect(p.number, 'O1234567');
    });

    test('a document number containing B is not turned into 8', () {
      final p = PassportOcrParser.fromMrzLines(_docWithB);
      expect(p.number, 'B7654321');
    });
  });

  group('names must survive OCR filler correction', () {
    // Regression: the K{2,} -> '<' rule (meant to undo '<<<' read as 'KKK')
    // ran over the whole line, so MAKKAWI became MA<<AWI. TD3 line 1 has no
    // check digit, so nothing caught it.
    test('a surname containing KK is not corrupted by the detector', () {
      final found = MrzDetector().detectFromText(_surnameWithKK.join('\n'));
      expect(found, isNotEmpty, reason: 'detector should locate the MRZ');
      expect(found.first, contains('MAKKAWI'));
    });

    test('a surname containing KK parses to the real name', () {
      final p = PassportOcrParser.fromMrzLines(_surnameWithKK);
      expect(p.surname, 'Makkawi');
      expect(p.givenName, 'Ahmed');
    });
  });

  group('OCR filler correction still works where it should', () {
    test('a long filler run misread as KKKK is still corrected', () {
      // The real defect this rule exists for: Vision/ML Kit reading '<<<<' as
      // 'KKKK'. Runs of 3+ must still collapse.
      final misread = [
        _surnameWithKK[0].replaceAll(
          RegExp(r'<{4,}$'),
          'KKKKKKKKKKKKKKKKKKKKKKKKK',
        ),
        _surnameWithKK[1],
      ];
      final found = MrzDetector().detectFromText(misread.join('\n'));
      expect(found, isNotEmpty);
      expect(found.first, contains('MAKKAWI'));
      expect(found.first.endsWith('<'), isTrue);
      expect(found.first, isNot(contains('KKK')));
    });

    test('the detector locates the ICAO specimen in noisy OCR text', () {
      final noisy =
          'REPUBLIC OF UTOPIA\nPASSPORT\n'
          '${_icaoTd3[0]}\n${_icaoTd3[1]}\nsome trailing noise';
      final found = MrzDetector().detectFromText(noisy);
      expect(found, hasLength(2));
      expect(found[0], _icaoTd3[0]);
      expect(found[1], _icaoTd3[1]);
    });
  });

  group('invalid documents are rejected, never guessed', () {
    test('a tampered document-number check digit throws', () {
      final tampered = [_icaoTd3[0], _icaoTd3[1].replaceRange(9, 10, '7')];
      expect(
        () => PassportOcrParser.fromMrzLines(tampered),
        throwsA(isA<Exception>()),
      );
    });

    test('a tampered birth-date check digit throws', () {
      final tampered = [_icaoTd3[0], _icaoTd3[1].replaceRange(19, 20, '9')];
      expect(
        () => PassportOcrParser.fromMrzLines(tampered),
        throwsA(isA<Exception>()),
      );
    });

    test('garbage input throws rather than returning a partial passport', () {
      expect(
        () => PassportOcrParser.fromMrzLines(['NOT<AN<MRZ', 'EITHER<IS<THIS']),
        throwsA(isA<Exception>()),
      );
    });
  });

  group(
    'OCR digit misreads are repaired, but only if the checks then agree',
    () {
      // The recogniser reading one digit of a date as its letter lookalike used
      // to sink the whole scan: the pair failed its check digits, every detector
      // dropped it, and the user was told to retake a photo that would fail the
      // same way.
      String misread(String line, int index, String letter) =>
          line.replaceRange(index, index + 1, letter);

      void expectRecovered(String line2) {
        final found = MrzDetector().detectFromText('${_icaoTd3[0]}\n$line2');
        expect(found, isNotEmpty, reason: 'the MRZ should still be located');

        final p = PassportOcrParser.fromMrzLines(found);
        expect(p.number, 'L898902C3');
        expect(p.dateOfBirth, DateTime.utc(1974, 8, 12));
        expect(p.expiryDate, DateTime.utc(2012, 4, 15));
      }

      test('S read for the 5 in the expiry date', () {
        expectRecovered(misread(_icaoTd3[1], 26, 'S'));
      });

      test('B read for the 8 in the birth date', () {
        expectRecovered(misread(_icaoTd3[1], 16, 'B'));
      });

      test('G read for the 6 in a check digit', () {
        expectRecovered(misread(_icaoTd3[1], 9, 'G'));
      });

      test('two misreads in the same line', () {
        expectRecovered(misread(misread(_icaoTd3[1], 26, 'S'), 16, 'B'));
      });

      test('letters in the document number are data, not misreads', () {
        // O1234567 must survive: the repair only touches the date and check
        // digit positions, never the alphanumeric document number.
        final found = MrzDetector().detectFromText(_docWithO.join('\n'));
        expect(found, isNotEmpty);
        expect(PassportOcrParser.fromMrzLines(found).number, 'O1234567');
      });

      test('a document with invented check digits is still refused', () {
        // A specimen passport doing the rounds as a stock photo: the MRZ is
        // shaped correctly but none of its check digits add up, and no single
        // digit repair can make them.
        const specimen = [
          'P<POLMUSIELAK<<<BORYS<ANDRZEJ<<<<<<<<<<<<<<<',
          'EM9638245<POL8404238M33012567544<<<<<<<<<<02',
        ];
        expect(MrzDetector().detectFromText(specimen.join('\n')), isEmpty);
        expect(
          () => PassportOcrParser.fromMrzLines(specimen),
          throwsA(isA<Exception>()),
        );
      });
    },
  );

  group('recognisers come back short on the filler run', () {
    // What Vision actually returns for a photographed passport: the long '<'
    // runs read as one blur and a few characters go missing. Padding on the
    // right then pushed line 2's two check digits off positions 43-44
    // (`...7544<<<<<<<02<<<`), so no real document could ever validate.
    test('three characters lost from each line still parses', () {
      final found = MrzDetector(lenTolerance: 8).detectFromText(
        '${_icaoTd3[0].replaceFirst('<<<<<<<<<<<<', '<<<<<<<<<')}\n'
        '${_icaoTd3[1].replaceFirst('<<<<<', '<<')}',
      );
      expect(found, isNotEmpty, reason: 'the short lines should be recovered');

      final p = PassportOcrParser.fromMrzLines(found);
      expect(p.number, 'L898902C3');
      expect(p.surname, 'Eriksson');
      expect(p.givenName, 'Anna Maria');
      expect(p.dateOfBirth, DateTime.utc(1974, 8, 12));
      expect(p.expiryDate, DateTime.utc(2012, 4, 15));
    });

    test('a short line plus a misread digit still parses', () {
      final found = MrzDetector(lenTolerance: 8).detectFromText(
        '${_icaoTd3[0]}\n'
        '${_icaoTd3[1].replaceFirst('<<<<<', '<<').replaceRange(26, 27, 'S')}',
      );
      expect(found, isNotEmpty);
      expect(
        PassportOcrParser.fromMrzLines(found).expiryDate,
        DateTime.utc(2012, 4, 15),
      );
    });

    test('refilling the run cannot rescue invented check digits', () {
      // The Polish specimen exactly as the iOS recogniser reads it, short
      // filler and all. Putting the characters back gets the layout right and
      // the document still does not add up.
      final found = MrzDetector(lenTolerance: 8).detectFromText(
        'P<POLMUSIELAK<<<BORYS<ANDRZEJ<<<<<<<<<<<<\n'
        'EM9638245<P0L8404238M33012567544<<<<<<<02',
      );
      expect(found, isEmpty);
    });
  });

  group('what the iOS recogniser actually hands back', () {
    // Captured by running Vision over a rendered MRZ: it reports the two rows
    // bottom-up, reads the trailing chevrons as '>', drops some of them, and
    // turns the O of the issuing country into a zero. Every one of those used
    // to sink the scan.
    const visionText =
        'L898902C36UT07408122F1204159ZE184226B<<<<<10\n'
        '>>>>>\n'
        '>>>>\n'
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<';

    test('the rows are paired whichever order they arrive in', () {
      final found = MrzDetector(lenTolerance: 8).detectFromText(visionText);
      expect(found, isNotEmpty);

      final p = PassportOcrParser.fromMrzLines(found);
      expect(p.number, 'L898902C3');
      expect(p.surname, 'Eriksson');
      expect(p.givenName, 'Anna Maria');
      expect(p.expiryDate, DateTime.utc(2012, 4, 15));
    });

    test("chevrons read as '>' are still chevrons", () {
      final found = MrzDetector(
        lenTolerance: 8,
      ).detectFromText('${_icaoTd3[0].replaceAll('<', '>')}\n${_icaoTd3[1]}');
      expect(found, isNotEmpty);
      expect(PassportOcrParser.fromMrzLines(found).surname, 'Eriksson');
    });
  });
}
