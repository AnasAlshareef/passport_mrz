import 'package:equatable/equatable.dart';
import 'package:mrz_parser/mrz_parser.dart' show Sex;

/// The fields an ICAO 9303 machine-readable zone actually carries.
///
/// Anything a passport prints but the MRZ does not encode — issue date, the
/// Arabic name block, the mother's name — is deliberately absent: this type
/// only holds what was read, so a caller can never mistake an empty string for
/// scanned data.
class MrzPassport extends Equatable {
  const MrzPassport({
    required this.givenName,
    required this.surname,
    required this.dateOfBirth,
    required this.sex,
    required this.title,
    required this.nationality,
    required this.number,
    required this.expiryDate,
    required this.countryOfIssuance,
  });

  /// `Anna Maria`, title-cased from the MRZ's upper case.
  final String givenName;
  final String surname;

  /// Midnight UTC on the date printed in the MRZ.
  final DateTime dateOfBirth;
  final Sex sex;

  /// `Mr`, `Mrs`, `Miss`, or empty when the MRZ leaves sex unspecified.
  ///
  /// Derived from [sex] and age, for forms that ask for a title; ignore it if
  /// your form does not.
  final String title;

  /// Three-letter issuing-state code of the holder's nationality.
  final String nationality;

  /// The document number, verbatim — ICAO defines it as alphanumeric, so it is
  /// never OCR-corrected.
  final String number;
  final DateTime expiryDate;

  /// Three-letter code of the state that issued the document.
  final String countryOfIssuance;

  @override
  List<Object?> get props => [
    givenName,
    surname,
    dateOfBirth,
    sex,
    title,
    nationality,
    number,
    expiryDate,
    countryOfIssuance,
  ];
}
