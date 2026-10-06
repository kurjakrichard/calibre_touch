import 'dart:typed_data';
import 'package:dart_mobi/dart_mobi.dart';
import 'package:html/parser.dart' as html_parser;
import '../metadata/readers/mobi_file.dart';
import 'utils.dart';

/// Thrown for DRM-protected MOBI/AZW books (the reader shows a message).
class MobiDrmException implements Exception {
  const MobiDrmException();

  @override
  String toString() => 'The book is DRM-protected';
}

/// Opens MOBI / AZW / AZW3 (KF8) / PRC books for the built-in reader by
/// turning them into an [EpubDocument] (sections + table of contents +
/// images), so the EPUB reader shows them unchanged.
///
/// `dart_mobi` decompresses the text and rebuilds the KF8 files; links and
/// images are resolved here, because `dart_mobi` 1.0.2 doesn't do it:
/// - KF8: one section per rebuilt file (`part0000.html`, ...);
///   `kindle:embed:XXXX` images and `kindle:pos:fid:XXXX:off:...` links.
/// - Old MOBI (KF7): one long HTML text, split into sections at
///   `<mbp:pagebreak>` (and very long parts at a paragraph);
///   `recindex="00001"` images and `filepos=123` links.
///
/// Pure Dart: call [MobiDocument.parse] through `compute`.
class MobiDocument {
  MobiDocument._();

  /// Formats this class opens (lower case). AZW4 (Print Replica, a PDF
  /// inside) is not one of them.
  static const extensions = {'mobi', 'azw', 'azw3', 'prc'};

  /// A KF7 part longer than this is split at a paragraph, so one huge
  /// "chapter" doesn't have to be laid out at once.
  static const int _maxSectionBytes = 200 * 1024;

  static String _href(int section) =>
      'part${section.toString().padLeft(4, '0')}.html';

  static String _imagePath(int number) => 'images/$number';

  /// Parses the bytes of a MOBI-family file. Throws [MobiDrmException] for
  /// DRM-protected books, [FormatException] if nothing readable is found.
  static Future<EpubDocument> parse(Uint8List bytes) async {
    final mobi = await MobiFile.parse(bytes);
    if (mobi.isEncrypted) throw const MobiDrmException();
    try {
      return _build(mobi);
    } catch (e) {
      // dart_mobi is a young port: if the KF8 part of a hybrid file fails,
      // the old KF7 copy of the text in the same file usually works.
      if (!mobi.isHybrid || !mobi.data.kf8) rethrow;
      mobi.useKf7();
      return _build(mobi);
    }
  }

  static EpubDocument _build(MobiFile mobi) {
    final rawml = _rawml(mobi);
    final markup = rawml.markup;
    if (markup == null || markup.data == null) {
      throw const FormatException('The book has no text');
    }
    if (markup.fileType == MobiFileType.pdf) {
      throw const FormatException('Print Replica (PDF) books are not supported');
    }
    final files = <String, Uint8List>{};
    final ncx = _parseNcx(mobi);

    final _Parts parts = (rawml.skel?.entriesCount ?? 0) > 0
        ? _kf8Parts(mobi, rawml, files, ncx)
        : _kf7Parts(mobi, markup.data!, files, ncx);
    if (parts.sections.isEmpty) {
      throw const FormatException('The book has no readable content');
    }

    var title = mobi.exthString(MobiFile.exthUpdatedTitle);
    if (title.isEmpty) title = mobi.fullName;
    return EpubDocument.fromParts(
      title: title,
      author: mobi.exthStrings(MobiFile.exthAuthor).join(' & '),
      sections: parts.sections,
      toc: parts.toc,
      files: files,
    );
  }

