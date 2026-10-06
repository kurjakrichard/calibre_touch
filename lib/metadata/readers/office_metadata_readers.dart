import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../book_metadata.dart';
import '../calibre.dart';
import '../cover_image.dart';
import '../metadata_reader.dart';
import 'office_files.dart';
import 'rtf_parser.dart';
import 'txt_metadata_reader.dart';
import 'txt_text.dart';

/// Word (.docx / .docm): docProps/core.xml (title, creator, description,
/// keywords, language), cover = an image near the start of the text.
/// Missing title/author (or the ones Word fills in by itself, like the
/// computer's user name) are guessed like for TXT from the file name and
/// the first paragraphs.
class DocxMetadataReader extends MetadataReader {
  const DocxMetadataReader();

  @override
  Set<String> get extensions => const {'docx', 'docm'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() => parseDocxMetadata(
          filePath, File(filePath).readAsBytesSync(),
          withCover: withCover));
}

/// OpenDocument text (.odt): meta.xml (title, creator, description,
/// keywords, language, and Calibre's own `opf.*` fields: series, title
/// sort, ...), cover = an image near the start. Fallbacks as for DOCX.
class OdtMetadataReader extends MetadataReader {
  const OdtMetadataReader();

  @override
  Set<String> get extensions => const {'odt'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() => parseOdtMetadata(
          filePath, File(filePath).readAsBytesSync(),
          withCover: withCover));
}

/// Rich Text Format: the `{\info}` group (title, author, subject,
/// keywords, comment), cover = a picture near the start. Fallbacks as for
/// DOCX.
class RtfMetadataReader extends MetadataReader {
  const RtfMetadataReader();

  @override
  Set<String> get extensions => const {'rtf'};

  @override
  Future<BookMetadata> read(String filePath, {bool withCover = true}) =>
      Isolate.run(() => parseRtfMetadata(
          filePath, File(filePath).readAsBytesSync(),
          withCover: withCover));
}

/// How many paragraphs from the start an image may be to count as cover.
const _coverParagraphs = 10;

// ---------------------------------------------------------------------
// DOCX
// ---------------------------------------------------------------------

BookMetadata parseDocxMetadata(String filePath, Uint8List bytes,
    {bool withCover = true}) {
  final zip = ZipFiles.open(bytes);
  final core = zip.xml('docProps/core.xml')?.rootElement;
  String prop(String name) => OfficeText.clean(core?.kid(name)?.innerText);

  final docPath = OfficeRels.mainDocumentPath(zip);
  final body = zip.xml(docPath)?.rootElement.kid('body');
  final paragraphs = <XmlElement>[];
  final lines = <String>[];
  for (final para in body?.deep('p') ?? const <XmlElement>[]) {
    final text = OfficeText.clean(para.deep('t').map((t) => t.innerText).join());
    final hasImage = para.deep('blip').isNotEmpty || para.deep('imagedata').isNotEmpty;
    if (text.isEmpty && !hasImage) continue;
    paragraphs.add(para);
    if (text.isNotEmpty) lines.add(text);
    if (paragraphs.length >= 60) break;
  }

  Uint8List? cover;
  if (withCover) {
    final rels = OfficeRels.relationships(zip, docPath);
    for (final para in paragraphs.take(_coverParagraphs)) {
      final ids = [
        ...para.deep('blip').map((b) => b.attr('embed')),
        ...para.deep('imagedata').map((d) => d.attr('id')),
      ].whereType<String>();
      cover = _coverFrom(ids.map((id) => rels[id]), zip);
      if (cover != null) break;
    }
  }

  return _finish(
    filePath: filePath,
    title: prop('title'),
    authors: prop('creator'),
    description: prop('description'),
    tags: prop('keywords').split(RegExp('[,;]')),
    language: prop('language'),
    lines: lines,
    cover: cover,
  );
}

// ---------------------------------------------------------------------
// ODT
// ---------------------------------------------------------------------

