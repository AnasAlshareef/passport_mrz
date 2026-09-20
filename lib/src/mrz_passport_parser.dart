import 'mrz_passport.dart';
import 'package:mrz_parser/mrz_parser.dart';

/// Turns validated MRZ lines into an [MrzPassport].
///
/// ICAO 9303 parsing and check-digit validation are delegated to `mrz_parser`,
/// which supports TD1 (3x30), TD2 (2x36) and TD3 (2x44) and — critically —
/// applies OCR corrections per field: letters become digits only in numeric
/// fields (dates, check digits), and the document number is never rewritten,
/// because ICAO defines it as alphanumeric.
///
/// This class only maps the result onto [MrzPassport] and derives the display
/// title. It deliberately has no "loose" mode: a document that fails
/// its check digits is rejected rather than guessed at, because a wrong
/// passport number reaches the airline and fails at check-in, whereas a
/// rejected scan just falls back to typing it in.
class PassportOcrParser {
  const PassportOcrParser._();

  /// Throws [MRZException] when [lines] are not a valid machine-readable zone.
  static MrzPassport fromMrzLines(List<String> lines) {
    final mrz = MRZParser.parse(lines);

    // mrz_parser returns local dates; MRZ dates are calendar dates, so they
    // are pinned to UTC midnight rather than left at the device's timezone.
    final birthDate = _asUtcDate(mrz.birthDate);
    final expiryDate = _asUtcDate(mrz.expiryDate);

    return MrzPassport(
      givenName: _titleCase(mrz.givenNames),
      surname: _titleCase(mrz.surnames),
      dateOfBirth: birthDate,
      sex: mrz.sex,
      title: _title(mrz.sex, birthDate),
      nationality: mrz.nationalityCountryCode,
      number: mrz.documentNumber,
      expiryDate: expiryDate,
      countryOfIssuance: mrz.countryCode,
    );
  }

  static DateTime _asUtcDate(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day);

  /// `ANNA MARIA` -> `Anna Maria`.
  static String _titleCase(String name) => name
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ')
      .trim();

  static String _title(Sex sex, DateTime dateOfBirth) {
    switch (sex) {
      case Sex.male:
        return 'Mr';
      case Sex.female:
        return _ageYears(dateOfBirth) >= 18 ? 'Mrs' : 'Miss';
      case Sex.none:
        return '';
    }
  }

  static int _ageYears(DateTime dateOfBirth, {DateTime? now}) {
    final today = now ?? DateTime.now().toUtc();
    var age = today.year - dateOfBirth.year;
    final hadBirthday =
        today.month > dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day >= dateOfBirth.day);
    if (!hadBirthday) age--;
    return age;
  }
}