  /// The text of the book, KF8 files rebuilt from skeletons + fragments.
  ///
  /// Same as dart_mobi's `parseOpt(false, false, false)` minus
  /// `reconstructResources`: that one decodes every font/audio/video
  /// record, and its font decoder throws "Invalid obfuscated font data
  /// offsets" for every obfuscated (embedded) font - a porting bug
  /// (`dataOffset > xorKeyOffset` instead of libmobi's `> maxlen`). The
  /// reader doesn't need those resources; images are read directly from
  /// the records ([MobiFile.image]).
  static MobiRawml _rawml(MobiFile mobi) {
    final data = mobi.data;
    final header = data.mobiHeader;
    final textLength = data.record0header?.textLength ?? 0;
    final text = RawMlUtils.getRawml(data, textLength);

    final rawml = MobiRawml();
    final sectionCount = header?.fdstSectionCount ?? 0;
    final version = header?.version ?? 0;
    final fdstIndex = header?.fdstIndex;
    final lastTextIndex = header?.lastTextIndex;
    if (version > 3 &&
        sectionCount > 1 &&
        ((fdstIndex != null && fdstIndex != MobiFile.notSet) ||
            (lastTextIndex != null && lastTextIndex != 0xFFFF))) {
      rawml.fdst = DartMobiReader.readFdst(data);
    }
    RawMlUtils.reconstructFlow(rawml, text, text.length);

    final skeleton = header?.skeletonIndex;
    final fragment = header?.fragmentIndex;
    // Only KF8 has skeleton/fragment indexes (in older headers these
    // fields can hold other data).
    if (version >= 8 &&
        skeleton != null &&
        skeleton != MobiFile.notSet &&
        fragment != null &&
        fragment != MobiFile.notSet) {
      final offset = mobi.kf8Offset;
      final skel = MobiIndx();
      RawMlUtils.parseIndex(data, skel, skeleton + offset);
      rawml.skel = skel;
      final frag = MobiIndx();
      RawMlUtils.parseIndex(data, frag, fragment + offset);
      rawml.frag = frag;
    }
    RawMlUtils.reconstructParts(rawml);
    return rawml;
  }

  // ---------------------------------------------------------------------
  // KF8 (AZW3 / new .mobi)
  // ---------------------------------------------------------------------

  static final _embed = RegExp(
      r'''kindle:embed:([0-9A-Va-v]{4})(?:\?mime=[^"'\s>)]*)?''');
  static final _pos = RegExp(
      r'kindle:pos:fid:([0-9A-Va-v]{4}):off:([0-9A-Va-v]{10})');

  static _Parts _kf8Parts(MobiFile mobi, MobiRawml rawml,
      Map<String, Uint8List> files, MobiIndx? ncx) {
    // Section index of every rebuilt file (= skeleton number).
    final sectionOfFile = <int, int>{};
    final htmlParts = <MobiPart>[];
    for (MobiPart? part = rawml.markup; part != null; part = part.next) {
      if (part.fileType != MobiFileType.html || part.data == null) continue;
      sectionOfFile[part.uid] = htmlParts.length;
      htmlParts.add(part);
    }

    // kindle:pos:fid:XXXX -> fragment XXXX -> the file it belongs to.
    int? sectionOfFid(int fid) {
      final frag = rawml.frag;
      if (frag == null || fid < 0 || fid >= frag.entries.length) return null;
      final file = _tag(frag.entries[fid], 3);
      return file == null ? null : sectionOfFile[file];
    }

    final sections = <EpubSection>[];
    for (var i = 0; i < htmlParts.length; i++) {
      var text = mobi.decode(htmlParts[i].data!);
      text = text.replaceAllMapped(_embed, (m) {
        final number = MobiFile.base32(m.group(1)!);
        if (number == null) return m.group(0)!;
        _addImage(mobi, files, number);
        return _imagePath(number);
      });
      text = text.replaceAllMapped(_pos, (m) {
        final fid = MobiFile.base32(m.group(1)!);
        final section = fid == null ? null : sectionOfFid(fid);
        // Unknown target: keep it - the reader ignores links it can't
        // resolve.
        return section == null ? m.group(0)! : _href(section);
      });
      sections.add(EpubSection(href: _href(i), html: _body(text)));
    }

    final toc = <EpubTocEntry>[];
    if (ncx != null) {
      for (final entry in ncx.entries) {
        final label = _cncxString(mobi, ncx, _tag(entry, 3));
        final fid = _tag(entry, 6);
        final section = fid == null ? null : sectionOfFid(fid);
        if (label.isEmpty || section == null) continue;
        toc.add(EpubTocEntry(
          title: label,
          href: _href(section),
          sectionIndex: section,
          depth: _tag(entry, 4) ?? 0,
        ));
      }
    }
    return _Parts(sections, toc);
  }

