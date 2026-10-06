import 'dart:convert';
import 'dart:typed_data';

/// Plain-text (.txt) helpers shared by [TxtMetadataReader] and the
/// reader's `TxtDocument`: encoding detection, language guess, Project
/// Gutenberg header/footer. Pure Dart, no exceptions on bad input.
class TxtText {
  TxtText._();

  /// Decodes a text file. Byte-order marks (UTF-8/UTF-16) win; otherwise
  /// valid UTF-8 is UTF-8; otherwise Windows-1250 (Central European:
  /// ő, ű, č, ł, ...) or Windows-1252 (Western), whichever gives more
  /// letters typical of those languages.
  static String decode(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(Uint8List.sublistView(bytes, 3), allowMalformed: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes, 2, littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes, 2, littleEndian: false);
    }
    if (isValidUtf8(bytes)) return utf8.decode(bytes, allowMalformed: true);
    return _singleByte(bytes, _prefersCp1250(bytes) ? _cp1250 : _cp1252);
  }

  /// True if [bytes] is UTF-8 (a sequence cut off at the very end - a
  /// sample of a longer file - is allowed). Doesn't throw, so the VS Code
  /// debugger doesn't stop here.
  static bool isValidUtf8(Uint8List bytes) {
    var i = 0;
    final n = bytes.length;
    while (i < n) {
      final b = bytes[i];
      int extra;
      if (b < 0x80) {
        i++;
        continue;
      } else if (b >= 0xC2 && b <= 0xDF) {
        extra = 1;
      } else if (b >= 0xE0 && b <= 0xEF) {
        extra = 2;
      } else if (b >= 0xF0 && b <= 0xF4) {
        extra = 3;
      } else {
        return false;
      }
      if (i + extra >= n) return true; // cut off at the end
      for (var k = 1; k <= extra; k++) {
        if (bytes[i + k] & 0xC0 != 0x80) return false;
      }
      i += extra + 1;
    }
    return true;
  }

  /// The character of byte [b] in Windows code page [codePage] (1250,
  /// 1251 or 1252; other code pages are read as 1252).
  static int singleByteChar(int b, int codePage) {
    if (b < 0x80 || b > 0xFF) return b;
    final table = switch (codePage) {
      1250 => _cp1250,
      1251 => _cp1251,
      _ => _cp1252,
    };
    return table[b - 0x80];
  }

  /// Decodes an XML file (FB2, ...) using the encoding in its
  /// `<?xml ... encoding="..."?>` declaration: UTF-8/16, windows-1250/
  /// 1251/1252, ISO-8859-1. Unknown or missing: like [decode].
  static String decodeXml(Uint8List bytes) {
    final head = String.fromCharCodes(
        bytes.length > 200 ? Uint8List.sublistView(bytes, 0, 200) : bytes);
    final m = RegExp(r'''encoding\s*=\s*["']([\w.:-]+)["']''').firstMatch(head);
    final encoding = m?.group(1)?.toLowerCase() ?? '';
    final hasBom = bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF) ||
            (bytes[0] == 0xEF && bytes[1] == 0xBB));
    int? codePage;
    if (encoding.contains('1251') || encoding == 'cp-1251') codePage = 1251;
    if (encoding.contains('1250')) codePage = 1250;
    if (encoding.contains('1252') ||
        encoding == 'iso-8859-1' ||
        encoding == 'latin1') {
      codePage = 1252;
    }
    if (codePage == null || hasBom) return decode(bytes);
    final table = codePage == 1251
        ? _cp1251
        : codePage == 1250
            ? _cp1250
            : _cp1252;
    return _singleByte(bytes, table);
  }

  static String _utf16(Uint8List bytes, int start,
      {required bool littleEndian}) {
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }

  static String _singleByte(Uint8List bytes, List<int> high) {
    final codes = Uint16List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      codes[i] = b < 0x80 ? b : high[b - 0x80];
    }
    return String.fromCharCodes(codes);
  }

  // Letters that decide between the two code pages, where the same byte
  // means something else in the other one (ő/õ, ű/û, č/è, ...).
  static final Set<int> _centralLetters =
      'őűŐŰčďěňřšťžůČĎĚŇŘŠŤŽŮąćęłńśźżĄĆĘŁŃŚŹŻľĺŕĽĹŔ'.runes.toSet();
  static final Set<int> _westernLetters =
      'ãìòèùøæåñàâêîôäëïÿœŒÃÌÒÈÙØÆÅÑÀÂÊÎÔ'.runes.toSet();

  static bool _prefersCp1250(Uint8List bytes) {
    final counts = List<int>.filled(128, 0);
    for (final b in bytes) {
      if (b >= 0x80) counts[b - 0x80]++;
    }
    var score = 0;
    for (var i = 0; i < 128; i++) {
      if (counts[i] == 0 || _cp1250[i] == _cp1252[i]) continue;
      if (_centralLetters.contains(_cp1250[i])) score += counts[i];
      if (_westernLetters.contains(_cp1252[i])) score -= counts[i];
    }
    return score > 0;
  }

  static const List<int> _cp1250 = [
    0x20AC, 0x0081, 0x201A, 0x0083, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x0088, 0x2030, 0x0160, 0x2039, 0x015A, 0x0164, 0x017D, 0x0179,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x0098, 0x2122, 0x0161, 0x203A, 0x015B, 0x0165, 0x017E, 0x017A,
    0x00A0, 0x02C7, 0x02D8, 0x0141, 0x00A4, 0x0104, 0x00A6, 0x00A7,
    0x00A8, 0x00A9, 0x015E, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x017B,
    0x00B0, 0x00B1, 0x02DB, 0x0142, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
    0x00B8, 0x0105, 0x015F, 0x00BB, 0x013D, 0x02DD, 0x013E, 0x017C,
    0x0154, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x0139, 0x0106, 0x00C7,
    0x010C, 0x00C9, 0x0118, 0x00CB, 0x011A, 0x00CD, 0x00CE, 0x010E,
    0x0110, 0x0143, 0x0147, 0x00D3, 0x00D4, 0x0150, 0x00D6, 0x00D7,
    0x0158, 0x016E, 0x00DA, 0x0170, 0x00DC, 0x00DD, 0x0162, 0x00DF,
    0x0155, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x013A, 0x0107, 0x00E7,
    0x010D, 0x00E9, 0x0119, 0x00EB, 0x011B, 0x00ED, 0x00EE, 0x010F,
    0x0111, 0x0144, 0x0148, 0x00F3, 0x00F4, 0x0151, 0x00F6, 0x00F7,
    0x0159, 0x016F, 0x00FA, 0x0171, 0x00FC, 0x00FD, 0x0163, 0x02D9,
  ];

  static const List<int> _cp1251 = [
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x0098, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7,
    0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7,
    0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
    0x0410, 0x0411, 0x0412, 0x0413, 0x0414, 0x0415, 0x0416, 0x0417,
    0x0418, 0x0419, 0x041A, 0x041B, 0x041C, 0x041D, 0x041E, 0x041F,
    0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
    0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F,
    0x0430, 0x0431, 0x0432, 0x0433, 0x0434, 0x0435, 0x0436, 0x0437,
    0x0438, 0x0439, 0x043A, 0x043B, 0x043C, 0x043D, 0x043E, 0x043F,
    0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
    0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F,
  ];

  static const List<int> _cp1252 = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
    0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
    0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
    0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
    0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7,
    0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF,
    0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D7,
    0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF,
    0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7,
    0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
    0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7,
    0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF,
  ];

  // ---- language ----

  static const Map<String, List<String>> _stopWords = {
    'eng': ['the', 'and', 'of', 'to', 'in', 'that', 'it', 'was', 'he', //
      'for', 'with', 'his', 'is', 'you'],
    'hun': ['a', 'az', 'és', 'hogy', 'nem', 'is', 'egy', 'meg', 'de', //
      'ez', 'csak', 'már', 'volt', 'még'],
    'deu': ['der', 'die', 'und', 'das', 'nicht', 'ist', 'zu', 'den', //
      'sie', 'es', 'ein', 'ich', 'mit'],
  };

  static final RegExp _word = RegExp(r'\p{L}+', unicode: true);

  /// Calibre language code (eng/hun/deu) from the most common short
  /// words of the first part of [text], or null if unsure.
  static String? language(String text) {
    final sample = text.length > 20000 ? text.substring(0, 20000) : text;
    final counts = <String, int>{};
    var total = 0;
    for (final m in _word.allMatches(sample.toLowerCase())) {
      counts.update(m.group(0)!, (c) => c + 1, ifAbsent: () => 1);
      total++;
    }
    if (total < 50) return null;
    String? best;
    var bestHits = 0;
    _stopWords.forEach((lang, words) {
      final hits = words.fold<int>(0, (sum, w) => sum + (counts[w] ?? 0));
      if (hits > bestHits) {
        best = lang;
        bestHits = hits;
      }
    });
    return bestHits >= total * 0.08 ? best : null;
  }

  // ---- Project Gutenberg ----

  static final RegExp _gutenbergStart = RegExp(
      r'^\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG.*$',
      multiLine: true,
      caseSensitive: false);
  static final RegExp _gutenbergEnd = RegExp(
      r'^\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG.*$',
      multiLine: true,
      caseSensitive: false);

  /// [text] without Project Gutenberg's licence header and footer.
  static String stripGutenberg(String text) {
    var t = text;
    final start = _gutenbergStart.firstMatch(t);
    if (start != null) t = t.substring(start.end);
    final end = _gutenbergEnd.firstMatch(t);
    if (end != null) t = t.substring(0, end.start);
    return t;
  }
}
