import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../book_metadata.dart';
import '../calibre.dart';

/// Reads the metadata stored inside a PDF without rendering it: the
/// document information dictionary (/Info: Title, Author, Subject,
/// Keywords) and the XMP packet (/Metadata - also where Calibre writes
/// series, rating, identifiers, ...). XMP wins over /Info, as in Calibre.
///
/// Pure Dart (dart:io's zlib for compressed object streams), so it can run
/// in an isolate. Page count and cover come from pdfrx instead, see
/// PdfMetadataReader.
BookMetadata parsePdfMetadata(Uint8List bytes) {
  final pdf = _RawPdf(bytes);
  final info = pdf.info();
  final xmpText = pdf.xmp();
  final xmp = xmpText == null ? null : _Xmp.parse(xmpText);

  String infoText(String key) => _clean(info[key] ?? '');

  final infoTitle = infoText('Title');
  final title = _usableTitle(xmp?.title ?? '') ?? _usableTitle(infoTitle) ?? '';

  var authors = xmp?.creators ?? const <String>[];
  if (authors.isEmpty) authors = Calibre.stringToAuthors(infoText('Author'));

  var tags = xmp?.subjects ?? const <String>[];
  if (tags.isEmpty) {
    tags = infoText('Keywords')
        .split(RegExp('[,;]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  final xmpDescription = xmp?.description ?? '';
  final description =
      xmpDescription.isNotEmpty ? xmpDescription : infoText('Subject');

  return BookMetadata(
    title: title,
    titleSort: xmp?.titleSort ?? '',
    authors: authors,
    authorSort: xmp?.authorSort ?? '',
    publisher: xmp?.publisher ?? '',
    pubdate: xmp?.date,
    description: description,
    series: xmp?.series ?? '',
    seriesIndex: xmp?.seriesIndex,
    tags: tags,
    languages: xmp?.languages ?? const [],
    identifiers: xmp?.identifiers ?? const {},
    rating: xmp?.rating,
    format: 'PDF',
  );
}

String _clean(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Null for titles that are really file names or placeholders
/// ("Microsoft Word - thesis.docx", "untitled") - the file name is better.
String? _usableTitle(String title) {
  final t = _clean(title);
  if (t.isEmpty) return null;
  final lower = t.toLowerCase();
  if (lower == 'untitled' || lower.startsWith('microsoft word - ')) return null;
  if (RegExp(r'\.(docx?|odt|rtf|txt|pdf|indd|qxd|tex|dvi|ps|pages)$')
      .hasMatch(lower)) {
    return null;
  }
  return t;
}

// ===========================================================================
// Raw PDF access: just enough of the file structure to find /Info and the
// catalog's /Metadata stream, including PDF 1.5+ files that keep objects in
// compressed object streams.
// ===========================================================================

class _Ref {
  const _Ref(this.number, this.generation);
  final int number;
  final int generation;
}

class _Name {
  const _Name(this.value);
  final String value;
}

class _Stream {
  _Stream(this.dict, this.data);
  final Map<String, Object?> dict;
  final Uint8List data;

  /// Data with /FlateDecode undone; null for other filters.
  Uint8List? decoded() {
    final filter = dict['Filter'];
    final filters = filter is List ? filter : [if (filter != null) filter];
    if (filters.isEmpty) return data;
    if (filters.length == 1 &&
        filters.first is _Name &&
        (filters.first as _Name).value == 'FlateDecode') {
      try {
        return Uint8List.fromList(zlib.decode(data));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class _RawPdf {
  _RawPdf(this.bytes) : source = latin1.decode(bytes);

  final Uint8List bytes;

  /// The file as a String with one char per byte, for regex searches.
  final String source;

  late final bool encrypted =
      RegExp(r'/Encrypt\s*(\d+\s+\d+\s+R|<<)').hasMatch(source);

  Map<String, Object?>? _objectStreamCache;

  /// Text values of the document information dictionary.
  Map<String, String> info() {
    if (encrypted) return const {}; // its strings are encrypted
    final ref = _lastRef('Info');
    if (ref == null) return const {};
    final dict = _resolve(ref);
    if (dict is! Map<String, Object?>) return const {};
    final result = <String, String>{};
    for (final entry in dict.entries) {
      final value = _resolve(entry.value);
      if (value is Uint8List) result[entry.key] = _pdfText(value);
    }
    return result;
  }

  /// The XMP packet, if any.
  String? xmp() {
    // The catalog's /Metadata stream (uncompressed or Flate).
    if (!encrypted) {
      final rootRef = _lastRef('Root');
      final root = rootRef == null ? null : _resolve(rootRef);
      if (root is Map<String, Object?>) {
        final stream = _resolve(root['Metadata']);
        if (stream is _Stream) {
          final data = stream.decoded();
          if (data != null) {
            final text = utf8.decode(data, allowMalformed: true);
            if (text.contains('xmpmeta')) return _xmpPacket(text);
          }
        }
      }
    }
    // Fallback: an uncompressed packet anywhere (the last one wins - later
    // incremental updates come last).
    final start = source.lastIndexOf('<x:xmpmeta');
    if (start < 0) return null;
    final end = source.indexOf('</x:xmpmeta>', start);
    if (end < 0) return null;
    final raw = bytes.sublist(start, end + '</x:xmpmeta>'.length);
    return utf8.decode(raw, allowMalformed: true);
  }

  static String _xmpPacket(String text) {
    final start = text.indexOf('<x:xmpmeta');
    final end = text.lastIndexOf('</x:xmpmeta>');
    if (start < 0 || end < start) return text;
    return text.substring(start, end + '</x:xmpmeta>'.length);
  }

  /// The last `/Key N G R` in a trailer (or cross-reference stream).
  _Ref? _lastRef(String key) {
    final matches =
        RegExp('/$key\\s+(\\d+)\\s+(\\d+)\\s+R').allMatches(source).toList();
    if (matches.isEmpty) return null;
    final m = matches.last;
    return _Ref(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// Follows references (one level is enough for metadata).
  Object? _resolve(Object? value, [int depth = 0]) {
    if (value is! _Ref || depth > 5) return value;
    return _resolve(_object(value.number, value.generation), depth + 1);
  }

  /// Object N G: the last "N G obj" in the file (later updates win), or
  /// from a compressed object stream.
  Object? _object(int number, int generation) {
    final matches = RegExp('(?:^|[^0-9])$number\\s+$generation\\s+obj\\b')
        .allMatches(source)
        .toList();
    if (matches.isNotEmpty) {
      final parser = _Parser(bytes, source, matches.last.end);
      return parser.indirectObjectBody();
    }
    return _objectStreams()[number.toString()];
  }

  /// Every object stored in /Type /ObjStm streams, by object number.
  Map<String, Object?> _objectStreams() {
    final cached = _objectStreamCache;
    if (cached != null) return cached;
    final result = <String, Object?>{};
    final headers =
        RegExp(r'(?:^|[^0-9])\d+\s+\d+\s+obj\b').allMatches(source);
    for (final header in headers) {
      // Cheap filter before parsing: only objects that mention ObjStm.
      final peek = source.substring(
          header.end, min(header.end + 400, source.length));
      if (!peek.contains('ObjStm')) continue;
      final value = _Parser(bytes, source, header.end).indirectObjectBody();
      if (value is! _Stream) continue;
      final type = value.dict['Type'];
      if (type is! _Name || type.value != 'ObjStm') continue;
      final data = value.decoded();
      final count = value.dict['N'];
      final first = value.dict['First'];
      if (data == null || count is! num || first is! num) continue;
      final text = latin1.decode(data);
      final numbers = RegExp(r'\d+')
          .allMatches(text.substring(0, min(max(first.toInt(), 0), text.length)))
          .map((m) => int.parse(m.group(0)!))
          .toList();
      for (var i = 0; i + 1 < numbers.length && i ~/ 2 < count; i += 2) {
        final offset = first.toInt() + numbers[i + 1];
        if (offset >= data.length) continue;
        result.putIfAbsent(numbers[i].toString(),
            () => _Parser(data, text, offset).value());
      }
    }
    return _objectStreamCache = result;
  }
}

/// A small PDF object parser: dictionaries, arrays, names, strings,
/// numbers, references, booleans, null, and stream data.
class _Parser {
  _Parser(this.bytes, this.source, this.pos);

  final Uint8List bytes;
  final String source;
  int pos;

  static bool _isWhite(int c) =>
      c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0;
  static bool _isDelimiter(int c) => '()<>[]{}/%'.codeUnits.contains(c);

  int get _length => source.length;
  int _char(int i) => source.codeUnitAt(i);

  void _skipSpace() {
    while (pos < _length) {
      final c = _char(pos);
      if (_isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        // % comment
        while (pos < _length && _char(pos) != 0x0A && _char(pos) != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  String _token() {
    final start = pos;
    while (pos < _length &&
        !_isWhite(_char(pos)) &&
        !_isDelimiter(_char(pos))) {
      pos++;
    }
    return source.substring(start, pos);
  }

  /// The value after "N G obj", plus its stream data if it has one.
  Object? indirectObjectBody() {
    final v = value();
    if (v is! Map<String, Object?>) return v;
    _skipSpace();
    if (!source.startsWith('stream', pos)) return v;
    pos += 'stream'.length;
    if (pos < _length && _char(pos) == 0x0D) pos++;
    if (pos < _length && _char(pos) == 0x0A) pos++;
    final length = v['Length'];
    int end;
    if (length is num &&
        pos + length.toInt() <= _length &&
        source.startsWith(
            'endstream', _skipWhiteFrom(pos + length.toInt()))) {
      end = pos + length.toInt();
    } else {
      // Indirect or wrong /Length: up to "endstream".
      end = source.indexOf('endstream', pos);
      if (end < 0) return v;
      while (end > pos && _isWhite(_char(end - 1))) {
        end--;
      }
    }
    return _Stream(v, Uint8List.sublistView(bytes, pos, end));
  }

  int _skipWhiteFrom(int i) {
    while (i < _length && _isWhite(_char(i))) {
      i++;
    }
    return i;
  }

  Object? value() {
    _skipSpace();
    if (pos >= _length) return null;
    final c = _char(pos);
    if (c == 0x3C && pos + 1 < _length && _char(pos + 1) == 0x3C) {
      return _dictionary();
    }
    if (c == 0x3C) return _hexString();
    if (c == 0x28) return _literalString();
    if (c == 0x2F) {
      pos++;
      return _Name(_decodeName(_token()));
    }
    if (c == 0x5B) return _array();
    final token = _token();
    if (token.isEmpty) {
      pos++; // unexpected delimiter: skip it
      return null;
    }
    if (token == 'true') return true;
    if (token == 'false') return false;
    if (token == 'null') return null;
    final number = num.tryParse(token);
    if (number == null) return _Name(token); // operator/keyword
    // "N G R" reference?
    if (number is int) {
      final save = pos;
      _skipSpace();
      final generation = int.tryParse(_token());
      if (generation != null) {
        _skipSpace();
        if (pos < _length && _char(pos) == 0x52 /* R */ &&
            (pos + 1 >= _length ||
                _isWhite(_char(pos + 1)) ||
                _isDelimiter(_char(pos + 1)))) {
          pos++;
          return _Ref(number, generation);
        }
      }
      pos = save;
    }
    return number;
  }

  Map<String, Object?> _dictionary() {
    pos += 2;
    final result = <String, Object?>{};
    while (true) {
      _skipSpace();
      if (pos >= _length) break;
      if (_char(pos) == 0x3E && pos + 1 < _length && _char(pos + 1) == 0x3E) {
        pos += 2;
        break;
      }
      final key = value();
      if (key is! _Name) {
        if (pos >= _length) break;
        continue;
      }
      result[key.value] = value();
    }
    return result;
  }

  List<Object?> _array() {
    pos++;
    final result = <Object?>[];
    while (true) {
      _skipSpace();
      if (pos >= _length) break;
      if (_char(pos) == 0x5D) {
        pos++;
        break;
      }
      result.add(value());
    }
    return result;
  }

  Uint8List _hexString() {
    pos++;
    final digits = StringBuffer();
    while (pos < _length && _char(pos) != 0x3E) {
      final ch = source[pos];
      if (RegExp(r'[0-9A-Fa-f]').hasMatch(ch)) digits.write(ch);
      pos++;
    }
    pos++; // '>'
    var hex = digits.toString();
    if (hex.length.isOdd) hex += '0';
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  Uint8List _literalString() {
    pos++;
    final out = <int>[];
    var depth = 1;
    while (pos < _length) {
      final c = _char(pos++);
      if (c == 0x5C /* \ */) {
        if (pos >= _length) break;
        final e = _char(pos++);
        switch (e) {
          case 0x6E: out.add(0x0A); // \n
          case 0x72: out.add(0x0D); // \r
          case 0x74: out.add(0x09); // \t
          case 0x62: out.add(0x08); // \b
          case 0x66: out.add(0x0C); // \f
          case 0x0D: // line continuation
            if (pos < _length && _char(pos) == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var octal = e - 0x30;
              for (var k = 0; k < 2 && pos < _length; k++) {
                final d = _char(pos);
                if (d < 0x30 || d > 0x37) break;
                octal = octal * 8 + (d - 0x30);
                pos++;
              }
              out.add(octal & 0xFF);
            } else {
              out.add(e); // \( \) \\ and unknown escapes
            }
        }
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29) {
        depth--;
        if (depth == 0) break;
      }
      out.add(c);
    }
    return Uint8List.fromList(out);
  }

  static String _decodeName(String raw) => raw.replaceAllMapped(
      RegExp(r'#([0-9A-Fa-f]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
}

/// Decodes a PDF text string: UTF-16BE (with BOM), UTF-8 (with BOM, or
/// valid non-ASCII UTF-8 as some producers write), else PDFDocEncoding.
String _pdfText(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final units = <int>[
      for (var i = 2; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1],
    ];
    return String.fromCharCodes(units).replaceAll('\u0000', '');
  }
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  if (b.any((x) => x >= 0x80)) {
    try {
      return utf8.decode(b);
    } on FormatException {
      // not UTF-8 -> PDFDocEncoding below
    }
  }
  return String.fromCharCodes(b.map((x) => _pdfDocEncoding[x] ?? x));
}

/// PDFDocEncoding characters that differ from Latin-1.
const Map<int, int> _pdfDocEncoding = {
  0x80: 0x2022, 0x81: 0x2020, 0x82: 0x2021, 0x83: 0x2026, 0x84: 0x2014, //
  0x85: 0x2013, 0x86: 0x0192, 0x87: 0x2044, 0x88: 0x2039, 0x89: 0x203A,
  0x8A: 0x2212, 0x8B: 0x2030, 0x8C: 0x201E, 0x8D: 0x201C, 0x8E: 0x201D,
  0x8F: 0x2018, 0x90: 0x2019, 0x91: 0x201A, 0x92: 0x2122, 0x93: 0xFB01,
  0x94: 0xFB02, 0x95: 0x0141, 0x96: 0x0152, 0x97: 0x0160, 0x98: 0x0178,
  0x99: 0x017D, 0x9A: 0x0131, 0x9B: 0x0142, 0x9C: 0x0153, 0x9D: 0x0161,
  0x9E: 0x017E, 0xA0: 0x20AC,
};

// ===========================================================================
// XMP
// ===========================================================================

class _Xmp {
  _Xmp({
    this.title,
    this.creators = const [],
    this.description,
    this.subjects = const [],
    this.publisher,
    this.languages = const [],
    this.date,
    this.identifiers = const {},
    this.series,
    this.seriesIndex,
    this.rating,
    this.titleSort,
    this.authorSort,
  });

  final String? title;
  final List<String> creators;
  final String? description;
  final List<String> subjects;
  final String? publisher;
  final List<String> languages;
  final DateTime? date;
  final Map<String, String> identifiers;
  final String? series;
  final double? seriesIndex;
  final int? rating;
  final String? titleSort;
  final String? authorSort;

  static const _dc = 'http://purl.org/dc/elements/1.1/';
  static const _rdf = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
  static const _xmp = 'http://ns.adobe.com/xap/1.0/';
  static const _pdf = 'http://ns.adobe.com/pdf/1.3/';
  static const _prism = 'http://prismstandard.org/namespaces/basic/2.0/';
  static const _xmpidq = 'http://ns.adobe.com/xmp/Identifier/qual/1.0/';
  static const _calibre = 'http://calibre-ebook.com/xmp-namespace';
  static const _calibreSI =
      'http://calibre-ebook.com/xmp-namespace-series-index';

  static _Xmp? parse(String packet) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(packet);
    } on XmlException {
      return null;
    }

    XmlElement? element(String ns, String name) =>
        doc.findAllElements(name, namespace: ns).firstOrNull;

    // rdf:li values (Alt/Seq/Bag), or the element's own text.
    List<String> values(XmlElement? e) {
      if (e == null) return const [];
      final items = e.findAllElements('li', namespace: _rdf).toList();
      if (items.isEmpty) {
        final t = _clean(e.innerText);
        return t.isEmpty ? const [] : [t];
      }
      // Language alternatives: x-default first.
      items.sort((a, b) {
        int rank(XmlElement li) =>
            li.getAttribute('xml:lang') == 'x-default' ? 0 : 1;
        return rank(a) - rank(b);
      });
      return [
        for (final li in items)
          if (_clean(li.innerText).isNotEmpty) _clean(li.innerText),
      ];
    }

    // A simple property, written as an element or as an attribute of
    // rdf:Description.
    String? simple(String ns, String name) {
      final v = values(element(ns, name)).firstOrNull;
      if (v != null) return v;
      for (final d in doc.findAllElements('Description', namespace: _rdf)) {
        final a = d.getAttribute(name, namespace: ns);
        if (a != null && _clean(a).isNotEmpty) return _clean(a);
      }
      return null;
    }

    final keywords = simple(_pdf, 'Keywords');
    var subjects = values(element(_dc, 'subject'));
    if (subjects.isEmpty && keywords != null) {
      subjects = keywords
          .split(RegExp('[,;]'))
          .map((k) => k.trim())
          .where((k) => k.isNotEmpty)
          .toList();
    }

    final identifiers = <String, String>{};
    // Calibre: <xmp:Identifier><rdf:Bag><rdf:li rdf:parseType="Resource">
    //   <xmpidq:Scheme>isbn</xmpidq:Scheme><rdf:value>...</rdf:value>
    for (final li in element(_xmp, 'Identifier')
            ?.findAllElements('li', namespace: _rdf) ??
        const <XmlElement>[]) {
      final scheme = li.findAllElements('Scheme', namespace: _xmpidq).firstOrNull;
      final value = li.findAllElements('value', namespace: _rdf).firstOrNull;
      final entry = Calibre.identifier(
          scheme?.innerText, value?.innerText ?? li.innerText);
      if (entry != null) identifiers.putIfAbsent(entry.key, () => entry.value);
    }
    for (final isbn in [simple(_prism, 'isbn'), simple(_prism, 'eIsbn')]) {
      final checked = isbn == null ? null : Calibre.checkIsbn(isbn);
      if (checked != null) identifiers.putIfAbsent('isbn', () => checked);
    }

    // Calibre: <calibre:series rdf:parseType="Resource"><rdf:value>Name
    //   </rdf:value><calibreSI:series_index>2</calibreSI:series_index>
    final seriesElement = element(_calibre, 'series');
    String? series;
    double? seriesIndex;
    if (seriesElement != null) {
      final value =
          seriesElement.findAllElements('value', namespace: _rdf).firstOrNull;
      series = _clean((value ?? seriesElement).innerText);
      seriesIndex = double.tryParse(_clean(seriesElement
              .findAllElements('series_index', namespace: _calibreSI)
              .firstOrNull
              ?.innerText ??
          ''));
      if (series.isEmpty) series = null;
    }

    final rating = double.tryParse(simple(_calibre, 'rating') ?? '');
    final dateText = values(element(_dc, 'date')).firstOrNull ??
        simple(_prism, 'publicationDate');

    final creators = <String>[
      for (final c in values(element(_dc, 'creator')))
        ...Calibre.stringToAuthors(c),
    ];

    return _Xmp(
      title: values(element(_dc, 'title')).firstOrNull,
      creators: creators,
      description: values(element(_dc, 'description')).firstOrNull,
      subjects: subjects,
      publisher: values(element(_dc, 'publisher')).firstOrNull,
      languages: [
        for (final l in values(element(_dc, 'language')))
          if (Calibre.languageCode(l) case final code?) code,
      ],
      date: dateText == null ? null : Calibre.parseDate(dateText),
      identifiers: identifiers,
      series: series,
      seriesIndex: series == null ? null : seriesIndex,
      rating: rating == null || rating <= 0
          ? null
          : rating.round().clamp(0, 10).toInt(),
      titleSort: simple(_calibre, 'title_sort'),
      authorSort: simple(_calibre, 'author_sort'),
    );
  }
}
