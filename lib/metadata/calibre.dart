import 'dart:math' show min;

import 'package:remove_diacritic/remove_diacritic.dart';

/// Calibre's own rules for the values it stores in metadata.db and for the
/// names of the folders/files in a library - ported from Calibre's Python
/// sources (ebooks/metadata/__init__.py, db/backend.py, utils/filenames.py)
/// so books added here look exactly like books added by Calibre.
class Calibre {
  Calibre._();

  /// What Calibre stores when a book has no author / title.
  static const String unknown = 'Unknown';

  /// Calibre's "no date" value (books.pubdate of a book without a date).
  static const String undefinedDate = '0101-01-01 00:00:00+00:00';

  // ---------------------------------------------------------------------
  // Dates
  // ---------------------------------------------------------------------

  /// A timestamp the way Calibre writes it: UTC, `+00:00`, microseconds
  /// only when non-zero - `2026-10-03 13:13:37.697500+00:00`.
  static String formatTimestamp(DateTime time) {
    final t = time.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final base = '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-'
        '${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    final micro = t.millisecond * 1000 + t.microsecond;
    return micro == 0
        ? '$base+00:00'
        : '$base.${micro.toString().padLeft(6, '0')}+00:00';
  }

  /// [formatTimestamp] for the current moment.
  static String now() => formatTimestamp(DateTime.now());

