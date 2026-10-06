import 'dart:async';
import 'dart:typed_data';
import 'utils.dart';

/// Turns the bytes of a book file into an [EpubDocument]. Must be a
/// static or top-level function (it runs in an isolate via `compute`).
typedef BookDocumentParser = FutureOr<EpubDocument> Function(Uint8List bytes);

/// One kind of book the built-in reader opens: the name shown to the user
/// (Settings), its file extensions and its converter.
class _BookFamily {
  const _BookFamily(this.name, this.extensions, this.parser);
  final String name;
  final Set<String> extensions;
  final BookDocumentParser parser;
}

/// The formats the built-in (EPUB-style) reader can show, and how each is
/// converted. PDF has its own reader.
///
/// Add a new format here only - Settings' "Built-in reader" text and
/// `ReaderPage.canRead` follow automatically.
class BookDocuments {
  BookDocuments._();

  static final List<_BookFamily> _families = [
    const _BookFamily('EPUB', {'epub', 'kepub'}, EpubDocument.parse),
    const _BookFamily(
        'MOBI/AZW3', MobiDocument.extensions, MobiDocument.parse),
    const _BookFamily('FB2', Fb2Document.extensions, Fb2Document.parse),
    const _BookFamily('TXT', TxtDocument.extensions, TxtDocument.parse),
    const _BookFamily('DOCX', DocxDocument.extensions, DocxDocument.parse),
    const _BookFamily('ODT', OdtDocument.extensions, OdtDocument.parse),
    const _BookFamily('RTF', RtfDocument.extensions, RtfDocument.parse),
  ];

  static final Map<String, BookDocumentParser> _parsers = {
    for (final family in _families)
      for (final ext in family.extensions) ext: family.parser,
  };

  /// Formats (lower case) the built-in reader opens.
  static Set<String> get formats => _parsers.keys.toSet();

  /// Short names for the user (EPUB, MOBI/AZW3, FB2, ...), one per kind.
  static List<String> get formatNames =>
      [for (final family in _families) family.name];

  static bool canRead(String format) =>
      _parsers.containsKey(format.toLowerCase());

  /// The converter for [format] (EPUB, MOBI, ...), or null.
  static BookDocumentParser? parserFor(String format) =>
      _parsers[format.toLowerCase()];
}