  // ---------------------------------------------------------------------
  // KF7 (old .mobi / .azw / .prc)
  // ---------------------------------------------------------------------

  static final _filepos =
      RegExp(r'''\bfilepos\s*=\s*["']?0*(\d+)["']?''', caseSensitive: false);
  static final _recindex = RegExp(
      r'''\b(?:hi|lo)?recindex\s*=\s*["']?0*(\d+)["']?''',
      caseSensitive: false);

  static _Parts _kf7Parts(MobiFile mobi, Uint8List text,
      Map<String, Uint8List> files, MobiIndx? ncx) {
    final starts = _kf7SectionStarts(text);

    // Byte position in the text -> part.
    int partAt(int position) {
      var low = 0, high = starts.length - 1;
      while (low < high) {
        final mid = (low + high + 1) >> 1;
        if (starts[mid] <= position) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      return low;
    }

    // 1) Each part as HTML, with images. Parts that are only a page break
    //    are dropped; links into them go to the next part with content.
    final bodies = <String>[];
    final sectionOfPart = List<int>.filled(starts.length, 0);
    for (var i = 0; i < starts.length; i++) {
      final end = i + 1 < starts.length ? starts[i + 1] : text.length;
      var html = mobi.decode(Uint8List.sublistView(text, starts[i], end));
      html = html.replaceAllMapped(_recindex, (m) {
        final number = int.tryParse(m.group(1)!);
        if (number == null) return '';
        _addImage(mobi, files, number);
        return 'src="${_imagePath(number)}"';
      });
      final body = _body(html);
      sectionOfPart[i] = bodies.length;
      final empty =
          body.replaceAll(RegExp(r'<[^>]*>|\s|&nbsp;'), '').isEmpty &&
              !body.contains('<img');
      if (!empty) bodies.add(body);
    }
    if (bodies.isEmpty) return const _Parts([], []);
    int sectionAt(int position) =>
        sectionOfPart[partAt(position)].clamp(0, bodies.length - 1);

    // 2) filepos links -> the section that holds that position.
    final sections = <EpubSection>[
      for (var i = 0; i < bodies.length; i++)
        EpubSection(
          href: _href(i),
          html: bodies[i].replaceAllMapped(_filepos, (m) {
            final position = int.tryParse(m.group(1)!);
            if (position == null) return '';
            return 'href="${_href(sectionAt(position))}"';
          }),
        ),
    ];

    final toc = <EpubTocEntry>[];
    if (ncx != null) {
      for (final entry in ncx.entries) {
        final label = _cncxString(mobi, ncx, _tag(entry, 3));
        final position = _tag(entry, 1);
        if (label.isEmpty || position == null) continue;
        final section = sectionAt(position);
        toc.add(EpubTocEntry(
          title: label,
          href: _href(section),
          sectionIndex: section,
          depth: _tag(entry, 4) ?? 0,
        ));
      }
    }
    return _Parts(sections, toc);
  }

  /// Byte offsets where KF7 sections start: 0, every `<mbp:pagebreak`,
  /// plus paragraph starts inside very long parts.
  static List<int> _kf7SectionStarts(Uint8List text) {
    final breaks = <int>[0];
    const pagebreak = '<mbp:pagebreak';
    var from = 0;
    while (true) {
      final at = _indexOfIgnoreCase(text, pagebreak, from);
      if (at < 0) break;
      if (at > breaks.last) breaks.add(at);
      from = at + pagebreak.length;
    }

    final starts = <int>[];
    for (var i = 0; i < breaks.length; i++) {
      final end = i + 1 < breaks.length ? breaks[i + 1] : text.length;
      var start = breaks[i];
      starts.add(start);
      while (end - start > _maxSectionBytes) {
        final cut = _paragraphStart(text, start + _maxSectionBytes ~/ 2, end);
        if (cut < 0 || end - cut < _maxSectionBytes ~/ 4) break;
        starts.add(cut);
        start = cut;
      }
    }
    return starts;
  }

  /// Position of the next `<p`, `<div` or `<h1`..`<h6` tag in
  /// [from, end), or -1.
  static int _paragraphStart(Uint8List text, int from, int end) {
    bool isLetter(int c) =>
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
    for (var i = from; i < end - 4; i++) {
      if (text[i] != 0x3C) continue; // <
      final c1 = text[i + 1] | 0x20, c2 = text[i + 2] | 0x20;
      if (c1 == 0x70 && !isLetter(text[i + 2])) return i; // <p
      if (c1 == 0x68 && text[i + 2] >= 0x31 && text[i + 2] <= 0x36) {
        return i; // <h1..<h6
      }
      if (c1 == 0x64 && c2 == 0x69 && (text[i + 3] | 0x20) == 0x76) {
        return i; // <div
      }
    }
    return -1;
  }

  static int _indexOfIgnoreCase(Uint8List data, String pattern, int from) {
    final p = pattern.codeUnits;
    outer:
    for (var i = from; i <= data.length - p.length; i++) {
      for (var j = 0; j < p.length; j++) {
        var c = data[i + j];
        if (c >= 0x41 && c <= 0x5A) c += 0x20;
        if (c != p[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  static void _addImage(
      MobiFile mobi, Map<String, Uint8List> files, int number) {
    final path = _imagePath(number);
    if (files.containsKey(path)) return;
    // recindex / kindle:embed numbers start at 1.
    final bytes = mobi.image(number - 1);
    if (bytes != null) files[path] = bytes;
  }

  /// The `<body>` contents of an HTML (or HTML fragment) string.
  static String _body(String html) =>
      html_parser.parse(html).body?.innerHtml ?? '';

  /// The NCX (table of contents) index, or null if the book has none or
  /// it can't be read - the book still opens without contents.
  static MobiIndx? _parseNcx(MobiFile mobi) {
    final header = mobi.data.mobiHeader;
    final index = header?.ncxIndex;
    if (index == null || index == MobiFile.notSet) return null;
    try {
      final ncx = MobiIndx();
      RawMlUtils.parseIndex(mobi.data, ncx, index + mobi.kf8Offset);
      return ncx;
    } catch (_) {
      return null;
    }
  }

  /// First value of [tagId] in an index entry, or null.
  static int? _tag(MobiIndexEntry entry, int tagId) {
    for (final tag in entry.tags) {
      if (tag.tagId == tagId && tag.tagValues.isNotEmpty) {
        return tag.tagValues.first;
      }
    }
    return null;
  }

  /// A string from the index's CNCX records (TOC labels): the high 16
  /// bits of [offset] pick the record, the low 16 bits the position; the
  /// string is a forward variable-length size followed by the bytes.
  static String _cncxString(MobiFile mobi, MobiIndx indx, int? offset) {
    if (offset == null) return '';
    MobiPdbRecord? record = indx.cncxRecord;
    for (var i = offset >> 16; i > 0 && record != null; i--) {
      record = record.next;
    }
    final data = record?.data;
    if (data == null) return '';
    var position = offset & 0xFFFF;
    var length = 0;
    for (var n = 0; n < 4 && position < data.length; n++) {
      final byte = data[position++];
      length = (length << 7) | (byte & 0x7F);
      if (byte & 0x80 != 0) break;
    }
    if (position + length > data.length) return '';
    return mobi
        .decode(Uint8List.sublistView(data, position, position + length))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _Parts {
  const _Parts(this.sections, this.toc);
  final List<EpubSection> sections;
  final List<EpubTocEntry> toc;
}