  /// Parses a date found in a book file (OPF `dc:date`, XMP `xmp:CreateDate`
  /// ...): `2015`, `2015-03`, `2015-03-26`, or a full ISO 8601 date-time.
  /// A date without a time is local midnight, as in Calibre. Returns null
  /// if [raw] is not a date.
  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    final dateOnly = RegExp(r'^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$').firstMatch(s);
    if (dateOnly != null) {
      final year = int.parse(dateOnly.group(1)!);
      final month = int.tryParse(dateOnly.group(2) ?? '') ?? 1;
      final day = int.tryParse(dateOnly.group(3) ?? '') ?? 1;
      if (year < 101 || month < 1 || month > 12 || day < 1 || day > 31) {
        return null;
      }
      return DateTime(year, month, day);
    }
    final parsed = DateTime.tryParse(s);
    if (parsed == null || parsed.year < 101) return null;
    return parsed;
  }

  // ---------------------------------------------------------------------
  // Sorting
  // ---------------------------------------------------------------------

  /// Leading articles moved to the end by [titleSort], per language
  /// (Calibre's `per_language_title_sort_articles` tweak, shortened).
  static const Map<String, List<String>> _articles = {
    'eng': ['A', 'The', 'An'],
    'hun': ['A', 'Az', 'Egy'],
    'deu': [
      'Der', 'Die', 'Das', 'Den', 'Ein', 'Eine', //
      'Einen', 'Dem', 'Des', 'Einem', 'Eines',
    ],
    'fra': ['Le', 'La', 'Les', 'Un', 'Une', 'Des', 'De La', 'De'],
    'spa': ['El', 'La', 'Lo', 'Los', 'Las', 'Un', 'Una', 'Unos', 'Unas'],
    'ita': ['Lo', 'Il', 'La', 'I', 'Gli', 'Le', 'Uno', 'Una', 'Un'],
    'por': ['A', 'O', 'Os', 'As', 'Um', 'Uns', 'Uma', 'Umas'],
    'nld': ['De', 'Het', 'Een', 'Den', 'Der', 'Des'],
    'swe': ['En', 'Ett', 'Det', 'Den', 'De'],
  };

  /// Elided articles (no space after them): L'Etranger -> Etranger, L'
  static const Map<String, List<String>> _elidedArticles = {
    'fra': ["L'", 'L\u2019', "D'", 'D\u2019'],
    'ita': ["L'", 'L\u2019', "Un'", 'Un\u2019'],
  };

  /// Quote characters Calibre skips at the start of a title.
  static final RegExp _ignoreStarts = RegExp('^[\'"\u2018-\u201F]');

  /// Calibre's title_sort(): "A Crown of Ruin" -> "Crown of Ruin, A".
  /// English articles are always recognised, plus those of the book's
  /// [languages] (Calibre 3-letter codes, e.g. `hun`).
  static String titleSort(String title, {List<String> languages = const []}) {
    var t = title.trim();
    if (t.isNotEmpty && _ignoreStarts.hasMatch(t)) t = t.substring(1);
    final spaced = <String>{..._articles['eng']!};
    final elided = <String>{};
    for (final lang in languages) {
      spaced.addAll(_articles[lang] ?? const []);
      elided.addAll(_elidedArticles[lang] ?? const []);
    }
    final alternatives = [
      ...spaced.map((a) => '${RegExp.escape(a)}\\s+'),
      ...elided.map(RegExp.escape),
    ];
    final match = RegExp('^(${alternatives.join('|')})', caseSensitive: false)
        .firstMatch(t);
    if (match != null) {
      final prep = match.group(1)!;
      t = '${t.substring(prep.length)}, $prep';
      if (t.isNotEmpty && _ignoreStarts.hasMatch(t)) t = t.substring(1);
    }
    return t.trim();
  }

  static const _namePrefixes = ['mr', 'mrs', 'ms', 'dr', 'prof'];
  static const _nameSuffixes = [
    'jr', 'sr', 'inc', 'ph.d', 'phd', 'md', 'm.d', //
    'i', 'ii', 'iii', 'iv', 'junior', 'senior',
  ];
  static const _copyWords = [
    'agency', 'corporation', 'company', 'co.', 'council', 'committee', //
    'inc.', 'institute', 'national', 'society', 'club', 'team',
    'software', 'games', 'entertainment', 'media', 'studios',
  ];

  /// Calibre's author_to_author_sort() with its default "invert" method:
  /// "Jennifer L. Armentrout" -> "Armentrout, Jennifer L.",
  /// "Martin Luther King Jr." -> "King, Martin Luther Jr.".
  static String authorSort(String author) {
    if (author.trim().isEmpty) return '';
    final stripped = author
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|\{[^}]*\}'), '')
        .trim();
    final tokens = stripped.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2) return author;
    final lower = tokens.map((t) => t.toLowerCase()).toSet();
    if (lower.any(_copyWords.contains)) return author;

    final prefixes = {..._namePrefixes, ..._namePrefixes.map((p) => '$p.')};
    final suffixes = {..._nameSuffixes, ..._nameSuffixes.map((s) => '$s.')};

    var first = 0;
    while (first < tokens.length && prefixes.contains(tokens[first].toLowerCase())) {
      first++;
    }
    if (first == tokens.length) return author;
    var last = tokens.length - 1;
    while (last >= first && suffixes.contains(tokens[last].toLowerCase())) {
      last--;
    }
    if (last < first) return author;

    final suffix = tokens.sublist(last + 1).join(' ');
    final sorted = [tokens[last], ...tokens.sublist(first, last)];
    final count = sorted.length;
    if (suffix.isNotEmpty) sorted.add(suffix);
    if (count > 1) sorted[0] = '${sorted[0]},';
    return sorted.join(' ');
  }

  /// Calibre's string_to_authors(): splits "A & B", "A and B", "A, with B".
  /// "&&" stands for a literal "&" inside a name.
  static List<String> stringToAuthors(String raw) {
    if (raw.trim().isEmpty) return const [];
    var s = raw.replaceAll('&&', '\uFFFF');
    s = s.replaceAll(RegExp(r',?\s+(and|with)\s+', caseSensitive: false), '&');
    return s
        .split('&')
        .map((a) => a.trim().replaceAll('\uFFFF', '&'))
        .where((a) => a.isNotEmpty)
        .toList();
  }

  // ---------------------------------------------------------------------
  // Languages
  // ---------------------------------------------------------------------

  static const Map<String, String> _iso639_1 = {
    'af': 'afr', 'ar': 'ara', 'be': 'bel', 'bg': 'bul', 'bn': 'ben', //
    'bs': 'bos', 'ca': 'cat', 'cs': 'ces', 'cy': 'cym', 'da': 'dan',
    'de': 'deu', 'el': 'ell', 'en': 'eng', 'eo': 'epo', 'es': 'spa',
    'et': 'est', 'eu': 'eus', 'fa': 'fas', 'fi': 'fin', 'fr': 'fra',
    'ga': 'gle', 'gl': 'glg', 'gu': 'guj', 'he': 'heb', 'hi': 'hin',
    'hr': 'hrv', 'hu': 'hun', 'hy': 'hye', 'id': 'ind', 'is': 'isl',
    'it': 'ita', 'ja': 'jpn', 'ka': 'kat', 'kk': 'kaz', 'ko': 'kor',
    'la': 'lat', 'lt': 'lit', 'lv': 'lav', 'mk': 'mkd', 'ml': 'mal',
    'mn': 'mon', 'mr': 'mar', 'ms': 'msa', 'mt': 'mlt', 'nb': 'nob',
    'nl': 'nld', 'nn': 'nno', 'no': 'nor', 'pa': 'pan', 'pl': 'pol',
    'pt': 'por', 'ro': 'ron', 'ru': 'rus', 'sk': 'slk', 'sl': 'slv',
    'sq': 'sqi', 'sr': 'srp', 'sv': 'swe', 'sw': 'swa', 'ta': 'tam',
    'te': 'tel', 'th': 'tha', 'tr': 'tur', 'uk': 'ukr', 'ur': 'urd',
    'uz': 'uzb', 'vi': 'vie', 'yi': 'yid', 'zh': 'zho',
  };

  /// ISO 639-2/B codes -> the 639-2/T (639-3) codes Calibre uses.
  static const Map<String, String> _bibliographic = {
    'alb': 'sqi', 'arm': 'hye', 'baq': 'eus', 'bur': 'mya', 'chi': 'zho', //
    'cze': 'ces', 'dut': 'nld', 'fre': 'fra', 'geo': 'kat', 'ger': 'deu',
    'gre': 'ell', 'ice': 'isl', 'mac': 'mkd', 'may': 'msa', 'per': 'fas',
    'rum': 'ron', 'slo': 'slk', 'tib': 'bod', 'wel': 'cym',
  };

  static const Map<String, String> _languageNames = {
    'english': 'eng', 'hungarian': 'hun', 'magyar': 'hun', 'german': 'deu', //
    'deutsch': 'deu', 'french': 'fra', 'spanish': 'spa', 'italian': 'ita',
    'portuguese': 'por', 'dutch': 'nld', 'russian': 'rus', 'polish': 'pol',
    'czech': 'ces', 'slovak': 'slk', 'romanian': 'ron', 'swedish': 'swe',
    'japanese': 'jpn', 'chinese': 'zho',
  };

  static const Map<String, String> _englishNames = {
    'eng': 'English', 'hun': 'Hungarian', 'deu': 'German', 'fra': 'French', //
    'spa': 'Spanish', 'ita': 'Italian', 'por': 'Portuguese', 'nld': 'Dutch',
    'rus': 'Russian', 'pol': 'Polish', 'ces': 'Czech', 'slk': 'Slovak',
    'ron': 'Romanian', 'swe': 'Swedish', 'nor': 'Norwegian', 'dan': 'Danish',
    'fin': 'Finnish', 'ell': 'Greek', 'tur': 'Turkish', 'ukr': 'Ukrainian',
    'hrv': 'Croatian', 'srp': 'Serbian', 'slv': 'Slovenian', 'bul': 'Bulgarian',
    'lat': 'Latin', 'jpn': 'Japanese', 'zho': 'Chinese', 'kor': 'Korean',
    'ara': 'Arabic', 'heb': 'Hebrew', 'hin': 'Hindi', 'epo': 'Esperanto',
  };

  /// Display name of a Calibre language code (English, like Calibre's
  /// English UI); the code itself if unknown.
  static String languageName(String code) => _englishNames[code] ?? code;

  /// A language as Calibre stores it in `languages.lang_code`: `en`,
  /// `en-US`, `eng`, `ger`, `English` -> `eng`/`deu`. Null for "undefined"
  /// codes (und, mul, zxx) and anything unrecognised.
  static String? languageCode(String raw) {
    final s = raw.trim().toLowerCase().replaceAll('_', '-');
    if (s.isEmpty) return null;
    if (_languageNames.containsKey(s)) return _languageNames[s];
    final code = s.split('-').first;
    if (const {'und', 'mul', 'zxx', 'mis'}.contains(code)) return null;
    if (code.length == 2) return _iso639_1[code];
    if (code.length == 3 && RegExp(r'^[a-z]{3}$').hasMatch(code)) {
      return _bibliographic[code] ?? code;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Identifiers
  // ---------------------------------------------------------------------

  /// A valid ISBN-10/13 (digits only, `X` allowed as ISBN-10 check digit),
  /// or null - like Calibre's check_isbn().
  static String? checkIsbn(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (s.length == 10) {
      var sum = 0;
      for (var i = 0; i < 10; i++) {
        final c = s[i];
        final v = c == 'X' ? (i == 9 ? 10 : -1) : int.parse(c);
        if (v < 0) return null;
        sum += v * (10 - i);
      }
      return sum % 11 == 0 ? s : null;
    }
    if (s.length == 13 && !s.contains('X')) {
      var sum = 0;
      for (var i = 0; i < 13; i++) {
        sum += int.parse(s[i]) * (i.isEven ? 1 : 3);
      }
      return sum % 10 == 0 ? s : null;
    }
    return null;
  }

  /// Turns an identifier found in a book file into Calibre's
  /// (type, value) form, e.g. `urn:isbn:978...` -> (isbn, 978...),
  /// scheme "MOBI-ASIN" -> (mobi-asin, ...). Returns null for identifiers
  /// Calibre doesn't keep in its identifiers table (its own uuid/book id,
  /// URLs, invalid ISBNs).
  static MapEntry<String, String>? identifier(String? scheme, String value) {
    var v = value.trim();
    var type = scheme?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return null;

    if (type.isEmpty) {
      final lower = v.toLowerCase();
      if (lower.startsWith('urn:')) {
        final parts = v.split(':');
        if (parts.length < 3) return null;
        type = parts[1].toLowerCase();
        v = parts.sublist(2).join(':');
      } else if (lower.startsWith('http:') || lower.startsWith('https:')) {
        return null;
      } else {
        final m = RegExp(r'^([a-z][a-z0-9_-]*):\s*(\S.*)$', caseSensitive: false)
            .firstMatch(v);
        if (m != null) {
          type = m.group(1)!.toLowerCase();
          v = m.group(2)!.trim();
        } else if (checkIsbn(v) != null) {
          type = 'isbn';
        } else {
          return null;
        }
      }
    }

    if (type == 'uuid' || type == 'calibre') return null;
    if (type == 'isbn') {
      final isbn = checkIsbn(v);
      return isbn == null ? null : MapEntry('isbn', isbn);
    }
    // Calibre forbids ':' and ',' in the type and ',' in the value.
    type = type.replaceAll(RegExp('[:,]'), '');
    v = v.replaceAll(',', '|');
    if (type.isEmpty || v.isEmpty) return null;
    return MapEntry(type, v);
  }

  // ---------------------------------------------------------------------
  // Library folder / file names
  // ---------------------------------------------------------------------

  /// Calibre's PATH_LIMIT on Windows. Calibre uses 100 on other systems,
  /// but the shorter limit keeps a library usable when it is shared with
  /// Calibre on Windows.
  static const int _pathLimit = 40;

  static const Set<String> _windowsReservedNames = {
    'CON', 'PRN', 'AUX', 'NUL', //
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Calibre's ascii_filename(): accents removed, characters that are not
  /// allowed in file names replaced with `_`.
  static String asciiFileName(String name) {
    final ascii = removeDiacritics(name)
        .replaceAll(RegExp(r'[^\x20-\x7e]'), '_')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var s = ascii.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll('..', '_');
    if (RegExp(r'^\.+$').hasMatch(s)) s = '_';
    if (s.isNotEmpty && (s.endsWith('.') || s.endsWith(' '))) {
      s = '${s.substring(0, s.length - 1)}_';
    }
    if (s.startsWith('.')) s = '_${s.substring(1)}';
    return s;
  }

  static String _cut(String s, int limit) =>
      s.substring(0, min(s.length, limit < 0 ? 0 : limit));

  /// `books.path` for a new book, exactly as Calibre builds it
  /// (construct_path_name): `Jennifer L. Armentrout/A Crown of Ruin (1)`.
  /// [author] is the book's first author.
  static String bookFolder(int bookId, String title, String author) {
    final idPart = ' ($bookId)';
    final limit = _pathLimit - (idPart.length ~/ 2) - 2;
    var a = _cut(asciiFileName(author), limit);
    var t = _cut(asciiFileName(title.trimLeft()), limit).trimRight();
    if (t.isEmpty) t = _cut(unknown, limit);
    while (a.isNotEmpty && (a.endsWith(' ') || a.endsWith('.'))) {
      a = a.substring(0, a.length - 1);
    }
    if (a.isEmpty) a = asciiFileName(unknown);
    if (_windowsReservedNames.contains(a.toUpperCase())) a = '${a}w';
    return '$a/$t$idPart';
  }

  /// `data.name` (file name without extension) for a new book, as Calibre
  /// builds it (construct_file_name): `A Crown of Ruin - Jennifer L. Armentrout`.
  static String bookFileName(String title, String author, String extension) {
    final extLength = extension.length + 1 < 14 ? 14 : extension.length + 1;
    final limit = _pathLimit - (extLength ~/ 2) - 2;
    final a = _cut(asciiFileName(author), limit);
    var t = _cut(asciiFileName(title.trimLeft()), limit).trimRight();
    if (t.isEmpty) t = _cut(unknown, limit);
    var name = '$t - $a';
    while (name.endsWith('.')) {
      name = name.substring(0, name.length - 1);
    }
    return name.isEmpty ? asciiFileName(unknown) : name;
  }
}
