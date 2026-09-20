# passport_mrz

On-device passport MRZ scanning for Flutter. Give it a photo, get back a
validated passport — or a reason it could not read one.

No network, no API key, no ML Kit iOS pod: OCR runs through **Vision** on iOS
and **ML Kit** on Android, and ICAO 9303 parsing happens in Dart.

## Why not `google_mlkit_text_recognition`

That plugin pulls ML Kit's iOS pods, whose only simulator slice is `x86_64`.
They cannot link on an Apple Silicon simulator at any version. This package
talks to ML Kit's Android SDK directly and uses Vision — part of the OS — on
iOS, so the simulator works.

## Install

```yaml
dependencies:
  passport_mrz:
    git:
      url: https://github.com/AnasAlshareef/passport_mrz.git
```

Android needs `minSdk 24`; iOS needs a deployment target of 13.0. Nothing to
register — it is a normal Flutter plugin.

## Use

```dart
import 'package:passport_mrz/passport_mrz.dart';

try {
  final passport = await const PassportMrzScanner().scan(
    file.path,
    // The MRZ band alone reads best — set this when you know you are looking
    // at a passport's photo page. Leave it off for an arbitrary photo.
    preferMrzCrop: true,
  );
  print('${passport.surname} ${passport.number} ${passport.expiryDate}');
} on MrzScanException catch (e) {
  switch (e.code) {
    case MrzScanErrorCode.mrzChecksumFailed:
      // The document does not add up. Another photo will fail the same way —
      // offer to type the details in.
    case MrzScanErrorCode.mrzNotDetected:
      // Worth retrying with a clearer, flatter shot.
    default:
  }
}
```

`MrzPassport` carries only what the MRZ actually encodes: names, date of birth,
sex, nationality, document number, expiry, issuing state. Anything a passport
prints but the MRZ omits — issue date, the Arabic name block — is deliberately
absent, so an empty string can never be mistaken for scanned data.

## What it does to get a read

A photographed MRZ is rarely clean. One `scan()` call runs, in order:

1. **Downscale** to 1400px longest side (`MrzPreprocess`), in a background
   isolate.
2. **Crop** to the bottom band and sharpen, when `preferMrzCrop` is set.
3. **OCR** through the native recogniser, retried at 0°/90°/180°/270°. The
   rotation happens natively, so no JPEG is re-encoded per attempt.
4. **Detect** the two MRZ rows four ways — direct length match, bounding-box
   row grouping, fragment stitching, and raw-text heuristics — because
   recognisers split, reorder, and merge the rows unpredictably.
5. **Repair** what OCR reliably gets wrong: `<<<<` read as `KKKK`, `>` read for
   `<`, letter/digit lookalikes in numeric fields only, and characters dropped
   from the filler run.
6. **Validate** with ICAO 9303 check digits via `mrz_parser`.

Step 5 never touches the document number or optional data: ICAO defines them as
alphanumeric, so a letter there is data, not a misread. A repaired reading is
only accepted if *every* check digit then agrees — a wrong guess cannot get
through, it just fails as it would have anyway.

**Nothing that fails its check digits is ever returned.** A wrong passport
number reaches the airline and fails at check-in; a rejected scan costs the
user some typing.

## Lower-level pieces

`MrzDetector`, `PassportOcrParser`, `MrzPreprocess` and `TextRecognizer` are all
exported if you want the OCR without the orchestration — `TextRecognizer` is a
general-purpose text recogniser, not an MRZ-specific one.

## Tests

```sh
flutter test
```

31 tests over the ICAO 9303 specimens, real recogniser output captured from
Vision, and the OCR failure modes above.

## Supported documents

TD1 (3×30), TD2 (2×36) and TD3 (2×44). Detection heuristics are tuned for TD3
passports; TD1/TD2 parse but are not searched for in noisy OCR output.