BookMetadata parseOdtMetadata(String filePath, Uint8List bytes,
    {bool withCover = true}) {
  final zip = ZipFiles.open(bytes);
  final meta = zip.xml('meta.xml')?.rootElement.kid('meta');
  String prop(String name) => OfficeText.clean(meta?.kid(name)?.innerText);

  // Calibre stores its own fields as user-defined properties "opf.*".
  final user = <String, String>{
    for (final u in meta?.kids('user-defined') ?? const <XmlElement>[])
      if (u.attr('name') != null) u.attr('name')!: OfficeText.clean(u.innerText),
  };

  final text = zip.xml('content.xml')?.rootElement.kid('body')?.kid('text');
  final paragraphs = <XmlElement>[];
  final lines = <String>[];
  for (final para in text?.descendants.whereType<XmlElement>() ??
      const <XmlElement>[]) {
    if (para.local != 'p' && para.local != 'h') continue;
    final t = OfficeText.clean(para.innerText);
    if (t.isEmpty && para.deep('image').isEmpty) continue;
    paragraphs.add(para);
    if (t.isNotEmpty) lines.add(t);
    if (paragraphs.length >= 60) break;
  }

  Uint8List? cover;
  if (withCover) {
    for (final para in paragraphs.take(_coverParagraphs)) {
      cover = _coverFrom(para.deep('image').map((i) => i.attr('href')), zip);
      if (cover != null) break;
    }
  }

  // dc:creator is whoever saved it last; initial-creator wrote it.
  var authors = user['opf.authors'] ?? '';
  if (authors.isEmpty) authors = prop('initial-creator');
  if (authors.isEmpty) authors = prop('creator');
  final keywords = [
    for (final k in meta?.kids('keyword') ?? const <XmlElement>[])
      OfficeText.clean(k.innerText),
    ...(user['opf.tags'] ?? '').split(','),
  ];

  var metadata = _finish(
    filePath: filePath,
    title: user['opf.title'] ?? prop('title'),
    authors: authors,
    description: prop('description'),
    tags: keywords,
    language: user['opf.language'] ?? prop('language'),
    lines: lines,
    cover: cover,
  );
  final series = user['opf.series'] ?? '';
  final isbn = Calibre.identifier('isbn', user['opf.isbn'] ?? '');
  metadata = metadata.copyWith(
    titleSort: user['opf.titlesort'],
    authorSort: user['opf.authorsort'],
    publisher: user['opf.publisher'],
    series: series.isEmpty ? null : series,
    seriesIndex: series.isEmpty
        ? null
        : double.tryParse(user['opf.seriesindex'] ?? '') ?? 1,
    identifiers: isbn == null ? null : {isbn.key: isbn.value},
  );
  return metadata;
}

// ---------------------------------------------------------------------
// RTF
// ---------------------------------------------------------------------

BookMetadata parseRtfMetadata(String filePath, Uint8List bytes,
    {bool withCover = true}) {
  if (!RtfParser.isRtf(bytes)) throw const FormatException('Not an RTF file');
  final content = RtfParser.parse(bytes, maxParagraphs: 60);
  final lines = [
    for (final para in content.paragraphs)
      if (para.text.isNotEmpty) para.text,
  ];

  Uint8List? cover;
  if (withCover) {
    for (final para in content.paragraphs.take(_coverParagraphs + 5)) {
      final m = RegExp(r'<img src="([^"]+)"').firstMatch(para.html);
      if (m == null) continue;
      final image = content.images[m.group(1)];
      if (image != null) cover = CoverImage.toJpeg(image);
      if (cover != null) break;
    }
  }

  final info = content.info;
  return _finish(
    filePath: filePath,
    title: info['title'] ?? '',
    authors: info['author'] ?? '',
    description: info['doccomm'] ?? '',
    tags: (info['keywords'] ?? '').split(RegExp('[,;]')),
    language: '',
    lines: lines,
    cover: cover,
  );
}

// ---------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------

/// JPEG cover from the first displayable image among [paths].
Uint8List? _coverFrom(Iterable<String?> paths, ZipFiles zip) {
  for (final path in paths) {
    if (path == null || path.contains('://')) continue;
    final bytes = zip.data(p.posix.normalize(path));
    if (bytes == null || bytes.length < 2048) continue; // icons, bullets
    final jpeg = CoverImage.toJpeg(bytes);
    if (jpeg != null) return jpeg;
  }
  return null;
}

/// Document properties, with title/author guessed from the file name and
/// the first [lines] when the document doesn't have real ones.
BookMetadata _finish({
  required String filePath,
  required String title,
  required String authors,
  required String description,
  required List<String> tags,
  required String language,
  required List<String> lines,
  Uint8List? cover,
}) {
  final text = lines.join('\n');
  final languageCode =
      Calibre.languageCode(language) ?? TxtText.language(text);

  var cleanTitle = OfficeText.cleanTitle(title);
  var authorList = [
    for (final a in Calibre.stringToAuthors(authors.replaceAll(';', '&')))
      if (!OfficeText.isJunkAuthor(a)) a,
  ];
  if (cleanTitle.isEmpty || authorList.isEmpty) {
    final guess = guessTxtTitleAuthor(filePath, text, language: languageCode);
    if (cleanTitle.isEmpty) cleanTitle = guess.title;
    if (authorList.isEmpty && guess.author.isNotEmpty) {
      authorList = [guess.author];
    }
  }

  return BookMetadata(
    title: cleanTitle,
    authors: authorList,
    description: description,
    tags: {
      for (final t in tags)
        if (t.trim().isNotEmpty) t.trim(),
    }.toList(),
    languages: languageCode == null ? const [] : [languageCode],
    cover: cover,
  );
}
