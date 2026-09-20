import 'dart:math';
import 'dart:ui' show Rect;
import 'package:mrz_parser/mrz_parser.dart';

import 'text_recognition.dart';

class MrzDetector {
  MrzDetector({
    this.lenTolerance = 8,
    this.rowYTolerance = 26.0,
    this.minMrzishLen = 12,
  });

  final int lenTolerance;

  final double rowYTolerance;

  final int minMrzishLen;

  List<String>? detectBestMrz(RecognizedText recognized) {
    final td3Candidates = <String>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final joined = line.words.join();
        final raw = joined.isEmpty ? line.text : joined;
        final s = _normalizeMrzChars(raw);
        if (!_looksMrzish(s)) continue;

        if ((s.length - 44).abs() <= max(lenTolerance, 6)) {
          td3Candidates.add(_normalizeToLen(s, 44));
        }
      }
    }

    if (td3Candidates.length >= 2) {
      td3Candidates.sort((a, b) {
        final ap = a.startsWith('P<') ? 0 : 1;
        final bp = b.startsWith('P<') ? 0 : 1;
        return ap.compareTo(bp);
      });

      for (int i = 0; i < td3Candidates.length; i++) {
        for (int j = 0; j < td3Candidates.length; j++) {
          if (i == j) continue;
          final l1 = td3Candidates[i];
          final l2 = td3Candidates[j];
          if (!_looksLikeTd3L1(l1)) continue;
          final pair = _acceptTd3(l1, l2);
          if (pair != null) return pair;
        }
      }
    }
    return null;
  }

  List<String>? detectFromLayout(RecognizedText recognized) {
    final candidates = <_LineRow>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final joined = line.words.join();
        final raw = joined.isEmpty ? line.text : joined;
        final normalized = _normalizeMrzChars(raw);
        if (!_looksMrzish(normalized)) continue;

        final centerY = _centerY(line.boundingBox);
        candidates.add(
          _LineRow(
            text: normalized,
            centerY: centerY,
            centerX: _centerX(line.boundingBox),
            box: line.boundingBox,
            ltDensity: _ltDensity(normalized),
          ),
        );
      }
    }
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => b.centerY.compareTo(a.centerY));
    final groups = _groupByRow(candidates);

    for (final g in groups) {
      final td3 = _pickBest(g, idealLen: 44, count: 2);
      if (td3 != null) {
        // Either row can come back first — see [detectFromText].
        final pair = _acceptTd3(td3[0], td3[1]) ?? _acceptTd3(td3[1], td3[0]);
        if (pair != null) return pair;
      }
    }

    final td3Global = _pickBest(candidates, idealLen: 44, count: 2);
    if (td3Global != null) {
      final pair =
          _acceptTd3(td3Global[0], td3Global[1]) ??
          _acceptTd3(td3Global[1], td3Global[0]);
      if (pair != null) return pair;
    }
    return null;
  }

  List<String>? detectByFragmentStitch(RecognizedText recognized) {
    final pieces = <_Piece>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final variants = <String>[line.words.join(), line.text];
        for (final raw in variants) {
          final s = _normalizeMrzChars(raw);
          if (s.isEmpty) continue;
          if (_mrzCharset.hasMatch(s) &&
              s.contains('<') &&
              s.length >= minMrzishLen) {
            pieces.add(
              _Piece(
                text: s,
                centerY: _centerY(line.boundingBox),
                centerX: _centerX(line.boundingBox),
                box: line.boundingBox,
              ),
            );
          }
        }
      }
    }
    if (pieces.isEmpty) return null;

    pieces.sort((a, b) => b.centerY.compareTo(a.centerY));
    final rows = _groupPiecesByRow(pieces);

    final stitchedByRow = <String>[];
    for (final row in rows) {
      row.sort((a, b) => a.centerX.compareTo(b.centerX));
      final n = row.length;
      for (int i = 0; i < n; i++) {
        String acc = row[i].text;
        for (int j = i + 1; j < min(n, i + 5); j++) {
          acc += row[j].text;
          if ((acc.length - 44).abs() <= max(lenTolerance, 10)) {
            stitchedByRow.add(_normalizeToLen(acc, 44));
          }
        }
      }
    }

    final longLines = pieces
        .where((p) => (p.text.length - 44).abs() <= max(lenTolerance, 6))
        .map((p) => _normalizeToLen(p.text, 44))
        .toList();

    final td3Pool = <String>{...stitchedByRow, ...longLines}.toList();

    td3Pool.sort((a, b) {
      final ap = a.startsWith('P<') ? 0 : 1;
      final bp = b.startsWith('P<') ? 0 : 1;
      return ap.compareTo(bp);
    });

    for (int i = 0; i < td3Pool.length; i++) {
      for (int j = 0; j < td3Pool.length; j++) {
        if (i == j) continue;
        final l1 = td3Pool[i], l2 = td3Pool[j];
        if (!_looksLikeTd3L1(l1)) continue;
        final pair = _acceptTd3(l1, l2);
        if (pair != null) return pair;
      }
    }
    return null;
  }

  List<String> detectFromText(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map(_normalizeMrzChars)
        .where((l) => l.isNotEmpty)
        .toList();

    bool isMrzLine(String s) =>
        RegExp(r'^[A-Z0-9<]+$').hasMatch(s) && s.contains('<');

    final candidates = lines.where(isMrzLine).toList();

    for (final block in [
      _tryPickBlock(candidates, idealLen: 44, count: 2),
      _tryPickBlockAny(candidates, idealLen: 44, count: 2),
    ]) {
      if (block.isEmpty) continue;
      // Recognisers do not promise reading order — Vision hands back the two
      // MRZ rows bottom-up as often as not — so the pair is tried both ways
      // round. Check digits still decide which one is the real document.
      final pair =
          _acceptTd3(block[0], block[1]) ?? _acceptTd3(block[1], block[0]);
      if (pair != null) return pair;
    }

    return const [];
  }

  List<String>? detectHeuristicTd3FromRawText(String rawText) {
    String norm(String s) => _normalizeMrzChars(s);

    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map(norm)
        .where((l) => l.isNotEmpty)
        .toList();

    bool mrzish(String s) =>
        s.length >= 30 && _mrzCharset.hasMatch(s) && s.contains('<');

    final l1s = lines.where((l) => l.startsWith('P<') && mrzish(l)).toList();
    if (l1s.isEmpty) return null;

    bool looksLikeL2(String s) {
      if (!mrzish(s)) return false;
      final l = _normalizeToLen(s, 44);
      String digits(String t) => _digitsOnlyFix(t);
      try {
        final nationality = l.substring(10, 13);
        final dob = digits(l.substring(13, 19));
        final sex = l[20];
        final exp = digits(l.substring(21, 27));
        if (!_isAlpha3(nationality)) return false;
        if (!RegExp(r'^\d{6}$').hasMatch(dob)) return false;
        if (!RegExp(r'^[MF<]$').hasMatch(sex)) return false;
        if (!RegExp(r'^\d{6}$').hasMatch(exp)) return false;
        return true;
      } catch (_) {
        return false;
      }
    }

    final l2s = lines.where(looksLikeL2).toList();
    if (l2s.isEmpty) return null;

    l1s.sort((a, b) => (a.length - 44).abs().compareTo((b.length - 44).abs()));
    l2s.sort((a, b) => (a.length - 44).abs().compareTo((b.length - 44).abs()));

    final l1 = _normalizeToLen(l1s.first, 44);
    final l2 = _normalizeToLen(l2s.first, 44);
    return [l1, l2];
  }

  List<String>? _pickBest(
    List<_LineRow> pool, {
    required int idealLen,
    required int count,
  }) {
    if (pool.isEmpty) return null;

    final filtered = pool.where((r) {
      final lenDiff = (r.text.length - idealLen).abs();
      return _looksMrzish(r.text) && lenDiff <= max(lenTolerance, 6);
    }).toList();

    if (filtered.length < count) return null;

    filtered.sort((a, b) {
      final lenA = (a.text.length - idealLen).abs();
      final lenB = (b.text.length - idealLen).abs();
      final byLen = lenA.compareTo(lenB);
      if (byLen != 0) return byLen;
      final byLt = b.ltDensity.compareTo(a.ltDensity);
      if (byLt != 0) return byLt;
      return b.centerY.compareTo(a.centerY);
    });

    final pick = filtered
        .take(count)
        .map((e) => _normalizeToLen(e.text, idealLen))
        .toList();

    return pick.length == count ? pick : null;
  }

  List<List<_LineRow>> _groupByRow(List<_LineRow> lines) {
    if (lines.isEmpty) return const [];
    final groups = <List<_LineRow>>[];
    var current = <_LineRow>[lines.first];
    for (int i = 1; i < lines.length; i++) {
      final prev = lines[i - 1];
      final curr = lines[i];
      if ((prev.centerY - curr.centerY).abs() <= rowYTolerance) {
        current.add(curr);
      } else {
        groups.add(current);
        current = <_LineRow>[curr];
      }
    }
    groups.add(current);
    return groups;
  }

  List<List<_Piece>> _groupPiecesByRow(List<_Piece> pieces) {
    if (pieces.isEmpty) return const [];
    final rows = <List<_Piece>>[];
    var current = <_Piece>[pieces.first];
    for (int i = 1; i < pieces.length; i++) {
      final prev = pieces[i - 1];
      final curr = pieces[i];
      if ((prev.centerY - curr.centerY).abs() <= rowYTolerance) {
        current.add(curr);
      } else {
        rows.add(current);
        current = <_Piece>[curr];
      }
    }
    rows.add(current);
    return rows;
  }

  bool _looksLikeTd3L1(String l1) => l1.startsWith('P<') && l1.length == 44;

  static final RegExp _allowed = RegExp(r'[^A-Z0-9<]');
  static final RegExp _mrzCharset = RegExp(r'^[A-Z0-9<]+$');

  String _normalizeMrzChars(String s) {
    if (s.isEmpty) return s;
    String out = s.toUpperCase();

    out = out.replaceAll(' ', '');

    out = out
        .replaceAll('«', '<')
        .replaceAll('»', '<')
        .replaceAll('>', '<')
        .replaceAll('‹', '<')
        .replaceAll('›', '<')
        .replaceAll('⟨', '<')
        .replaceAll('⟩', '<')
        .replaceAll('“', '<')
        .replaceAll('”', '<')
        .replaceAll('’', '<')
        .replaceAll('‘', '<');

    out = out.replaceAll('|', 'I');

    out = out.replaceAll(_allowed, '');

    out = _normalizeLikelyConfusions(out);

    return out;
  }

  String _normalizeLikelyConfusions(String s) {
    var out = s;

    if (out.length >= 2 && out.startsWith('PK')) {
      out = 'P<${out.substring(2)}';
    }

    // OCR reads long '<<<<' filler as 'KKKK'. Only collapse runs of three or
    // more, plus a trailing run, so genuine double consonants survive
    // (MAKKAWI, SUKKAR, BAKKAR). Line 1 carries no check digit, so a mangled
    // surname would validate silently and reach the airline.
    out = out.replaceAllMapped(
      RegExp(r'K{3,}'),
      (m) => '<' * m.group(0)!.length,
    );
    out = out.replaceAllMapped(
      RegExp(r'K{2,}$'),
      (m) => '<' * m.group(0)!.length,
    );

    out = out.replaceAllMapped(RegExp(r'(?<=\d|<)O(?=\d|<)'), (_) => '0');
    out = out.replaceAllMapped(RegExp(r'(?<=\d)O(?=[MF<])'), (_) => '0');

    return out;
  }

  bool _looksMrzish(String s) {
    if (s.length < 20) return false;
    if (!_mrzCharset.hasMatch(s)) return false;
    if (!s.contains('<')) return false;
    return true;
  }

  String _normalizeToLen(String s, int idealLen) => s.length >= idealLen
      ? s.substring(0, idealLen)
      : s.padRight(idealLen, '<');

  double _ltDensity(String s) {
    if (s.isEmpty) return 0;
    final count = '<'.allMatches(s).length;
    return count / s.length;
  }

  double _centerY(Rect box) => (box.top + box.bottom) / 2;
  double _centerX(Rect box) => (box.left + box.right) / 2;

  /// The pair to keep, or null when it is not a real MRZ.
  ///
  /// Acceptance is ICAO 9303 check digits, delegated to mrz_parser so the rule
  /// here is the one the parser applies later — and so alphanumeric fields
  /// (document number, optional data) are never rewritten before their check
  /// digit is computed.
  ///
  /// If the lines as read do not validate, one repaired reading is tried:
  /// letters that cannot occur in a numeric field become the digit they were
  /// misread from. That reading is only returned if *every* check digit then
  /// agrees, so a wrong guess cannot get through — it just fails as before.
  List<String>? _acceptTd3(String l1, String l2) {
    for (final candidate in _line2Readings(l2)) {
      if (MRZParser.tryParse(<String>[l1, candidate]) != null) {
        return [l1, candidate];
      }
    }
    return null;
  }

  /// Line 2 as read, then the repaired readings, best first.
  Iterable<String> _line2Readings(String l2) sync* {
    yield l2;
    yield _repairTd3NumericFields(l2);
    for (final refilled in _refillTrailingFiller(l2)) {
      yield refilled;
      yield _repairTd3NumericFields(refilled);
    }
  }

  /// Recognisers routinely come back a few characters short on TD3 line 2,
  /// because the optional-data field is a long run of identical '<' and the
  /// tail of it reads as one blur. Padding on the right then puts those
  /// characters after the check digits — `...7544<<<<<<<02<<<` — which moves
  /// the composite check digit off position 44, so the document can never
  /// validate however good the photo was.
  ///
  /// The dropped characters belong inside that filler run, before the final
  /// check digits. Both plausible splits are offered; the check digits decide
  /// which, if either, is real.
  Iterable<String> _refillTrailingFiller(String l2) sync* {
    final trailing = RegExp(r'<+$').firstMatch(l2)?.group(0)?.length ?? 0;
    // A complete line 2 ends on the composite check digit, never on filler.
    if (trailing == 0 || trailing >= l2.length) return;

    final content = l2.substring(0, l2.length - trailing);
    for (final tail in const [2, 1]) {
      if (content.length <= tail) continue;
      yield content.substring(0, content.length - tail) +
          '<' * trailing +
          content.substring(content.length - tail);
    }
  }

  /// Letters an OCR pass produces for digits. Applied to TD3 line 2's numeric
  /// fields only: the document number and the optional data field are
  /// alphanumeric by ICAO, so a letter there is data, not a misread.
  static const _digitLookalikes = <String, String>{
    'O': '0',
    'D': '0',
    'Q': '0',
    'I': '1',
    'L': '1',
    'Z': '2',
    'A': '4',
    'S': '5',
    'G': '6',
    'T': '7',
    'B': '8',
  };

  /// Positions of TD3 line 2 that must hold a digit: the birth and expiry
  /// dates and every check digit. Check digits are allowed to be '<' on an
  /// empty field, and '<' is left alone.
  static const _numericPositions = <int>[
    9, // document number check
    13, 14, 15, 16, 17, 18, 19, // birth date + check
    21, 22, 23, 24, 25, 26, 27, // expiry + check
    42, // optional data check
    43, // composite check
  ];

  String _repairTd3NumericFields(String l2) {
    if (l2.length != 44) return l2;

    final chars = l2.split('');
    for (final i in _numericPositions) {
      final fixed = _digitLookalikes[chars[i]];
      if (fixed != null) chars[i] = fixed;
    }
    return chars.join();
  }

  String _digitsOnlyFix(String s) =>
      s.split('').map((c) => _digitLookalikes[c] ?? c).join();

  bool _isAlpha3(String s) => RegExp(r'^[A-Z]{3}$').hasMatch(s);

  List<String> _tryPickBlock(
    List<String> candidates, {
    required int idealLen,
    required int count,
  }) {
    for (int i = 0; i + count - 1 < candidates.length; i++) {
      final window = candidates.sublist(i, i + count);
      if (window.every((l) => (l.length - idealLen).abs() <= lenTolerance)) {
        return window.map((l) => _normalizeToLen(l, idealLen)).toList();
      }
    }
    return const [];
  }

  List<String> _tryPickBlockAny(
    List<String> candidates, {
    required int idealLen,
    required int count,
  }) {
    final good = candidates
        .where((l) => (l.length - idealLen).abs() <= lenTolerance)
        .toList();
    if (good.length < count) return const [];
    return good.take(count).map((l) => _normalizeToLen(l, idealLen)).toList();
  }
}

class _LineRow {
  _LineRow({
    required this.text,
    required this.centerY,
    required this.centerX,
    required this.box,
    required this.ltDensity,
  });
  final String text;
  final double centerY;
  final double centerX;
  final Rect box;
  final double ltDensity;
}

class _Piece {
  _Piece({
    required this.text,
    required this.centerY,
    required this.centerX,
    required this.box,
  });
  final String text;
  final double centerY;
  final double centerX;
  final Rect box;
}
